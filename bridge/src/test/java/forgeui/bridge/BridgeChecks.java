package forgeui.bridge;

import com.google.gson.*;
import forge.game.card.CardView;
import forge.game.cost.Cost;
import forge.game.spellability.SpellAbility;
import forge.game.spellability.SpellAbilityView;
import java.util.*;
import java.util.concurrent.*;

/** Dependency-free regression checks; run with tools/test.ps1 after Maven test-compile/package. */
public final class BridgeChecks {
    private static int checks;
    private static JsonElement json(String value) { return JsonParser.parseString(value); }
    private static JsonObject object(String value) { return json(value).getAsJsonObject(); }
    private static void check(boolean value, String message) {
        checks++;
        if (!value) throw new AssertionError(message);
    }
    private static void rejects(Runnable action) {
        try { action.run(); } catch (IllegalArgumentException expected) { checks++; return; }
        throw new AssertionError("Invalid input was accepted");
    }
    private static void valid(JsonObject ask, String value) {
        BridgeProtocol.validateAnswer(ask, json(value)); checks++;
    }
    private static void invalid(JsonObject ask, String value) {
        rejects(() -> BridgeProtocol.validateAnswer(ask, json(value)));
    }

    public static void main(String[] args) throws Exception {
        String accented = "1 Troll of Khazad-d\u00fbm|LTR|[111]\r\n1 Nazg\u00fbl\r\n1 Lothl\u00f3rien Revealed\r\n1 Minsc & Boo, Timeless Heroes\r\n";
        check(DeckFiles.decode(accented.getBytes(java.nio.charset.StandardCharsets.UTF_8)).equals(accented), "UTF-8 deck names preserve accents");
        check(DeckFiles.decode(accented.getBytes(java.nio.charset.Charset.forName("windows-1252"))).equals(accented), "Legacy Windows decks preserve accents instead of replacement glyphs");
        check(DeckFiles.decode(("\ufeff" + accented).getBytes(java.nio.charset.StandardCharsets.UTF_8)).equals(accented), "UTF-8 BOM is removed before section parsing");
        check(DeckFiles.decode(("\ufeff" + accented).getBytes(java.nio.charset.StandardCharsets.UTF_16LE)).equals(accented), "BOM-marked UTF-16LE decks remain readable");
        check(DeckFiles.decode(("\ufeff" + accented).getBytes(java.nio.charset.StandardCharsets.UTF_16BE)).equals(accented), "BOM-marked UTF-16BE decks remain readable");
        matchSettings();
        java.nio.file.Path languages = java.nio.file.Path.of(BridgeChecks.class.getProtectionDomain().getCodeSource().getLocation().toURI())
                .resolve("../../../forge/forge-gui/res/languages").normalize();
        forge.util.Localizer.getInstance().initialize("en-US", languages.toString());
        for (int mulligans = 0; mulligans <= 4; mulligans++) {
            check(forge.game.mulligan.LondonMulligan.returnCount(mulligans, true) == Math.max(0, mulligans - 1), "Multiplayer London preview must preserve the free first mulligan");
            check(forge.game.mulligan.LondonMulligan.returnCount(mulligans, false) == mulligans, "London without a free mulligan must count every redraw");
        }
        check(GameStateJson.isRoutineCast(stackAbility(forge.game.ability.ApiType.PermanentNoncreature, true, false)), "Simple artifact casts should allow routine priority");
        check(GameStateJson.isRoutineCast(stackAbility(forge.game.ability.ApiType.PermanentCreature, true, false)), "Simple creature casts should allow routine priority");
        check(!GameStateJson.isRoutineCast(stackAbility(forge.game.ability.ApiType.PermanentNoncreature, true, true)), "Targeted permanents must retain the response window");
        check(!GameStateJson.isRoutineCast(stackAbility(forge.game.ability.ApiType.DealDamage, true, false)), "Damage spells must retain the response window");
        check(!GameStateJson.isRoutineCast(stackAbility(forge.game.ability.ApiType.DamageAll, true, false)), "Untargeted damage must also pause");
        check(!GameStateJson.isRoutineCast(stackAbility(forge.game.ability.ApiType.PermanentCreature, false, false)), "Activated/triggered effects must pause");
        check(!GameStateJson.isRoutineCast(null), "An unknown stack item must never auto-pass");
        for (var api : List.of(forge.game.ability.ApiType.Draw, forge.game.ability.ApiType.GainLife, forge.game.ability.ApiType.PutCounter,
                forge.game.ability.ApiType.Scry, forge.game.ability.ApiType.Surveil, forge.game.ability.ApiType.Proliferate, forge.game.ability.ApiType.Token)) {
            check(GameStateJson.isRoutineInteraction(stackAbility(api, false, false)), "Routine local " + api + " effects should proceed into engine decisions");
            check(!GameStateJson.isRoutineInteraction(stackAbility(api, false, true)), "Targeted " + api + " effects must retain their response window");
        }
        check(!GameStateJson.isRoutineInteraction(stackAbility(forge.game.ability.ApiType.DamageAll, true, false)), "Board wipes must retain an explicit response window");
        check(!GameStateJson.isRoutineInteraction(stackAbility(null, false, false)), "Abilities without a classified API must retain the response window");
        stackInteractionPolicy();
        check(GameStateJson.inputKind(new java.util.ArrayList<>() {}.getClass()).equals("ArrayList"), "Anonymous inputs must retain their named input kind");
        check(BridgeProtocol.manaColor(0) == forge.card.mana.ManaAtom.COLORLESS, "Wire colorless mana must map to Forge's pool key, not the no-color value");
        check(BridgeProtocol.manaColor(16) == forge.card.mana.ManaAtom.GREEN, "Colored mana must preserve its pool key");
        rejects(() -> BridgeProtocol.manaColor(3));
        SpellAbility search = stackAbility(forge.game.ability.ApiType.ChangeZone, false, false);
        search.getMapParams().putAll(Map.of("Origin", "Library", "Destination", "Battlefield", "ChangeType", "Land.Basic"));
        check(GameStateJson.isRoutineCast(search), "Land search should resolve into its engine chooser");
        search.getMapParams().put("ChangeType", "Creature");
        check(!GameStateJson.isRoutineCast(search), "Other zone-changing effects retain their response window");
        SpellAbility bounce = stackAbility(forge.game.ability.ApiType.ChangeZone, false, false);
        bounce.getMapParams().putAll(Map.of("Origin", "Battlefield", "Destination", "Hand", "ChangeType", "Land.YouCtrl", "Mandatory", "True"));
        check(GameStateJson.isRoutineCast(bounce), "Required land return should resolve into its engine chooser");
        bounce.getMapParams().remove("Mandatory");
        check(!GameStateJson.isRoutineCast(bounce), "Other bounce effects must not be auto-classified");
        targetedEffects();
        check(TargetedEffectHistory.isMassRemoval(stackAbility(forge.game.ability.ApiType.DestroyAll, true, false)), "Untargeted destruction must produce a board-wide notice");
        check(!TargetedEffectHistory.isMassRemoval(stackAbility(forge.game.ability.ApiType.Destroy, true, true)), "Single-target removal must keep the targeted notice");
        var massDamage = stackAbility(forge.game.ability.ApiType.DamageAll, true, false);
        check(!TargetedEffectHistory.isMassRemoval(massDamage), "Player-only damage must not be labeled permanent removal");
        massDamage.getMapParams().put("ValidCards", "Creature");
        check(TargetedEffectHistory.isMassRemoval(massDamage), "Mass creature damage must be visible even without targets");
        var massExile = stackAbility(forge.game.ability.ApiType.ChangeZoneAll, true, false);
        massExile.getMapParams().putAll(Map.of("Origin", "Battlefield", "Destination", "Exile"));
        check(TargetedEffectHistory.isMassRemoval(massExile), "Mass exile of permanents must produce a notice");
        massExile.getMapParams().put("Origin", "Graveyard");
        check(!TargetedEffectHistory.isMassRemoval(massExile), "Graveyard-only exile is not a board wipe");
        blocking(languages.getParent().getParent().toString());
        for (var phase : forge.game.phase.PhaseType.values()) {
            check(BridgeGuiGame.defaultPhaseStop(phase) == java.util.Set.of(
                    forge.game.phase.PhaseType.MAIN1, forge.game.phase.PhaseType.COMBAT_DECLARE_ATTACKERS,
                    forge.game.phase.PhaseType.COMBAT_DECLARE_BLOCKERS, forge.game.phase.PhaseType.MAIN2).contains(phase),
                    "Only M1, DA, DB and M2 should stop by default: " + phase);
        }
        SpellAbility manaChoice = new SpellAbility(null, Cost.Zero) {
            @Override public boolean canPlay() { return true; }
            @Override public boolean isManaAbility() { return true; }
            @Override public void resolve() {}
        };
        manaChoice.setManaPart(new forge.game.spellability.AbilityManaPart(manaChoice, Map.of("Produced", "Combo U B")));
        check(BridgeGuiGame.directManaColors(manaChoice).equals(List.of("U", "B")), "Literal single-mana choices must expand in engine order");
        check(BridgeGuiGame.directManaLabel("{T}: Add {W}, {B}, or {G}.", "G").equals("{T}: Add {G}."), "Tri-land choice must show only the selected mana");
        check(BridgeGuiGame.directManaLabel("{T}: Add {W} or {B}.", "B").equals("{T}: Add {B}."), "Two-color mana choice remains exact");
        check(BridgeGuiGame.directManaLabel("{T}: Add {W}, {U}, or {B}. This deals 1 damage to you.", "U").equals("{T}: Add {U}. This deals 1 damage to you."), "Mana labels preserve other consequences");
        manaChoice.getMapParams().put("Amount", "2");
        check(BridgeGuiGame.directManaColors(manaChoice).isEmpty(), "Multiple-mana choices must retain the engine chooser");
        manaChoice.getMapParams().remove("Amount");
        manaChoice.getMapParams().put("Chooser", "Opponent");
        check(BridgeGuiGame.directManaColors(manaChoice).isEmpty(), "Another player's color decision must not be preselected");
        manaChoice.getMapParams().clear();
        manaChoice.setManaPart(new forge.game.spellability.AbilityManaPart(manaChoice, Map.of("Produced", "Combo ColorIdentity")));
        check(BridgeGuiGame.directManaColors(manaChoice).isEmpty(), "Dynamic color menus must retain the engine chooser");
        JsonObject choose = object("{kind:'choose',min:1,max:2,options:[{},{}]}".replace('\'', '"'));
        valid(choose, "[0]"); valid(choose, "[1,0]");
        for (String value : List.of("[]", "[0,0]", "[2]", "[-1]", "[0.5]", "[\"0\"]", "null", "{}", "[true]")) invalid(choose, value);
        JsonObject order = choose.deepCopy(); order.addProperty("kind", "order"); order.addProperty("min", 2);
        valid(order, "[1,0]"); invalid(order, "[0]");
        JsonObject distribution = object("{\"kind\":\"distribute\",\"amount\":4,\"atLeastOne\":false,\"options\":[{},{}]}");
        valid(distribution, "[0,4]");
        for (String value : List.of("[4]", "[1,1]", "[-1,5]", "[1.5,2.5]", "[2147483647,2147483647]", "null")) invalid(distribution, value);
        distribution.addProperty("atLeastOne", true);
        invalid(distribution, "[0,4]"); valid(distribution, "[1,3]");
        distribution.addProperty("maySkip", true); valid(distribution, "null");
        distribution.addProperty("atLeastOne", false);
        distribution.add("lethal", json("[2]"));
        distribution.addProperty("overrideOrder", false); distribution.addProperty("divideDamage", false);
        invalid(distribution, "[1,3]"); valid(distribution, "[2,2]");
        distribution.addProperty("overrideOrder", true); invalid(distribution, "[1,3]");
        distribution.addProperty("divideDamage", true); valid(distribution, "[1,3]");
        JsonObject input = object("{\"kind\":\"input\",\"numeric\":true}");
        valid(input, "\"12\""); valid(input, "null");
        invalid(input, "12"); invalid(input, "\"1.5\""); invalid(input, "\"2147483648\"");
        rejects(() -> BridgeProtocol.integer(json("2147483648")));
        rejects(() -> BridgeProtocol.revision(json("-1")));
        rejects(() -> BridgeProtocol.revision(json("1.1")));
        check(BridgeProtocol.revision(json("42")) == 42, "Valid revision rejected");

        BlockingQueue<JsonObject> events = new LinkedBlockingQueue<>();
        BridgeGuiGame gui = new BridgeGuiGame(new BridgeGuiGame.Listener() {
            public void stateChanged() {}
            public void send(JsonObject message) { events.add(message.deepCopy()); }
        });
        ExecutorService engine = Executors.newSingleThreadExecutor();
        try {
            forge.util.ITriggerEvent click = new forge.util.ITriggerEvent() {
                public int getButton() { return 1; }
                public int getX() { return 0; }
                public int getY() { return 0; }
            };
            SpellAbilityView disabled = ability(false);
            SpellAbilityView enabled = ability(true);
            check(gui.getAbilityToPlay(null, List.of(disabled), click) == null, "A lone disabled ability must never execute from a click");
            check(gui.getAbilityToPlay(null, List.of(disabled, enabled), click) == enabled, "Only the playable ability may be auto-selected from a click");
            check(gui.getAbilityToPlay(null, List.of(disabled, ability(false)), click) == null, "All-disabled clicked abilities must not open a choice");
            check(gui.getAbilityToPlay(null, List.of(disabled), null) == disabled, "Engine-triggered ability preparation must not be rejected for lacking manual activation permission");
            SpellAbilityView otherEnabled = ability(true);
            Future<SpellAbilityView> abilityChoice = engine.submit(() -> gui.getAbilityToPlay(null, List.of(disabled, enabled, otherEnabled), click));
            JsonObject abilityAsk = next(events, "ask");
            check(abilityAsk.getAsJsonArray("options").size() == 2, "Disabled abilities must be excluded from choices");
            gui.answer(abilityAsk.get("id").getAsInt(), json("[1]"));
            check(abilityChoice.get(3, TimeUnit.SECONDS) == otherEnabled, "Filtered ability indices must map back to the correct ability");
            next(events, "askClosed");
            Future<List<String>> result = engine.submit(() -> gui.getChoices("Pick", 1, 1, List.of("A", "B"), null, null));
            JsonObject ask = next(events, "ask");
            int id = ask.get("id").getAsInt();
            rejects(() -> gui.answer(id, json("[]")));
            check(!result.isDone() && gui.openAsks().size() == 1, "Rejected answer closed the decision");
            // A reconnect reads the same still-pending decision from the snapshot's asks list.
            check(gui.openAsks().get(0).equals(ask), "Pending ask was not retained");
            gui.answer(id, json("[1]"));
            check(result.get(3, TimeUnit.SECONDS).equals(List.of("B")), "Choice did not map to the engine item");
            next(events, "askClosed");
            check(gui.openAsks().isEmpty(), "Resolved ask retained");
            rejects(() -> gui.answer(id, json("[0]")));

            var warningCard = new forge.item.PaperCard(forge.card.CardRules.fromScript(List.of("Name:Warning card", "ManaCost:1 G", "Types:Creature Beast", "PT:2/2", "Oracle:Example rules.")), "TST", forge.card.CardRarity.Common);
            Future<?> warning = engine.submit(() -> gui.getChoices("AI cannot play these cards well", -1, -1, List.of("=== Main ===", warningCard), null, null));
            ask = next(events, "ask");
            var warningFace = ask.getAsJsonArray("options").get(1).getAsJsonObject().getAsJsonObject("card");
            check(warningFace.get("name").getAsString().equals("Warning card") && warningFace.get("imageKey").getAsString().contains("Warning card"), "AI warning must carry the revealed paper card's exact face");
            gui.answer(ask.get("id").getAsInt(), json("true"));
            warning.get(3, TimeUnit.SECONDS); next(events, "askClosed");

            Future<List<String>> ordered = engine.submit(() -> gui.order("Order", "", 0, 0, List.of("A", "B"), null, null, false, false).ordered());
            ask = next(events, "ask"); gui.answer(ask.get("id").getAsInt(), json("[1,0]"));
            check(ask.get("autoOrder").getAsBoolean(), "A full ordering must expose Forge's Auto behavior");
            check(ordered.get(3, TimeUnit.SECONDS).equals(List.of("B", "A")), "Ordering lost permutation"); next(events, "askClosed");

            Map<Object, Integer> recipients = new LinkedHashMap<>(); recipients.put("A", 0); recipients.put("B", 0);
            Future<Map<Object, Integer>> allocated = engine.submit(() -> gui.assignGenericAmount(null, recipients, 4, true, "counters"));
            ask = next(events, "ask"); gui.answer(ask.get("id").getAsInt(), json("[1,3]"));
            check(allocated.get(3, TimeUnit.SECONDS).equals(Map.of("A", 1, "B", 3)), "Distribution mapped to wrong recipients"); next(events, "askClosed");

            Future<String> entered = engine.submit(() -> gui.showInputDialog("Name", "", null, "", null, false));
            ask = next(events, "ask"); gui.answer(ask.get("id").getAsInt(), json("null"));
            check(entered.get(3, TimeUnit.SECONDS) == null, "Input cancellation lost"); next(events, "askClosed");

            Future<?> message = engine.submit(() -> gui.message("Notice", ""));
            ask = next(events, "ask"); gui.answer(ask.get("id").getAsInt(), json("true"));
            message.get(3, TimeUnit.SECONDS); next(events, "askClosed");

            CardView card = new CardView(123, null, "Private card");
            check(GameStateJson.describeCard(card, false).equals(object("{\"id\":123,\"hidden\":true}")), "Hidden card contains private fields");
            Future<?> reveal = engine.submit(() -> gui.getChoices("Look at these cards", -1, -1, List.of(card), null, null));
            ask = next(events, "ask");
            check(ask.getAsJsonArray("options").get(0).getAsJsonObject().getAsJsonObject("card").get("name").getAsString().equals("Private card"), "An explicit reveal must show its authorized face even in a private zone");
            gui.answer(ask.get("id").getAsInt(), json("true"));
            reveal.get(3, TimeUnit.SECONDS); next(events, "askClosed");
            CardView other = new CardView(124, null, "Another viewed card");
            var delayed = new forge.game.player.DelayedReveal(List.of(), forge.game.zone.ZoneType.Library, null);
            delayed.getCards().add(card); delayed.getCards().add(other);
            Future<forge.game.GameEntityView> pickRevealed = engine.submit(() -> gui.chooseSingleEntityForEffect("Choose artifact", List.of(card), delayed, true));
            ask = next(events, "ask");
            check(ask.get("kind").getAsString().equals("choose") && ask.getAsJsonArray("revealedCards").size() == 2, "A delayed reveal and its eligible choices belong to the same decision");
            check(ask.getAsJsonArray("options").size() == 1 && ask.getAsJsonArray("options").get(0).getAsJsonObject().getAsJsonObject("card").get("id").getAsInt() == 123, "Viewed-only cards must never become eligible choices");
            gui.answer(ask.get("id").getAsInt(), json("[0]"));
            check(pickRevealed.get(3, TimeUnit.SECONDS) == card, "The combined reveal must preserve the exact engine choice instance"); next(events, "askClosed");
            gui.showRevealedCards(List.of(card)); check(gui.revealedCards().equals(List.of(card)), "Reveal callback lost cards");
            gui.hideRevealedCards(); check(gui.revealedCards().isEmpty(), "Hidden reveal persisted");
            gui.setWeaklySelectable(List.of(card, card)); check(gui.getWeakSelectableStrength(card) == 2, "Weak selection weight lost");
            gui.clearWeaklySelectable(); check(gui.getWeakSelectableStrength(card) == 0, "Weak selection not cleared");
        } finally { engine.shutdownNow(); }
        System.out.println("PASS: " + checks + " bridge regression checks");
    }

    private static JsonObject next(BlockingQueue<JsonObject> events, String type) throws InterruptedException {
        JsonObject value = events.poll(3, TimeUnit.SECONDS);
        check(value != null && value.get("type").getAsString().equals(type), "Missing " + type + " event");
        return value;
    }

    private static void targetedEffects() {
        var local = new forge.game.player.PlayerView(42, null);
        local.set(forge.trackable.TrackableProperty.Name, "You");
        var opponent = new forge.game.player.PlayerView(71, null);
        opponent.set(forge.trackable.TrackableProperty.Name, "Opponent");
        var commander = new CardView(899, null, "Commander");
        commander.set(forge.trackable.TrackableProperty.Owner, local);
        commander.set(forge.trackable.TrackableProperty.IsCommander, true);
        local.set(forge.trackable.TrackableProperty.CommanderCast, new HashMap<>(Map.of(899, 2)));
        commander.set(forge.trackable.TrackableProperty.Zone, forge.game.zone.ZoneType.Command);
        check(GameStateJson.describeCard(commander, true).get("commanderTax").getAsInt() == 4, "Two command-zone casts must display four generic commander tax");
        commander.set(forge.trackable.TrackableProperty.Zone, forge.game.zone.ZoneType.Graveyard);
        commander.set(forge.trackable.TrackableProperty.Zone, forge.game.zone.ZoneType.Command);
        check(GameStateJson.describeCard(commander, true).get("commanderTax").getAsInt() == 4, "Zone returns must not increment the tax without a cast");
        var source = new CardView(900, null, "Mortify");
        source.set(forge.trackable.TrackableProperty.Zone, forge.game.zone.ZoneType.Stack);
        var target = new CardView(901, null, "Atraxa");
        target.set(forge.trackable.TrackableProperty.Controller, local);
        var item = new forge.game.spellability.StackItemView(902, null);
        item.set(forge.trackable.TrackableProperty.SourceCard, source);
        item.set(forge.trackable.TrackableProperty.ActivatingPlayer, opponent);
        item.set(forge.trackable.TrackableProperty.TargetCards, new forge.trackable.TrackableCollection<>(target));
        var history = new TargetedEffectHistory();
        history.record(item, local);
        check(history.snapshot().size() == 1, "Targeted enemy spell must be retained");
        var event = history.snapshot().get(0).getAsJsonObject();
        check(event.getAsJsonObject("source").get("name").getAsString().equals("Mortify"), "Notice must retain the spell identity");
        check(event.getAsJsonArray("targets").get(0).getAsJsonObject().get("name").getAsString().equals("Atraxa"), "Notice must identify the local target");
        check(event.getAsJsonArray("targets").get(0).getAsJsonObject().getAsJsonObject("card").get("name").getAsString().equals("Atraxa"), "Notice must freeze the exact target card face");
        target.set(forge.trackable.TrackableProperty.Name, "Changed after resolution");
        history.record(item, local);
        check(history.snapshot().size() == 1 && history.snapshot().get(0).equals(event), "Resolution and duplicate events must not alter the captured notice");
        item.set(forge.trackable.TrackableProperty.ActivatingPlayer, local);
        var own = new TargetedEffectHistory(); own.record(item, local);
        check(own.snapshot().isEmpty(), "Own spells must not create enemy-hit popups");
        item.set(forge.trackable.TrackableProperty.ActivatingPlayer, opponent);
        target.set(forge.trackable.TrackableProperty.Controller, opponent);
        own.record(item, local);
        check(own.snapshot().isEmpty(), "Spells targeting another player must not create a local popup");
        target.set(forge.trackable.TrackableProperty.Controller, local);
        target.set(forge.trackable.TrackableProperty.Facedown, true);
        source.set(forge.trackable.TrackableProperty.Zone, forge.game.zone.ZoneType.Hand);
        own.record(item, local);
        var hidden = own.snapshot().get(0).getAsJsonObject();
        check(hidden.getAsJsonObject("source").equals(object("{\"id\":900,\"hidden\":true}")), "A hidden source must not disclose its name, image or rules");
        check(hidden.getAsJsonArray("targets").get(0).getAsJsonObject().get("name").getAsString().equals("Face-down card"), "Face-down targets must not disclose their name");
        check(hidden.getAsJsonArray("targets").get(0).getAsJsonObject().getAsJsonObject("card").get("hidden").getAsBoolean(), "Target thumbnails must preserve face-down privacy");
        for (int i = 0; i < 40; i++) {
            var next = new forge.game.spellability.StackItemView(1000 + i, null);
            next.set(forge.trackable.TrackableProperty.SourceCard, source);
            next.set(forge.trackable.TrackableProperty.ActivatingPlayer, opponent);
            next.set(forge.trackable.TrackableProperty.TargetCards, new forge.trackable.TrackableCollection<>(target));
            own.record(next, local);
        }
        check(own.snapshot().size() == 32, "Targeted history must stay bounded");
	    var wipeHistory = new TargetedEffectHistory();
	    item.set(forge.trackable.TrackableProperty.TargetCards, new forge.trackable.TrackableCollection<CardView>());
	    source.set(forge.trackable.TrackableProperty.Zone, forge.game.zone.ZoneType.Stack);
	    wipeHistory.record(item, local, stackAbility(forge.game.ability.ApiType.DestroyAll, true, false));
	    check(wipeHistory.snapshot().size() == 1 && wipeHistory.snapshot().get(0).getAsJsonObject().get("kind").getAsString().equals("massRemoval"), "Board wipes must survive fast resolution without a single target");
    }

    private static forge.player.LobbyPlayerHuman testPlayer(String name) {
        return new forge.player.LobbyPlayerHuman(name) {
            @Override public forge.game.player.Player createIngamePlayer(forge.game.Game game, int id) {
                var player = new forge.game.player.Player(getName(), game, id);
                player.setFirstController(new forge.player.PlayerControllerHuman(game, player, this) {
                    @Override public void pushBlockerCandidates(forge.game.player.Player defender, forge.game.combat.Combat combat) { }
                });
                return player;
            }
        };
    }

    private static forge.game.card.Card testCreature(forge.game.player.Player owner, String name) {
        var rules = forge.card.CardRules.fromScript(List.of("Name:" + name, "ManaCost:1", "Types:Creature Beast", "PT:2/3"));
        var paper = new forge.item.PaperCard(rules, "", forge.card.CardRarity.Common);
        var card = forge.game.card.CardFactory.getCard(paper, owner, owner.getGame());
        owner.getZone(forge.game.zone.ZoneType.Battlefield).add(card);
        return card;
    }

    private static void stackInteractionPolicy() {
        var api = (java.util.function.Function<forge.game.ability.ApiType, SpellAbility>) type -> stackAbility(type, false, false);
        var creature = stackAbility(forge.game.ability.ApiType.PermanentCreature, true, false);
        check(StackInteractionPolicy.mayAutoPass(creature, false, false, false, false), "An opponent's normal creature resolves without a response");
        check(StackInteractionPolicy.mayAutoPass(creature, false, true, false, false), "An unrelated instant must not hold an opponent's creature or commander cast");
        check(!StackInteractionPolicy.mayAutoPass(creature, false, true, true, false), "A counterspell that can target the creature preserves the window");
        check(StackInteractionPolicy.mayAutoPass(creature, true, true, false, false), "Own routine casts keep their existing automatic commit");
        check(!StackInteractionPolicy.mayAutoPass(null, false, false, false, false), "An unknown stack item must never auto-pass");
        for (var type : List.of(forge.game.ability.ApiType.Draw, forge.game.ability.ApiType.GainLife,
                forge.game.ability.ApiType.Scry, forge.game.ability.ApiType.Surveil, forge.game.ability.ApiType.Token,
                forge.game.ability.ApiType.Discard, forge.game.ability.ApiType.Pump, forge.game.ability.ApiType.Mill)) {
            var ability = api.apply(type);
            check(StackInteractionPolicy.mayAutoPass(ability, false, true, false, false), "Opponent self-only " + type + " should proceed even when we hold an unrelated response");
            ability.getMapParams().put("Defined", "You");
            check(StackInteractionPolicy.isSelfContained(ability), "Explicit controller recipients remain self-only for " + type);
            ability.getMapParams().put("Defined", "Player");
            check(!StackInteractionPolicy.isSelfContained(ability), "Untargeted " + type + " affecting everyone must not be treated as self-only");
        }
        // Monarch end-step draw, Kindred Discovery and Spellbound Dragon / The Ur-Dragon attack triggers.
        var monarch = api.apply(forge.game.ability.ApiType.Draw);
        monarch.getMapParams().put("Defined", "You");
        check(StackInteractionPolicy.mayAutoPass(monarch, false, true, false, false), "The monarch draw must not hold other seats");
        check(!StackInteractionPolicy.mayAutoPass(monarch, false, true, true, false), "Holding Stifle-like responses keeps the trigger window");
        var spellbound = api.apply(forge.game.ability.ApiType.Draw);
        var discard = new forge.game.spellability.AbilitySub(forge.game.ability.ApiType.Discard, null, null, new java.util.HashMap<>(Map.of("Mode", "TgtChoose")));
        discard.setSubAbility(new forge.game.spellability.AbilitySub(forge.game.ability.ApiType.Pump, null, null, new java.util.HashMap<>(Map.of("NumAtt", "+X"))));
        spellbound.setSubAbility(discard);
        check(StackInteractionPolicy.mayAutoPass(spellbound, false, true, false, false), "Draw/discard/self-pump attack triggers must not hold defenders");
        var urDragon = api.apply(forge.game.ability.ApiType.Draw);
        urDragon.setSubAbility(new forge.game.spellability.AbilitySub(forge.game.ability.ApiType.ChangeZone, null, null,
                new java.util.HashMap<>(Map.of("Origin", "Hand", "Destination", "Battlefield", "ChangeType", "Permanent"))));
        check(StackInteractionPolicy.isSelfContained(urDragon), "Putting a permanent from your own hand onto the battlefield is self-only");
        var bounce = api.apply(forge.game.ability.ApiType.ChangeZone);
        bounce.getMapParams().putAll(Map.of("Origin", "Battlefield", "Destination", "Hand", "ChangeType", "Creature", "Hidden", "True"));
        check(!StackInteractionPolicy.isSelfContained(bounce), "Untargeted battlefield choices can reach other players' permanents");
        var counters = api.apply(forge.game.ability.ApiType.PutCounter);
        counters.getMapParams().put("Defined", "Self");
        check(StackInteractionPolicy.isSelfContained(counters), "Counters on the opponent's source can proceed");
        counters.getMapParams().put("Choices", "Card");
        check(!StackInteractionPolicy.isSelfContained(counters), "Broad counter choices can affect local permanents");
        check(!StackInteractionPolicy.isSelfContained(api.apply(forge.game.ability.ApiType.Proliferate)), "Opponent proliferate can include our counters");
        var wipe = stackAbility(forge.game.ability.ApiType.DestroyAll, true, false);
        check(!StackInteractionPolicy.mayAutoPass(wipe, false, true, false, false), "Board wipes keep a response window when we can respond");
        check(StackInteractionPolicy.mayAutoPass(wipe, false, false, false, false), "Board wipes resolve without a pause when we have no response");
        var edict = stackAbility(forge.game.ability.ApiType.Sacrifice, true, false);
        edict.getMapParams().put("Defined", "Player");
        check(!StackInteractionPolicy.mayAutoPass(edict, false, true, false, false), "Each-player sacrifice keeps a response window");
        check(!StackInteractionPolicy.isSelfContained(stackAbility(null, false, false)), "Unknown effects remain reviewable");
        var removal = stackAbility(forge.game.ability.ApiType.Destroy, true, true);
        check(StackInteractionPolicy.mayAutoPass(removal, false, false, false, false), "Removal proceeds when we have no response");
        check(!StackInteractionPolicy.mayAutoPass(removal, false, true, false, false), "A legal response still pauses targeted removal");
        check(!StackInteractionPolicy.mayAutoPass(removal, false, true, false, true), "Removal of our permanent retains the window when we can respond");
        check(StackInteractionPolicy.mayAutoPass(removal, true, false, false, true), "Our completed target choice proceeds when Forge finds no legal response");
        check(!StackInteractionPolicy.mayAutoPass(removal, true, true, false, true), "Our targeted effect still preserves a legal response window");
        var token = stackAbility(forge.game.ability.ApiType.Token, true, false);
        token.getMapParams().put("TokenOwner", "Opponent");
        check(!StackInteractionPolicy.isSelfContained(token), "Token effects giving another player permanents must not be classified as self-only");
        var local = new forge.game.player.PlayerView(81, null);
        var opponent = new forge.game.player.PlayerView(82, null);
        var card = new CardView(83, null, "Target");
        card.set(forge.trackable.TrackableProperty.Controller, opponent);
        card.set(forge.trackable.TrackableProperty.Owner, opponent);
        var item = new forge.game.spellability.StackItemView(84, null);
        item.set(forge.trackable.TrackableProperty.TargetCards, new forge.trackable.TrackableCollection<>(card));
        check(!StackInteractionPolicy.targetsLocal(item, local), "Other players' targets are not local threats");
        card.set(forge.trackable.TrackableProperty.Owner, local);
        check(StackInteractionPolicy.targetsLocal(item, local), "A stolen local card still counts as local impact");
        card.set(forge.trackable.TrackableProperty.Owner, opponent);
        card.set(forge.trackable.TrackableProperty.Controller, local);
        check(StackInteractionPolicy.targetsLocal(item, local), "A controlled permanent counts as local impact");
        item.set(forge.trackable.TrackableProperty.TargetCards, new forge.trackable.TrackableCollection<CardView>());
        item.set(forge.trackable.TrackableProperty.TargetPlayers, new forge.trackable.TrackableCollection<>(local));
        check(StackInteractionPolicy.targetsLocal(item, local), "Direct player targets must retain attention");
    }

    private static void blocking(String assets) {
        forge.gui.GuiBase.setInterface(new HeadlessGuiBase(assets));
        forge.util.Lang.createInstance("en-US");
        var players = List.of(new forge.game.player.RegisteredPlayer(new forge.deck.Deck()).setPlayer(testPlayer("Defender")),
                new forge.game.player.RegisteredPlayer(new forge.deck.Deck()).setPlayer(testPlayer("Attacker")));
        var rules = new forge.game.GameRules(forge.game.GameType.Constructed);
        var game = new forge.game.Game(players, rules, new forge.game.Match(rules, players, "Blocking regression"));
        var defender = game.getPlayers().get(0);
        var attackerPlayer = game.getPlayers().get(1);
        var controller = (forge.player.PlayerControllerHuman) defender.getController();
        var gui = new BridgeGuiGame(new BridgeGuiGame.Listener() {
            public void stateChanged() { }
            public void send(JsonObject message) { }
        });
        controller.setGui(gui);
        gui.setOriginalGameController(defender.getView(), controller);
        gui.setCurrentPlayer(defender.getView());
        gui.setGameView(game.getView());
        var soloGui = new BridgeGuiGame(new BridgeGuiGame.Listener() {
            public void stateChanged() { }
            public void send(JsonObject message) { }
        });
        soloGui.setOriginalGameController(defender.getView(), controller);
        soloGui.setCurrentPlayer(defender.getView());
        for (var phase : forge.game.phase.PhaseType.values()) {
            for (boolean available : List.of(false, true, false)) {
                defender.getView().setHasAvailableActions(available);
                for (var player : game.getPlayers()) {
                    check(soloGui.isUiSetToSkipPhase(player.getView(), phase) == !BridgeGuiGame.defaultPhaseStop(phase),
                            "Solo-game stops pause on every player's turn regardless of legal actions: " + phase);
                }
            }
        }
        soloGui.setPhaseStop(attackerPlayer.getView(), forge.game.phase.PhaseType.MAIN1, false);
        check(soloGui.isUiSetToSkipPhase(attackerPlayer.getView(), forge.game.phase.PhaseType.MAIN1),
                "Disabling a solo-game bot main phase skips it");
        soloGui.setPhaseStop(attackerPlayer.getView(), forge.game.phase.PhaseType.MAIN1, true);
        check(!soloGui.isUiSetToSkipPhase(attackerPlayer.getView(), forge.game.phase.PhaseType.MAIN1),
                "Re-enabling a solo-game bot main phase pauses again");
        gui.setOnlineMatch(true);
        for (var phase : forge.game.phase.PhaseType.values()) {
            defender.getView().setHasAvailableActions(false);
            check(gui.isUiSetToSkipPhase(attackerPlayer.getView(), phase), "An idle nonactive seat never gates another player's phase: " + phase);
            boolean declarationPriority = phase == forge.game.phase.PhaseType.COMBAT_DECLARE_ATTACKERS
                    || phase == forge.game.phase.PhaseType.COMBAT_DECLARE_BLOCKERS;
            check(gui.isUiSetToSkipPhase(defender.getView(), phase) == (declarationPriority || !BridgeGuiGame.defaultPhaseStop(phase)), "Own-turn stops skip redundant combat priority without a response: " + phase);
            defender.getView().setHasAvailableActions(true);
            check(gui.isUiSetToSkipPhase(attackerPlayer.getView(), phase), "A nonactive seat holding a response still lets another turn flow without a stop: " + phase);
            check(gui.isUiSetToSkipPhase(defender.getView(), phase) == !BridgeGuiGame.defaultPhaseStop(phase), "A legal active-player response retains the default combat window: " + phase);
            if (phase != forge.game.phase.PhaseType.UNTAP) {
                for (boolean available : List.of(false, true, false)) {
                    defender.getView().setHasAvailableActions(available);
                    var stops = gui.phaseStops();
                    check(stops.getAsJsonObject(String.valueOf(defender.getId())).get(phase.name()).getAsBoolean()
                                    == BridgeGuiGame.defaultPhaseStop(phase),
                            "Displayed own-turn defaults stay stable as legal actions change: " + phase);
                    check(!stops.getAsJsonObject(String.valueOf(attackerPlayer.getId())).get(phase.name()).getAsBoolean(),
                            "Another player's turn shows no default stop online, matching its behavior: " + phase);
                }
            }
        }
        defender.getView().setHasAvailableActions(false);
        gui.setPhaseStop(attackerPlayer.getView(), forge.game.phase.PhaseType.UPKEEP, true);
        check(!gui.isUiSetToSkipPhase(attackerPlayer.getView(), forge.game.phase.PhaseType.UPKEEP), "An explicit phase stop remains available without a legal response");
        for (boolean available : List.of(true, false, true)) {
            defender.getView().setHasAvailableActions(available);
            check(gui.phaseStops().getAsJsonObject(String.valueOf(attackerPlayer.getId())).get("UPKEEP").getAsBoolean(),
                    "An enabled opponent stop remains displayed across action changes");
        }
        gui.setPhaseStop(defender.getView(), forge.game.phase.PhaseType.MAIN1, false);
        defender.getView().setHasAvailableActions(true);
        check(!gui.phaseStops().getAsJsonObject(String.valueOf(defender.getId())).get("MAIN1").getAsBoolean()
                        && gui.isUiSetToSkipPhase(defender.getView(), forge.game.phase.PhaseType.MAIN1),
                "An explicitly disabled own default remains off even when a response is available");
        gui.setPhaseStop(defender.getView(), forge.game.phase.PhaseType.MAIN1, true);
        defender.getView().setHasAvailableActions(false);
        gui.setPhaseStop(defender.getView(), forge.game.phase.PhaseType.COMBAT_DECLARE_BLOCKERS, true);
        check(!gui.isUiSetToSkipPhase(defender.getView(), forge.game.phase.PhaseType.COMBAT_DECLARE_BLOCKERS), "An explicit own-turn blocker stop still pauses with no legal response");
        var attacker = testCreature(attackerPlayer, "Attacker");
        var blocker = testCreature(defender, "Blocker");
        // Stinkdrinker Bandit: "Whenever a Rogue you control attacks and isn't blocked, it gets +2/+1."
        var bandit = testCreature(attackerPlayer, "Stinkdrinker Bandit");
        var banditPump = forge.game.ability.AbilityFactory.getAbility("DB$ Pump | NumAtt$ +2 | NumDef$ +1 | Defined$ TriggeredAttacker", bandit);
        banditPump.setActivatingPlayer(attackerPlayer);
        banditPump.setTriggeringObject(forge.game.ability.AbilityKey.Attacker, attacker);
        check(StackInteractionPolicy.isSelfContained(banditPump), "A trigger pumping the opponent's own attacker is self-only");
        check(StackInteractionPolicy.mayAutoPass(banditPump, false, true, false, false), "An opponent's own-attacker pump must not hold a seat with an unrelated instant");
        check(!StackInteractionPolicy.mayAutoPass(banditPump, false, true, true, false), "Holding a Stifle-like response keeps the pump trigger window");
        banditPump.setTriggeringObject(forge.game.ability.AbilityKey.Attacker, blocker);
        check(!StackInteractionPolicy.isSelfContained(banditPump), "A triggered pump on our creature keeps the response window");
        var unfilled = forge.game.ability.AbilityFactory.getAbility("DB$ Pump | NumAtt$ +1 | Defined$ Remembered", bandit);
        unfilled.setActivatingPlayer(attackerPlayer);
        check(!StackInteractionPolicy.isSelfContained(unfilled), "A reference not yet filled in keeps the response window");
        var scry = forge.game.ability.AbilityFactory.getAbility("SP$ Scry | Cost$ U | ScryNum$ 1", blocker);
        scry.setSubAbility(new forge.game.spellability.AbilitySub(forge.game.ability.ApiType.Draw, blocker, null, Map.of("NumCards", "1")));
        check(GameStateJson.isRoutineInteraction(scry), "A local scry-then-draw chain must proceed into its real engine choices");
        scry.setSubAbility(new forge.game.spellability.AbilitySub(forge.game.ability.ApiType.DamageAll, blocker, null, Map.of("NumDmg", "1")));
        check(!GameStateJson.isRoutineInteraction(scry), "A harmless first step must not auto-pass a damaging sub-ability");
        var tapped = testCreature(defender, "Tapped blocker");
        bulkEntityChoices(defender, attackerPlayer, blocker, attacker);
	    var pool = defender.getManaPool();
	    var spell = forge.game.ability.AbilityFactory.getAbility("SP$ Draw | Cost$ 3 G | NumCards$ 1", blocker);
	    spell.setActivatingPlayer(defender);
	    var cost = new forge.game.mana.ManaCostBeingPaid(new forge.card.mana.ManaCost(new forge.card.mana.ManaCostParser("3 G")));
	    for (byte color : new byte[] {1, 16, 32, 32}) pool.addManaNoEvent(new forge.game.mana.Mana(color, blocker, null, defender));
	    check(!pool.tryPayCostWithColor((byte) 0, spell, cost, spell.getPayingMana()), "The old colorless key cannot spend actual floating colorless mana");
	    for (int color : new int[] {1, 16, 0, 0}) {
	        check(pool.tryPayCostWithColor(BridgeProtocol.manaColor(color), spell, cost, spell.getPayingMana()), "W/G/C/C must pay each part of Forgotten Ancient's 3G cost");
	    }
	    check(cost.isPaid() && pool.totalMana() == 0, "One white, one green, and two colorless must completely pay 3G");
        tapped.setTapped(true);
        var combat = new forge.game.combat.Combat(attackerPlayer);
        game.getPhaseHandler().setCombat(combat);
        combat.addAttacker(attacker, defender);
        forge.gui.GuiBase.getInterface().invokeInEdtAndWait(() -> {
            var input = new forge.gamemodes.match.input.InputBlock(controller, defender, combat);
            check(input.selectCard(attacker, null, null), "An attacker click must select the blocking target");
            check(input.selectCard(blocker, null, null) && combat.isBlocking(blocker, attacker), "A legal creature click must assign the block in Forge");
            check(input.selectCard(blocker, null, null) && !combat.isBlocking(blocker, attacker), "Clicking the same blocker must remove its assignment");
            check(!input.selectCard(tapped, null, null) && !combat.isBlocking(tapped), "A tapped creature must be rejected as a blocker");
            check(input.selectCard(blocker, null, null) && forge.game.combat.CombatUtil.validateBlocks(combat, defender) == null, "The final declaration must pass Forge's block validation");
        });
        inputLifecycle(controller, gui);
    }

    private static void inputLifecycle(forge.player.PlayerControllerHuman controller, BridgeGuiGame gui) {
        class FixtureInput extends forge.gamemodes.match.input.InputSyncronizedBase {
            FixtureInput() { super(controller); }
            @Override public String getActivateAction(forge.game.card.Card card) { return null; }
            @Override protected void showMessage() {
                gui.showPromptMessage(getOwner(), "Fixture decision");
                gui.updateButtons(getOwner(), "OK", "Cancel", true, false, true);
            }
        }
        var first = new FixtureInput();
        var next = new FixtureInput();
        checkedEdt(() -> controller.getInputQueue().setInput(first));
        checkedEdt(() -> check(gui.hasCurrentPrompt(first), "A presented input owns its buttons"));
        checkedEdt(() -> {
            controller.getInputQueue().removeInput(first);
            check(gui.currentInput() == null && !gui.hasCurrentPrompt(first) && !gui.hasCurrentPrompt(null),
                    "A removed input loses permission immediately even before Forge paints a waiting prompt");
            controller.getInputQueue().setInput(next);
            check(!gui.hasCurrentPrompt(next), "A replacement input cannot inherit the previous decision's buttons");
        });
        checkedEdt(() -> {
            check(gui.hasCurrentPrompt(next) && !gui.hasCurrentPrompt(first), "Only the presented replacement accepts actions");
            controller.getInputQueue().removeInput(next);
        });
    }

    private static void checkedEdt(Runnable action) {
        // HeadlessGuiBase logs exceptions in callbacks; propagate assertions to
        // the test thread so a failed EDT assertion cannot report a passing suite.
        var result = new CompletableFuture<Void>();
        forge.gui.GuiBase.getInterface().invokeInEdtAndWait(() -> {
            try { action.run(); result.complete(null); }
            catch (Throwable failure) { result.completeExceptionally(failure); }
        });
        result.join();
    }

    private static void bulkEntityChoices(forge.game.player.Player local, forge.game.player.Player opponent,
                                           forge.game.card.Card mine, forge.game.card.Card theirs) {
        var events = new LinkedBlockingQueue<JsonObject>();
        var gui = new BridgeGuiGame(new BridgeGuiGame.Listener() {
            public void stateChanged() { }
            public void send(JsonObject message) { events.add(message.deepCopy()); }
        });
        gui.setCurrentPlayer(local.getView());
        List<forge.game.GameEntityView> choices = List.of(mine.getView(), theirs.getView(), opponent.getView());
        var engine = Executors.newSingleThreadExecutor();
        try {
            var result = engine.submit(() -> gui.chooseEntitiesForEffect("Proliferate", choices, 0, choices.size(), null));
            var ask = next(events, "ask");
            check(ask.get("bulkSelection").getAsBoolean() && ask.get("localPlayerId").getAsInt() == local.getId(), "Any-number entity choices must advertise the local selection shortcut");
            check(ask.getAsJsonArray("options").size() == 3, "The shortcut must preserve opponents and players as individual choices");
            check(ask.getAsJsonArray("options").get(0).getAsJsonObject().get("controllerId").getAsInt() == local.getId(), "Shortcut ownership must use the current controller");
            check(ask.get("kind").getAsString().equals("choose"), "Proliferate is a selection, not an ordering decision");
            gui.answer(ask.get("id").getAsInt(), json("[0,2]"));
            check(result.get(3, TimeUnit.SECONDS).equals(List.of(mine.getView(), opponent.getView())), "Mixed permanent/player choices must map back to exact engine objects");
            next(events, "askClosed");
            var none = engine.submit(() -> gui.chooseEntitiesForEffect("Proliferate", choices, 0, choices.size(), null));
            ask = next(events, "ask");
            gui.answer(ask.get("id").getAsInt(), json("[]"));
            check(none.get(3, TimeUnit.SECONDS).isEmpty(), "Choosing no proliferate recipients must remain valid");
            next(events, "askClosed");
        } catch (Exception error) {
            throw new AssertionError("Bulk entity selection failed", error);
        } finally {
            engine.shutdownNow();
        }
    }

    private static void matchSettings() throws Exception {
        var human = object("{\"name\":\"Pilot\",\"avatar\":2}");
        check(MatchSetup.profile(human).get("name").getAsString().equals("Pilot"), "Match profiles preserve player names");
        check(MatchSetup.profile(object("{\"name\":\"Pilot\",\"avatar\":125}")).get("avatar").getAsInt() == 125, "The last Forge preset is a valid avatar selection");
        for (String bad : List.of("{\"name\":\"\"}", "{\"name\":\"Pilot\",\"avatar\":126}", "{\"name\":\"Pilot\",\"portrait\":\"not an image\"}")) {
            boolean rejected = false;
            try { MatchSetup.profile(object(bad)); } catch (Exception expected) { rejected = true; }
            check(rejected, "Invalid names, portraits and avatar choices must be rejected");
        }
        for (String mode : List.of("unknown", "precon", "commander")) {
            var setup = new JsonObject(); setup.add("human", human);
            var bot = new JsonObject(); bot.addProperty("name", "Bot"); bot.addProperty("mode", mode);
            var bots = new JsonArray(); bots.add(bot); setup.add("bots", bots);
            boolean rejected = false;
            try { MatchSetup.prepare(setup, null, ""); } catch (IllegalArgumentException expected) { rejected = true; }
            check(rejected, "Unknown sources and missing selected Forge deck IDs must be rejected");
        }
        for (int count : List.of(0, 1, 3, 4)) {
            var setup = new JsonObject(); setup.add("human", human);
            var bots = new JsonArray();
            for (int index = 0; index < count; index++) bots.add(object("{\"name\":\"Bot\",\"mode\":\"generated\"}"));
            setup.add("bots", bots);
            boolean accepted;
            try { accepted = MatchSetup.prepare(setup, null, "").getAsJsonArray("bots").size() == count; }
            catch (IllegalArgumentException expected) { accepted = false; }
            check(accepted == (count >= 1 && count <= 3), "Match settings accept exactly one to three bots");
        }
    }

    private static SpellAbility stackAbility(forge.game.ability.ApiType apiType, boolean spellFlag, boolean targetedFlag) {
        return new SpellAbility(null, Cost.Zero) {
            @Override public boolean canPlay() { return true; }
            @Override public boolean isSpell() { return spellFlag; }
            @Override public void resolve() { }
            @Override public boolean usesTargeting() { return targetedFlag; }
            @Override public forge.game.ability.ApiType getApi() { return apiType; }
        };
    }

    private static SpellAbilityView ability(boolean playable) {
        SpellAbility ability = new SpellAbility(null, Cost.Zero) {
            @Override public boolean canPlay() { return playable; }
            @Override public boolean canPlay(boolean optionalCosts) { return playable; }
            @Override public void resolve() {}
        };
        SpellAbilityView view = ability.getView();
        view.updateCanPlay(ability);
        return view;
    }
}
