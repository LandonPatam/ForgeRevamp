package forgeui.bridge;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import forge.game.event.GameEvent;
import forge.game.event.GameEventCardDamaged;
import forge.game.event.GameEventPlayerDamaged;
import forge.game.phase.PhaseType;
import java.util.ArrayDeque;

/** Public table happenings the client animates (who hit whom, for how much), numbered so a
 *  snapshot carries the recent ones and the client plays each id once. Presentation only:
 *  nothing here is ever an answer to Forge, and only public facts (ids and amounts) are sent. */
final class TableFx {
    private static final int KEEP = 48;
    private final ArrayDeque<JsonObject> events = new ArrayDeque<>();
    private int sequence;
    /** Attackers already matched to a planeswalker/battle loss in the current damage step. */
    private final java.util.Set<String> credited = new java.util.HashSet<>();
    private long creditedStep = -1;

    synchronized void record(GameEvent event, forge.game.Game game) {
        if (event instanceof GameEventCardDamaged damaged && damaged.amount() > 0 && damaged.card() != null) {
            JsonObject fx = damage(damaged.source() == null ? -1 : damaged.source().getId(), damaged.amount());
            fx.addProperty("targetKind", "card");
            fx.addProperty("targetId", damaged.card().getId());
            fx.addProperty("combat", combatDamage(game, damaged.source() == null ? -1 : damaged.source().getId()));
            if (damaged.type() == GameEventCardDamaged.DamageType.Deathtouch) fx.addProperty("deathtouch", true);
            if (damaged.type() == GameEventCardDamaged.DamageType.M1M1Counters) fx.addProperty("counters", true);
            add(fx);
        } else if (event instanceof GameEventPlayerDamaged damaged && damaged.amount() > 0 && damaged.target() != null) {
            JsonObject fx = damage(damaged.source() == null ? -1 : damaged.source().getId(), damaged.amount());
            fx.addProperty("targetKind", "player");
            fx.addProperty("targetId", damaged.target().getId());
            fx.addProperty("combat", damaged.combat());
            if (damaged.infect()) fx.addProperty("infect", true);
            add(fx);
        } else if (event instanceof forge.game.event.GameEventCardCounters counters && counters.card() != null
                && counters.newValue() < counters.oldValue()
                && (counters.type().is(forge.game.card.CounterEnumType.LOYALTY) || counters.type().is(forge.game.card.CounterEnumType.DEFENSE))) {
            // Forge deals damage to planeswalkers and battles by removing counters, with no damage
            // event. In a combat damage step, the loss comes from an unblocked attacker on that card.
            int sourceId = combatAttackerOf(game, counters.card().getId(), counters.oldValue() - counters.newValue());
            if (sourceId < 0) return;
            JsonObject fx = damage(sourceId, counters.oldValue() - counters.newValue());
            fx.addProperty("targetKind", "card");
            fx.addProperty("targetId", counters.card().getId());
            fx.addProperty("combat", true);
            add(fx);
        }
    }

    /** The unblocked attacker on this planeswalker or battle that dealt this much, preferring one
     *  not yet credited this step; -1 outside a combat damage step. */
    private int combatAttackerOf(forge.game.Game game, int defenderId, int amount) {
        if (game == null) return -1;
        try {
            PhaseType phase = game.getPhaseHandler().getPhase();
            var combat = game.getCombat();
            var defender = game.findById(defenderId);
            if (combat == null || defender == null || (phase != PhaseType.COMBAT_DAMAGE && phase != PhaseType.COMBAT_FIRST_STRIKE_DAMAGE)) return -1;
            long step = game.getPhaseHandler().getTurn() * 100L + phase.ordinal();
            if (step != creditedStep) {
                credited.clear();
                creditedStep = step;
            }
            int chosen = -1;
            for (var attacker : combat.getAttackersOf(defender)) {
                if (combat.isBlocked(attacker) && !attacker.hasKeyword(forge.game.keyword.Keyword.TRAMPLE)) continue;
                if (credited.contains(attacker.getId() + ">" + defenderId)) continue;
                if (attacker.getNetCombatDamage() == amount) {
                    chosen = attacker.getId();
                    break;
                }
                if (chosen < 0) chosen = attacker.getId();
            }
            if (chosen >= 0) credited.add(chosen + ">" + defenderId);
            return chosen;
        } catch (RuntimeException unreadable) {
            return -1;
        }
    }

    private JsonObject damage(int sourceId, int amount) {
        JsonObject fx = new JsonObject();
        fx.addProperty("kind", "damage");
        fx.addProperty("sourceId", sourceId);
        fx.addProperty("amount", amount);
        return fx;
    }

    /** Damage a creature deals as an attacker or blocker in a combat damage step. */
    private static boolean combatDamage(forge.game.Game game, int sourceId) {
        if (game == null || sourceId < 0) return false;
        try {
            PhaseType phase = game.getPhaseHandler().getPhase();
            var combat = game.getCombat();
            if (combat == null || (phase != PhaseType.COMBAT_DAMAGE && phase != PhaseType.COMBAT_FIRST_STRIKE_DAMAGE)) return false;
            var card = game.findById(sourceId);
            return card != null && (combat.isAttacking(card) || combat.isBlocking(card));
        } catch (RuntimeException unreadable) {
            return false;
        }
    }

    private void add(JsonObject fx) {
        fx.addProperty("id", ++sequence);
        events.addLast(fx);
        while (events.size() > KEEP) events.removeFirst();
    }

    synchronized JsonArray snapshot() {
        JsonArray result = new JsonArray();
        for (JsonObject fx : events) result.add(fx.deepCopy());
        return result;
    }
}
