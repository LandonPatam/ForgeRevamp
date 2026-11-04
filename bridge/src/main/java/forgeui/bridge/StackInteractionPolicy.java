package forgeui.bridge;

import forge.game.ability.ApiType;
import forge.game.player.PlayerView;
import forge.game.spellability.SpellAbility;
import forge.game.spellability.StackItemView;

/** Presentation policy only: Forge still puts spells on the stack and owns every decision. */
final class StackInteractionPolicy {
    private StackInteractionPolicy() { }

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

    static boolean mayAutoPass(SpellAbility ability, boolean ownEffect, boolean hasResponse, boolean targetsLocal) {
        if (ownEffect) return GameStateJson.isRoutineInteraction(ability) || (ability != null && !hasResponse);
        return !hasResponse && !targetsLocal && isRoutineOpponentEffect(ability);
    }

    static boolean isRoutineOpponentEffect(SpellAbility ability) {
        if (ability == null || ability.getApi() == null) return false;
        if (ability.getSubAbility() != null && !isRoutineOpponentEffect(ability.getSubAbility())) return false;
        if (ability.hasParam("Radiance")) return false;
        // Unknown recipient definitions can include us even without explicit targets.
        for (String key : java.util.List.of("Defined", "DefinedPlayer", "Chooser", "OptionalDecider", "TokenOwner", "TokenController", "TokenAttachTo")) {
            if (ability.hasParam(key) && !java.util.Set.of("You", "Self", "SourceController").contains(ability.getParam(key))) return false;
        }
        if (ability.usesTargeting()) {
            // The frozen stack view has already excluded local cards, players and
            // spells. Only explicit-target effects qualify; mass/unknown APIs don't.
            return java.util.Set.of(ApiType.Draw, ApiType.GainLife, ApiType.PutCounter,
                    ApiType.Destroy, ApiType.ChangeZone, ApiType.DealDamage, ApiType.Pump,
                    ApiType.Tap, ApiType.Untap, ApiType.Counter).contains(ability.getApi())
                    && !ability.hasParam("Choices") && !ability.hasParam("EachFromSource")
                    && !ability.hasParam("PutOnDefined") && !ability.hasParam("PutOnEachOther");
        }
        // Proliferate and broad counter-placement choices can affect our permanents.
        if (ability.getApi() == ApiType.PutCounter) {
            if (!ability.getParamOrDefault("Defined", "").equals("Self")) return false;
            for (String key : java.util.List.of("Choices", "EachFromSource", "PutOnDefined", "PutOnEachOther")) {
                if (ability.hasParam(key)) return false;
            }
            return true;
        }
        if (java.util.Set.of(ApiType.Draw, ApiType.GainLife, ApiType.Scry, ApiType.Surveil,
                ApiType.Explore, ApiType.Token).contains(ability.getApi())) return true;
        return GameStateJson.isRoutineCast(ability);
    }
}
