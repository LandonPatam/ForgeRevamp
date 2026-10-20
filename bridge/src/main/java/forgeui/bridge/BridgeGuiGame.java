package forgeui.bridge;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import forge.LobbyPlayer;
import forge.deck.CardPool;
import forge.game.GameEntityView;
import forge.game.card.CardView;
import forge.game.event.GameEvent;
import forge.game.phase.PhaseType;
import forge.game.player.DelayedReveal;
import forge.game.player.IHasIcon;
import forge.game.player.PlayerView;
import forge.game.spellability.SpellAbilityView;
import forge.game.spellability.StackItemView;
import forge.gamemodes.match.AbstractGuiGame;
import forge.item.PaperCard;
import forge.localinstance.properties.ForgePreferences;
import forge.localinstance.properties.ForgePreferences.FPref;
import forge.localinstance.skin.FSkinProp;
import forge.model.FModel;
import forge.trackable.TrackableCollection;
import forge.util.FSerializableFunction;
import forge.util.ITriggerEvent;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * The bridge's {@link forge.gui.interfaces.IGuiGame}: everything the engine asks of the UI.
 *
 * <p>Two kinds of interaction reach a player:
 * <ul>
 *   <li><b>Inputs</b> (priority, targeting, attackers, paying mana): the engine sets a prompt message,
 *   button labels and selectable cards, then waits for a click. Those are kept as {@link #prompt}
 *   state and answered through {@link forge.interfaces.IGameController}.</li>
 *   <li><b>Asks</b> (every blocking dialog method below): the calling thread waits until the client
 *   answers. All of them go through a few generic shapes ({@code choose}, {@code order},
 *   {@code distribute}, {@code input}, {@code message}) so any prompt is answerable before it has a
 *   custom UI.</li>
 * </ul>
 */
final class BridgeGuiGame extends AbstractGuiGame {
    interface Listener {
        void stateChanged();
        void send(JsonObject message);
    }

    private final Listener listener;
    private final AtomicInteger askIds = new AtomicInteger();
    private final Map<Integer, CompletableFuture<JsonElement>> pending = new ConcurrentHashMap<>();
    /** Open asks, in order, so a client that (re)connects sees them. */
    private final Map<Integer, JsonObject> openAsks = new ConcurrentHashMap<>();

    final JsonObject prompt = new JsonObject();
    volatile boolean finished;

    BridgeGuiGame(Listener listener) {
        this.listener = listener;
        prompt.addProperty("message", "");
        setButtons("OK", "Cancel", false, false);
    }

    List<JsonObject> openAsks() {
        List<JsonObject> list = new ArrayList<>();
        openAsks.keySet().stream().sorted().forEach(id -> list.add(openAsks.get(id)));
        return list;
    }

    /** A client answered an ask. */
    void answer(int id, JsonElement value) {
        CompletableFuture<JsonElement> f = pending.get(id);
        if (f != null) {
            f.complete(value);
        }
    }

    // ---------------------------------------------------------------- asks

    private JsonElement ask(JsonObject ask) {
        int id = askIds.incrementAndGet();
        ask.addProperty("type", "ask");
        ask.addProperty("id", id);
        CompletableFuture<JsonElement> f = new CompletableFuture<>();
        pending.put(id, f);
        openAsks.put(id, ask);
        listener.send(ask);
        try {
            return f.get();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new RuntimeException(e);
        } catch (ExecutionException e) {
            throw new RuntimeException(e);
        } finally {
            pending.remove(id);
            openAsks.remove(id);
            JsonObject closed = new JsonObject();
            closed.addProperty("type", "askClosed");
            closed.addProperty("id", id);
            listener.send(closed);
        }
    }

    private static JsonObject newAsk(String kind, String title, String message) {
        JsonObject a = new JsonObject();
        a.addProperty("kind", kind);
        a.addProperty("title", title == null ? "" : title);
        a.addProperty("message", message == null ? "" : message);
        return a;
    }

    private static <T> JsonArray options(List<T> items, FSerializableFunction<T, String> display) {
        JsonArray arr = new JsonArray();
        for (T item : items) {
            arr.add(option(item, display));
        }
        return arr;
    }

    @SuppressWarnings("unchecked")
    private static <T> JsonObject option(T item, FSerializableFunction<T, String> display) {
        JsonObject o = new JsonObject();
        String label;
        if (display != null) {
            label = display.apply(item);
        } else if (item instanceof CardView cv) {
            label = cv.getName();
        } else if (item instanceof PlayerView pv) {
            label = pv.getName();
        } else if (item instanceof StackItemView si) {
            label = si.getText();
        } else {
            label = String.valueOf(item);
        }
        o.addProperty("label", label);
        if (item instanceof CardView cv) {
            o.addProperty("cardId", cv.getId());
        } else if (item instanceof PlayerView pv) {
            o.addProperty("playerId", pv.getId());
        }
        return o;
    }

    /** Generic pick: returns the chosen indices. */
    private List<Integer> choose(String title, String message, int min, int max, JsonArray options, List<Integer> preselected) {
        JsonObject a = newAsk("choose", title, message);
        a.addProperty("min", min);
        a.addProperty("max", max);
        a.add("options", options);
        JsonArray pre = new JsonArray();
        if (preselected != null) {
            preselected.forEach(pre::add);
        }
        a.add("selected", pre);
        JsonElement res = ask(a);
        List<Integer> picked = new ArrayList<>();
        if (res != null && res.isJsonArray()) {
            for (JsonElement e : res.getAsJsonArray()) {
                int i = e.getAsInt();
                if (i >= 0 && i < options.size() && !picked.contains(i)) {
                    picked.add(i);
                }
            }
        }
        return picked;
    }

    private int chooseOne(String title, String message, List<String> labels, int defaultIndex) {
        JsonArray opts = new JsonArray();
        for (String l : labels) {
            JsonObject o = new JsonObject();
            o.addProperty("label", l);
            opts.add(o);
        }
        List<Integer> picked = choose(title, message, 1, 1, opts, defaultIndex >= 0 ? List.of(defaultIndex) : null);
        return picked.isEmpty() ? defaultIndex : picked.get(0);
    }

    @Override
    public <T> List<T> getChoices(String message, int min, int max, List<T> choices, List<T> selected, FSerializableFunction<T, String> display) {
        if (choices == null || choices.isEmpty()) {
            return new ArrayList<>();
        }
        if (min == -1 && max == -1) {
            // reveal: nothing to choose, just acknowledge
            JsonObject a = newAsk("message", "", message);
            a.add("options", options(choices, display));
            ask(a);
            return new ArrayList<>();
        }
        List<Integer> pre = new ArrayList<>();
        if (selected != null) {
            for (T t : selected) {
                int i = choices.indexOf(t);
                if (i >= 0) pre.add(i);
            }
        }
        List<Integer> picked = choose("", message, Math.max(min, 0), max < 0 ? choices.size() : max, options(choices, display), pre);
        List<T> out = new ArrayList<>();
        for (int i : picked) {
            out.add(choices.get(i));
        }
        return out;
    }

    @Override
    public <T> OrderResult<T> order(String title, String top, int remainingObjectsMin, int remainingObjectsMax, List<T> sourceChoices,
                                    List<T> destChoices, CardView referenceCard, boolean sideboardingMode, boolean showRememberCheckbox) {
        int n = sourceChoices.size();
        int pickMax = remainingObjectsMin < 0 ? n : Math.max(0, n - remainingObjectsMin);
        int pickMin = remainingObjectsMax < 0 ? 0 : Math.max(0, n - remainingObjectsMax);
        pickMin = Math.min(pickMin, pickMax);
        List<T> out = new ArrayList<>();
        if (destChoices != null) {
            out.addAll(destChoices);
        }
        if (n == 0) {
            return new OrderResult<>(out, false);
        }
        JsonObject a = newAsk("order", title, top);
        a.addProperty("min", pickMin);
        a.addProperty("max", pickMax);
        a.add("options", options(sourceChoices, null));
        if (referenceCard != null) {
            a.addProperty("cardId", referenceCard.getId());
        }
        JsonElement res = ask(a);
        if (res != null && res.isJsonArray()) {
            for (JsonElement e : res.getAsJsonArray()) {
                int i = e.getAsInt();
                if (i >= 0 && i < n && !out.contains(sourceChoices.get(i))) {
                    out.add(sourceChoices.get(i));
                }
            }
        }
        return new OrderResult<>(out, false);
    }

    @Override
    public List<CardView> manipulateCardList(String title, Iterable<CardView> cards, Iterable<CardView> manipulable, boolean toTop, boolean toBottom, boolean toAnywhere) {
        List<CardView> list = new ArrayList<>();
        cards.forEach(list::add);
        return order(title, "Order (first = top)", 0, 0, list, null, null, false, false).ordered();
    }

    private Map<Object, Integer> distribute(String title, String message, List<?> keys, List<String> labels, int amount, boolean atLeastOne) {
        JsonObject a = newAsk("distribute", title, message);
        a.addProperty("amount", amount);
        a.addProperty("atLeastOne", atLeastOne);
        JsonArray opts = new JsonArray();
        for (int i = 0; i < keys.size(); i++) {
            JsonObject o = option(keys.get(i), null);
            o.addProperty("label", labels.get(i));
            opts.add(o);
        }
        a.add("options", opts);
        JsonElement res = ask(a);
        if (res == null || !res.isJsonArray()) {
            return null;
        }
        Map<Object, Integer> out = new LinkedHashMap<>();
        JsonArray arr = res.getAsJsonArray();
        for (int i = 0; i < keys.size() && i < arr.size(); i++) {
            int v = arr.get(i).getAsInt();
            if (v > 0) {
                out.put(keys.get(i), v);
            }
        }
        return out;
    }

    @Override
    public Map<CardView, Integer> assignCombatDamage(CardView attacker, List<CardView> blockers, int damage, GameEntityView defender, boolean overrideOrder, boolean maySkip) {
        List<Object> keys = new ArrayList<>(blockers);
        List<String> labels = new ArrayList<>();
        blockers.forEach(b -> labels.add(b.getName()));
        if (defender != null) {
            keys.add(null);
            labels.add(String.valueOf(defender) + " (defender)");
        }
        Map<Object, Integer> res = distribute("Assign combat damage", attacker.getName() + " assigns " + damage + " damage", keys, labels, damage, false);
        if (res == null) {
            return null;
        }
        Map<CardView, Integer> out = new LinkedHashMap<>();
        res.forEach((k, v) -> out.put((CardView) k, v));
        return out;
    }

    @Override
    public Map<Object, Integer> assignGenericAmount(CardView effectSource, Map<Object, Integer> target, int amount, boolean atLeastOne, String amountLabel) {
        List<Object> keys = new ArrayList<>(target.keySet());
        List<String> labels = new ArrayList<>();
        keys.forEach(k -> labels.add(k instanceof CardView cv ? cv.getName() : String.valueOf(k)));
        return distribute("Distribute " + amountLabel, (effectSource == null ? "" : effectSource.getName() + ": ") + "distribute " + amount + " " + amountLabel, keys, labels, amount, atLeastOne);
    }

    @Override
    public SpellAbilityView getAbilityToPlay(CardView hostCard, List<SpellAbilityView> abilities, ITriggerEvent triggerEvent) {
        if (abilities.isEmpty()) {
            return null;
        }
        if (abilities.size() == 1) {
            return abilities.get(0);
        }
        List<Integer> picked = choose("Choose ability", hostCard == null ? "" : hostCard.getName(), 0, 1, options(abilities, null), null);
        return picked.isEmpty() ? null : abilities.get(picked.get(0));
    }

    @Override
    public void message(String message, String title) {
        ask(newAsk("message", title, message));
    }

    @Override
    public void showErrorDialog(String message, String title) {
        ask(newAsk("message", title, message));
    }

    @Override
    public boolean showConfirmDialog(String message, String title, String yesButtonText, String noButtonText, boolean defaultYes) {
        return chooseOne(title, message, List.of(yesButtonText, noButtonText), defaultYes ? 0 : 1) == 0;
    }

    @Override
    public int showOptionDialog(String message, String title, FSkinProp icon, List<String> options, int defaultOption) {
        return chooseOne(title, message, options, defaultOption);
    }

    @Override
    public String showInputDialog(String message, String title, FSkinProp icon, String initialInput, List<String> inputOptions, boolean isNumeric) {
        if (inputOptions != null && !inputOptions.isEmpty()) {
            int i = chooseOne(title, message, inputOptions, inputOptions.indexOf(initialInput));
            return i < 0 ? null : inputOptions.get(i);
        }
        JsonObject a = newAsk("input", title, message);
        a.addProperty("initial", initialInput == null ? "" : initialInput);
        a.addProperty("numeric", isNumeric);
        JsonElement res = ask(a);
        return res == null || res.isJsonNull() ? null : res.getAsString();
    }

    @Override
    public boolean confirm(CardView c, String question, boolean defaultIsYes, List<String> options) {
        List<String> labels = options == null || options.size() < 2 ? List.of("Yes", "No") : options;
        JsonArray opts = new JsonArray();
        for (String l : labels) {
            JsonObject o = new JsonObject();
            o.addProperty("label", l);
            opts.add(o);
        }
        JsonObject a = newAsk("choose", c == null ? "" : c.getName(), question);
        a.addProperty("min", 1);
        a.addProperty("max", 1);
        a.add("options", opts);
        JsonArray pre = new JsonArray();
        pre.add(defaultIsYes ? 0 : 1);
        a.add("selected", pre);
        if (c != null) {
            a.addProperty("cardId", c.getId());
        }
        JsonElement res = ask(a);
        int picked = res != null && res.isJsonArray() && !res.getAsJsonArray().isEmpty() ? res.getAsJsonArray().get(0).getAsInt() : (defaultIsYes ? 0 : 1);
        return picked == 0;
    }

    @Override
    public List<PaperCard> sideboard(CardPool sideboard, CardPool main, String message) {
        return main.toFlatList(); // no sideboarding in Commander
    }

    @Override
    public GameEntityView chooseSingleEntityForEffect(String title, List<? extends GameEntityView> optionList, DelayedReveal delayedReveal, boolean isOptional) {
        if (delayedReveal != null) {
            reveal(delayedReveal.getMessagePrefix(), delayedReveal.getCards());
        }
        return isOptional ? oneOrNone(title, optionList) : one(title, optionList);
    }

    @Override
    @SuppressWarnings("unchecked")
    public List<GameEntityView> chooseEntitiesForEffect(String title, List<? extends GameEntityView> optionList, int min, int max, DelayedReveal delayedReveal) {
        if (delayedReveal != null) {
            reveal(delayedReveal.getMessagePrefix(), delayedReveal.getCards());
        }
        return (List<GameEntityView>) order(title, "Selected", optionList.size() - max, optionList.size() - min, optionList, null, null, false);
    }

    // ---------------------------------------------------------------- input prompt state

    private void setButtons(String label1, String label2, boolean enable1, boolean enable2) {
        synchronized (prompt) {
            prompt.addProperty("okLabel", label1);
            prompt.addProperty("cancelLabel", label2);
            prompt.addProperty("okEnabled", enable1);
            prompt.addProperty("cancelEnabled", enable2);
        }
    }

    @Override
    public void showPromptMessage(PlayerView playerView, String message, CardView card) {
        synchronized (prompt) {
            prompt.addProperty("message", message == null ? "" : message);
            if (card != null) {
                prompt.addProperty("cardId", card.getId());
            } else {
                prompt.remove("cardId");
            }
        }
        listener.stateChanged();
    }

    @Override
    public void updateButtons(PlayerView owner, String label1, String label2, boolean enable1, boolean enable2, boolean focus1) {
        setButtons(label1, label2, enable1, enable2);
        listener.stateChanged();
    }

    @Override
    public boolean isUiSetToSkipPhase(PlayerView playerTurn, PhaseType phase) {
        // Same stops as the stock desktop client, read from the shared Forge preferences.
        if (phase.ordinal() == 0) {
            return false;
        }
        ForgePreferences prefs = FModel.getPreferences();
        FPref[] keys = isLocalPlayer(playerTurn) ? FPref.PHASES_HUMAN : FPref.PHASES_AI;
        int idx = phase.ordinal() - 1;
        return idx < keys.length && !prefs.getPrefBoolean(keys[idx]);
    }

    // ---------------------------------------------------------------- notifications

    @Override protected void updateCurrentPlayer(PlayerView player) { listener.stateChanged(); }
    @Override public void openView(TrackableCollection<PlayerView> myPlayers) { listener.stateChanged(); }
    @Override public void showCombat() { listener.stateChanged(); }
    @Override public void flashIncorrectAction() {
        JsonObject m = new JsonObject();
        m.addProperty("type", "flash");
        listener.send(m);
    }
    @Override public void alertUser() { }
    @Override public void finishGame() {
        finished = true;
        listener.stateChanged();
    }
    @Override public void setPanelSelection(CardView hostCard) { }
    @Override public void setCard(CardView card) { }
    @Override public void setPlayerAvatar(LobbyPlayer player, IHasIcon ihi) { }

    @Override public void handleGameEvent(GameEvent event) {
        super.handleGameEvent(event);
        listener.stateChanged();
    }
    @Override public void updateStack() { listener.stateChanged(); }
    @Override public void updatePhase(boolean saveState) { listener.stateChanged(); }
    @Override public void updateTurn(PlayerView player) { listener.stateChanged(); }
    @Override public void updateCards(Iterable<CardView> cards) { listener.stateChanged(); }
    @Override public void updateZones(Iterable<forge.player.PlayerZoneUpdate> zones) { listener.stateChanged(); }
    @Override public void updateManaPool(Iterable<PlayerView> manaPoolUpdate) { listener.stateChanged(); }
    @Override public void updateLives(Iterable<PlayerView> livesUpdate) { listener.stateChanged(); }
    @Override public void refreshField() { listener.stateChanged(); }
    @Override public void setSelection(forge.gamemodes.match.Selection selection) {
        super.setSelection(selection);
        listener.stateChanged();
    }
    @Override public void setWeaklySelectable(Iterable<CardView> cards) {
        super.setWeaklySelectable(cards);
        listener.stateChanged();
    }
    @Override public void clearWeaklySelectable() {
        super.clearWeaklySelectable();
        listener.stateChanged();
    }
}
