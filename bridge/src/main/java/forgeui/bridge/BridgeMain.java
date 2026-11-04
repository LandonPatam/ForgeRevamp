package forgeui.bridge;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import forge.LobbyPlayer;
import forge.deck.Deck;
import forge.deck.io.DeckSerializer;
import forge.game.GameType;
import forge.game.card.CardView;
import forge.game.zone.ZoneType;
import forge.player.PlayerControllerHuman;
import forge.game.player.PlayerView;
import forge.game.player.RegisteredPlayer;
import forge.game.spellability.StackItemView;
import forge.gamemodes.match.HostedMatch;
import forge.gui.GuiBase;
import forge.interfaces.IGameController;
import forge.model.FModel;
import forge.player.GamePlayerUtil;
import forge.util.ITriggerEvent;
import forge.util.storage.IStorage;
import io.netty.channel.Channel;

import java.io.File;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.List;
import java.util.Map;
import java.util.HashMap;
import java.util.UUID;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Phase 1 spike: starts a Commander game against AI opponents and serves it to a browser page.
 *
 * <pre>
 * java -cp ... forgeui.bridge.BridgeMain [--assets DIR] [--port N] [--deck NAME] [--opponents N]
 * </pre>
 */
public final class BridgeMain {
    private static final ITriggerEvent CLICK = new ITriggerEvent() {
        @Override public int getButton() { return 1; }
        @Override public int getX() { return 0; }
        @Override public int getY() { return 0; }
    };

    /** Forge removes an attacker from combat on a right-click (button 3). */
    private static final ITriggerEvent RIGHT_CLICK = new ITriggerEvent() {
        @Override public int getButton() { return 3; }
        @Override public int getX() { return 0; }
        @Override public int getY() { return 0; }
    };

    private record Snapshot(long revision, String json, Map<Integer, CardView> cards,
                            Map<Integer, PlayerView> players, Map<Integer, StackItemView> stackItems,
                            forge.gamemodes.match.input.Input input) {}
    /**
     * One human player's view of the match. Each has its own Forge controller, GUI and
     * visibility-filtered snapshots. The host's seat is served to every socket on the loopback
     * server; an online seat belongs to the single connection that presented its token.
     */
    private final class Seat {
        final BridgeGuiGame gui;
        final String token;
        final AtomicLong revision = new AtomicLong();
        final AtomicBoolean dirty = new AtomicBoolean(true);
        final AtomicBoolean releasing = new AtomicBoolean();
        volatile Snapshot snapshot;
        volatile Channel channel;
        volatile long absentSince = System.nanoTime();
        volatile boolean gone;

        Seat(String token) {
            this.token = token;
            gui = new BridgeGuiGame(new BridgeGuiGame.Listener() {
                @Override public void stateChanged() { changed(); }
                @Override public void gameInitialized(forge.game.Game game) { observeStartingToss(game); }
                @Override public void send(JsonObject message) {
                    synchronized (publicationLock) {
                        changed();
                        publish(envelope(Seat.this, message).toString());
                    }
                }
            }, portraits);
        }

        boolean online() { return token != null; }

        void publish(String json) {
            if (!online()) { server.broadcast(json); return; }
            Channel current = channel;
            if (current != null && current.isActive()) server.send(current, json);
        }
    }

    /** An absent online player holds up the table for this long before their seat concedes. */
    private static final long ABSENT_LIMIT_NANOS = TimeUnit.MINUTES.toNanos(5);
    private final String sessionId = UUID.randomUUID().toString();
    private final Object publicationLock = new Object();
    private final Map<String, String> portraits = new java.util.concurrent.ConcurrentHashMap<>();
    private final List<Seat> seats = new java.util.concurrent.CopyOnWriteArrayList<>();
    private final Map<Channel, Seat> seatByChannel = new java.util.concurrent.ConcurrentHashMap<>();
    private BridgeServer server;
    private BridgeServer onlineServer;
    private BridgeGuiGame gui;
    private final AtomicBoolean sessionEnding = new AtomicBoolean();
    private volatile boolean tableStarted;
    private forge.game.Game tossGame;
    private volatile JsonObject startingToss;
    private int tossId;

    /** Register before HostedMatch starts the game thread, so the first toss cannot be missed. */
    private synchronized void observeStartingToss(forge.game.Game game) {
        if (tossGame == game) return;
        tossGame = game;
        startingToss = null;
        game.subscribeToEvents(new Object() {
            @com.google.common.eventbus.Subscribe public void onToss(forge.game.event.GameEventFlipCoin event) {
                if (!event.startingToss()) return;
                JsonObject toss = new JsonObject();
                toss.addProperty("id", ++tossId);
                toss.addProperty("winnerId", event.flipper().getId());
                toss.addProperty("winnerName", event.flipper().getName());
                toss.addProperty("heads", event.heads());
                toss.addProperty("choosing", true);
                startingToss = toss;
                changed();
            }
            @com.google.common.eventbus.Subscribe public void onStarted(forge.game.event.GameEventGameStarted event) {
                JsonObject current = startingToss;
                if (current == null) return;
                JsonObject toss = current.deepCopy();
                toss.addProperty("choosing", false);
                toss.addProperty("firstId", event.firstTurn().getId());
                toss.addProperty("firstName", event.firstTurn().getName());
                startingToss = toss;
                changed();
            }
        });
    }
    private long lastSnapshotWarning;
    private final SnapshotStats stats = new SnapshotStats();
    private boolean firstGameLogged, firstPromptLogged;
    /** Log prefix MatchService reads to report why a match could not start. */
    static final String STARTUP_FAILURE = "[startup-failure] ";
    /** Epoch ms of the parent's launch request, or this JVM's start when run directly. */
    private static long launchEpoch;

    /** Startup and snapshot timings, written to this match's session log. */
    private static void timing(String text) { System.out.println("[timing] " + text); }

    private static long millisSince(long nanoStart) { return TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - nanoStart); }

    /** Snapshot build/size totals, reported once a minute and at shutdown. */
    private static final class SnapshotStats {
        private long windowStart = System.nanoTime(), buildNanos, maxBuildNanos, chars;
        private int builds, sent, discarded, maxChars, largestLogged;

        synchronized void record(long nanos, int length, boolean broadcast) {
            // Matches are usually force-stopped (no shutdown hook), so note size growth as it happens.
            if (broadcast && length > largestLogged * 1.25) {
                largestLogged = length;
                timing(String.format(java.util.Locale.ROOT, "largest snapshot so far %.0f KB, build+serialize %.1f ms", length / 1024.0, nanos / 1e6));
            }
            builds++; buildNanos += nanos; maxBuildNanos = Math.max(maxBuildNanos, nanos);
            chars += length; maxChars = Math.max(maxChars, length);
            if (broadcast) sent++;
        }

        synchronized void discard() { discarded++; }

        synchronized void report(boolean force) {
            long window = System.nanoTime() - windowStart;
            if (builds + discarded == 0 || (!force && window < TimeUnit.SECONDS.toNanos(60))) return;
            timing(String.format(java.util.Locale.ROOT,
                    "snapshots over %ds: %d built, %d sent, %d discarded; build+serialize avg %.1f ms, max %.1f ms; size avg %.0f KB, max %.0f KB",
                    TimeUnit.NANOSECONDS.toSeconds(window), builds, sent, discarded,
                    builds == 0 ? 0.0 : buildNanos / 1e6 / builds, maxBuildNanos / 1e6,
                    builds == 0 ? 0.0 : chars / 1024.0 / builds, maxChars / 1024.0));
            windowStart = System.nanoTime(); buildNanos = maxBuildNanos = chars = 0; builds = sent = discarded = maxChars = 0;
        }
    }

    /** Engine changes can alter what any seat sees, so every seat rebuilds its snapshot. */
    private void changed() {
        synchronized (publicationLock) {
            for (Seat seat : seats) {
                seat.revision.incrementAndGet();
                seat.dirty.set(true);
            }
        }
    }

    private JsonObject envelope(Seat seat, JsonObject message) {
        return stamp(seat, message.deepCopy());
    }

    /** Adds protocol metadata in place; for freshly built messages nothing else holds. */
    private JsonObject stamp(Seat seat, JsonObject message) {
        message.addProperty("protocolVersion", BridgeProtocol.VERSION);
        message.addProperty("sessionId", sessionId);
        message.addProperty("revision", seat.revision.get());
        return message;
    }

    public static void main(String[] args) throws Exception {
        long jvmStart = java.lang.management.ManagementFactory.getRuntimeMXBean().getStartTime();
        String launched = System.getenv("FORGEUI_LAUNCH_EPOCH_MS");
        launchEpoch = launched == null || launched.isBlank() ? jvmStart : Long.parseLong(launched);
        timing("launch request to JVM start " + (jvmStart - launchEpoch) + " ms; JVM start to main "
                + (System.currentTimeMillis() - jvmStart) + " ms");
        String assets = "../forge/forge-gui";
        int port = 7777;
        String deckName = null;
        String deckFile = null;
        String testState = null;
        String setupFile = null;
        boolean installedOpponents = false;
        int opponents = 3;
        BridgeProtocol.require(args.length % 2 == 0, "Options require values");
        for (int i = 0; i + 1 < args.length; i += 2) {
            switch (args[i]) {
                case "--assets" -> assets = args[i + 1];
                case "--port" -> port = Integer.parseInt(args[i + 1]);
                case "--deck" -> deckName = args[i + 1];
                case "--deck-file" -> deckFile = args[i + 1];
                case "--test-state" -> testState = args[i + 1];
                case "--setup-file" -> setupFile = args[i + 1];
                case "--artwork-file" -> { /* handled below after the bridge exists */ }
                case "--opponents" -> opponents = Integer.parseInt(args[i + 1]);
                case "--opponent-policy" -> {
                    BridgeProtocol.require(args[i + 1].equals("installed") || args[i + 1].equals("mirror"), "Unknown opponent policy");
                    installedOpponents = args[i + 1].equals("installed");
                }
                default -> throw new IllegalArgumentException("Unknown option " + args[i]);
            }
        }
        BridgeProtocol.require(port > 0 && port <= 65535, "Invalid port");
        // A setup file may seat only online players; MatchSetup has already checked its table size.
        BridgeProtocol.require(opponents >= (setupFile != null ? 0 : 1) && opponents <= 3, "Use 1 to 3 AI opponents");
        BridgeProtocol.require(testState == null || deckFile != null, "Prepared test states require an explicit fixture deck");
        System.setProperty("java.awt.headless", "true");
        System.setProperty("java.util.Arrays.useLegacyMergeSort", "true");
        watchApplicationParent();
        BridgeMain bridge = new BridgeMain();
        for (int i = 0; i + 1 < args.length; i += 2) {
            if (args[i].equals("--artwork-file")) bridge.artworkFile = java.nio.file.Path.of(args[i + 1]);
        }
        try {
            if (setupFile != null) {
                var path = java.nio.file.Path.of(setupFile);
                BridgeProtocol.require(java.nio.file.Files.size(path) <= 500000, "Match settings file is too large");
                bridge.matchSetup = JsonParser.parseString(java.nio.file.Files.readString(path)).getAsJsonObject();
            }
            bridge.run(new File(assets).getCanonicalPath(), port, deckName, deckFile, opponents, testState, installedOpponents);
        } catch (Throwable e) {
            // Forge and server threads would keep this JVM alive with no game, so the
            // application would wait for a table that never comes. Exit so it sees the failure.
            e.printStackTrace();
            String reason = e.getMessage() == null || e.getMessage().isBlank() ? e.getClass().getSimpleName() : e.getMessage();
            System.out.println(STARTUP_FAILURE + reason.replace('\n', ' '));
            System.out.flush();
            System.exit(1);
        }
    }

    private static void watchApplicationParent() {
        String value = System.getenv("FORGEUI_PARENT_PID");
        if (value == null || value.isBlank()) return;
        watchParent(Long.parseLong(value), 1000);
    }

    /** Exits (running shutdown hooks) once the process that owns this one has gone. */
    static void watchParent(long pid, long pollMillis) {
        Thread watcher = new Thread(() -> {
            while (ProcessHandle.of(pid).map(ProcessHandle::isAlive).orElse(false)) {
                try { Thread.sleep(pollMillis); } catch (InterruptedException e) { return; }
            }
            System.exit(0); // never orphan an owned game if the application service is killed
        }, "application-parent");
        watcher.setDaemon(true); watcher.start();
    }

    private void run(String assets, int port, String deckName, String deckFile, int opponents, String testState, boolean installedOpponents) throws Exception {
        GuiBase.setInterface(new HeadlessGuiBase(assets));
        System.out.println("Loading Forge from " + assets + " ...");
        long step = System.nanoTime();
        FModel.initialize(null, null);
        timing("Forge initialization " + millisSince(step) + " ms");

        Seat host = new Seat(null);
        gui = host.gui;
        seats.add(host);
        JsonArray remotes = matchSetup == null ? null : matchSetup.getAsJsonArray("remotes");
        if (remotes != null) for (var remote : remotes) seats.add(new Seat(remote.getAsJsonObject().get("token").getAsString()));
        for (Seat seat : seats) seat.gui.setOnlineMatch(seats.size() > 1);
        if (seats.size() > 1) forge.game.mulligan.MulliganService.onlineDecisions = new OnlineOpeningHands();

        step = System.nanoTime();
        server = new BridgeServer(port, (channel, text) -> onClientMessage(host, channel, text), channel -> sendSnapshot(host, channel));
        server.start();
        if (remotes != null && !remotes.isEmpty()) startOnlineServer(matchSetup.get("remotePort").getAsInt());
        timing("server start " + millisSince(step) + " ms");
        ScheduledExecutorService pump = Executors.newSingleThreadScheduledExecutor(r -> {
            Thread t = new Thread(r, "bridge-state");
            t.setDaemon(true);
            return t;
        });
        pump.scheduleWithFixedDelay(this::pushState, 100, 60, TimeUnit.MILLISECONDS);
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            endOnlineSession();
            pump.shutdownNow();
            stats.report(true);
            if (onlineServer != null) onlineServer.close();
            server.close();
        }, "bridge-shutdown"));
        System.out.println("Bridge ready: http://127.0.0.1:" + port + "/");
        timing("bridge ready " + (System.currentTimeMillis() - launchEpoch) + " ms after launch request");

        step = System.nanoTime();
        startCommanderGame(deckName, deckFile, opponents, testState, installedOpponents);
        timing("game setup (decks and match start) " + millisSince(step) + " ms");
        Thread.currentThread().join(); // keep running; the game lives on Forge's threads
    }

    private JsonObject matchSetup;
    private java.nio.file.Path artworkFile;

    /** The lobby released this port moments ago, so allow it a little time to come free. */
    private void startOnlineServer(int port) throws Exception {
        for (int attempt = 1; ; attempt++) {
            var candidate = BridgeServer.exposed(port, this::onOnlineMessage, this::awaitSeatToken, this::onOnlineDisconnect);
            try {
                candidate.start();
                onlineServer = candidate;
                return;
            } catch (Exception e) {
                candidate.close();
                if (attempt >= 20) throw new IllegalStateException("Could not reopen online port " + port);
                Thread.sleep(250);
            }
        }
    }

    /** A connection that doesn't present a seat token promptly is dropped. */
    private void awaitSeatToken(Channel channel) {
        channel.eventLoop().schedule(() -> { if (!seatByChannel.containsKey(channel)) channel.close(); }, 10, TimeUnit.SECONDS);
    }

    private void onOnlineMessage(Channel channel, String text) {
        Seat seat = seatByChannel.get(channel);
        if (seat != null) {
            if (text.contains("\"leave\"") && isLeave(text)) abandon(seat);
            else onClientMessage(seat, channel, text);
            return;
        }
        Seat claimed = null;
        try {
            JsonObject message = JsonParser.parseString(text).getAsJsonObject();
            if ("auth".equals(DeckLibrary.string(message, "type", ""))) {
                byte[] token = DeckLibrary.string(message, "token", "").getBytes(java.nio.charset.StandardCharsets.UTF_8);
                for (Seat candidate : seats) {
                    if (candidate.online() && !candidate.gone && java.security.MessageDigest.isEqual(token,
                            candidate.token.getBytes(java.nio.charset.StandardCharsets.UTF_8))) claimed = candidate;
                }
            }
        } catch (RuntimeException e) { /* Treated as a failed claim below. */ }
        if (claimed == null) { channel.close(); return; }
        // A reconnecting player replaces their own stale connection.
        Channel previous = claimed.channel;
        claimed.channel = channel;
        seatByChannel.put(channel, claimed);
        if (previous != null) { seatByChannel.remove(previous); previous.close(); }
        changed();
        sendSnapshot(claimed, channel);
    }

    private static boolean isLeave(String text) {
        try { return "leave".equals(DeckLibrary.string(JsonParser.parseString(text).getAsJsonObject(), "type", "")); }
        catch (RuntimeException e) { return false; }
    }

    private void onOnlineDisconnect(Channel channel) {
        Seat seat = seatByChannel.remove(channel);
        if (seat == null || seat.channel != channel) return;
        seat.channel = null;
        seat.absentSince = System.nanoTime();
        changed();
    }

    /** The player has left for good: release whatever they hold so the table can continue, then concede. */
    private void abandon(Seat seat) {
        if (seat.gone) return;
        seat.gone = true;
        seat.gui.abandon();
        GuiBase.getInterface().invokeInEdtLater(() -> {
            IGameController controller = seat.gui.getGameController();
            if (controller != null) controller.concede();
            changed();
        });
        Channel current = seat.channel;
        if (current != null) current.close();
    }

    /**
     * Forge's concede only releases a waiting prompt when the game ends, so at a larger table the
     * departed player's mulligan or first-player choice would hold everyone up. Clear those through
     * the normal input calls, one per tick.
     */
    private void releaseAbandonedInput(Seat seat) {
        if (seat.releasing.getAndSet(true)) return;
        GuiBase.getInterface().invokeInEdtLater(() -> {
            try {
                if (!(seat.gui.getGameController() instanceof PlayerControllerHuman human)) return;
                var input = human.getInputQueue().getInput();
                if (input == null || input instanceof forge.gamemodes.match.input.InputLockUI) return;
                boolean ok, cancel;
                synchronized (seat.gui.prompt) {
                    ok = seat.gui.prompt.get("okEnabled").getAsBoolean();
                    cancel = seat.gui.prompt.get("cancelEnabled").getAsBoolean();
                }
                if (ok) human.selectButtonOk();
                else if (cancel) human.selectButtonCancel();
                else if (input instanceof forge.gamemodes.match.input.InputSelectEntitiesFromList<?> selection) {
                    for (var entity : selection.getValidChoices()) {
                        if (entity instanceof forge.game.player.Player player) human.selectPlayer(player.getView(), CLICK);
                        else if (entity instanceof forge.game.card.Card card) human.selectCard(card.getView(), null, CLICK);
                        break;
                    }
                }
            } finally {
                seat.releasing.set(false);
            }
        });
    }

    /** Names of online players the table is currently missing. */
    private JsonArray absentPlayers() {
        JsonArray names = new JsonArray();
        for (int index = 1; index < seats.size(); index++) {
            Seat seat = seats.get(index);
            if (seat.channel == null && !seat.gone) names.add(matchSetup.getAsJsonArray("remotes").get(index - 1).getAsJsonObject().get("name").getAsString());
        }
        return names;
    }

    private void applyProfile(LobbyPlayer player, JsonObject profile) throws Exception {
        JsonObject checked = MatchSetup.profile(profile);
        player.setName(checked.get("name").getAsString());
        player.setAvatarIndex(checked.get("avatar").getAsInt());
        String portrait = checked.get("portrait").getAsString();
        if (!portrait.isEmpty()) {
            String key = "forgeui:" + java.util.UUID.randomUUID();
            gui.portraits.put(key, portrait);
            player.setAvatarCardImageKey(key);
        } else player.setAvatarCardImageKey(null);
    }

    private void startCommanderGame(String deckName, String deckFile, int opponents, String testState, boolean installedOpponents) throws Exception {
        IStorage<Deck> decks = FModel.getDecks().getCommander();
        List<Deck> all = new ArrayList<>();
        decks.forEach(all::add);
        Deck selectedFile = null;
        if (deckFile != null) {
            File file = new File(deckFile);
            BridgeProtocol.require(file.isFile(), "Deck file does not exist: " + deckFile);
            selectedFile = DeckFiles.read(file);
            BridgeProtocol.require(selectedFile != null, "Cannot read the selected deck");
            if (!installedOpponents) all.clear();
            if (all.isEmpty()) all.add(selectedFile);
        }
        if (all.isEmpty()) {
            throw new IllegalStateException("No Commander decks found in " + forge.localinstance.properties.ForgeConstants.DECK_COMMANDER_DIR);
        }
        Deck mine = selectedFile != null ? selectedFile : deckName == null ? all.get(0) : decks.get(deckName);
        if (mine == null) {
            throw new IllegalArgumentException("No Commander deck named '" + deckName + "'. Have: " + decks.getItemNames());
        }
        System.out.println("Your deck: " + mine.getName());

        List<RegisteredPlayer> regs = new ArrayList<>();
        RegisteredPlayer human = RegisteredPlayer.forCommander(mine);
        human.setPlayer(GamePlayerUtil.getGuiPlayer());
        if (matchSetup != null) applyProfile(human.getPlayer(), matchSetup.getAsJsonObject("human"));
        regs.add(human);
        List<Deck> artworkDecks = new ArrayList<>();
        artworkDecks.add(mine);

        List<Deck> others = new ArrayList<>(all);
        others.remove(mine);
        if (others.isEmpty()) {
            others.add(mine);
        }
        BotDecks botDecks = null;
        for (int i = 0; i < opponents; i++) {
            Deck d = others.get(i % others.size());
            JsonObject settings = matchSetup == null ? null : matchSetup.getAsJsonArray("bots").get(i).getAsJsonObject();
            if (settings != null) {
                String mode = DeckLibrary.string(settings, "mode", "saved");
                if (mode.equals("generated")) {
                    System.out.println("Generating Commander deck for bot " + (i + 1));
                    d = forge.deck.DeckgenUtil.generateCommanderDeck(true, GameType.Commander);
                } else if (mode.equals("precon") || mode.equals("commander")) {
                    if (botDecks == null) botDecks = new BotDecks();
                    d = botDecks.create(mode, settings.get("deckId").getAsString());
                } else d = DeckFiles.read(new File(settings.get("deckFile").getAsString()));
                BridgeProtocol.require(d != null && forge.deck.DeckFormat.Commander.getDeckConformanceProblem(d) == null, "Bot " + (i + 1) + " needs a valid Commander deck");
            }
            RegisteredPlayer ai = RegisteredPlayer.forCommander(d);
            LobbyPlayer aiPlayer = GamePlayerUtil.createAiPlayer("AI " + (i + 1) + " (" + d.getName() + ")");
            if (settings != null) applyProfile(aiPlayer, settings);
            ai.setPlayer(aiPlayer);
            regs.add(ai);
            artworkDecks.add(d);
            System.out.println("Opponent " + (i + 1) + ": " + d.getName());
        }
        Map<RegisteredPlayer, forge.gui.interfaces.IGuiGame> guis = new java.util.LinkedHashMap<>();
        guis.put(human, gui);
        for (int i = 1; i < seats.size(); i++) {
            JsonObject settings = matchSetup.getAsJsonArray("remotes").get(i - 1).getAsJsonObject();
            Deck deck = DeckFiles.read(new File(settings.get("deckFile").getAsString()));
            BridgeProtocol.require(deck != null && forge.deck.DeckFormat.Commander.getDeckConformanceProblem(deck) == null, settings.get("name").getAsString() + " needs a valid Commander deck");
            RegisteredPlayer remote = RegisteredPlayer.forCommander(deck);
            LobbyPlayer remotePlayer = new forge.player.LobbyPlayerHuman(settings.get("name").getAsString());
            applyProfile(remotePlayer, settings);
            remote.setPlayer(remotePlayer);
            regs.add(remote);
            guis.put(remote, seats.get(i).gui);
            artworkDecks.add(deck);
            System.out.println("Online player " + i + ": " + remotePlayer.getName() + " with " + deck.getName());
        }

        try { prepareArtwork(artworkDecks); }
        catch (Exception e) { System.err.println("[artwork] Background manifest unavailable: " + e.getMessage()); }
        System.out.println("Decks ready: " + regs.size() + " players");
        HostedMatch match = GuiBase.getInterface().hostMatch();
        if (testState != null) {
            var prepared = new forge.game.GameState();
            try (var input = java.nio.file.Files.newInputStream(java.nio.file.Path.of(testState))) {
                prepared.parse(input);
            }
            match.setStartGameHook(() -> {
                prepared.applyToGame(match.getGame());
                match.getGame().updateTurnForView();
                match.getGame().updatePhaseForView();
                match.getGame().updatePlayerTurnForView();
                gui.pendingDraws.clear();
                changed();
                System.out.println("Test state applied: " + new File(testState).getName());
            });
        }
        // Forge's replay recorder runs a delta-sync serializer on the game thread and writes a
        // replay file per match. It is chosen once at game start, so switch it off only for that
        // call and restore the value. A blank player name makes Forge save preferences during
        // start; skip the switch then so the user's Forge settings are never persisted changed.
        var prefs = FModel.getPreferences();
        var replays = forge.localinstance.properties.ForgePreferences.FPref.UI_RECORD_REPLAYS;
        String recordReplays = prefs.getPref(replays);
        boolean skipReplay = !prefs.getPref(forge.localinstance.properties.ForgePreferences.FPref.PLAYER_NAME).isBlank();
        if (skipReplay) prefs.setPref(replays, false);
        try {
            match.startMatch(GameType.Commander, EnumSet.of(GameType.Commander), regs, guis);
        } finally {
            if (skipReplay) prefs.setPref(replays, recordReplays);
        }
        // Observe original events on the game thread. In-process protocol delta
        // batches share live views and need no UI-side replay of those events.
        match.getGame().subscribeToEvents(new Object() {
            @com.google.common.eventbus.Subscribe public void onEvent(forge.game.event.GameEvent event) {
                for (Seat seat : seats) seat.gui.trackDrawEvent(event);
                changed();
            }
        });
    }

    /** Publish only printing identities before shuffling; no player/zone assignment. */
    private void prepareArtwork(List<Deck> decks) throws Exception {
        if (artworkFile == null) return; // Standalone bridge tools retain their direct startup.
        var faces = new com.google.gson.JsonArray();
        var seen = new java.util.HashSet<String>();
        for (Deck deck : decks) for (var section : deck) for (var entry : section.getValue()) {
            var card = entry.getKey();
            if (!seen.add(DeckLibrary.key(card))) continue;
            JsonObject face = new JsonObject();
            face.addProperty("key", DeckLibrary.key(card));
            face.addProperty("name", card.getName());
            face.addProperty("imageKey", card.getImageKey(false));
            face.addProperty("manaValue", card.getRules().getManaCost().getCMC());
            face.addProperty("commander", section.getKey() == forge.deck.DeckSection.Commander);
            if (card.hasBackFace()) face.addProperty("backImageKey", card.getImageKey(true));
            faces.add(face);
        }
        var sections = new JsonObject(); sections.add("Main", faces);
        var manifest = new JsonObject(); manifest.add("sections", sections);
        var temporary = java.nio.file.Path.of(artworkFile + ".tmp");
        java.nio.file.Files.writeString(temporary, manifest.toString());
        java.nio.file.Files.move(temporary, artworkFile, java.nio.file.StandardCopyOption.REPLACE_EXISTING);
        timing("published " + faces.size() + " deck printings for background artwork warmup");
    }

    private void pushState() {
        for (Seat seat : seats) pushState(seat);
    }

    private boolean tableReady() {
        if (tableStarted) return true;
        for (Seat seat : seats) {
            if (!seat.gui.openAsks().isEmpty()
                    || (seat.gui.getGameController() instanceof PlayerControllerHuman human
                    && human.getInputQueue().getInput() != null
                    && !(human.getInputQueue().getInput() instanceof forge.gamemodes.match.input.InputLockUI))) {
                tableStarted = true;
                return true;
            }
        }
        return false;
    }

    /** Deliver a terminal event before closing sockets. No client should reconnect to an ended match. */
    private void endOnlineSession() {
        if (!sessionEnding.compareAndSet(false, true)) return;
        long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(1500);
        List<Channel> departing = new java.util.ArrayList<>();
        JsonObject event = new JsonObject();
        event.addProperty("type", "sessionEnded");
        event.addProperty("message", "The host ended the game.");
        for (Seat seat : seats) {
            if (!seat.online()) { if (server != null) server.broadcast(envelope(seat, event).toString()); continue; }
            Channel channel = seat.channel;
            if (channel != null && channel.isActive()) {
                channel.writeAndFlush(new io.netty.handler.codec.http.websocketx.TextWebSocketFrame(envelope(seat, event).toString()))
                        .awaitUninterruptibly(Math.max(0, TimeUnit.NANOSECONDS.toMillis(deadline - System.nanoTime())));
                departing.add(channel);
            }
        }
        // Godot can discard unread frames when the close handshake completes.
        // Let clients read sessionEnded and initiate their own close first.
        for (Channel channel : departing) channel.closeFuture().awaitUninterruptibly(
                Math.max(0, TimeUnit.NANOSECONDS.toMillis(deadline - System.nanoTime())));
    }

    private void pushState(Seat seat) {
        try {
            if (sessionEnding.get()) return;
            if (seat.online() && !seat.gone && seat.channel == null && System.nanoTime() - seat.absentSince > ABSENT_LIMIT_NANOS) abandon(seat);
            if (seat.gone) { releaseAbandonedInput(seat); return; }
            // Continue an authorized undo even if no further engine events arrive.
            seat.gui.advanceLandUndo();
            // An absent player gets a fresh snapshot when they reconnect; don't build for nobody.
            if (seat.online() && seat.channel == null) return;
            if (!seat.dirty.getAndSet(false)) return;
            long currentRevision = seat.revision.get();
            long buildStart = System.nanoTime();
            Map<Integer, CardView> cards = new HashMap<>();
            Map<Integer, PlayerView> players = new HashMap<>();
            Map<Integer, StackItemView> stackItems = new HashMap<>();
            GameStateJson builder = new GameStateJson(seat.gui, cards, players, stackItems);
            JsonObject state = stamp(seat, builder.build());
            state.addProperty("tableReady", tableReady());
            JsonObject toss = startingToss;
            if (toss != null) state.add("startingToss", toss.deepCopy());
            state.addProperty("revision", currentRevision);
            if (seats.size() > 1) state.add("absentPlayers", absentPlayers());
            synchronized (publicationLock) {
                if (seat.revision.get() != currentRevision) { seat.dirty.set(true); stats.discard(); return; }
                String json = state.toString();
                Snapshot previous = seat.snapshot;
                seat.snapshot = new Snapshot(currentRevision, json, Map.copyOf(cards), Map.copyOf(players), Map.copyOf(stackItems), builder.input);
                boolean changedJson = previous == null || !json.equals(previous.json());
                if (changedJson) seat.publish(json);
                stats.record(System.nanoTime() - buildStart, json.length(), changedJson);
            }
            if (!seat.online()) logFirstSnapshots(state);
            stats.report(false);
        } catch (RuntimeException e) {
            // The engine mutates views on its own thread; a torn read just means try again next tick.
            seat.dirty.set(true);
            long now = System.nanoTime();
            if (now - lastSnapshotWarning > TimeUnit.SECONDS.toNanos(5)) {
                lastSnapshotWarning = now;
                System.err.println("[bridge] Retrying snapshot after " + e.getClass().getSimpleName());
            }
        }
    }

    /** The first game snapshot, then the first one with a real prompt or decision (the table can reveal). */
    private void logFirstSnapshots(JsonObject state) {
        if (firstPromptLogged || state.has("loading")) return;
        long total = System.currentTimeMillis() - launchEpoch;
        if (!firstGameLogged) { firstGameLogged = true; timing("first game snapshot " + total + " ms after launch request"); }
        JsonObject prompt = state.getAsJsonObject("prompt");
        String input = prompt != null && prompt.has("inputKind") ? prompt.get("inputKind").getAsString() : "";
        boolean asks = state.has("asks") && state.getAsJsonArray("asks").size() > 0;
        if (asks || !(input.isEmpty() || input.equals("InputLockUI"))) {
            firstPromptLogged = true;
            timing("first playable prompt (" + (asks ? "decision" : input) + ") " + total + " ms after launch request");
        }
    }

    private void sendSnapshot(Seat seat, Channel channel) {
        synchronized (publicationLock) {
            Snapshot current = seat.snapshot;
            if (current != null && current.revision() == seat.revision.get()) server.send(channel, current.json());
            seat.dirty.set(true);
        }
    }

    private void reply(Seat seat, Channel channel, String type, String requestId, String code, String message) {
        JsonObject response = new JsonObject();
        response.addProperty("type", type);
        if (requestId != null) response.addProperty("requestId", requestId);
        response.addProperty("code", code);
        response.addProperty("message", message);
        server.send(channel, envelope(seat, response).toString());
    }

    private void onClientMessage(Seat seat, Channel channel, String text) {
        String requestId = null;
        try {
            JsonObject msg = JsonParser.parseString(text).getAsJsonObject();
            String type = BridgeProtocol.string(msg, "type");
            if (type.equals("hello")) { sendSnapshot(seat, channel); return; }
            requestId = BridgeProtocol.string(msg, "requestId");
            BridgeProtocol.require(!requestId.isBlank() && requestId.length() <= 128, "Invalid requestId");
            BridgeProtocol.require(BridgeProtocol.integer(msg.get("protocolVersion")) == BridgeProtocol.VERSION, "Unsupported protocol version");
            if (!sessionId.equals(BridgeProtocol.string(msg, "sessionId"))) {
                reply(seat, channel, "error", requestId, "stale_session", "Request belongs to a different bridge session");
                sendSnapshot(seat, channel);
                return;
            }
            if (type.equals("shutdown")) {
                BridgeProtocol.require(!seat.online(), "Only the host service can end this session");
                BridgeProtocol.revision(msg.get("revision"));
                var shutdown = new Thread(() -> { endOnlineSession(); System.exit(0); }, "owned-match-stop");
                shutdown.setDaemon(true);
                shutdown.start();
                return;
            }
            BridgeProtocol.require(!sessionEnding.get(), "This session has ended");
            if (type.equals("answer")) {
                seat.gui.answer(BridgeProtocol.integer(msg.get("id")), msg.get("value"));
                reply(seat, channel, "ack", requestId, "answered", "Answer accepted");
                return;
            }
            BridgeProtocol.require(type.equals("action"), "Unknown message type");
            dispatchAction(seat, channel, requestId, msg);
        } catch (IllegalArgumentException e) {
            reply(seat, channel, "error", requestId, "invalid_request", e.getMessage());
        } catch (RuntimeException e) {
            reply(seat, channel, "error", requestId, "invalid_request", "Malformed request");
        }
    }

    private void dispatchAction(Seat seat, Channel channel, String requestId, JsonObject msg) {
        BridgeGuiGame gui = seat.gui; // This seat's own controller and permissions, never the host's.
        String action = BridgeProtocol.string(msg, "action");
        BridgeProtocol.require(List.of("ok", "cancel", "card", "equip", "player", "attack", "undeclare", "phase_stop", "stack", "mana", "undo", "undo_card", "undo_tap", "draw_ack", "concede").contains(action), "Unknown action");
        int id = msg.has("id") ? BridgeProtocol.integer(msg.get("id")) : -1;
        int target = List.of("attack", "equip").contains(action) ? BridgeProtocol.integer(msg.get("target")) : -1;
        long expectedRevision = BridgeProtocol.revision(msg.get("revision"));
        GuiBase.getInterface().invokeInEdtLater(() -> {
          try {
            Snapshot current = seat.snapshot;
            if (current == null || (!action.equals("phase_stop") && (current.revision() != expectedRevision || seat.revision.get() != expectedRevision))) {
                reply(seat, channel, "error", requestId, "stale_state", "State changed; review the latest snapshot before acting");
                sendSnapshot(seat, channel);
                return;
            }
            IGameController c = gui.getGameController();
            BridgeProtocol.require(c != null, "Game controller is not ready");
            BridgeProtocol.require(!gui.isLandUndoPending() || action.equals("concede"), "Wait for the land return to finish");
            if (action.equals("phase_stop")) {
                BridgeProtocol.require(current.players().containsKey(id), "Player is no longer available");
                var phase = forge.game.phase.PhaseType.valueOf(BridgeProtocol.string(msg, "phase"));
                BridgeProtocol.require(phase != forge.game.phase.PhaseType.UNTAP, "Untap has no priority stop");
                var enabled = msg.get("enabled");
                BridgeProtocol.require(enabled != null && enabled.isJsonPrimitive() && enabled.getAsJsonPrimitive().isBoolean(), "enabled must be a boolean");
                gui.setPhaseStop(current.players().get(id), phase, enabled.getAsBoolean());
                changed();
                reply(seat, channel, "ack", requestId, "configured", "Phase stop updated");
                return;
            }
            BridgeProtocol.require(gui.openAsks().isEmpty(), "Answer the pending decision first");
            if (!action.equals("concede") && !action.equals("draw_ack")) {
                BridgeProtocol.require(current.input() != null && current.input() == gui.currentInput()
                        && gui.hasCurrentPrompt(current.input()), "Wait for your current Forge input");
            }
            if (action.equals("draw_ack")) BridgeProtocol.require(gui.pendingDraws.contains(id), "That draw is no longer pending");
            else if (!action.equals("concede")) BridgeProtocol.require(gui.pendingDraws.isEmpty(), "Take the pending draw from your library first");
            if (action.equals("card") || action.equals("undeclare")) BridgeProtocol.require(current.cards().containsKey(id), "Card is no longer available");
            if (action.equals("undeclare")) {
                BridgeProtocol.require(c instanceof PlayerControllerHuman human
                        && human.getInputQueue().getInput() instanceof forge.gamemodes.match.input.InputAttack, "Attackers can only be called back while declaring attackers");
                var human = (PlayerControllerHuman)c;
                var attacker = human.getGame().findByView(current.cards().get(id));
                var combat = human.getGame().getCombat();
                BridgeProtocol.require(attacker != null && combat != null && combat.getAttackers().contains(attacker)
                        && attacker.getController().equals(human.getPlayer()), "That creature is not one of your declared attackers");
            }
            if (action.equals("player")) BridgeProtocol.require(current.players().containsKey(id), "Player is no longer available");
            if (action.equals("stack")) BridgeProtocol.require(current.stackItems().containsKey(id), "Stack item is no longer available");
            if (action.equals("mana")) BridgeProtocol.manaColor(id);
            if (action.equals("undo_card")) BridgeProtocol.require(gui.mayReturnToHand(current.cards().get(id)), "That card's play can no longer be undone");
            if (action.equals("undo_tap")) BridgeProtocol.require(gui.mayUndoTap(current.cards().get(id)), "That mana tap can no longer be undone");
            if (action.equals("equip")) BridgeProtocol.require(current.cards().containsKey(id) && current.cards().containsKey(target)
                    && gui.canEquip(current.cards().get(id), current.cards().get(target)), "That equipment cannot equip that creature now");
            if (action.equals("attack")) {
                BridgeProtocol.require(current.cards().containsKey(id) && current.players().containsKey(target), "Attacker or defending player is no longer available");
                BridgeProtocol.require(c instanceof PlayerControllerHuman human
                        && human.getInputQueue().getInput() instanceof forge.gamemodes.match.input.InputAttack, "Choose attackers during the declare attackers input");
                var human = (PlayerControllerHuman)c;
                var attacker = human.getGame().findByView(current.cards().get(id));
                var defender = human.getGame().getPlayer(current.players().get(target));
                var combat = human.getGame().getCombat();
                BridgeProtocol.require(attacker != null && attacker.isInPlay() && attacker.isCreature()
                        && attacker.getController().equals(human.getPlayer()), "Choose one of your battlefield creatures");
                BridgeProtocol.require(defender != null && combat != null && combat.getDefenders().contains(defender), "That player cannot be attacked");
                BridgeProtocol.require(forge.game.combat.CombatUtil.canAttack(attacker, defender), "That creature cannot attack that player");
            }
            if (action.equals("ok") || action.equals("cancel")) {
                synchronized (gui.prompt) {
                    BridgeProtocol.require(gui.prompt.get(action.equals("ok") ? "okEnabled" : "cancelEnabled").getAsBoolean(), "Button is disabled");
                }
            }
            // Consume this revision so two queued clicks cannot both use the same input state.
            if (!seat.revision.compareAndSet(expectedRevision, expectedRevision + 1)) {
                reply(seat, channel, "error", requestId, "stale_state", "State changed before the action could run");
                sendSnapshot(seat, channel);
                return;
            }
            seat.dirty.set(true);
            // Track an attempted land play without discarding the previous one
            // when a harmless/invalid selection does not change the game.
            CardView clicked = action.equals("card") ? current.cards().get(id) : null;
            if (!action.equals("undo_card") && !action.equals("undo") && !action.equals("phase_stop")) gui.commitAcceptedTakeback();
            if (clicked != null && clicked.getZone() == ZoneType.Hand
                    && clicked.getCurrentState().isLand()
                    && clicked.getController() != null && clicked.getController().equals(gui.getCurrentPlayer())) gui.noteLandPlay(clicked);
            if (clicked != null && clicked.getController() != null && clicked.getController().equals(gui.getCurrentPlayer())) gui.noteSpellAttempt(clicked);
            switch (action) {
                case "ok" -> c.selectButtonOk();
                case "cancel" -> c.selectButtonCancel();
                case "card" -> {
                    CardView cv = current.cards().get(id);
                    if (cv != null) BridgeProtocol.require(c.selectCard(cv, null, CLICK), "Forge rejected that card for the current action");
                }
                case "undeclare" -> BridgeProtocol.require(c.selectCard(current.cards().get(id), null, RIGHT_CLICK), "Forge rejected calling back that attacker");
                case "equip" -> BridgeProtocol.require(gui.selectEquip(current.cards().get(id), current.cards().get(target), CLICK), "Forge rejected that equip activation");
                case "player" -> {
                    PlayerView pv = current.players().get(id);
                    if (pv != null) c.selectPlayer(pv, CLICK);
                }
                case "attack" -> {
                    var human = (PlayerControllerHuman)c;
                    CardView attacker = current.cards().get(id);
                    PlayerView defender = current.players().get(target);
                    c.selectPlayer(defender, CLICK);
                    // Re-selecting the same defender keeps the declaration instead of toggling it off.
                    if (!human.getGame().getCombat().isAttacking(human.getGame().findByView(attacker), human.getGame().getPlayer(defender)))
                        BridgeProtocol.require(c.selectCard(attacker, null, CLICK), "Forge rejected that attacker");
                }
                case "stack" -> {
                    StackItemView si = current.stackItems().get(id);
                    if (si != null) c.selectStackItem(si);
                }
                case "mana" -> c.useMana(BridgeProtocol.manaColor(id));
                case "undo" -> {
                    CardView takeback = gui.takebackCard();
                    if (takeback != null) BridgeProtocol.require(gui.returnLandToHand(takeback), "Forge cannot undo that cast now");
                    else c.undoLastAction();
                }
                case "undo_card" -> BridgeProtocol.require(gui.returnLandToHand(current.cards().get(id)), "Forge cannot undo that play now");
                case "undo_tap" -> BridgeProtocol.require(gui.undoManaTap(current.cards().get(id)), "Forge cannot undo that mana tap now");
                case "draw_ack" -> gui.pendingDraws.remove(id);
                case "concede" -> c.concede();
            }
            reply(seat, channel, "ack", requestId, "dispatched", "Action sent to Forge; await authoritative state");
          } catch (IllegalArgumentException e) {
            reply(seat, channel, "error", requestId, "invalid_action", e.getMessage());
          } catch (RuntimeException e) {
            reply(seat, channel, "error", requestId, "action_failed", "Forge could not process the action");
          } finally {
            seat.dirty.set(true);
          }
        });
    }
}
