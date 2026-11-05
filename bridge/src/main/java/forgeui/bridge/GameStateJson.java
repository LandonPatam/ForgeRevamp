package forgeui.bridge;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import forge.game.GameEntityView;
import forge.game.GameView;
import forge.game.card.CardView;
import forge.game.card.CardView.CardStateView;
import forge.game.card.CounterType;
import forge.game.combat.CombatView;
import forge.game.player.PlayerView;
import forge.game.spellability.StackItemView;
import forge.game.spellability.SpellAbility;
import forge.game.ability.ApiType;
import forge.game.zone.ZoneType;
import forge.gamemodes.match.Selection;
import forge.trackable.TrackableObject;
import forge.player.PlayerControllerHuman;

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
    private static final byte[] MANA = forge.card.mana.ManaAtom.MANATYPES;
    private static final String[] MANA_KEYS = {"W", "U", "B", "R", "G", "C"};
    /** Keywords that change how combat plays out; sent as enum names for on-card badges. */
    private static final forge.game.keyword.Keyword[] COMBAT_KEYWORDS = {
            forge.game.keyword.Keyword.FLYING, forge.game.keyword.Keyword.REACH, forge.game.keyword.Keyword.HASTE,
            forge.game.keyword.Keyword.VIGILANCE, forge.game.keyword.Keyword.MENACE, forge.game.keyword.Keyword.TRAMPLE,
            forge.game.keyword.Keyword.DEATHTOUCH, forge.game.keyword.Keyword.LIFELINK, forge.game.keyword.Keyword.FIRST_STRIKE,
            forge.game.keyword.Keyword.DOUBLE_STRIKE, forge.game.keyword.Keyword.INDESTRUCTIBLE, forge.game.keyword.Keyword.HEXPROOF,
            forge.game.keyword.Keyword.SHROUD, forge.game.keyword.Keyword.WARD, forge.game.keyword.Keyword.PROTECTION,
            forge.game.keyword.Keyword.DEFENDER, forge.game.keyword.Keyword.INFECT, forge.game.keyword.Keyword.WITHER,
            forge.game.keyword.Keyword.SKULK, forge.game.keyword.Keyword.SHADOW, forge.game.keyword.Keyword.FEAR,
            forge.game.keyword.Keyword.INTIMIDATE, forge.game.keyword.Keyword.HORSEMANSHIP
    };

    private final BridgeGuiGame gui;
    private final Map<Integer, CardView> cards;
    private final Map<Integer, PlayerView> players;
    private final Map<Integer, StackItemView> stackItems;
    final forge.gamemodes.match.input.Input input;

    GameStateJson(BridgeGuiGame gui, Map<Integer, CardView> cards, Map<Integer, PlayerView> players, Map<Integer, StackItemView> stackItems) {
        this.gui = gui;
        this.cards = cards;
        this.players = players;
        this.stackItems = stackItems;
        this.input = gui.currentInput();
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
        gui.refreshUndoPermissions();
        root.addProperty("undoPending", gui.isLandUndoPending());
        root.addProperty("me", me == null ? -1 : me.getId());
        root.addProperty("openingHandComplete", gui.openingHandComplete);

        JsonObject game = new JsonObject();
        game.addProperty("turn", gv.getTurn());
        game.addProperty("phase", gv.getPhase() == null ? "" : gv.getPhase().nameForUi);
        game.addProperty("phaseKey", gv.getPhase() == null ? "" : gv.getPhase().name());
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
        root.add("phaseStops", gui.phaseStops());
        JsonArray pendingDraws = new JsonArray();
        gui.pendingDraws.forEach(pendingDraws::add);
        root.add("pendingDraws", pendingDraws);

        JsonArray stack = new JsonArray();
        if (gv.getStack() != null) {
            for (StackItemView si : gv.getStack()) {
                stackItems.put(si.getId(), si);
                stack.add(stackItem(si));
            }
        }
        root.add("stack", stack);
        CardView takeback = gui.takebackCard();
        if (takeback != null) root.add("takebackCast", card(takeback));
        root.add("targetedEffects", gui.targetedEffects.snapshot());
        int autoPassStackId = -1;
        if (gui.getGameController() instanceof PlayerControllerHuman human) {
            var top = human.getGame().getStack().peek();
            if (top != null && stackItems.containsKey(top.getId())
                    && input instanceof forge.gamemodes.match.input.InputPassPriority
                    && StackInteractionPolicy.mayAutoPass(top.getSpellAbility(),
                            top.getSpellAbility().getActivatingPlayer() == human.getPlayer(),
                            human.getPlayer().getView().hasAvailableActions(),
                            gui.canTargetStackItem(top.getId()),
                            StackInteractionPolicy.targetsLocal(stackItems.get(top.getId()), me))) {
                autoPassStackId = top.getId();
            }
        }
        root.addProperty("autoPassStackId", autoPassStackId);

        JsonArray combat = new JsonArray();
        CombatView cv = gv.getCombat();
        if (cv != null) {
            for (CardView attacker : cv.getAttackers()) {
                JsonObject o = new JsonObject();
                o.addProperty("attacker", attacker.getId());
                if (gui.getGameController() instanceof PlayerControllerHuman human) {
                    var liveAttacker = human.getGame().findByView(attacker);
                    var liveCombat = human.getGame().getCombat();
                    o.addProperty("blocked", liveAttacker != null && liveCombat != null && liveCombat.isBlocked(liveAttacker));
                    o.addProperty("trample", liveAttacker != null && liveAttacker.hasKeyword("Trample"));
                }
                GameEntityView def = cv.getDefender(attacker);
                o.addProperty("defender", def == null ? "" : def.toString());
                if (def != null) {
                    o.addProperty("defenderId", def.getId());
                    o.addProperty("defenderKind", def instanceof PlayerView ? "player" : "card");
                }
                JsonArray blockers = new JsonArray();
                var assigned = input instanceof forge.gamemodes.match.input.InputBlock
                        ? cv.getPlannedBlockers(attacker) : cv.getBlockers(attacker);
                if (assigned != null) assigned.forEach(b -> blockers.add(b.getId()));
                o.add("blockers", blockers);
                combat.add(o);
            }
        }
        root.add("combat", combat);
        JsonArray revealed = new JsonArray();
        for (CardView card : gui.revealedCards()) {
            cards.put(card.getId(), card);
            // This callback explicitly authorizes showing these cards for the current prompt.
            revealed.add(describeCard(card, true));
        }
        root.add("revealed", revealed);

        JsonObject prompt;
        synchronized (gui.prompt) {
            prompt = gui.prompt.deepCopy();
        }
        boolean currentPrompt = gui.hasCurrentPrompt(input);
        if (!currentPrompt) {
            // A waiting seat must not inherit the last turn's enabled buttons or
            // declaration text while another player owns Forge's live input.
            prompt = new JsonObject();
            prompt.addProperty("okEnabled", false);
            prompt.addProperty("cancelEnabled", false);
            PlayerView waiting = gv.getPlayers().stream().filter(PlayerView::getHasPriority).findFirst().orElse(gv.getPlayerTurn());
            prompt.addProperty("message", waiting != null && !waiting.equals(me)
                    ? "Waiting for " + waiting.getName() + "." : "Waiting for Forge.");
        }
        prompt.addProperty("inputKind", input == null ? "InputLockUI" : inputKind(input.getClass()));
        if (prompt.has("cardId")) {
            CardView source = cards.get(prompt.get("cardId").getAsInt());
            if (source != null) prompt.add("sourceCard", describeCard(source, gui.mayView(source)));
        }
        Selection sel = currentPrompt ? gui.getSelection() : Selection.NONE;
        JsonArray effectReveal = gui.effectRevealedCards();
        if (!effectReveal.isEmpty()) prompt.add("revealedCards", effectReveal);
        prompt.add("selectable", ids(sel.cards()));
        prompt.add("targets", refs(sel.targets()));
        prompt.add("chosen", refs(sel.chosen()));
        prompt.addProperty("selMin", sel.min());
        prompt.addProperty("selMax", sel.max());
        JsonArray selectionCards = new JsonArray();
        for (CardView card : sel.cards()) {
            cards.put(card.getId(), card);
            selectionCards.add(describeCard(card, gui.mayView(card)));
        }
        prompt.add("cards", selectionCards);
        JsonArray entities = new JsonArray();
        for (TrackableObject offered : sel.targets()) {
            if (offered instanceof StackItemView stackTarget) {
                stackItems.put(stackTarget.getId(), stackTarget);
                JsonObject entry = stackItem(stackTarget);
                entry.addProperty("kind", "stack");
                entities.add(entry);
            } else if (offered instanceof PlayerView playerTarget) {
                entities.add(playerChoice(playerTarget));
            }
        }
        if (gui.getGameController() instanceof PlayerControllerHuman human && input != null) {
            if (input instanceof forge.gamemodes.match.input.InputSelectEntitiesFromList<?> selection) {
                for (var entity : selection.getValidChoices()) {
                    if (entity instanceof forge.game.player.Player player) entities.add(playerChoice(player.getView()));
                }
                if (sel.min() == 0 && sel.max() == selection.getValidChoices().size()) {
                    for (var mode : forge.gamemodes.match.input.MassSelectMode.values()) {
                        if (prompt.has("cancelLabel") && prompt.get("cancelLabel").getAsString().equals(mode.getTranslatedName())) {
                            prompt.addProperty("selectionShortcut", mode.name());
                        }
                    }
                }
            }
            prompt.addProperty("inputKind", inputKind(input.getClass()));
            if (input instanceof forge.gamemodes.match.input.InputConfirmMulligan
                    && forge.StaticData.instance().getMulliganRule() == forge.MulliganDefs.MulliganRule.London) {
                boolean firstFree = human.getGame().getPlayers().size() > 2
                        || human.getGame().getRules().hasAppliedVariant(forge.game.GameType.Brawl);
                prompt.addProperty("mulliganReturnCount", forge.game.mulligan.LondonMulligan.returnCount(
                        human.getPlayer().getStats().getMulliganCount(), firstFree));
            }
        }
        prompt.add("entities", entities);
        root.add("prompt", prompt);

        JsonArray log = new JsonArray();
        if (gv.getGameLog() != null) {
            gv.getGameLog().getLogEntries(null).stream().limit(40).forEach(e -> log.add(e.toString()));
        }
        root.add("log", log);
        root.add("asks", toArray(gui.openAsks()));
        return root;
    }

    private JsonObject playerChoice(PlayerView player) {
        players.put(player.getId(), player);
        JsonObject entry = new JsonObject();
        entry.addProperty("id", player.getId());
        entry.addProperty("kind", "player");
        entry.addProperty("name", player.getName());
        return entry;
    }

    private JsonObject stackItem(StackItemView item) {
        JsonObject result = new JsonObject();
        result.addProperty("id", item.getId());
        result.addProperty("text", item.getText());
        result.addProperty("ability", item.isAbility());
        result.addProperty("trigger", item.isTrigger());
        result.addProperty("targetsLocal", StackInteractionPolicy.targetsLocal(item, gui.getCurrentPlayer()));
        if (item.getSourceCard() != null) {
            JsonObject source = card(item.getSourceCard());
            result.addProperty("sourceId", item.getSourceCard().getId());
            result.addProperty("sourceName", source.has("name") ? source.get("name").getAsString() : "Hidden source");
            result.add("card", source);
        }
        if (item.getActivatingPlayer() != null) {
            result.addProperty("controller", item.getActivatingPlayer().getId());
            result.addProperty("controllerName", item.getActivatingPlayer().getName());
        }
        JsonArray targets = new JsonArray();
        stackTargets(item, targets, new java.util.HashSet<>());
        result.add("targets", targets);
        return result;
    }

    private void stackTargets(StackItemView item, JsonArray targets, java.util.Set<String> seen) {
        if (item.getTargetCards() != null) for (CardView target : item.getTargetCards()) {
            if (!seen.add("card:" + target.getId())) continue;
            JsonObject face = card(target);
            JsonObject entry = new JsonObject();
            entry.addProperty("kind", "card");
            entry.addProperty("id", target.getId());
            entry.addProperty("name", face.has("name") ? face.get("name").getAsString() : "Hidden card");
            entry.add("card", face);
            targets.add(entry);
        }
        if (item.getTargetPlayers() != null) for (PlayerView target : item.getTargetPlayers()) {
            if (seen.add("player:" + target.getId())) targets.add(playerChoice(target));
        }
        if (item.getTargetStackItems() != null) for (StackItemView target : item.getTargetStackItems()) {
            if (!seen.add("stack:" + target.getId())) continue;
            JsonObject entry = new JsonObject();
            entry.addProperty("kind", "stack");
            entry.addProperty("id", target.getId());
            entry.addProperty("text", target.getText());
            if (target.getSourceCard() != null) {
                JsonObject face = card(target.getSourceCard());
                entry.add("card", face);
                entry.addProperty("name", face.has("name") ? face.get("name").getAsString() : "Hidden source");
            }
            targets.add(entry);
        }
        if (item.getSubInstance() != null) stackTargets(item.getSubInstance(), targets, seen);
    }

    static boolean isRoutineInteraction(SpellAbility ability) {
        if (ability == null || ability.getApi() == null || ability.usesTargeting()) return false;
        if (ability.getSubAbility() != null && !isRoutineInteraction(ability.getSubAbility())) return false;
        if (java.util.Set.of(ApiType.Draw, ApiType.GainLife, ApiType.PutCounter, ApiType.Proliferate,
                ApiType.Scry, ApiType.Surveil, ApiType.Explore, ApiType.Token).contains(ability.getApi())) return true;
        return isRoutineCast(ability);
    }

    static boolean isRoutineCast(SpellAbility ability) {
        // Targets, damage and chained effects retain their response window.
        if (ability == null || ability.usesTargeting() || ability.getSubAbility() != null) return false;
        if (ability.isSpell() && (ability.getApi() == ApiType.PermanentCreature || ability.getApi() == ApiType.PermanentNoncreature)) return true;
        // Resolve untargeted land searches/land-return triggers into their real
        // engine decision. Passing priority is not answering that decision.
        if (ability.getApi() != ApiType.ChangeZone) return false;
        String origin = ability.getParamOrDefault("Origin", "");
        String destination = ability.getParamOrDefault("Destination", "");
        String type = ability.getParamOrDefault("ChangeType", "");
        return (origin.equals("Library") && (destination.equals("Battlefield") || destination.equals("Hand")) && (type.startsWith("Land") || type.equals("Basic")))
                || (origin.equals("Battlefield") && destination.equals("Hand") && type.equals("Land.YouCtrl") && ability.hasParam("Mandatory"));
    }

    static String inputKind(Class<?> type) {
        // Cleanup/discard and other effects use anonymous input subclasses.
        while (type.getSimpleName().isEmpty() && type.getSuperclass() != null) type = type.getSuperclass();
        return type.getSimpleName();
    }

    private JsonObject player(PlayerView p, GameView gv) {
        JsonObject o = new JsonObject();
        o.addProperty("id", p.getId());
        o.addProperty("name", p.getName());
        o.addProperty("avatar", p.getAvatarIndex());
        if (gv.getDeck(p) != null) o.addProperty("deckName", gv.getDeck(p).getName());
        String portrait = p.getAvatarCardImageKey() == null ? null : gui.portraits.get(p.getAvatarCardImageKey());
        if (portrait != null) o.addProperty("portrait", portrait);
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
        JsonObject result = describeCard(c, gui.mayView(c));
        if (!result.has("hidden")) {
            result.addProperty("weakSelection", gui.getWeakSelectableStrength(c));
            JsonObject actions = new JsonObject();
            actions.addProperty("returnToHand", gui.mayReturnToHand(c));
            actions.addProperty("undoTap", gui.mayUndoTap(c));
            result.add("availableActions", actions);
        }
        return result;
    }

    static JsonObject describeCard(CardView c, boolean visible) {
        JsonObject o = new JsonObject();
        o.addProperty("id", c.getId());
        if (!visible) {
            o.addProperty("hidden", true);
            return o;
        }
        CardStateView s = c.getCurrentState();
        o.addProperty("name", c.getName());
        o.addProperty("tapped", c.isTapped());
        o.addProperty("sick", c.isSick());
        o.addProperty("token", c.isToken());
        o.addProperty("commander", c.isCommander());
        if (c.isCommander() && c.getOwner() != null) {
            int casts = c.getOwner().getCommanderCast(c);
            o.addProperty("commanderCasts", casts);
            o.addProperty("commanderTax", casts * 2);
        }
        o.addProperty("faceDown", c.isFaceDown());
        // Colors chosen as the permanent entered (e.g. "choose a color"), as W/U/B/R/G.
        try {
            List<String> chosen = c.getChosenColors();
            if (chosen != null && !chosen.isEmpty()) {
                JsonArray colors = new JsonArray();
                for (String name : chosen) {
                    String code = switch (name == null ? "" : name.trim().toLowerCase(java.util.Locale.ROOT)) {
                        case "white", "w" -> "W";
                        case "blue", "u" -> "U";
                        case "black", "b" -> "B";
                        case "red", "r" -> "R";
                        case "green", "g" -> "G";
                        default -> "";
                    };
                    if (!code.isEmpty()) colors.add(code);
                }
                if (colors.size() > 0) o.add("chosenColors", colors);
            }
        } catch (RuntimeException e) {
            // A view mid-update omits the indicator for this snapshot only.
        }
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
            JsonArray urls = new JsonArray();
            CardArtwork.urls(s.getImageKey()).forEach(urls::add);
            o.add("imageUrls", urls);
            if (c.isToken()) o.add("tokenImageUrls", urls);
            // Current keywords, including ones granted by other effects (equipment, auras, anthems).
            JsonArray keywords = new JsonArray();
            try {
                if (s.getKeywords() != null) for (var keyword : COMBAT_KEYWORDS) if (s.hasKeyword(keyword)) keywords.add(keyword.name());
                if (s.hasWard() && !keywords.contains(new com.google.gson.JsonPrimitive("WARD"))) keywords.add("WARD");
            } catch (RuntimeException e) {
                // A view mid-update omits badges for this snapshot only.
            }
            o.add("keywords", keywords);
        }
        try {
            o.addProperty("text", c.getText());
        } catch (RuntimeException e) {
            o.addProperty("text", "");
        }
        if (c.getDamage() > 0) o.addProperty("damage", c.getDamage());
        o.add("counters", counters(c.getCounters()));
        if (c.getAttachedTo() != null) {
            o.addProperty("attachedTo", c.getAttachedTo().getId());
            o.addProperty("attachmentKind", c.getAttachedTo() instanceof CardView ? "card" : "player");
        }
        return o;
    }

    static JsonObject describePaperCard(forge.item.PaperCard card) {
        JsonObject o = new JsonObject();
        o.addProperty("id", -1);
        o.addProperty("name", card.getName());
        o.addProperty("imageKey", card.getImageKey(false));
        o.addProperty("typeLine", card.getRules().getType().toString());
        o.addProperty("manaCost", card.getRules().getManaCost().toString());
        o.addProperty("text", card.getRules().getMainPart().getOracleText());
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
