package forgeui.bridge;

import com.google.gson.JsonObject;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.TimeUnit;

/** Owns only the child JVM started for this application's current Commander match. */
final class MatchService implements AutoCloseable {
    // The child writes its log in the platform charset; markers are ASCII, so decode bytes without failing.
    private static final java.nio.charset.Charset LOG_CHARSET = java.nio.charset.StandardCharsets.ISO_8859_1;
    private final DeckLibrary library;
    private final String assets;
    private final boolean installedOpponents;
    private final OnlineLobby lobby;
    private Process process;
    private Path log;
    private Path artwork;
    private String owner = "", launchKey = "", session = "";
    private int port;
    private long started;
    private boolean stopped, ready, artworkDelivered;

    MatchService(DeckLibrary library, String assets, boolean installedOpponents, OnlineLobby lobby) {
        this.library = library; this.assets = assets; this.installedOpponents = installedOpponents; this.lobby = lobby;
    }

    JsonObject handle(JsonObject request) throws Exception {
        String caller = DeckLibrary.string(request, "owner", "");
        BridgeProtocol.require(caller.length() >= 16 && caller.length() <= 100, "Missing application identity");
        return switch (DeckLibrary.string(request, "op", "")) {
            case "match.start" -> start(request, caller);
            case "match.status" -> {
                BridgeProtocol.require(process == null || owner.equals(caller), "Another application owns the current game");
                yield status();
            }
            case "match.artworkSeen" -> {
                BridgeProtocol.require(process != null && process.isAlive() && owner.equals(caller)
                        && session.equals(DeckLibrary.string(request, "session", "")), "This application does not own that game");
                artworkDelivered = true;
                yield status();
            }
            case "match.stop" -> {
                boolean exactSession = session.equals(DeckLibrary.string(request, "session", ""));
                boolean pendingLaunch = !ready && launchKey.equals(DeckLibrary.string(request, "launchKey", ""));
                BridgeProtocol.require(process == null || (owner.equals(caller) && (exactSession || pendingLaunch)), "This application does not own that game");
                close(); yield status();
            }
            default -> throw new IllegalArgumentException("Unknown match operation");
        };
    }

    private JsonObject start(JsonObject request, String caller) throws Exception {
        String key = DeckLibrary.string(request, "launchKey", "");
        BridgeProtocol.require(key.length() >= 16 && key.length() <= 100, "Missing launch identity");
        if (process != null && process.isAlive()) {
            BridgeProtocol.require(owner.equals(caller) && launchKey.equals(key), "A Commander game is already running");
            return status(); // retries never create a second game
        }
        long requested = System.currentTimeMillis();
        lobby.requireReady();
        BridgeProtocol.require(!lobby.status().get("hosting").getAsBoolean() || request.has("setup"), "Online games require lobby settings");
        Path deck = library.playableDeck(DeckLibrary.string(request, "id", ""));
        try (var socket = new ServerSocket(0, 1, InetAddress.getLoopbackAddress())) { port = socket.getLocalPort(); }
        String javaName = System.getProperty("os.name").toLowerCase(Locale.ROOT).contains("win") ? "java.exe" : "java";
        String java = Path.of(System.getProperty("java.home"), "bin", javaName).toString();
        String id = UUID.randomUUID().toString();
        String data = System.getProperty("forgeui.data");
        Path logs = (data == null ? Path.of("../client-godot/artifacts/app-sessions") : Path.of(data, "app-sessions")).toAbsolutePath().normalize();
        Files.createDirectories(logs);
        Path output = logs.resolve(id + ".log");
        artwork = logs.resolve(id + ".artwork.json");
        var arguments = new ArrayList<>(List.of(java, "-Xmx4g", "-cp", System.getProperty("java.class.path"),
                "forgeui.bridge.BridgeMain", "--assets", assets, "--port", Integer.toString(port),
                "--opponents", "2", "--deck-file", deck.toString(), "--opponent-policy", installedOpponents ? "installed" : "mirror",
                "--artwork-file", artwork.toString()));
        if (request.has("setup")) {
            JsonObject setup = MatchSetup.prepare(request.getAsJsonObject("setup"), library, DeckLibrary.string(request, "id", ""), lobby.playerCount());
            BridgeProtocol.require(setup.getAsJsonArray("bots").size() + lobby.playerCount() >= 1, "Add a bot or wait for a player to join");
            lobby.beginMatch(setup); // Frees the online port; the match process binds it next.
            Path setupFile = logs.resolve(id + ".setup.json");
            Files.writeString(setupFile, setup.toString());
            arguments.set(arguments.indexOf("--opponents") + 1, Integer.toString(setup.getAsJsonArray("bots").size()));
            arguments.addAll(List.of("--setup-file", setupFile.toString()));
        }
        var command = new ProcessBuilder(arguments);
        command.environment().put("FORGEUI_PARENT_PID", Long.toString(ProcessHandle.current().pid()));
        // The match logs its startup timings relative to this request (see "[timing]" lines).
        command.environment().put("FORGEUI_LAUNCH_EPOCH_MS", Long.toString(requested));
        command.redirectErrorStream(true).redirectOutput(output.toFile());
        process = command.start();
        log = output; owner = caller; launchKey = key; session = id; started = System.nanoTime(); stopped = false; ready = false; artworkDelivered = false;
        return status();
    }

    private JsonObject status() throws Exception {
        JsonObject result = new JsonObject();
        if (process == null) { result.addProperty("state", "none"); return result; }
        result.addProperty("session", session); result.addProperty("pid", process.pid());
        if (stopped) { result.addProperty("state", "stopped"); return result; }
        if (!process.isAlive()) {
            result.addProperty("state", "failed");
            String reason;
            try (var lines = Files.lines(log, LOG_CHARSET)) {
                reason = lines.filter(s -> s.startsWith(BridgeMain.STARTUP_FAILURE)).reduce((a, b) -> b)
                        .map(s -> s.substring(BridgeMain.STARTUP_FAILURE.length()).strip()).orElse(null);
            }
            if (reason != null && !reason.endsWith(".")) reason += ".";
            result.addProperty("error", reason != null ? "Forge could not start this game: " + reason + " Try starting the game again."
                    : "Forge exited while running this game. See " + log);
            return result;
        }
        // Readiness is latched: once seen, later polls skip rereading the growing log.
        // Scan the whole log so extra Forge startup warnings cannot hide the marker.
        if (!ready) {
            try (var lines = Files.lines(log, LOG_CHARSET)) { ready = lines.anyMatch(s -> s.startsWith("Decks ready:")); }
            if (ready) System.out.println("[timing] match " + session + " reported ready to the application after "
                    + TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started) + " ms (status poll)");
        }
        if (!artworkDelivered && artwork != null && Files.isRegularFile(artwork)) {
            try { result.add("artwork", com.google.gson.JsonParser.parseString(Files.readString(artwork))); }
            catch (Exception e) { System.err.println("[artwork] Manifest unavailable: " + e.getMessage()); }
        }
        if (!ready && TimeUnit.NANOSECONDS.toSeconds(System.nanoTime() - started) > 180) {
            close(); result.addProperty("state", "failed"); result.addProperty("error", "Forge startup timed out. Try starting the game again.");
            return result;
        }
        result.addProperty("state", ready ? "ready" : "starting");
        if (ready) result.addProperty("url", "ws://127.0.0.1:" + port + "/ws");
        return result;
    }

    @Override public void close() {
        if (process != null && process.isAlive()) {
            // Windows destroy() force-terminates Java without shutdown hooks.
            // Ask our own loopback bridge to notify remote seats and exit first.
            signalShutdown();
            try {
                if (!process.waitFor(2, TimeUnit.SECONDS)) process.destroy();
                if (!process.waitFor(3, TimeUnit.SECONDS)) { process.destroyForcibly(); process.waitFor(3, TimeUnit.SECONDS); }
            }
            catch (InterruptedException e) { process.destroyForcibly(); Thread.currentThread().interrupt(); }
        }
        stopped = true;
        lobby.release();
    }

    private void signalShutdown() {
        var sent = new java.util.concurrent.CompletableFuture<Void>();
        var delivered = new java.util.concurrent.CompletableFuture<Void>();
        java.net.http.WebSocket socket = null;
        try {
            var listener = new java.net.http.WebSocket.Listener() {
                private final StringBuilder frame = new StringBuilder();
                private boolean requested;
                @Override public void onOpen(java.net.http.WebSocket ws) { ws.request(1); }
                @Override public java.util.concurrent.CompletionStage<?> onText(java.net.http.WebSocket ws, CharSequence data, boolean last) {
                    frame.append(data);
                    if (last) {
                        JsonObject state = com.google.gson.JsonParser.parseString(frame.toString()).getAsJsonObject();
                        frame.setLength(0);
                        if ("sessionEnded".equals(DeckLibrary.string(state, "type", ""))) delivered.complete(null);
                        if (!requested && state.has("sessionId")) {
                            requested = true;
                            JsonObject stop = new JsonObject();
                            stop.addProperty("type", "shutdown");
                            stop.addProperty("protocolVersion", BridgeProtocol.VERSION);
                            stop.add("sessionId", state.get("sessionId"));
                            stop.add("revision", state.get("revision"));
                            stop.addProperty("requestId", UUID.randomUUID().toString());
                            ws.sendText(stop.toString(), true).whenComplete((ignored, error) -> {
                                if (error == null) sent.complete(null); else sent.completeExceptionally(error);
                            });
                        }
                    }
                    ws.request(1);
                    return null;
                }
                @Override public java.util.concurrent.CompletionStage<?> onClose(java.net.http.WebSocket ws, int code, String reason) {
                    delivered.complete(null);
                    return null;
                }
                @Override public void onError(java.net.http.WebSocket ws, Throwable error) {
                    sent.completeExceptionally(error);
                    delivered.completeExceptionally(error);
                }
            };
            socket = java.net.http.HttpClient.newHttpClient().newWebSocketBuilder()
                    .connectTimeout(java.time.Duration.ofSeconds(1))
                    .buildAsync(java.net.URI.create("ws://127.0.0.1:" + port + "/ws"), listener).get(2, TimeUnit.SECONDS);
            sent.get(1, TimeUnit.SECONDS);
            delivered.get(1, TimeUnit.SECONDS);
        } catch (Exception e) {
            // Startup failures may not have a listener yet; owned-process fallback still stops them.
        } finally { if (socket != null) socket.abort(); }
    }
}
