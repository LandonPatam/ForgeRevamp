package forgeui.bridge;

import com.google.gson.*;
import forge.deck.Deck;
import forge.deck.DeckFormat;
import forge.localinstance.properties.ForgeNetPreferences;
import forge.model.FModel;
import io.netty.channel.Channel;
import io.netty.handler.codec.http.websocketx.TextWebSocketFrame;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import org.jupnp.DefaultUpnpServiceConfiguration;
import org.jupnp.UpnpService;
import org.jupnp.UpnpServiceImpl;
import org.jupnp.model.meta.Device;
import org.jupnp.registry.Registry;
import org.jupnp.support.igd.PortMappingListener;
import org.jupnp.support.model.PortMapping;

/**
 * The host's waiting room. Lives in the library service, holds the online port until the match
 * starts, then hands the joined players and the port to the match process. Every seat the roster
 * leaves empty is open: a player who connects takes one without the host doing anything.
 */
final class OnlineLobby implements AutoCloseable {
    /** Bumped when lobby messages or the seat protocol change, so mismatched builds are told plainly. */
    static final int NET_VERSION = 4;
    private static final int MAX_PLAYERS = 4;
    private static final int MAX_DECK_BYTES = 256 * 1024;
    private static final int MAX_WAITING_CONNECTIONS = 16;
    private static final long START_DELIVERY_MILLIS = 2000;

    private record Joined(int id, Channel channel, JsonObject profile, Path deckFile, String deckName, String commander) {}

    private final DeckLibrary library;
    private final Map<Channel, Joined> joined = new LinkedHashMap<>();
    private final Set<Channel> waiting = new HashSet<>();
    private final Set<Channel> ready = new HashSet<>();
    private boolean hostReady;
    private final ExecutorService worker = Executors.newSingleThreadExecutor(r -> { var t = new Thread(r, "online-lobby"); t.setDaemon(true); return t; });
    private BridgeServer server;
    private Channel owner;
    private JsonObject config = new JsonObject();
    private Path deckDirectory;
    private UpnpService upnp;
    private int port, nextId;
    private volatile String lanAddress = "", publicAddress = "", upnpState = "off";

    OnlineLobby(DeckLibrary library) { this.library = library; }

    JsonObject handle(JsonObject request, Channel caller) throws Exception {
        return switch (DeckLibrary.string(request, "op", "")) {
            case "lobby.host" -> host(request, caller);
            case "lobby.config" -> configure(request);
            case "lobby.ready" -> hostReady(request);
            case "lobby.kick" -> kick(request);
            case "lobby.stop" -> { stop(); yield status(); }
            case "lobby.status" -> status();
            case "lobby.deckText" -> deckText(request);
            default -> throw new IllegalArgumentException("Unknown lobby operation");
        };
    }

    private synchronized JsonObject host(JsonObject request, Channel caller) throws Exception {
        BridgeProtocol.require(server == null, "You are already hosting a session");
        config = readConfig(request.getAsJsonObject("config"));
        port = FModel.getNetPreferences().getPrefInt(ForgeNetPreferences.FNetPref.NET_PORT);
        var candidate = BridgeServer.exposed(port, this::onMessage, this::onConnect, this::onDisconnect);
        try { candidate.start(); }
        catch (Exception e) { throw new IllegalArgumentException("Could not open port " + port + ". Is another Forge hosting a game?"); }
        server = candidate;
        owner = caller;
        joined.clear();
        waiting.clear();
        resetReady();
        nextId = 0;
        deckDirectory = Files.createTempDirectory("forgeui-lobby");
        lanAddress = ""; publicAddress = "";
        // Checks turn this off: finding addresses contacts an outside service and the router.
        boolean discover = !request.has("discover") || request.get("discover").getAsBoolean();
        upnpState = discover ? "working" : "off";
        if (discover) {
            var discovery = new Thread(this::discoverAddresses, "online-address");
            discovery.setDaemon(true);
            discovery.start();
        } else lanAddress = "127.0.0.1";
        return status();
    }

    private synchronized JsonObject configure(JsonObject request) {
        BridgeProtocol.require(server != null, "You are not hosting a session");
        JsonObject candidate = readConfig(request.getAsJsonObject("config"));
        BridgeProtocol.require(candidate.getAsJsonArray("bots").size() + joined.size() < MAX_PLAYERS, "Every seat is taken");
        if (!config.equals(candidate)) {
            config = candidate;
            resetReady();
        }
        broadcast();
        return status();
    }

    private synchronized JsonObject hostReady(JsonObject request) {
        BridgeProtocol.require(server != null, "You are not hosting a session");
        if (!request.get("ready").getAsBoolean()) resetReady();
        else hostReady = true;
        broadcast();
        return status();
    }

    private void resetReady() { hostReady = false; ready.clear(); }

    private boolean allReady() {
        return hostReady && ready.containsAll(joined.keySet());
    }

    synchronized void requireReady() {
        if (server != null) BridgeProtocol.require(allReady(), "Every player must press PLAY to ready up before the game starts");
    }

    private JsonObject readConfig(JsonObject input) {
        BridgeProtocol.require(input != null && input.has("human") && input.get("bots") != null && input.get("bots").isJsonArray(), "Missing lobby settings");
        BridgeProtocol.require(input.getAsJsonArray("bots").size() < MAX_PLAYERS, "Every seat is taken");
        return input.deepCopy();
    }

    private synchronized JsonObject kick(JsonObject request) {
        int id = BridgeProtocol.integer(request.get("id"));
        for (Joined player : joined.values()) if (player.id() == id) {
            send(player.channel(), rejection("The host removed you from the session."));
            player.channel().close();
        }
        return status();
    }

    synchronized JsonObject status() {
        JsonObject result = new JsonObject();
        result.addProperty("hosting", server != null);
        if (server == null) return result;
        result.addProperty("port", port);
        result.addProperty("defaultPort", port == Integer.parseInt(ForgeNetPreferences.FNetPref.NET_PORT.getDefault()));
        result.addProperty("lan", lanAddress);
        result.addProperty("public", publicAddress);
        result.addProperty("upnp", upnpState);
        result.addProperty("hostReady", hostReady);
        result.addProperty("allReady", allReady());
        JsonArray players = new JsonArray();
        for (Joined player : joined.values()) players.add(describe(player));
        result.add("players", players);
        return result;
    }

    private JsonObject describe(Joined player) {
        JsonObject entry = player.profile().deepCopy();
        entry.addProperty("id", player.id());
        entry.addProperty("kind", "player");
        entry.addProperty("deck", player.deckName());
        entry.addProperty("commander", player.commander());
        entry.addProperty("ready", ready.contains(player.channel()));
        return entry;
    }

    /** How many remote players the match setup must account for. */
    synchronized int playerCount() { return server == null ? 0 : joined.size(); }

    /** Assign each joined player a seat token, tell them to connect, and free the port for the match process. */
    void beginMatch(JsonObject setup) {
        BridgeServer closing;
        List<Channel> leaving = new ArrayList<>();
        synchronized (this) {
            if (server == null) return;
            requireReady();
            JsonArray remotes = new JsonArray();
            var random = new SecureRandom();
            for (Joined player : joined.values()) {
                byte[] bytes = new byte[32];
                random.nextBytes(bytes);
                String token = HexFormat.of().formatHex(bytes);
                JsonObject remote = player.profile().deepCopy();
                remote.addProperty("deckFile", player.deckFile().toString());
                remote.addProperty("token", token);
                remotes.add(remote);
                JsonObject start = new JsonObject();
                start.addProperty("type", "start");
                start.addProperty("token", token);
                start.addProperty("port", port);
                send(player.channel(), start);
                leaving.add(player.channel());
            }
            setup.add("remotes", remotes);
            setup.addProperty("remotePort", port);
            closing = server;
            server = null;
            joined.clear();
            waiting.clear();
            resetReady();
        }
        // Outside the lock: closing waits for network threads that may be waiting on this lobby.
        awaitDeparture(leaving);
        closing.close();
    }

    /** Players leave once they have read "start"; a client can lose that message if the close arrives with it. */
    private static void awaitDeparture(List<Channel> leaving) {
        long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(START_DELIVERY_MILLIS);
        try {
            for (Channel channel : leaving) channel.closeFuture().await(Math.max(0, TimeUnit.NANOSECONDS.toMillis(deadline - System.nanoTime())));
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    /** The host's application went away; never leave a port open on their behalf. */
    void ownerDisconnected(Channel channel) {
        worker.execute(() -> {
            boolean lost;
            synchronized (this) { lost = channel == owner && server != null; }
            if (lost) stop();
        });
    }

    private void stop() {
        BridgeServer closing;
        synchronized (this) {
            closing = server;
            server = null;
            JsonObject closed = new JsonObject();
            closed.addProperty("type", "closed");
            closed.addProperty("message", "The host closed the session.");
            for (Channel channel : joined.keySet()) send(channel, closed);
            joined.clear();
            waiting.clear();
            resetReady();
        }
        if (closing != null) closing.close(); // Outside the lock, as in beginMatch.
        release();
    }

    /** The online session is over, so close the router port and remove the received deck copies. */
    synchronized void release() {
        if (server != null) return;
        if (upnp != null) {
            UpnpService service = upnp;
            upnp = null;
            var shutdown = new Thread(() -> {
                // The JDK wraps a failed multicast leave in AssertionError, which jupnp doesn't catch.
                try { service.shutdown(); } catch (Exception | AssertionError e) { System.err.println("[online] UPnP shutdown incomplete: " + e); }
            }, "online-upnp-stop");
            shutdown.setDaemon(true);
            shutdown.start();
        }
        upnpState = "off";
        if (deckDirectory != null) {
            try (var files = Files.list(deckDirectory)) { files.forEach(file -> file.toFile().delete()); }
            catch (Exception e) { System.err.println("[online] Could not clear received decks: " + e.getMessage()); }
            deckDirectory.toFile().delete();
            deckDirectory = null;
        }
    }

    @Override public void close() { stop(); worker.shutdownNow(); }

    private void onConnect(Channel channel) {
        synchronized (this) {
            if (waiting.size() >= MAX_WAITING_CONNECTIONS) { channel.close(); return; }
            waiting.add(channel);
        }
        // A connection that never introduces itself cannot hold a slot open.
        channel.eventLoop().schedule(() -> {
            synchronized (this) { if (waiting.contains(channel)) channel.close(); }
        }, 15, TimeUnit.SECONDS);
    }

    private void onDisconnect(Channel channel) {
        synchronized (this) {
            waiting.remove(channel);
            Joined player = joined.remove(channel);
            if (player != null) {
                resetReady();
                player.deckFile().toFile().delete();
                broadcast();
            }
        }
    }

    private void onMessage(Channel channel, String text) {
        worker.execute(() -> {
            try {
                JsonObject message = JsonParser.parseString(text).getAsJsonObject();
                switch (DeckLibrary.string(message, "type", "")) {
                    case "join" -> join(channel, message);
                    case "deck" -> changeDeck(channel, message);
                    case "ready" -> ready(channel, message);
                    default -> throw new IllegalArgumentException("Unknown lobby message");
                }
            } catch (IllegalArgumentException e) {
                send(channel, rejection(e.getMessage()));
                synchronized (this) { if (!joined.containsKey(channel)) channel.close(); }
            } catch (Exception e) {
                send(channel, rejection("The host could not read that request."));
                synchronized (this) { if (!joined.containsKey(channel)) channel.close(); }
            }
        });
    }

    private synchronized void join(Channel channel, JsonObject message) throws Exception {
        BridgeProtocol.require(server != null && waiting.contains(channel), "This connection has already joined");
        BridgeProtocol.require(message.has("version") && BridgeProtocol.integer(message.get("version")) == NET_VERSION,
                "This game build does not match the host's. Everyone needs the same build.");
        BridgeProtocol.require(openSeats() > 0, "That session is full.");
        JsonObject profile = MatchSetup.profile(message);
        profile.addProperty("name", uniqueName(profile.get("name").getAsString()));
        int id = ++nextId;
        joined.put(channel, readDeck(id, channel, profile, message));
        waiting.remove(channel);
        resetReady();
        broadcast();
    }

    private synchronized void changeDeck(Channel channel, JsonObject message) throws Exception {
        Joined player = joined.get(channel);
        BridgeProtocol.require(player != null, "Join the session first");
        Joined replacement = readDeck(player.id(), channel, player.profile(), message);
        joined.put(channel, replacement);
        player.deckFile().toFile().delete();
        resetReady();
        broadcast();
    }

    private synchronized void ready(Channel channel, JsonObject message) {
        BridgeProtocol.require(joined.containsKey(channel), "Join the session first");
        if (message.get("ready").getAsBoolean()) ready.add(channel);
        else ready.remove(channel);
        broadcast();
    }

    /** Decks arrive as the bytes of the player's own deck file, and must be legal on the host's Forge. */
    private Joined readDeck(int id, Channel channel, JsonObject profile, JsonObject message) throws Exception {
        byte[] bytes;
        try { bytes = Base64.getDecoder().decode(DeckLibrary.string(message, "deckData", "")); }
        catch (IllegalArgumentException e) { throw new IllegalArgumentException("That deck could not be read."); }
        BridgeProtocol.require(bytes.length > 0 && bytes.length <= MAX_DECK_BYTES, "That deck could not be read.");
        // Validate a separate copy so a rejected change cannot overwrite the accepted deck.
        Path file = Files.createTempFile(deckDirectory, "player-" + id + "-", ".dck");
        boolean accepted = false;
        try {
            Files.write(file, bytes);
            Deck deck;
            try { deck = DeckFiles.read(file.toFile()); }
            catch (RuntimeException e) { throw new IllegalArgumentException("That deck could not be read."); }
            BridgeProtocol.require(deck != null, "That deck could not be read.");
            String problem = DeckFormat.Commander.getDeckConformanceProblem(deck);
            BridgeProtocol.require(problem == null, "The host's Forge rejected your deck: " + problem);
            String commander = String.join(" / ", deck.getCommanders().stream().map(card -> card.getName()).toList());
            String name = deck.getName() == null || deck.getName().isBlank() ? commander : deck.getName();
            accepted = true;
            return new Joined(id, channel, profile, file, name.length() > 80 ? name.substring(0, 80) : name, commander);
        } finally {
            if (!accepted) Files.deleteIfExists(file);
        }
    }

    private int openSeats() {
        return MAX_PLAYERS - 1 - config.getAsJsonArray("bots").size() - joined.size();
    }

    private String uniqueName(String wanted) {
        var taken = new HashSet<String>();
        taken.add(DeckLibrary.string(config.getAsJsonObject("human"), "name", "").strip().toLowerCase(Locale.ROOT));
        for (JsonElement bot : config.getAsJsonArray("bots")) taken.add(DeckLibrary.string(bot.getAsJsonObject(), "name", "").strip().toLowerCase(Locale.ROOT));
        for (Joined player : joined.values()) taken.add(player.profile().get("name").getAsString().toLowerCase(Locale.ROOT));
        if (!taken.contains(wanted.toLowerCase(Locale.ROOT))) return wanted;
        String base = wanted.length() > 28 ? wanted.substring(0, 28) : wanted;
        for (int number = 2; ; number++) {
            String candidate = base + " " + number;
            if (!taken.contains(candidate.toLowerCase(Locale.ROOT))) return candidate;
        }
    }

    private void broadcast() {
        JsonArray roster = new JsonArray();
        JsonObject host = rosterEntry(config.getAsJsonObject("human"), "host");
        host.addProperty("ready", hostReady);
        roster.add(host);
        for (JsonElement bot : config.getAsJsonArray("bots")) roster.add(rosterEntry(bot.getAsJsonObject(), "bot"));
        for (Joined player : joined.values()) roster.add(describe(player));
        for (Joined player : joined.values()) {
            JsonObject update = new JsonObject();
            update.addProperty("type", "lobby");
            update.addProperty("you", player.id());
            update.addProperty("open", openSeats());
            update.addProperty("allReady", allReady());
            update.add("roster", roster);
            send(player.channel(), update);
        }
    }

    private static JsonObject rosterEntry(JsonObject profile, String kind) {
        JsonObject entry = new JsonObject();
        entry.addProperty("kind", kind);
        entry.addProperty("name", DeckLibrary.string(profile, "name", ""));
        entry.addProperty("portrait", DeckLibrary.string(profile, "portrait", ""));
        entry.addProperty("avatar", profile.has("avatar") ? profile.get("avatar").getAsInt() : 0);
        return entry;
    }

    private static JsonObject rejection(String message) {
        JsonObject result = new JsonObject();
        result.addProperty("type", "rejected");
        result.addProperty("message", message);
        return result;
    }

    private void send(Channel channel, JsonObject message) {
        if (channel.isActive()) channel.writeAndFlush(new TextWebSocketFrame(message.toString()));
    }

    /** The deck file a joining player sends to the host, from their own library. */
    private JsonObject deckText(JsonObject request) throws Exception {
        Path file = library.playableDeck(DeckLibrary.string(request, "id", ""));
        byte[] bytes = Files.readAllBytes(file);
        BridgeProtocol.require(bytes.length <= MAX_DECK_BYTES, "That deck file is too large to send");
        JsonObject result = new JsonObject();
        result.addProperty("deckData", Base64.getEncoder().encodeToString(bytes));
        result.addProperty("version", NET_VERSION);
        return result;
    }

    private void discoverAddresses() {
        String lan = "";
        // Connecting a UDP socket sends nothing; it only asks the OS which interface routes outward.
        try (var socket = new DatagramSocket()) {
            socket.connect(InetAddress.getByName("8.8.8.8"), 12345);
            lan = socket.getLocalAddress().getHostAddress();
            lanAddress = lan;
        } catch (Exception e) { System.err.println("[online] No local address: " + e.getMessage()); }
        openRouterPort(lan);
        try {
            var client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
            var request = HttpRequest.newBuilder(URI.create("https://checkip.amazonaws.com")).timeout(Duration.ofSeconds(5)).build();
            publicAddress = client.send(request, HttpResponse.BodyHandlers.ofString()).body().strip();
        } catch (Exception e) { System.err.println("[online] No public address: " + e.getMessage()); }
    }

    /** Asks the router to forward the port. Optional: it fails on many routers, and a manual forward or LAN play still works. */
    private void openRouterPort(String lan) {
        if (lan.isEmpty()) { upnpState = "failed"; return; }
        try {
            // Gateways and TVs routinely break the UPnP spec in ways jupnp tolerates; don't log each one.
            org.jupnp.util.SpecificationViolationReporter.disableReporting();
            var service = new UpnpServiceImpl(new DefaultUpnpServiceConfiguration());
            service.startup();
            synchronized (this) {
                if (server == null) { service.shutdown(); return; }
                upnp = service;
            }
            service.getRegistry().addListener(new PortMappingListener(new PortMapping(port, lan, PortMapping.Protocol.TCP, "ForgeUI")) {
                @Override public synchronized void deviceAdded(Registry registry, Device device) {
                    super.deviceAdded(registry, device);
                    if (!activePortMappings.isEmpty()) upnpState = "open";
                }
                @Override protected void handleFailureMessage(String message) {
                    super.handleFailureMessage(message);
                    if (!upnpState.equals("open")) upnpState = "failed";
                }
            });
            service.getControlPoint().search();
            Thread.sleep(5000);
            if (upnpState.equals("working")) upnpState = "failed";
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        } catch (Exception | LinkageError e) {
            System.err.println("[online] UPnP unavailable: " + e);
            upnpState = "failed";
        }
    }
}
