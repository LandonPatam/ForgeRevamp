package forgeui.bridge;

import com.google.gson.*;
import forge.gui.GuiBase;
import forge.localinstance.properties.ForgeConstants;
import forge.model.FModel;
import io.netty.channel.Channel;
import java.io.FileOutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.Executors;

/** Application library service; Commander matches run in a separately owned child JVM. */
public final class LibraryMain {
    public static void main(String[] args) throws Exception {
        String assets = "../forge/forge-gui", directory = null, statusFile = null, dataDir = null; int port = 7778; long parentPid = 0;
        BridgeProtocol.require(args.length % 2 == 0, "Options require values");
        for (int i = 0; i < args.length; i += 2) switch (args[i]) {
            case "--assets" -> assets = args[i + 1];
            case "--port" -> port = Integer.parseInt(args[i + 1]);
            case "--library-root" -> directory = args[i + 1];
            case "--startup-status" -> statusFile = args[i + 1];
            case "--data-dir" -> dataDir = args[i + 1];
            case "--parent-pid" -> parentPid = Long.parseLong(args[i + 1]);
            default -> throw new IllegalArgumentException("Unknown option: " + args[i]);
        }
        if (dataDir != null) {
            // Installed builds have no source tree: keep match logs here and the service's own output in a file.
            System.setProperty("forgeui.data", dataDir);
            Files.createDirectories(Path.of(dataDir));
            var log = new PrintStream(new FileOutputStream(Path.of(dataDir, "service.log").toFile()), true, StandardCharsets.UTF_8);
            System.setOut(log); System.setErr(log);
        }
        if (parentPid > 0) BridgeMain.watchParent(parentPid, 250); // closing the application closes the service cleanly
        var startup = new StartupStatus(statusFile);
        try {
        startup.write("cards", "Loading Forge and card database", "Loading card rules, formats and your Forge settings.");
        System.setProperty("java.awt.headless", "true");
        GuiBase.setInterface(new HeadlessGuiBase(Path.of(assets).toAbsolutePath().normalize().toString()));
        FModel.initialize(null, null);
        startup.write("catalog", "Building the card catalog", "Indexing cards and printings for the deck editor.");
        var library = new DeckLibrary(Path.of(directory == null ? ForgeConstants.DECK_COMMANDER_DIR : directory));
        var lobby = new OnlineLobby(library);
        var matches = new MatchService(library, Path.of(assets).toAbsolutePath().normalize().toString(), directory == null, lobby);
        var worker = Executors.newSingleThreadExecutor(r -> { var t = new Thread(r, "deck-library"); t.setDaemon(true); return t; });
        var server = new BridgeServer(port, (Channel channel, String text) -> worker.execute(() -> {
            JsonObject response = new JsonObject();
            try {
                JsonObject request = JsonParser.parseString(text).getAsJsonObject();
                response.add("requestId", request.get("requestId"));
                response.addProperty("op", DeckLibrary.string(request, "op", ""));
                String operation = DeckLibrary.string(request, "op", "");
                response.add("result", operation.startsWith("match.") ? matches.handle(request)
                        : operation.startsWith("lobby.") ? lobby.handle(request, channel) : library.handle(request));
                response.addProperty("ok", true);
            } catch (Exception e) { response.addProperty("ok", false); response.addProperty("error", e.getMessage() == null ? "Library operation failed" : e.getMessage()); }
            if (channel.isActive()) channel.writeAndFlush(new io.netty.handler.codec.http.websocketx.TextWebSocketFrame(response.toString()));
        }), channel -> {}, lobby::ownerDisconnected);
        Runtime.getRuntime().addShutdownHook(new Thread(() -> { matches.close(); lobby.close(); worker.shutdownNow(); server.close(); }));
        startup.write("connecting", "Opening your deck library", "Starting the connection to your saved Commander decks.");
        server.start();
        System.out.println("Library ready: ws://127.0.0.1:" + server.localPort() + "/ws");
        startup.write("ready", "Opening your deck library", "Connecting the menu and reading your saved decks.");
        Thread.currentThread().join();
        } catch (Exception e) {
            startup.write("failed", "Forge could not start", e.getMessage() == null ? "Check the startup logs for details." : e.getMessage());
            throw e;
        }
    }
}
