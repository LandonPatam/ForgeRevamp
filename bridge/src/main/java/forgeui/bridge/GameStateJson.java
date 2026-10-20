package forgeui.bridge;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import forge.card.MagicColor;
import forge.game.GameEntityView;
import forge.game.GameView;
import forge.game.card.CardView;
import forge.game.card.CardView.CardStateView;
import forge.game.card.CounterType;
import forge.game.combat.CombatView;
import forge.game.player.PlayerView;
import forge.game.spellability.StackItemView;
import forge.game.zone.ZoneType;
import forge.gamemodes.match.Selection;
import forge.trackable.TrackableObject;

import java.util.List;
import java.util.Map;

/**
 * Full snapshot of what the local player may see, as JSON. Hidden cards are sent as id-only stubs.
 * Also fills the id lookups the action handler uses to turn client ids back into views.
 */
final class GameStateJson {
    private static final ZoneType[] VISIBLE_ZONES = {
            ZoneType.Battlefield, ZoneType.Hand, ZoneType.Graveyard, ZoneType.Exile, ZoneType.Command
    };
    private static final byte[] MANA = {MagicColor.WHITE, MagicColor.BLUE, MagicColor.BLACK, MagicColor.RED, MagicColor.GREEN, MagicColor.COLORLESS};
    private static final String[] MANA_KEYS = {"W", "U", "B", "R", "G", "C"};

    private final BridgeGuiGame gui;
    private final Map<Integer, CardView> cards;
    private final Map<Integer, PlayerView> players;
    private final Map<Integer, StackItemView> stackItems;

    GameStateJson(BridgeGuiGame gui, Map<Integer, CardView> cards, Map<Integer, PlayerView> players, Map<Integer, StackItemView> stackItems) {
        this.gui = gui;
        this.cards = cards;
        this.players = players;
        this.stackItems = stackItems;
    }

    JsonObject build() {
        GameView gv = gui.getGameView();
        JsonObject root = new JsonObject();
        root.addProperty("type", "state");
        if (gv == null) {
            root.addProperty("loading", true);
            return root;
        }
        PlayerView me = gui.getCurrentPlayer();
        root.addProperty("me", me == null ? -1 : me.getId());

        JsonObject game = new JsonObject();
        game.addProperty("turn", gv.getTurn());
        game.addProperty("phase", gv.getPhase() == null ? "" : gv.getPhase().nameForUi);
        game.addProperty("activePlayer", gv.getPlayerTurn() == null ? -1 : gv.getPlayerTurn().getId());
        game.addProperty("mulligan", gv.isMulligan());
        game.addProperty("gameOver", gv.isGameOver());
        if (gv.isGameOver()) {
            game.addProperty("winner", gv.getWinningPlayerName());
        }
        root.add("game", game);

        JsonArray ps = new JsonArray();
        for (PlayerView p : gv.getPlayers()) {
            players.put(p.getId(), p);
            ps.add(player(p, gv));
        }
        root.add("players", ps);

        JsonArray stack = new JsonArray();
        if (gv.getStack() != null) {
            for (StackItemView si : gv.getStack()) {
                stackItems.put(si.getId(), si);
                JsonObject o = new JsonObject();
                o.addProperty("id", si.getId());
                o.addProperty("text", si.getText());
                if (si.getSourceCard() != null) {
                    o.addProperty("sourceId", si.getSourceCard().getId());
                    o.addProperty("sourceName", si.getSourceCard().getName());
                }
                if (si.getActivatingPlayer() != null) {
                    o.addProperty("controller", si.getActivatingPlayer().getId());
                }
                stack.add(o);
            }
        }
        root.add("stack", stack);

        JsonArray combat = new JsonArray();
        CombatView cv = gv.getCombat();
        if (cv != null) {
            for (CardView attacker : cv.getAttackers()) {
                JsonObject o = new JsonObject();
                o.addProperty("attacker", attacker.getId());
                GameEntityView def = cv.getDefender(attacker);
                o.addProperty("defender", def == null ? "" : def.toString());
                JsonArray blockers = new JsonArray();
                if (cv.getBlockers(attacker) != null) {
                    cv.getBlockers(attacker).forEach(b -> blockers.add(b.getId()));
                }
                o.add("blockers", blockers);
                combat.add(o);
            }
        }
        root.add("combat", combat);

        JsonObject prompt;
        synchronized (gui.prompt) {
            prompt = gui.prompt.deepCopy();
        }
        Selection sel = gui.getSelection();
        prompt.add("selectable", ids(sel.cards()));
        prompt.add("targets", refs(sel.targets()));
        prompt.add("chosen", refs(sel.chosen()));
        prompt.addProperty("selMin", sel.min());
        prompt.addProperty("selMax", sel.max());
        root.add("prompt", prompt);

        JsonArray log = new JsonArray();
        if (gv.getGameLog() != null) {
            gv.getGameLog().getLogEntries(null).stream().limit(40).forEach(e -> log.add(e.toString()));
        }
        root.add("log", log);
        root.add("asks", toArray(gui.openAsks()));
        return root;
    }

    private JsonObject player(PlayerView p, GameView gv) {
        JsonObject o = new JsonObject();
        o.addProperty("id", p.getId());
        o.addProperty("name", p.getName());
        o.addProperty("life", p.getLife());
        o.addProperty("ai", p.isAI());
        o.addProperty("lost", p.getHasLost());
        o.addProperty("priority", p.getHasPriority());
        o.addProperty("libraryCount", p.getZoneSize(ZoneType.Library));
        o.addProperty("handCount", p.getZoneSize(ZoneType.Hand));
        o.add("counters", counters(p.getCounters()));

        JsonObject mana = new JsonObject();
        for (int i = 0; i < MANA.length; i++) {
            int n = p.getMana(MANA[i]);
            if (n > 0) mana.addProperty(MANA_KEYS[i], n);
        }
        o.add("mana", mana);

        // Commander damage this player has taken, per enemy commander
        JsonArray cmdDmg = new JsonArray();
        for (PlayerView other : gv.getPlayers()) {
            if (other.getCommanders() == null) continue;
            for (CardView cmd : other.getCommanders()) {
                int dmg = p.getCommanderDamage(cmd);
                if (dmg > 0) {
                    JsonObject d = new JsonObject();
                    d.addProperty("commanderId", cmd.getId());
                    d.addProperty("name", cmd.getName());
                    d.addProperty("amount", dmg);
                    cmdDmg.add(d);
                }
            }
        }
        o.add("commanderDamage", cmdDmg);

        JsonObject zones = new JsonObject();
        for (ZoneType z : VISIBLE_ZONES) {
            JsonArray arr = new JsonArray();
            if (p.getCards(z) != null) {
                for (CardView c : p.getCards(z)) {
                    arr.add(card(c));
                }
            }
            zones.add(z.name(), arr);
        }
        o.add("zones", zones);
        return o;
    }

    private JsonObject card(CardView c) {
        cards.put(c.getId(), c);
        JsonObject o = new JsonObject();
        o.addProperty("id", c.getId());
        if (!gui.mayView(c)) {
            o.addProperty("hidden", true);
            return o;
        }
        CardStateView s = c.getCurrentState();
        o.addProperty("name", c.getName());
        o.addProperty("tapped", c.isTapped());
        o.addProperty("sick", c.isSick());
        o.addProperty("token", c.isToken());
        o.addProperty("commander", c.isCommander());
        o.addProperty("faceDown", c.isFaceDown());
        if (c.getController() != null) o.addProperty("controller", c.getController().getId());
        if (s != null) {
            o.addProperty("manaCost", s.getManaCost() == null ? "" : s.getManaCost().toString());
            o.addProperty("typeLine", s.getType() == null ? "" : s.getType().toString());
            if (s.isCreature()) {
                o.addProperty("power", s.getPower());
                o.addProperty("toughness", s.getToughness());
            }
            if (s.isPlaneswalker()) o.addProperty("loyalty", s.getLoyalty());
            o.addProperty("imageKey", s.getImageKey());
        }
        try {
            o.addProperty("text", c.getText());
        } catch (RuntimeException e) {
            o.addProperty("text", "");
        }
        if (c.getDamage() > 0) o.addProperty("damage", c.getDamage());
        o.add("counters", counters(c.getCounters()));
        if (c.getAttachedTo() != null) o.addProperty("attachedTo", c.getAttachedTo().getId());
        return o;
    }

    private static JsonObject counters(Iterable<CounterType> multiset) {
        JsonObject o = new JsonObject();
        if (multiset instanceof com.google.common.collect.Multiset<CounterType> ms) {
            for (com.google.common.collect.Multiset.Entry<CounterType> e : ms.entrySet()) {
                o.addProperty(e.getElement().toString(), e.getCount());
            }
        }
        return o;
    }

    private static JsonArray ids(List<? extends TrackableObject> objs) {
        JsonArray a = new JsonArray();
        if (objs != null) {
            for (TrackableObject t : objs) {
                if (t != null) a.add(t.getId());
            }
        }
        return a;
    }

    /** Ids tagged with their kind, since card, player and stack ids can collide. */
    private static JsonArray refs(List<? extends TrackableObject> objs) {
        JsonArray a = new JsonArray();
        if (objs != null) {
            for (TrackableObject t : objs) {
                if (t == null) continue;
                String kind = t instanceof PlayerView ? "player" : t instanceof StackItemView ? "stack" : "card";
                a.add(kind + ":" + t.getId());
            }
        }
        return a;
    }

    private static JsonArray toArray(List<JsonObject> list) {
        JsonArray a = new JsonArray();
        list.forEach(a::add);
        return a;
    }
}
