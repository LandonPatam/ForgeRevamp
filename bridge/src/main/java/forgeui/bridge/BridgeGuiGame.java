package forgeui.bridge;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import forge.LobbyPlayer;
import forge.deck.CardPool;
import forge.game.GameEntityView;
import forge.game.card.CardView;
import forge.game.event.GameEvent;
import forge.game.event.GameEventTurnPhase;
import forge.game.event.GameEventCardChangeZone;
import forge.game.phase.PhaseType;
import forge.game.zone.ZoneType;
import forge.player.PlayerControllerHuman;
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
    final Map<String, String> portraits;
    private volatile boolean abandoned;
    @Override
    public void setOriginalGameController(PlayerView player, forge.interfaces.IGameController controller) {
        if (controller instanceof PlayerControllerHuman human) {
            // Compute the response predicate on Forge's game thread at each priority
            // checkpoint, not by probing/mutating the game from the snapshot thread.
            // These overrides are local to this controller and never saved to disk.
            var yields = human.getYieldController();
            yields.setPref(FPref.UI_SHOW_ACTIONABLE_HIGHLIGHTS, "true");
            yields.setPref(FPref.YIELD_AUTO_PASS_NO_ACTIONS, "false");
            yields.setPref(FPref.YIELD_DECLINE_SCOPE_STACK_YIELD, "NEVER");
            yields.setPref(FPref.YIELD_DECLINE_SCOPE_NO_ACTIONS, "NEVER");
            // Pass turn (Space) uses Forge's end-of-turn yield. It stops when this seat is
            // attacked, targeted or facing a board wipe, not for every opposing spell.
            yields.setPref(FPref.YIELD_INTERRUPT_ON_ATTACKERS, "true");
            yields.setPref(FPref.YIELD_INTERRUPT_ON_TARGETING, "true");
            yields.setPref(FPref.YIELD_INTERRUPT_ON_MASS_REMOVAL, "true");
            yields.setPref(FPref.YIELD_INTERRUPT_ON_OPPONENT_SPELL, "false");
        }
        super.setOriginalGameController(player, controller);
        if (controller instanceof PlayerControllerHuman human) {
            // Queue removal does not reliably produce a new prompt: Forge's delayed
            // InputLockUI can leave the previous buttons visible indefinitely.
            // Invalidate snapshots at the actual input transition, including when
            // a seat goes idle while another human or bot continues the turn.
            human.getInputQueue().addObserver((queue, value) -> listener.stateChanged());
            listener.gameInitialized(human.getGame());
        }
    }

    interface Listener {
        void stateChanged();
        void send(JsonObject message);
        default void gameInitialized(forge.game.Game game) { }
    }

    private final Listener listener;
    private final AtomicInteger askIds = new AtomicInteger();
    private final Map<Integer, CompletableFuture<JsonElement>> pending = new ConcurrentHashMap<>();
    /** Open asks, in order, so a client that (re)connects sees them. */
    private final Map<Integer, JsonObject> openAsks = new ConcurrentHashMap<>();
    private volatile List<CardView> revealed = List.of();
    private volatile CardView decisionCard;
    private volatile forge.game.spellability.SpellAbility revealedEffect;
    private volatile JsonArray effectReveal = new JsonArray();
    final TargetedEffectHistory targetedEffects = new TargetedEffectHistory();

    final JsonObject prompt = new JsonObject();
    private forge.gamemodes.match.input.Input promptInput;

    forge.gamemodes.match.input.Input currentInput() {
        return getGameController() instanceof PlayerControllerHuman human
                ? human.getInputQueue().getInput() : null;
    }

    boolean hasCurrentPrompt(forge.gamemodes.match.input.Input input) {
        synchronized (prompt) { return input != null && input == currentInput() && input == promptInput; }
    }
    volatile boolean finished;
    volatile boolean openingHandComplete;
    void openingChanged() { listener.stateChanged(); }
    volatile int returnToHandCandidate = -1;
    private volatile CardView pendingLandPlay;
    private volatile long pendingLandPhase = -1;
    private volatile long returnPhase = -1;
    private volatile CardView pendingCast;
    private volatile ZoneType pendingCastOrigin;
    private volatile boolean pendingCastMoved;
    private volatile int returnUndoDepth = -1;
    private volatile CardView undoLand;
    private volatile int undoTargetDepth;
    private volatile int undoIssuedDepth;
    private volatile long undoPhase;
    private volatile long undoStarted;
    private volatile boolean restoringSnapshot;
    private final java.util.concurrent.atomic.AtomicBoolean undoQueued = new java.util.concurrent.atomic.AtomicBoolean();
    final java.util.Set<Integer> pendingDraws = new java.util.concurrent.CopyOnWriteArraySet<>();
    private volatile int drawingPlayer = -1;
    private final Map<String, Boolean> phaseStopOverrides = new ConcurrentHashMap<>();
    private boolean onlineMatch;

    void setOnlineMatch(boolean online) { onlineMatch = online; }
    private volatile CardView pendingManaTap;
    private volatile int pendingManaDepth;
    private volatile long pendingManaPhase;
    private volatile boolean sawTapMana;
    private volatile CardView undoTapCard;
    private volatile int undoTapDepth;
    private volatile long undoTapPhase;
    private record LandReturnUndo(int cardId, int depth, long phase) {}
    private volatile LandReturnUndo pendingManaLandReturn;
    private volatile LandReturnUndo restoringManaLandReturn;
    private record ManaTapUndo(CardView card, int depth, long phase, LandReturnUndo landReturn) {}
    private final List<ManaTapUndo> manaTapHistory = new java.util.concurrent.CopyOnWriteArrayList<>();
    private volatile int undoTapTargetDepth;
    private volatile boolean undoingMana;
    private volatile CardView takebackCast;
    private volatile long takebackPhase;
    private volatile int takebackTargetDepth;
    private volatile int takebackBeforeDepth;
    private volatile int takebackApprovedDepth = -1;
    private volatile boolean takebackCastSeen;
    private volatile boolean undoingCast;

    void commitTakeback() { takebackCast = null; }
    void commitAcceptedTakeback() {
        if (takebackCast != null && takebackCastSeen) {
            if (getGameController() instanceof PlayerControllerHuman human)
                human.getGame().getUndoManager().barrier("Cast committed before passing priority");
            commitTakeback();
        }
    }

    CardView takebackCard() {
        CardView card = takebackCast;
        return mayTakeBackCast(card) ? card : null;
    }

    private boolean mayTakeBackCast(CardView card) {
        return card != null && card == takebackCast && takebackCastSeen
                && card.getZone() == ZoneType.Stack && undoLand == null
                && phaseStamp() == takebackPhase && openAsks.isEmpty()
                && getGameController() instanceof PlayerControllerHuman human && human.canUndoLastAction()
                && human.getGame().getUndoManager().depth() == takebackApprovedDepth;
    }

    boolean mayUndoTap(CardView card) {
        return card != null && undoTapCard != null && card.getId() == undoTapCard.getId()
                && card.getZone() == ZoneType.Battlefield && card.isTapped()
                && undoLand == null && phaseStamp() == undoTapPhase
                && getGameController() instanceof PlayerControllerHuman human && human.canUndoLastAction()
                && human.getInputQueue().getInput() instanceof forge.gamemodes.match.input.InputPassPriority
                && human.getGame().getUndoManager().depth() == undoTapDepth;
    }

    private SpellAbilityView noteSelectedAbility(CardView host, SpellAbilityView selected) {
        if (selected == null) return null;
        // Forge can ask again about optional costs after the priority input closes.
        // Preserve the pending activation through those callbacks.
        if (host == null || !(getGameController() instanceof PlayerControllerHuman human)
                || !(human.getInputQueue().getInput() instanceof forge.gamemodes.match.input.InputPassPriority)) return selected;
        undoTapCard = null;
        pendingManaTap = null;
        var source = human.getGame().findByView(host);
        if (source == null || !source.isInPlay() || source.isTapped() || source.getController() != human.getPlayer()) return selected;
        for (var ability : source.getSpellAbilities()) {
            if (ability.getId() == selected.getId() && ability.isManaAbility()
                    && ability.getPayCosts() != null && ability.getPayCosts().hasTapCost()) {
                pendingManaDepth = human.getGame().getUndoManager().depth();
                pendingManaPhase = phaseStamp();
                pendingManaLandReturn = returnToHandCandidate >= 0
                        ? new LandReturnUndo(returnToHandCandidate, returnUndoDepth, returnPhase) : null;
                sawTapMana = false;
                pendingManaTap = host;
                pendingCast = null;
                break;
            }
        }
        return selected;
    }

    void setPhaseStop(PlayerView player, PhaseType phase, boolean enabled) {
        phaseStopOverrides.put(player.getId() + ":" + phase.name(), enabled);
        getGameController().sendYieldUpdate(new forge.gamemodes.match.YieldUpdate.SkipPhase(player, phase, !enabled));
        listener.stateChanged();
    }

    JsonObject phaseStops() {
        JsonObject result = new JsonObject();
        if (getGameView() == null) return result;
        for (PlayerView player : getGameView().getPlayers()) {
            JsonObject stops = new JsonObject();
            for (PhaseType phase : PhaseType.values()) {
                if (phase == PhaseType.UNTAP) continue;
                // Report preferences, not the transient no-legal-action yield policy.
                stops.addProperty(phase.name(), displayedPhaseStop(player, phase));
            }
            result.add(String.valueOf(player.getId()), stops);
        }
        return result;
    }

    boolean configuredPhaseStop(PlayerView player, PhaseType phase) {
        return phaseStopOverrides.getOrDefault(player.getId() + ":" + phase.name(), defaultPhaseStop(phase));
    }

    /** Online, another player's turn stops this seat only where it was explicitly checked. */
    private boolean displayedPhaseStop(PlayerView player, PhaseType phase) {
        if (!onlineMatch || isOwnTurn(player)) return configuredPhaseStop(player, phase);
        return phaseStopOverrides.getOrDefault(player.getId() + ":" + phase.name(), false);
    }

    private boolean isOwnTurn(PlayerView playerTurn) {
        return !(getGameController() instanceof PlayerControllerHuman human)
                || playerTurn.equals(human.getPlayer().getView());
    }

    boolean mayReturnToHand(CardView card) {
        if (mayTakeBackCast(card)) return true;
        return card != null && card.getId() == returnToHandCandidate
                && undoLand == null
                && card.getZone() == ZoneType.Battlefield
                && getGameController() instanceof PlayerControllerHuman human
                && human.canUndoLastAction()
                && human.getGame().getUndoManager().depth() >= returnUndoDepth;
    }

    void noteLandPlay(CardView card) {
        pendingLandPlay = card;
        pendingLandPhase = phaseStamp();
    }

    void noteSpellAttempt(CardView card) {
        if (!card.getCurrentState().isLand() && card.getZone() == ZoneType.Hand
                && getGameController() instanceof PlayerControllerHuman human
                && human.getInputQueue().getInput() instanceof forge.gamemodes.match.input.InputPassPriority
                && human.getGame().getUndoManager().mode() == forge.game.undo.UndoManager.Mode.FREE
                && human.getGame().getUndoManager().depth() < 95) {
            takebackCast = card;
            takebackPhase = phaseStamp();
            takebackTargetDepth = human.getGame().getUndoManager().depth();
            takebackBeforeDepth = takebackTargetDepth;
            // Unspent mana activations form the payment gesture preceding the cast.
            for (ManaTapUndo tap : manaTapHistory) {
                if (tap.phase() == takebackPhase && tap.card().isTapped())
                    takebackTargetDepth = Math.min(takebackTargetDepth, tap.depth() - 1);
            }
            takebackApprovedDepth = -1;
            takebackCastSeen = false;
        }
        if ((returnToHandCandidate >= 0 || !manaTapHistory.isEmpty()) && !card.getCurrentState().isLand()
                && (card.getZone() == ZoneType.Hand || card.getZone() == ZoneType.Command)
                && getGameController() instanceof PlayerControllerHuman human && human.canUndoLastAction()
                && human.getInputQueue().getInput() instanceof forge.gamemodes.match.input.InputPassPriority) {
            // Single-step mode/capped history cannot retain the older land checkpoint.
            if (human.getGame().getUndoManager().mode() != forge.game.undo.UndoManager.Mode.FREE
                    || human.getGame().getUndoManager().depth() >= 99) {
                returnToHandCandidate = -1;
                manaTapHistory.clear();
                return;
            }
            pendingCastOrigin = card.getZone();
            pendingCastMoved = false;
            pendingCast = card;
        }
    }

    private long phaseStamp() {
        var game = getGameView();
        return game == null ? -1 : game.getTurn() * 100L + (game.getPhase() == null ? 0 : game.getPhase().ordinal());
    }

    void refreshUndoPermissions() {
        if (restoringSnapshot) return;
        if (!(getGameController() instanceof PlayerControllerHuman human) || getGameView() == null) return;
        long phase = phaseStamp();
        CardView manaSource = pendingManaTap;
        if (manaSource != null && phase != pendingManaPhase) pendingManaTap = null;
        else if (manaSource != null && sawTapMana && manaSource.isTapped()
                && human.canUndoLastAction() && human.getGame().getUndoManager().depth() == pendingManaDepth + 1) {
            // The next priority checkpoint proves the entire mana activation finished.
            undoTapDepth = human.getGame().getUndoManager().depth();
            undoTapPhase = phase;
            undoTapCard = manaSource;
            undoTapTargetDepth = pendingManaDepth;
            manaTapHistory.add(new ManaTapUndo(manaSource, undoTapDepth, phase, pendingManaLandReturn));
            pendingManaTap = null;
        }
        boolean atPriority = human.getInputQueue().getInput() instanceof forge.gamemodes.match.input.InputPassPriority;
        if (atPriority && pendingManaTap != null && !pendingManaTap.isTapped() && !sawTapMana
                && phase == pendingManaPhase && human.canUndoLastAction()
                && human.getGame().getUndoManager().mode() == forge.game.undo.UndoManager.Mode.FREE
                && human.getGame().getUndoManager().depth() == pendingManaDepth + 1) {
            // Tap costs can be paid before Forge asks for mana. Canceling that
            // prompt refunds the tap without ever producing mana.
            LandReturnUndo landReturn = pendingManaLandReturn;
            if (landReturn != null && landReturn.phase() == phase) {
                returnToHandCandidate = landReturn.cardId();
                returnUndoDepth = landReturn.depth();
                returnPhase = landReturn.phase();
            }
            pendingManaTap = null;
        }
        if (takebackCast != null && atPriority && takebackCastSeen) {
            int depth = human.getGame().getUndoManager().depth();
            if (phase != takebackPhase || takebackCast.getZone() != ZoneType.Stack
                    || (takebackApprovedDepth >= 0 && depth != takebackApprovedDepth)) commitTakeback();
            else if (human.canUndoLastAction() && depth > takebackBeforeDepth) takebackApprovedDepth = depth;
        }
        if (atPriority && pendingCastMoved && pendingCast != null && pendingCast.getZone() == pendingCastOrigin) {
            // A canceled cast has refunded payment and returned to its origin.
            // Only provisional moves/payment events may preserve this history.
            pendingCast = null;
            restoreManaTapPermission(human, phase);
        }
        if (atPriority && undoLand == null && undoingMana) {
            undoingMana = false;
            LandReturnUndo landReturn = restoringManaLandReturn;
            restoringManaLandReturn = null;
            // Restore only the permission belonging to the exact checkpoint that
            // Forge has finished restoring, never infer it from an untapped card.
            if (landReturn != null && landReturn.phase() == phase
                    && human.getGame().getUndoManager().depth() == undoTargetDepth
                    && undoTargetDepth >= landReturn.depth() && human.canUndoLastAction()) {
                returnToHandCandidate = landReturn.cardId();
                returnUndoDepth = landReturn.depth();
                returnPhase = landReturn.phase();
            }
            restoreManaTapPermission(human, phase);
        }
        if (undoTapCard != null && (phase != undoTapPhase || !undoTapCard.isTapped()
                || human.getGame().getUndoManager().depth() != undoTapDepth)) undoTapCard = null;
        if (returnToHandCandidate >= 0 && (returnPhase != phase
                || human.getGame().getUndoManager().depth() < returnUndoDepth)) {
            returnToHandCandidate = -1;
            pendingCast = null;
        }
        if (pendingLandPhase != phase) pendingLandPlay = null;
        CardView attempt = pendingLandPlay;
        if (attempt != null && attempt.getZone() == ZoneType.Battlefield && human.canUndoLastAction()) {
            returnToHandCandidate = attempt.getId();
            returnPhase = phase;
            returnUndoDepth = human.getGame().getUndoManager().depth();
            pendingLandPlay = null;
        }
    }

    boolean isLandUndoPending() { return undoLand != null; }

    private void restoreManaTapPermission(PlayerControllerHuman human, long phase) {
        int depth = human.getGame().getUndoManager().depth();
        manaTapHistory.removeIf(tap -> tap.phase() != phase || !tap.card().isTapped() || tap.depth() > depth);
        if (manaTapHistory.isEmpty() || !human.canUndoLastAction()) return;
        ManaTapUndo tap = manaTapHistory.get(manaTapHistory.size() - 1);
        undoTapCard = tap.card();
        undoTapDepth = depth;
        undoTapTargetDepth = tap.depth() - 1;
        undoTapPhase = phase;
    }

    private volatile java.util.Set<Integer> requestedEquipAbilities = java.util.Set.of();

    private List<forge.game.spellability.SpellAbility> equipAbilities(CardView sourceView, CardView targetView) {
        if (!(getGameController() instanceof PlayerControllerHuman human)
                || !(human.getInputQueue().getInput() instanceof forge.gamemodes.match.input.InputPassPriority)) return List.of();
        var source = human.getGame().findByView(sourceView);
        var target = human.getGame().findByView(targetView);
        if (source == null || target == null || !source.isInPlay() || !source.isEquipment()
                || !target.isInPlay() || !target.isCreature() || source.getController() != human.getPlayer()
                || target.getController() != human.getPlayer()) return List.of();
        return source.getAllPossibleAbilities(human.getPlayer(), true).stream()
                .filter(ability -> ability.isEquip() && ability.canTarget(target)).toList();
    }

    boolean canEquip(CardView source, CardView target) { return !equipAbilities(source, target).isEmpty(); }

    boolean selectEquip(CardView source, CardView target, ITriggerEvent event) {
        requestedEquipAbilities = equipAbilities(source, target).stream().map(ability -> ability.getId()).collect(java.util.stream.Collectors.toSet());
        if (requestedEquipAbilities.isEmpty()) return false;
        try { return getGameController().selectCard(source, null, event); }
        finally { requestedEquipAbilities = java.util.Set.of(); }
    }

    boolean undoManaTap(CardView card) {
        if (!mayUndoTap(card) || !(getGameController() instanceof PlayerControllerHuman human)) return false;
        undoTargetDepth = undoTapTargetDepth;
        undoIssuedDepth = human.getGame().getUndoManager().depth();
        undoPhase = undoTapPhase;
        undoStarted = System.nanoTime();
        restoringManaLandReturn = manaTapHistory.isEmpty() ? null
                : manaTapHistory.get(manaTapHistory.size() - 1).landReturn();
        undoingMana = true;
        undoLand = card;
        if (human.tryUndoLastAction()) return true;
        undoLand = null;
        undoingMana = false;
        restoringManaLandReturn = null;
        return false;
    }

    boolean returnLandToHand(CardView card) {
        if (!mayReturnToHand(card) || !(getGameController() instanceof PlayerControllerHuman human)) return false;
        undoingCast = mayTakeBackCast(card);
        undoTargetDepth = undoingCast ? takebackTargetDepth : returnUndoDepth - 1;
        undoingMana = false;
        undoIssuedDepth = human.getGame().getUndoManager().depth();
        undoPhase = undoingCast ? takebackPhase : returnPhase;
        undoStarted = System.nanoTime();
        undoLand = card;
        commitTakeback();
        if (human.tryUndoLastAction()) return true;
        undoLand = null;
        undoingCast = false;
        return false;
    }

    void advanceLandUndo() {
        CardView land = undoLand;
        if (land == null || restoringSnapshot) return;
        if ((!undoingCast && land.getZone() == ZoneType.Hand) || (undoingMana && !land.isTapped()) || phaseStamp() != undoPhase
                || System.nanoTime() - undoStarted > java.util.concurrent.TimeUnit.SECONDS.toNanos(10)) {
            undoLand = null;
            listener.stateChanged();
            return;
        }
        if (!(getGameController() instanceof PlayerControllerHuman human)) return;
        int depth = human.getGame().getUndoManager().depth();
        if (depth >= undoIssuedDepth) return; // Wait for the outstanding restore, never replay it.
        if (depth <= undoTargetDepth || (!undoingCast && land.getZone() != ZoneType.Battlefield)) {
            undoLand = null;
            undoingCast = false;
            listener.stateChanged();
            return;
        }
        if (!human.canUndoLastAction()) return;
        if (!undoQueued.compareAndSet(false, true)) return;
        forge.gui.GuiBase.getInterface().invokeInEdtLater(() -> {
            try {
                if (undoLand != land || restoringSnapshot || phaseStamp() != undoPhase || !human.canUndoLastAction()) return;
                int latest = human.getGame().getUndoManager().depth();
                if (latest >= undoIssuedDepth || latest <= undoTargetDepth) return;
                undoIssuedDepth = latest;
                if (!human.tryUndoLastAction()) undoLand = null;
            } finally {
                undoQueued.set(false);
                listener.stateChanged();
            }
        });
    }

    BridgeGuiGame(Listener listener) { this(listener, new ConcurrentHashMap<>()); }

    /** Seats in one match share uploaded portraits, so every player can draw every player. */
    BridgeGuiGame(Listener listener, Map<String, String> portraits) {
        this.listener = listener;
        this.portraits = portraits;
        prompt.addProperty("message", "");
        setButtons("OK", "Cancel", false, false);
    }

    /** This seat's player has left: release any decision they hold and answer later ones with a safe default. */
    void abandon() {
        abandoned = true;
        pending.forEach((id, future) -> {
            JsonObject ask = openAsks.get(id);
            if (ask != null) future.complete(BridgeProtocol.fallbackAnswer(ask));
        });
    }

    List<JsonObject> openAsks() {
        List<JsonObject> list = new ArrayList<>();
        openAsks.entrySet().stream().sorted(Map.Entry.comparingByKey()).forEach(e -> list.add(e.getValue()));
        return list;
    }

    /** A client answered an ask. */
    void answer(int id, JsonElement value) {
        CompletableFuture<JsonElement> f = pending.get(id);
        JsonObject ask = openAsks.get(id);
        if (f == null || ask == null || f.isDone()) throw new IllegalArgumentException("Decision is no longer pending");
        BridgeProtocol.validateAnswer(ask, value);
        if (!f.complete(value.deepCopy())) throw new IllegalArgumentException("Decision is already answered");
    }

    // ---------------------------------------------------------------- asks

    private JsonElement ask(JsonObject ask) {
        if (abandoned) return BridgeProtocol.fallbackAnswer(ask);
        if (ask.has("kind") && ask.get("kind").getAsString().equals("choose") && !ask.has("revealedCards")) {
            JsonArray context = effectRevealedCards();
            if (!context.isEmpty()) ask.add("revealedCards", context);
        }
        if (!ask.has("sourceCard")) {
            CardView source = null;
            if (getGameController() instanceof PlayerControllerHuman human && human.getGame().getStack().isResolving()
                    && human.getGame().getStack().peek() != null) {
                var resolving = human.getGame().getStack().peekAbility();
                source = resolving.getHostCard().getView();
                ask.addProperty("effectText", resolving.toString());
            } else if (decisionCard != null) {
                source = decisionCard;
            }
            if (source != null) ask.add("sourceCard", GameStateJson.describeCard(source, mayView(source)));
        }
        commitTakeback(); // Blocking decisions may reveal information or a reaction.
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

    private <T> JsonArray options(List<T> items, FSerializableFunction<T, String> display) {
        JsonArray arr = new JsonArray();
        for (T item : items) {
            arr.add(option(item, display));
        }
        return arr;
    }

    @SuppressWarnings("unchecked")
    private <T> JsonObject option(T item, FSerializableFunction<T, String> display) {
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
            if (cv.getController() != null) o.addProperty("controllerId", cv.getController().getId());
            o.add("card", GameStateJson.describeCard(cv, mayView(cv)));
        } else if (item instanceof PaperCard paper) {
            o.add("card", GameStateJson.describePaperCard(paper));
        } else if (item instanceof PlayerView pv) {
            o.addProperty("playerId", pv.getId());
        } else if (item instanceof StackItemView si) {
            o.addProperty("stackId", si.getId());
            if (si.getSourceCard() != null) o.add("card", GameStateJson.describeCard(si.getSourceCard(), mayView(si.getSourceCard())));
        } else if (item instanceof forge.game.card.IHasCardView source && source.getCardView() != null) {
            CardView host = source.getCardView();
            o.add("card", GameStateJson.describeCard(host, mayView(host)));
            int abilityId = item instanceof SpellAbilityView view ? view.getId()
                    : item instanceof forge.game.spellability.SpellAbility ability ? ability.getId() : -1;
            if (abilityId >= 0 && getGameController() instanceof PlayerControllerHuman human) {
                for (var instance : human.getGame().getStack()) {
                    if (instance.getSpellAbility().getId() == abilityId) {
                        o.addProperty("stackId", instance.getId());
                        break;
                    }
                }
            }
        }
        return o;
    }

    /** Generic pick: returns the chosen indices. */
    private List<Integer> choose(String title, String message, int min, int max, JsonArray options, List<Integer> preselected) {
        return choose(title, message, min, max, options, preselected, null);
    }

    private List<Integer> choose(String title, String message, int min, int max, JsonArray options, List<Integer> preselected, JsonObject metadata) {
        JsonObject a = newAsk("choose", title, message);
        if (metadata != null) metadata.entrySet().forEach(entry -> a.add(entry.getKey(), entry.getValue()));
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
            JsonArray shown = options(choices, display);
            // A reveal callback authorizes these faces even when their zone is private.
            for (int i = 0; i < choices.size(); i++) {
                if (choices.get(i) instanceof CardView card) shown.get(i).getAsJsonObject().add("card", GameStateJson.describeCard(card, true));
            }
            a.add("options", shown);
            var effect = resolvingEffect();
            if (effect != null) {
                JsonArray faces = new JsonArray();
                for (JsonElement entry : shown) if (entry.getAsJsonObject().has("card")) faces.add(entry.getAsJsonObject().get("card").deepCopy());
                effectReveal = faces;
                revealedEffect = effect;
            }
            // A remembered reveal immediately followed by a library choice is
            // context for that choice. Keep the authorized faces without a
            // separate acknowledgment that looks like a disabled selection.
            var next = effect == null ? null : effect.getSubAbility();
            boolean combinedChoice = effect != null && effect.getApi() == forge.game.ability.ApiType.PeekAndReveal
                    && effect.hasParam("RememberRevealed") && !effect.hasParam("RevealOptional")
                    && next != null && next.getApi() == forge.game.ability.ApiType.ChangeZone
                    && next.getParamOrDefault("Origin", "").equals("Library")
                    && next.getParamOrDefault("ChangeType", "").contains("IsRemembered");
            if (!combinedChoice) ask(a);
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
        a.addProperty("autoOrder", remainingObjectsMin == 0 && remainingObjectsMax == 0);
        a.addProperty("abilityOrder", sourceChoices.stream().anyMatch(item -> item instanceof SpellAbilityView));
        a.addProperty("min", pickMin);
        a.addProperty("max", pickMax);
        a.add("options", options(sourceChoices, null));
        if (referenceCard != null) {
            a.addProperty("cardId", referenceCard.getId());
            a.add("sourceCard", GameStateJson.describeCard(referenceCard, mayView(referenceCard)));
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
        return distribute(title, message, keys, labels, amount, atLeastOne, null);
    }

    private Map<Object, Integer> distribute(String title, String message, List<?> keys, List<String> labels, int amount, boolean atLeastOne, JsonObject metadata) {
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
        if (metadata != null) metadata.entrySet().forEach(e -> a.add(e.getKey(), e.getValue()));
        JsonElement res = ask(a);
        if (res == null || res.isJsonNull()) {
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
        // Match the pinned stock damage dialog's recipient policy.
        boolean divide = attacker.getCurrentState().hasDivideDamage();
        boolean canHitDefender = defender != null && (attacker.getCurrentState().hasTrample() || (divide && overrideOrder));
        if (canHitDefender) {
            keys.add(null);
            labels.add(String.valueOf(defender) + " (defender)");
        }
        JsonObject metadata = new JsonObject();
        metadata.addProperty("maySkip", maySkip);
        metadata.addProperty("overrideOrder", overrideOrder);
        metadata.addProperty("divideDamage", divide);
        metadata.addProperty("sourceId", attacker.getId());
        JsonArray lethal = new JsonArray();
        for (CardView blocker : blockers) {
            int required = Math.max(0, blocker.getLethalDamage());
            if (blocker.getCurrentState().isPlaneswalker()) required = Integer.parseInt(blocker.getCurrentState().getLoyalty());
            else if (attacker.getCurrentState().hasDeathtouch()) required = Math.min(required, 1);
            lethal.add(required);
        }
        metadata.add("lethal", lethal);
        if (canHitDefender) {
            metadata.addProperty("defenderId", defender.getId());
            metadata.addProperty("defenderKind", defender instanceof PlayerView ? "player" : "card");
        }
        Map<Object, Integer> res = distribute("Assign combat damage", attacker.getName() + " assigns " + damage + " damage", keys, labels, damage, false, metadata);
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
        // Mouse-triggered selection includes disabled options for stock keyboard
        // shortcuts. Never return one of those as an executable ability.
        // Internal cost/trigger preparation also uses this callback with no
        // mouse event. Those abilities are not manually activatable; Forge has
        // already authorized their execution. Filtering them drops ETB triggers.
        if (triggerEvent != null) abilities = abilities.stream().filter(SpellAbilityView::canPlay).toList();
        if (triggerEvent != null && !requestedEquipAbilities.isEmpty())
            abilities = abilities.stream().filter(view -> requestedEquipAbilities.contains(view.getId())).toList();
        if (abilities.isEmpty()) {
            return null;
        }
        record Choice(SpellAbilityView view, forge.game.spellability.SpellAbility ability, String color, String label) {}
        List<Choice> choices = new ArrayList<>();
        var source = triggerEvent != null && hostCard != null && getGameController() instanceof PlayerControllerHuman human
                ? human.getGame().findByView(hostCard) : null;
        for (var view : abilities) {
            var ability = source == null ? null : source.getSpellAbilities().stream()
                    .filter(sa -> sa.getId() == view.getId()).findFirst().orElse(null);
            List<String> colors = directManaColors(ability);
            if (colors.isEmpty()) {
                choices.add(new Choice(view, ability, "", view.toString()));
            } else {
                // Reset a previous canceled activation before offering a fresh choice.
                ability.getManaPart().clearExpressChoice();
                for (String color : colors) {
                    String name = switch (color) {
                        case "W" -> "White"; case "U" -> "Blue"; case "B" -> "Black";
                        case "R" -> "Red"; case "G" -> "Green"; default -> "Colorless";
                    };
                    choices.add(new Choice(view, ability, color, name + " \u2014 " + directManaLabel(view.toString(), color)));
                }
            }
        }
        Choice selected;
        if (choices.size() == 1) selected = choices.get(0);
        else {
            JsonObject metadata = new JsonObject();
            metadata.addProperty("abilityChoice", true);
            boolean manaChoice = choices.stream().allMatch(choice -> choice.ability() != null && choice.ability().isManaAbility()
                    && choice.ability().getPayCosts() != null && choice.ability().getPayCosts().hasTapCost()
                    && choice.ability().getPayCosts().hasOnlySpecificCostType(forge.game.cost.CostTap.class));
            metadata.addProperty("manaChoice", manaChoice);
            if (hostCard != null) metadata.add("sourceCard", GameStateJson.describeCard(hostCard, mayView(hostCard)));
            JsonArray abilityOptions = options(choices.stream().map(Choice::label).toList(), null);
            for (int i = 0; i < choices.size(); i++) {
                var choice = choices.get(i);
                // A click requests this activation. Present a tap-only mana source as a color
                // decision; Forge still performs the tap and enforces any additional costs.
                if (choice.ability() != null && choice.ability().isManaAbility() && choice.ability().getPayCosts() != null
                        && choice.ability().getPayCosts().hasTapCost()
                        && choice.ability().getPayCosts().hasOnlySpecificCostType(forge.game.cost.CostTap.class)) {
                    abilityOptions.get(i).getAsJsonObject().addProperty("label", choice.label().replaceFirst("\\{T\\}\\s*:\\s*", ""));
                }
            }
            List<Integer> picked = choose(manaChoice ? "Choose mana" : "Choose ability", hostCard == null ? "" : hostCard.getName(), 0, 1,
                    abilityOptions, null, metadata);
            if (picked.isEmpty()) return null;
            selected = choices.get(picked.get(0));
        }
        // Forge consumes this on the real ability, still paying all costs and resolving
        // its sub-abilities (including pain-land damage), then clears it after production.
        if (!selected.color().isEmpty()) selected.ability().getManaPart().setExpressChoice(selected.color());
        return noteSelectedAbility(hostCard, selected.view());
    }

    static String directManaLabel(String description, String color) {
        return description.replaceFirst("(?i)Add\\s+\\{[WUBRGC]\\}(?:\\s*(?:,\\s*(?:or\\s+)?|or\\s+)\\{[WUBRGC]\\})*", "Add {" + color + "}");
    }

    static List<String> directManaColors(forge.game.spellability.SpellAbility ability) {
        if (ability == null || !ability.isManaAbility() || ability.getManaPart() == null
                || ability.hasParam("Chooser") || ability.hasParam("Defined") || ability.hasParam("Optional")
                || ability.hasParam("Each") || !ability.getParamOrDefault("Amount", "1").equals("1")) return List.of();
        // Only literal single-mana choices. Dynamic/restricted/multiple-mana effects
        // retain their engine chooser rather than guessing their available colors.
        String produced = ability.getManaPart().getOrigProduced();
        if (produced == null || !produced.matches("Combo [WUBRG]( [WUBRG])+")) return List.of();
        return List.of(produced.substring(6).split(" "));
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
            a.add("sourceCard", GameStateJson.describeCard(c, mayView(c)));
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
        if (optionList.isEmpty()) {
            if (delayedReveal != null) reveal(delayedReveal.getMessagePrefix(), delayedReveal.getCards());
            return null;
        }
        JsonObject metadata = revealMetadata(delayedReveal);
        JsonArray choices = effectOptions(optionList, delayedReveal);
        List<Integer> picked = choose(title, "Choose a card from the eligible cards.", isOptional ? 0 : 1, 1, choices, null, metadata);
        return picked.isEmpty() ? null : optionList.get(picked.get(0));
    }

    private JsonObject revealMetadata(DelayedReveal reveal) {
        JsonObject metadata = new JsonObject();
        if (reveal != null) {
            JsonArray cards = new JsonArray();
            for (CardView card : reveal.getCards()) cards.add(GameStateJson.describeCard(card, true));
            metadata.add("revealedCards", cards);
            metadata.addProperty("revealMessage", reveal.getMessagePrefix());
        }
        return metadata;
    }

    private JsonArray effectOptions(List<? extends GameEntityView> entities, DelayedReveal reveal) {
        JsonArray choices = options(entities, null);
        if (reveal != null) for (int i = 0; i < entities.size(); i++) {
            if (entities.get(i) instanceof CardView card && reveal.getCards().contains(card)) {
                choices.get(i).getAsJsonObject().add("card", GameStateJson.describeCard(card, true));
            }
        }
        return choices;
    }

    @Override
    @SuppressWarnings("unchecked")
    public List<GameEntityView> chooseEntitiesForEffect(String title, List<? extends GameEntityView> optionList, int min, int max, DelayedReveal delayedReveal) {
        JsonObject metadata = revealMetadata(delayedReveal);
        boolean permanentChoices = optionList.stream().allMatch(entity -> entity instanceof PlayerView
                || entity instanceof CardView card && card.getZone() == forge.game.zone.ZoneType.Battlefield);
        metadata.addProperty("bulkSelection", min == 0 && max >= optionList.size() && permanentChoices);
        if (getCurrentPlayer() != null) metadata.addProperty("localPlayerId", getCurrentPlayer().getId());
        List<Integer> picked = choose(title, "Choose the permanents and/or players to include.", min, max,
                effectOptions(optionList, delayedReveal), null, metadata);
        List<GameEntityView> result = new ArrayList<>();
        for (int index : picked) result.add(optionList.get(index));
        return result;
    }

    // ---------------------------------------------------------------- input prompt state

    private forge.game.spellability.SpellAbility resolvingEffect() {
        if (getGameController() instanceof PlayerControllerHuman human && human.getGame().getStack().isResolving()) {
            return human.getGame().getStack().peekAbility();
        }
        return null;
    }

    JsonArray effectRevealedCards() {
        var effect = resolvingEffect();
        return effect != null && effect == revealedEffect ? effectReveal.deepCopy() : new JsonArray();
    }

    List<CardView> revealedCards() { return revealed; }

    @Override public void showRevealedCards(Iterable<CardView> cards) {
        List<CardView> copy = new ArrayList<>();
        cards.forEach(copy::add);
        revealed = List.copyOf(copy);
        listener.stateChanged();
    }

    @Override public void hideRevealedCards() {
        revealed = List.of();
        listener.stateChanged();
    }

    @Override public void showPromptMessageNoCancel(PlayerView player, String message) {
        showPromptMessage(player, message, null);
        setButtons("OK", "Cancel", false, false);
        listener.stateChanged();
    }

    private void setButtons(String label1, String label2, boolean enable1, boolean enable2) {
        synchronized (prompt) {
            promptInput = currentInput();
            prompt.addProperty("okLabel", label1);
            prompt.addProperty("cancelLabel", label2);
            prompt.addProperty("okEnabled", enable1);
            prompt.addProperty("cancelEnabled", enable2);
        }
    }

    @Override
    public void showPromptMessage(PlayerView playerView, String message, CardView card) {
        decisionCard = card;
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
        // In solo games every checked phase is a stop, including bot turns.
        if (!onlineMatch) return !configuredPhaseStop(playerTurn, phase);
        Boolean enabled = phaseStopOverrides.get(playerTurn.getId() + ":" + phase.name());
        if (enabled != null) return !enabled;
        if (!isOwnTurn(playerTurn)) {
            // Another person's (or bot's) turn flows without this seat approving each
            // empty-stack step, even when it holds an instant: otherwise the table waits on
            // a nonactive seat at every phase. Checking a phase on that player's row restores
            // the window. Stack responses and blocker/target/payment inputs are separate
            // and never skipped here.
            return true;
        }
        if (getGameController() instanceof PlayerControllerHuman human
                && (phase == PhaseType.COMBAT_DECLARE_ATTACKERS || phase == PhaseType.COMBAT_DECLARE_BLOCKERS)
                && !human.getPlayer().getView().hasAvailableActions()) {
            // The declaration inputs already require their owner's confirmation.
            // Empty-stack priority afterwards needs another click only when the
            // player has a response or explicitly enabled this phase stop.
            return true;
        }
        return !defaultPhaseStop(phase);
    }

    static boolean defaultPhaseStop(PhaseType phase) {
        return phase == PhaseType.MAIN1 || phase == PhaseType.COMBAT_DECLARE_ATTACKERS
                || phase == PhaseType.COMBAT_DECLARE_BLOCKERS || phase == PhaseType.MAIN2;
    }

    // ---------------------------------------------------------------- notifications

    @Override protected void updateCurrentPlayer(PlayerView player) { listener.stateChanged(); }
    @Override public void openView(TrackableCollection<PlayerView> myPlayers) { listener.stateChanged(); }
    @Override public void showCombat() {
        // InputBlock edits the live Combat before declaration is committed.
        // Refresh its view now so provisional assignments reach the next frame.
        if (getGameController() instanceof PlayerControllerHuman human) human.getGame().updateCombatForView();
        listener.stateChanged();
    }
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
    @Override public void setPanelSelection(CardView hostCard) { decisionCard = hostCard; }
    @Override public void setCard(CardView card) { decisionCard = card; }
    @Override public void setPlayerAvatar(LobbyPlayer player, IHasIcon ihi) { }

    void trackDrawEvent(GameEvent event) {
        CardView candidate = takebackCast;
        if (candidate != null) {
            boolean ownCast = event instanceof forge.game.event.GameEventSpellAbilityCast cast
                    && cast.si().getSourceCard() != null && cast.si().getSourceCard().getId() == candidate.getId()
                    && cast.sa().isSpell();
            boolean castMove = event instanceof GameEventCardChangeZone change && change.card().getId() == candidate.getId()
                    && change.from() != null && change.to() != null
                    && change.from().zoneType() == ZoneType.Hand && change.to().zoneType() == ZoneType.Stack;
            if (ownCast) takebackCastSeen = true;
            else if ((event instanceof forge.game.event.GameEventSpellAbilityCast)
                    || (event instanceof GameEventCardChangeZone && !castMove)
                    || event instanceof forge.game.event.GameEventPlayerLivesChanged
                    || event instanceof forge.game.event.GameEventPlayerCounters
                    || event instanceof forge.game.event.GameEventCardCounters
                    || event instanceof forge.game.event.GameEventPlayerDamaged
                    || event instanceof forge.game.event.GameEventCardDamaged
                    || event instanceof forge.game.event.GameEventScry || event instanceof forge.game.event.GameEventSurveil
                    || event instanceof forge.game.event.GameEventShuffle || event instanceof GameEventTurnPhase
                    || event instanceof forge.game.event.GameEventSnapshotRestored
                    || (takebackCastSeen && (event instanceof forge.game.event.GameEventManaPool
                        || event instanceof forge.game.event.GameEventCardTapped))) commitTakeback();
        }
        boolean provisionalMove = event instanceof GameEventCardChangeZone change && isProvisionalCastMove(change);
        if (provisionalMove) pendingCastMoved = true;
        boolean payment = pendingCast != null && event instanceof forge.game.event.GameEventManaPool mana
                && getCurrentPlayer() != null && mana.player().equals(getCurrentPlayer());
        boolean tapActivation = pendingManaTap != null && (event instanceof forge.game.event.GameEventManaPool
                || event instanceof forge.game.event.GameEventCardTapped
                || event instanceof forge.game.event.GameEventPlayerDamaged
                || event instanceof forge.game.event.GameEventPlayerLivesChanged);
        if (event instanceof forge.game.event.GameEventSpellAbilityCast cast) {
            forge.game.spellability.SpellAbility ability = null;
            if (getGameController() instanceof PlayerControllerHuman human) {
                for (var instance : human.getGame().getStack()) {
                    if (instance.getId() == cast.si().getId()) {
                        ability = instance.getSpellAbility();
                        break;
                    }
                }
            }
            targetedEffects.record(cast.si(), getCurrentPlayer(), ability);
        }
        if (pendingManaTap != null && event instanceof forge.game.event.GameEventManaPool mana
                && mana.mode() == forge.game.event.EventValueChangeType.Added
                && getCurrentPlayer() != null && mana.player().equals(getCurrentPlayer())) sawTapMana = true;
        if (event instanceof forge.game.event.GameEventManaPool || event instanceof forge.game.event.GameEventCardTapped
                || event instanceof forge.game.event.GameEventSpellAbilityCast || event instanceof GameEventCardChangeZone
                || event instanceof forge.game.event.GameEventAttackersDeclared
                || event instanceof forge.game.event.GameEventPlayerLivesChanged
                || event instanceof forge.game.event.GameEventCardCounters || event instanceof forge.game.event.GameEventPlayerCounters
                || event instanceof forge.game.event.GameEventPlayerDamaged || event instanceof forge.game.event.GameEventCardDamaged
                || event instanceof forge.game.event.GameEventScry || event instanceof forge.game.event.GameEventSurveil
                || event instanceof forge.game.event.GameEventShuffle || event instanceof forge.game.event.GameEventSnapshotRestored) {
            undoTapCard = null;
            // Forge refunds mana before starting the snapshot restore. This is
            // part of the authorized undo, not a new spend that commits the
            // earlier activations. Reconcile history at the restored checkpoint.
            if (!provisionalMove && !payment && !tapActivation && !undoingMana) {
                manaTapHistory.clear();
                pendingManaLandReturn = null;
                pendingCast = null;
            }
        }
        if (event instanceof forge.game.event.GameEventSpellAbilityCast || event instanceof GameEventCardChangeZone
                || event instanceof forge.game.event.GameEventScry || event instanceof forge.game.event.GameEventSurveil
                || event instanceof forge.game.event.GameEventShuffle || event instanceof forge.game.event.GameEventSnapshotRestored) {
            pendingManaTap = null;
        }
        // Mutations revoke the gesture. A fully undone mana activation may
        // restore its saved permission at the exact authorized checkpoint.
        if (event instanceof forge.game.event.GameEventSnapshotRestored restored) {
            restoringSnapshot = restored.start();
            returnToHandCandidate = -1;
            pendingLandPlay = null;
            pendingCast = null;
        } else if (returnToHandCandidate >= 0 && (event instanceof forge.game.event.GameEventManaPool
                || event instanceof forge.game.event.GameEventCardTapped
                || event instanceof forge.game.event.GameEventSpellAbilityCast
                || event instanceof forge.game.event.GameEventAttackersDeclared
                || event instanceof forge.game.event.GameEventPlayerLivesChanged
                || event instanceof forge.game.event.GameEventPlayerCounters
                || event instanceof forge.game.event.GameEventCardCounters
                || event instanceof forge.game.event.GameEventPlayerDamaged
                || event instanceof forge.game.event.GameEventCardDamaged
                || event instanceof forge.game.event.GameEventScry
                || event instanceof forge.game.event.GameEventSurveil
                || event instanceof forge.game.event.GameEventShuffle
                || (event instanceof GameEventCardChangeZone change && !isProvisionalCastMove(change)))) {
            returnToHandCandidate = -1;
            pendingCast = null;
        }
        if (event instanceof GameEventTurnPhase phase) {
            long nextPhase = getGameView() == null ? -1 : getGameView().getTurn() * 100L + phase.phase().ordinal();
            if (returnToHandCandidate >= 0 && returnPhase != nextPhase) {
                returnToHandCandidate = -1;
                pendingCast = null;
            }
            if (pendingLandPhase != nextPhase) pendingLandPlay = null;
            drawingPlayer = phase.phase() == PhaseType.DRAW ? phase.playerTurn().getId() : -1;
        }
        if (event instanceof GameEventCardChangeZone change && change.from() != null && change.to() != null
                && change.from().zoneType() == ZoneType.Library && change.to().zoneType() == ZoneType.Hand
                && change.to().player().getId() == drawingPlayer
                && getCurrentPlayer() != null && drawingPlayer == getCurrentPlayer().getId()) {
            pendingDraws.add(change.card().getId());
        }
        if (event instanceof GameEventCardChangeZone change && change.from() != null && change.from().zoneType() == ZoneType.Hand) {
            pendingDraws.remove(change.card().getId());
        }
    }

    private boolean isProvisionalCastMove(GameEventCardChangeZone change) {
        CardView cast = pendingCast;
        return cast != null && cast.getId() == change.card().getId()
                && change.from() != null && change.to() != null
                && ((change.from().zoneType() == pendingCastOrigin && change.to().zoneType() == ZoneType.Stack)
                    || (change.from().zoneType() == ZoneType.Stack && change.to().zoneType() == pendingCastOrigin));
    }
    @Override public void handleGameEvent(GameEvent event) {
        trackDrawEvent(event);
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
    /** Stack item whose actionable scan was last recorded, and whether a response can target it. */
    private volatile int respondScanStackId = -1;
    private volatile boolean respondScanCanTarget = true;

    /** Unknown/stale scans conservatively report that the item can be answered. */
    boolean canTargetStackItem(int stackId) {
        return respondScanStackId != stackId || respondScanCanTarget;
    }

    @Override public void setWeaklySelectable(Iterable<CardView> cards) {
        super.setWeaklySelectable(cards);
        // Forge pushes its game-thread actionable scan at each priority prompt; record
        // whether any of it can answer the top item itself (counterspell, Stifle).
        if (getGameController() instanceof PlayerControllerHuman human) {
            var top = human.getGame().getStack().peek();
            if (top == null || human.getInputQueue().getInput() instanceof forge.gamemodes.match.input.InputPayMana) {
                respondScanStackId = -1; // Payment pushes mana sources, not responses.
            } else {
                var actionable = new ArrayList<forge.game.card.Card>();
                for (CardView view : cards) {
                    var card = human.getGame().findByView(view);
                    if (card != null) actionable.add(card);
                }
                respondScanCanTarget = StackInteractionPolicy.canTargetStackItem(human.getPlayer(), actionable, top.getSpellAbility());
                respondScanStackId = top.getId();
            }
        }
        listener.stateChanged();
    }
    @Override public void clearWeaklySelectable() {
        super.clearWeaklySelectable();
        respondScanStackId = -1;
        listener.stateChanged();
    }
}
