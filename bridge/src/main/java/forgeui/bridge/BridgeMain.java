package forgeui.bridge;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import forge.LobbyPlayer;
import forge.deck.Deck;
import forge.game.GameType;
import forge.game.card.CardView;
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

import java.io.File;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

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

    private final Map<Integer, CardView> cards = new ConcurrentHashMap<>();
    private final Map<Integer, PlayerView> players = new ConcurrentHashMap<>();
    private final Map<Integer, StackItemView> stackItems = new ConcurrentHashMap<>();
    private final AtomicBoolean dirty = new AtomicBoolean(true);
    private BridgeServer server;
    private BridgeGuiGame gui;
    private volatile String lastState;

    public static void main(String[] args) throws Exception {
        String assets = "../forge/forge-gui";
        int port = 7777;
        String deckName = null;
        int opponents = 3;
        for (int i = 0; i + 1 < args.length; i += 2) {
            switch (args[i]) {
                case "--assets" -> assets = args[i + 1];
                case "--port" -> port = Integer.parseInt(args[i + 1]);
                case "--deck" -> deckName = args[i + 1];
                case "--opponents" -> opponents = Integer.parseInt(args[i + 1]);
                default -> throw new IllegalArgumentException("Unknown option " + args[i]);
            }
        }
        System.setProperty("java.awt.headless", "true");
        System.setProperty("java.util.Arrays.useLegacyMergeSort", "true");
        new BridgeMain().run(new File(assets).getCanonicalPath(), port, deckName, opponents);
    }

    private void run(String assets, int port, String deckName, int opponents) throws Exception {
        GuiBase.setInterface(new HeadlessGuiBase(assets));
        System.out.println("Loading Forge from " + assets + " ...");
        FModel.initialize(null, null);

        gui = new BridgeGuiGame(new BridgeGuiGame.Listener() {
            @Override public void stateChanged() { dirty.set(true); }
            @Override public void send(JsonObject message) {
                server.broadcast(message.toString());
                dirty.set(true);
            }
        });

        server = new BridgeServer(port, this::onClientMessage, () -> dirty.set(true));
        server.start();
        ScheduledExecutorService pump = Executors.newSingleThreadScheduledExecutor(r -> {
            Thread t = new Thread(r, "bridge-state");
            t.setDaemon(true);
            return t;
        });
        pump.scheduleWithFixedDelay(this::pushState, 100, 60, TimeUnit.MILLISECONDS);
        System.out.println("Bridge ready: http://127.0.0.1:" + port + "/");

        startCommanderGame(deckName, opponents);
        Thread.currentThread().join(); // keep running; the game lives on Forge's threads
    }

    private void startCommanderGame(String deckName, int opponents) {
        IStorage<Deck> decks = FModel.getDecks().getCommander();
        List<Deck> all = new ArrayList<>();
        decks.forEach(all::add);
        if (all.isEmpty()) {
            throw new IllegalStateException("No Commander decks found in " + forge.localinstance.properties.ForgeConstants.DECK_COMMANDER_DIR);
        }
        Deck mine = deckName == null ? all.get(0) : decks.get(deckName);
        if (mine == null) {
            throw new IllegalArgumentException("No Commander deck named '" + deckName + "'. Have: " + decks.getItemNames());
        }
        System.out.println("Your deck: " + mine.getName());

        List<RegisteredPlayer> regs = new ArrayList<>();
        RegisteredPlayer human = RegisteredPlayer.forCommander(mine);
        human.setPlayer(GamePlayerUtil.getGuiPlayer());
        regs.add(human);

        List<Deck> others = new ArrayList<>(all);
        others.remove(mine);
        if (others.isEmpty()) {
            others.add(mine);
        }
        for (int i = 0; i < opponents; i++) {
            Deck d = others.get(i % others.size());
            RegisteredPlayer ai = RegisteredPlayer.forCommander(d);
            LobbyPlayer aiPlayer = GamePlayerUtil.createAiPlayer("AI " + (i + 1) + " (" + d.getName() + ")");
            ai.setPlayer(aiPlayer);
            regs.add(ai);
            System.out.println("Opponent " + (i + 1) + ": " + d.getName());
        }

        HostedMatch match = GuiBase.getInterface().hostMatch();
        match.startMatch(GameType.Commander, EnumSet.of(GameType.Commander), regs, human, gui);
    }

    private void pushState() {
        if (!dirty.getAndSet(false)) {
            return;
        }
        try {
            String json = new GameStateJson(gui, cards, players, stackItems).build().toString();
            if (!json.equals(lastState)) {
                lastState = json;
                server.broadcast(json);
            }
        } catch (RuntimeException e) {
            // The engine mutates views on its own thread; a torn read just means try again next tick.
            dirty.set(true);
        }
    }

    private void onClientMessage(String text) {
        JsonObject msg = JsonParser.parseString(text).getAsJsonObject();
        String type = msg.get("type").getAsString();
        if (type.equals("hello")) {
            dirty.set(true);
            lastState = null; // force a full resend to the new client
            return;
        }
        if (type.equals("answer")) {
            gui.answer(msg.get("id").getAsInt(), msg.get("value"));
            return;
        }
        if (!type.equals("action")) {
            return;
        }
        String action = msg.get("action").getAsString();
        int id = msg.has("id") ? msg.get("id").getAsInt() : -1;
        GuiBase.getInterface().invokeInEdtLater(() -> {
            IGameController c = gui.getGameController();
            if (c == null) {
                return;
            }
            switch (action) {
                case "ok" -> c.selectButtonOk();
                case "cancel" -> c.selectButtonCancel();
                case "card" -> {
                    CardView cv = cards.get(id);
                    if (cv != null) c.selectCard(cv, null, CLICK);
                }
                case "player" -> {
                    PlayerView pv = players.get(id);
                    if (pv != null) c.selectPlayer(pv, CLICK);
                }
                case "stack" -> {
                    StackItemView si = stackItems.get(id);
                    if (si != null) c.selectStackItem(si);
                }
                case "mana" -> c.useMana((byte) id);
                case "undo" -> c.undoLastAction();
                case "concede" -> c.concede();
                default -> System.err.println("Unknown action " + action);
            }
            dirty.set(true);
        });
    }
}
