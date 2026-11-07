package forgeui.bridge;

import forge.game.ability.ApiType;
import forge.game.card.Card;
import forge.game.player.Player;
import forge.game.player.PlayerView;
import forge.game.spellability.SpellAbility;
import forge.game.spellability.StackItemView;
import forge.game.zone.ZoneType;

import java.util.EnumSet;
import java.util.List;
import java.util.Set;

/** Presentation policy only: Forge still puts spells on the stack and owns every decision. */
final class StackInteractionPolicy {
    private StackInteractionPolicy() { }

    /** Recipient parameters that may name players/cards other than the effect's controller. */
    private static final List<String> RECIPIENTS = List.of("Defined", "DefinedPlayer", "DefinedCards", "Chooser",
            "OptionalDecider", "TokenOwner", "TokenController", "TokenAttachTo", "AttachedTo", "AttachedToPlayer");
    private static final Set<String> SELF = Set.of("You", "Self", "SourceController");
    /** Effects that, with no foreign recipients and no targets, only touch their controller's own
     *  library, hand, graveyard, life, permanents or tokens. */
    private static final Set<ApiType> SELF_APIS = EnumSet.of(ApiType.Draw, ApiType.Discard, ApiType.GainLife,
            ApiType.LoseLife, ApiType.Scry, ApiType.Surveil, ApiType.Explore, ApiType.Connive, ApiType.Token,
            ApiType.Investigate, ApiType.Pump, ApiType.Animate, ApiType.Tap, ApiType.Untap, ApiType.Mill,
            ApiType.Dig, ApiType.DigUntil, ApiType.RearrangeTopOfLibrary, ApiType.Shuffle, ApiType.Sacrifice,
            ApiType.Discover, ApiType.Cleanup, ApiType.StoreSVar);

    static boolean targetsLocal(StackItemView item, PlayerView local) {
        if (item == null || local == null) return false;
        if (item.getTargetPlayers() != null) for (var player : item.getTargetPlayers()) {
            if (player.equals(local)) return true;
        }
        if (item.getTargetCards() != null) for (var card : item.getTargetCards()) {
            if (local.equals(card.getController()) || local.equals(card.getOwner())) return true;
        }
        if (item.getTargetStackItems() != null) for (var target : item.getTargetStackItems()) {
            if (local.equals(target.getActivatingPlayer())) return true;
        }
        return targetsLocal(item.getSubInstance(), local);
    }

    /** Untargeted effects on players that the table only needs to hear about (Smart: notice, no stop). */
    private static final Set<ApiType> NOTICE_APIS = EnumSet.of(ApiType.Draw, ApiType.GainLife, ApiType.LoseLife,
            ApiType.Mill, ApiType.Scry, ApiType.Surveil);

    /**
     * Smart stack policy for one seat.
     * @param hasResponse    Forge found any affordable non-mana spell/ability for this player
     * @param canTargetItem  one of those can target this stack item itself (counterspell, Stifle)
     */
    static boolean mayAutoPass(SpellAbility ability, boolean ownEffect, boolean hasResponse,
                               boolean canTargetItem, boolean targetsLocal) {
        if (ability == null) return false;
        if (!hasResponse) return true;
        if (ownEffect) return GameStateJson.isRoutineInteraction(ability) || isSelfContained(ability);
        // Another player's instant or sorcery always offers a response window.
        if (isInstantOrSorcery(ability)) return false;
        // Abilities that only touch their controller's own things (even when they target them)
        // never hold other seats, and untargeted player effects such as "each opponent loses 1
        // life" pass with a notice. A response that can answer the item itself keeps the window;
        // effects on our things, board wipes and unknown effects keep it too.
        return !targetsLocal && !canTargetItem && (isSelfContained(ability) || isPlayerNotice(ability));
    }

    static boolean isInstantOrSorcery(SpellAbility ability) {
        if (ability == null || !ability.isSpell()) return false;
        Card host = ability.getHostCard();
        return host != null && (host.isInstant() || host.isSorcery());
    }

    /** True when the effect and every sub-ability only involve their controller's own things. */
    static boolean isSelfContained(SpellAbility ability) {
        if (!isSelfContainedPart(ability)) return false;
        return ability.getSubAbility() == null || isSelfContained(ability.getSubAbility());
    }

    /** This part alone (not its sub-abilities) only involves its controller's own things. */
    private static boolean isSelfContainedPart(SpellAbility ability) {
        if (ability == null || ability.getApi() == null) return false;
        if (ability.hasParam("Radiance")) return false;
        // A target is only self-contained once chosen, and only if every target is the controller's own.
        if (ability.usesTargeting() && !targetsOnlyController(ability)) return false;
        for (String key : RECIPIENTS) {
            if (ability.hasParam(key) && !SELF.contains(ability.getParam(key))
                    && !resolvesToControllerOnly(ability, ability.getParam(key))) return false;
        }
        ApiType api = ability.getApi();
        if (api == ApiType.PermanentCreature || api == ApiType.PermanentNoncreature) return ability.isSpell();
        if (api == ApiType.PutCounter) {
            // Proliferate-like choices can reach other players' permanents.
            for (String key : List.of("Choices", "EachFromSource", "PutOnDefined", "PutOnEachOther")) {
                if (ability.hasParam(key)) return false;
            }
            return true;
        }
        if (api == ApiType.ChangeZone) return isOwnZoneChange(ability);
        return SELF_APIS.contains(api);
    }

    private static Player controllerOf(SpellAbility ability) {
        if (ability.getActivatingPlayer() != null) return ability.getActivatingPlayer();
        return ability.getHostCard() == null ? null : ability.getHostCard().getController();
    }

    private static boolean targetsOnlyController(SpellAbility ability) {
        Player controller = controllerOf(ability);
        var targets = ability.getTargets();
        if (controller == null || targets == null || targets.isEmpty()) return false;
        for (var target : targets) {
            if (target instanceof Player player) {
                if (!player.equals(controller)) return false;
            } else if (target instanceof Card card) {
                if (!controller.equals(card.getController())) return false;
            } else {
                return false; // Stack items and other objects are never routine.
            }
        }
        return true;
    }

    static boolean isPlayerNotice(SpellAbility ability) {
        return !noticePlayers(ability).isEmpty();
    }

    /**
     * Players affected by an untargeted draw/life/mill/scry effect that reaches beyond its controller
     * ("each opponent loses 1 life", "each player draws"); empty when the effect is anything else.
     */
    static Set<Player> noticePlayers(SpellAbility ability) {
        Set<Player> affected = new java.util.LinkedHashSet<>();
        if (ability == null) return affected;
        Player controller = controllerOf(ability);
        boolean reachesOthers = false;
        for (SpellAbility part = ability; part != null; part = part.getSubAbility()) {
            if (isSelfContainedPart(part)) continue;
            if (part.getApi() == null || !NOTICE_APIS.contains(part.getApi()) || part.usesTargeting()
                    || part.hasParam("Radiance") || part.getHostCard() == null) return Set.of();
            for (String key : RECIPIENTS) {
                if (!part.hasParam(key) || SELF.contains(part.getParam(key))) continue;
                if (!key.equals("Defined") && !key.equals("DefinedPlayer")) return Set.of();
                try {
                    var objects = forge.game.ability.AbilityUtils.getDefinedObjects(part.getHostCard(), part.getParam(key), part);
                    if (objects.isEmpty()) return Set.of();
                    for (var object : objects) {
                        if (!(object instanceof Player player)) return Set.of();
                        affected.add(player);
                        if (!player.equals(controller)) reachesOthers = true;
                    }
                } catch (RuntimeException unreadable) {
                    return Set.of();
                }
            }
        }
        return reachesOthers ? affected : Set.of();
    }

    /**
     * A recipient named by reference (TriggeredAttacker, Enchanted, Remembered, ParentTarget...)
     * is self-only when Forge resolves it, right now, to the effect's controller and/or cards
     * that player controls. Nothing resolved, a stack object, or an unreadable reference keeps
     * the response window: the reference may not be filled in until resolution.
     */
    private static boolean resolvesToControllerOnly(SpellAbility ability, String defined) {
        Card host = ability.getHostCard();
        if (host == null) return false;
        Player controller = ability.getActivatingPlayer() != null ? ability.getActivatingPlayer() : host.getController();
        if (controller == null) return false;
        try {
            var objects = forge.game.ability.AbilityUtils.getDefinedObjects(host, defined, ability);
            if (objects.isEmpty()) return false;
            for (var object : objects) {
                if (object instanceof Player player) {
                    if (!player.equals(controller)) return false;
                } else if (object instanceof Card card) {
                    if (!controller.equals(card.getController())) return false;
                } else {
                    return false;
                }
            }
            return true;
        } catch (RuntimeException unreadable) {
            return false;
        }
    }

    private static boolean isOwnZoneChange(SpellAbility ability) {
        String origin = ability.getParamOrDefault("Origin", "");
        if (origin.isEmpty()) return false;
        String type = ability.getParamOrDefault("ChangeType", "");
        for (String zone : origin.split(",")) {
            switch (zone.trim()) {
                // Hidden zones are the controller's own unless DefinedPlayer says otherwise.
                case "Hand", "Library", "Sideboard", "Command", "Graveyard", "Exile" -> { }
                case "Battlefield" -> {
                    boolean onlySource = type.isEmpty() && !ability.hasParam("Hidden");
                    if (!onlySource && !type.contains("YouCtrl") && !type.contains("YouOwn")) return false;
                }
                default -> { return false; }
            }
        }
        return true;
    }

    /** Whether any of the player's actionable cards has a spell/ability that could target the top stack item. */
    static boolean canTargetStackItem(Player player, Iterable<Card> actionable, SpellAbility top) {
        if (player == null || top == null) return false;
        for (Card card : actionable) {
            try {
                for (SpellAbility sa : card.getAllPossibleAbilities(player, true)) {
                    if (sa.isManaAbility()) continue;
                    for (SpellAbility part = sa; part != null; part = part.getSubAbility()) {
                        var restrictions = part.getTargetRestrictions();
                        if (restrictions != null && restrictions.getZone() != null
                                && restrictions.getZone().contains(ZoneType.Stack)
                                && top.canBeTargetedBy(part)) {
                            return true;
                        }
                    }
                }
            } catch (RuntimeException unknown) {
                return true; // Keep the response window when Forge cannot answer cleanly.
            }
        }
        return false;
    }
}
