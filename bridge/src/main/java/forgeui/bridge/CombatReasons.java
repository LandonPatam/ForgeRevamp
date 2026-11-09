package forgeui.bridge;

import forge.game.GameEntity;
import forge.game.card.Card;
import forge.game.combat.Combat;
import forge.game.combat.CombatUtil;
import forge.game.keyword.Keyword;
import forge.game.player.Player;
import forge.game.staticability.StaticAbility;
import forge.game.staticability.StaticAbilityCantAttackBlock;
import forge.game.staticability.StaticAbilityMode;
import forge.game.zone.ZoneType;

/**
 * Plain-language reasons for Forge's yes/no combat rules, for players who would otherwise read a
 * refused click as a bug. Forge's {@link CombatUtil} only answers true/false; these walk the same
 * checks in the same order and name the first one that applies, with the card responsible.
 * Presentation only: Forge still decides every attack and block.
 */
final class CombatReasons {
    private CombatReasons() { }

    /** Why this creature can't block at all right now, or null when it can. */
    static String cantBlock(Card blocker, Combat combat) {
        if (blocker == null || !blocker.isCreature()) return null;
        if (combat != null ? CombatUtil.canBlock(blocker, combat) : CombatUtil.canBlock(blocker)) return null;
        String name = blocker.getName();
        if (blocker.isPhasedOut()) return name + " is phased out.";
        if (blocker.isTapped() && !StaticAbilityCantAttackBlock.canBlockTapped(blocker)) return name + " is tapped. Tapped creatures can't block.";
        if (blocker.hasKeyword("CARDNAME can't block.") || blocker.hasKeyword("CARDNAME can't attack or block."))
            return name + " can't block (its own ability).";
        String source = staticSource(blocker, StaticAbilityMode.CantBlock, null);
        if (source != null) return name + " can't block: " + source;
        if (blocker.isDetained()) return name + " is detained: it can't attack or block until its controller's next turn.";
        if (combat != null && !combat.getAttackersBlockedBy(blocker).isEmpty())
            return name + " is already blocking, and can only block one creature.";
        return name + " can't block right now (an effect on the battlefield prevents it).";
    }

    /** Why this blocker can't block this attacker (the blocker itself may be able to block others). */
    static String cantBlock(Card attacker, Card blocker, Combat combat) {
        if (attacker == null || blocker == null) return null;
        String general = cantBlock(blocker, combat);
        if (general != null) return general;
        if (CombatUtil.canBlock(attacker, blocker, combat)) return null;
        String a = attacker.getName(), b = blocker.getName();
        if (attacker.hasKeyword(Keyword.FLYING) && !blocker.hasKeyword(Keyword.FLYING) && !blocker.hasKeyword(Keyword.REACH))
            return a + " has flying: only creatures with flying or reach can block it, and " + b + " has neither.";
        if (attacker.hasKeyword(Keyword.SHADOW) && !blocker.hasKeyword(Keyword.SHADOW))
            return a + " has shadow: only creatures with shadow can block it.";
        if (attacker.hasKeyword(Keyword.HORSEMANSHIP) && !blocker.hasKeyword(Keyword.HORSEMANSHIP))
            return a + " has horsemanship: only creatures with horsemanship can block it.";
        if (attacker.hasKeyword(Keyword.FEAR) && !blocker.isArtifact() && !blocker.isBlack())
            return a + " has fear: only artifact or black creatures can block it.";
        if (attacker.hasKeyword(Keyword.INTIMIDATE) && !blocker.isArtifact() && !blocker.sharesColorWith(attacker))
            return a + " has intimidate: only artifact creatures or creatures sharing a color with it can block it.";
        if (attacker.hasKeyword(Keyword.SKULK) && blocker.getNetPower() > attacker.getNetPower())
            return a + " has skulk: creatures with greater power (" + b + ") can't block it.";
        for (var keyword : attacker.getKeywords()) {
            String original = keyword.getOriginal();
            if (original != null && original.startsWith("Protection"))
                return a + " has " + original.toLowerCase().replace(":", " ").replaceAll("\\s+", " ").trim()
                        + ": creatures it's protected from (like " + b + ") can't block it.";
        }
        String source = staticSource(attacker, StaticAbilityMode.CantBlockBy, blocker);
        if (source != null) return a + " can't be blocked by " + b + ": " + source;
        return "Forge doesn't allow " + b + " to block " + a + " (an ability on one of them restricts it; check both cards' text).";
    }

    /** Why this creature can't attack at all this combat, or null when it can attack someone. */
    static String cantAttack(Card attacker) {
        if (attacker == null || !attacker.isCreature()) return null;
        if (CombatUtil.canAttack(attacker)) return null;
        String name = attacker.getName();
        if (attacker.isTapped()) return name + " is tapped. Tapped creatures can't attack.";
        if (attacker.hasSickness())
            return name + " has summoning sickness: it came under your control this turn, so it can't attack until your next turn (unless it has haste).";
        if (attacker.hasKeyword(Keyword.DEFENDER)) return name + " has defender: it can't attack.";
        if (attacker.hasKeyword("CARDNAME can't attack.") || attacker.hasKeyword("CARDNAME can't attack or block."))
            return name + " can't attack (its own ability).";
        String source = staticSource(attacker, StaticAbilityMode.CantAttack, null);
        if (source != null) return name + " can't attack: " + source;
        if (attacker.isDetained()) return name + " is detained: it can't attack or block until its controller's next turn.";
        return name + " can't attack right now (an effect on the battlefield prevents it).";
    }

    /** Why this creature can't attack this player (it may be able to attack someone else). */
    static String cantAttack(Card attacker, GameEntity defender) {
        String general = cantAttack(attacker);
        if (general != null) return general;
        if (defender == null || CombatUtil.canAttack(attacker, defender)) return null;
        String source = staticSource(attacker, StaticAbilityMode.CantAttack, null);
        String who = defender instanceof Player player ? player.getName() : defender.toString();
        if (source != null) return attacker.getName() + " can't attack " + who + ": " + source;
        return attacker.getName() + " can't attack " + who + " (an effect restricts who it can attack).";
    }

    /** The static ability of this mode that applies to the card, named by its source and owner. */
    private static String staticSource(Card card, StaticAbilityMode mode, Card other) {
        java.util.List<Card> hosts = new java.util.ArrayList<>();
        hosts.add(card);
        if (other != null) hosts.add(other);
        for (Card host : card.getGame().getCardsIn(ZoneType.STATIC_ABILITIES_SOURCE_ZONES)) hosts.add(host);
        for (Card host : hosts) {
            for (StaticAbility ability : host.getStaticAbilities()) {
                if (!ability.checkConditions(mode)) continue;
                boolean applies;
                try {
                    applies = switch (mode) {
                        case CantBlock -> StaticAbilityCantAttackBlock.applyCantBlockAbility(ability, card);
                        case CantAttack -> StaticAbilityCantAttackBlock.applyCantAttackAbility(ability, card, null);
                        case CantBlockBy -> StaticAbilityCantAttackBlock.applyCantBlockByAbility(ability, card, other);
                        default -> false;
                    };
                } catch (RuntimeException unreadable) {
                    applies = false;
                }
                if (applies) return describe(host, ability);
            }
        }
        return null;
    }

    /** "Taunt from the Rampart (Bot 1): Until your next turn, those creatures can't block." */
    private static String describe(Card host, StaticAbility ability) {
        String name = host.getName().replaceAll(" \\(\\d+\\)", "").replaceAll("'s Effect$", "");
        Player owner = host.getController() != null ? host.getController() : host.getOwner();
        String text = ability.hasParam("Description") ? ability.getParam("Description") : host.getOracleText();
        text = text == null ? "" : text.replace("CARDNAME", host.getName()).replaceAll("\\s+", " ").trim();
        return name + (owner != null ? " (" + owner.getName() + ")" : "") + (text.isEmpty() ? "" : ": " + text);
    }
}
