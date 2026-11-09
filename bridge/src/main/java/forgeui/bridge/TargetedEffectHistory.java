package forgeui.bridge;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import forge.game.card.CardView;
import forge.game.player.PlayerView;
import forge.game.spellability.StackItemView;
import forge.game.zone.ZoneType;
import java.util.LinkedHashMap;
import java.util.HashSet;
import java.util.Set;

/** Frozen public cast/target details survive fast resolution between snapshot ticks. */
final class TargetedEffectHistory {
    private final LinkedHashMap<Integer, JsonObject> events = new LinkedHashMap<>();
    private int sequence;

    synchronized void record(StackItemView item, PlayerView localPlayer) {
        record(item, localPlayer, null);
    }

    /** X as paid for this spell/ability or any of its parts, when its cost has an X. */
    static Integer xPaid(forge.game.spellability.SpellAbility ability) {
        for (var part = ability; part != null; part = part.getSubAbility()) {
            Integer x = part.getXManaCostPaid();
            if (x != null) return x;
        }
        if (ability != null && ability.getPayCosts() != null && ability.getPayCosts().getTotalMana() != null
                && ability.getPayCosts().getTotalMana().countX() > 0) {
            Object root = ability.getRootAbility().getXManaCostPaid();
            if (root instanceof Integer x) return x;
            return 0;
        }
        return null;
    }

    static boolean isMassRemoval(forge.game.spellability.SpellAbility ability) {
        if (ability == null) return false;
        var api = ability.getApi();
        if (api == forge.game.ability.ApiType.DestroyAll || api == forge.game.ability.ApiType.SacrificeAll) return true;
        if (api == forge.game.ability.ApiType.DamageAll && !ability.getParamOrDefault("ValidCards", "").isEmpty()) return true;
        if (api == forge.game.ability.ApiType.ChangeZoneAll
                && ability.getParamOrDefault("Origin", "").contains("Battlefield")
                && Set.of("Graveyard", "Exile", "Hand", "Library").contains(ability.getParamOrDefault("Destination", ""))) return true;
        if (api == forge.game.ability.ApiType.PumpAll && ability.getParamOrDefault("NumDef", "").startsWith("-")) return true;
        return isMassRemoval(ability.getSubAbility());
    }

    /** Whether a board-wide removal can actually reach one of this player's permanents: a delayed
     *  "sacrifice it at the next end step" (SacrificeAll of one remembered token) on someone else's
     *  board, or a wipe of only its controller's things, is no news for this seat. */
    static boolean massRemovalReaches(forge.game.spellability.SpellAbility ability, forge.game.player.Player local) {
        if (ability == null) return false;
        if (local == null) return isMassRemoval(ability);
        if (isMassRemoval(ability) && reachesHere(ability, local)) return true;
        forge.game.spellability.SpellAbility sub = ability.getSubAbility();
        return sub != null && massRemovalReaches(sub, local);
    }

    private static boolean reachesHere(forge.game.spellability.SpellAbility ability, forge.game.player.Player local) {
        var api = ability.getApi();
        boolean wipeApi = api == forge.game.ability.ApiType.DestroyAll || api == forge.game.ability.ApiType.SacrificeAll
                || api == forge.game.ability.ApiType.DamageAll || api == forge.game.ability.ApiType.ChangeZoneAll
                || api == forge.game.ability.ApiType.PumpAll;
        if (!wipeApi) return false;
        try {
            var host = ability.getHostCard();
            if (ability.hasParam("Defined")) {
                for (var card : forge.game.ability.AbilityUtils.getDefinedCards(host, ability.getParam("Defined"), ability)) {
                    if (card.getController() != null && card.getController().equals(local)) return true;
                }
                return false;
            }
            String valid = ability.getParamOrDefault("ValidCards", ability.getParamOrDefault("ChangeType", ""));
            if (valid.isEmpty()) return true; // Unknown shape: keep the warning.
            var mine = local.getCardsIn(ZoneType.Battlefield);
            return !forge.game.card.CardLists.getValidCards(mine, valid, ability.getActivatingPlayer(), host, ability).isEmpty();
        } catch (RuntimeException e) {
            return true; // Never hide a wipe because the check itself failed.
        }
    }

    /** Every permanent on the table a wipe will reach (all players'), frozen when it is first seen,
     *  so the client can draw the spell's lines to each one before it resolves. */
    static JsonArray affectedPermanents(forge.game.spellability.SpellAbility ability) {
        JsonArray result = new JsonArray();
        Set<Integer> seen = new HashSet<>();
        for (var part = ability; part != null; part = part.getSubAbility()) {
            if (!isMassRemoval(part) || part.getHostCard() == null || part.getHostCard().getGame() == null) continue;
            var api = part.getApi();
            if (api != forge.game.ability.ApiType.DestroyAll && api != forge.game.ability.ApiType.SacrificeAll
                    && api != forge.game.ability.ApiType.DamageAll && api != forge.game.ability.ApiType.ChangeZoneAll
                    && api != forge.game.ability.ApiType.PumpAll) continue;
            try {
                var host = part.getHostCard();
                Iterable<forge.game.card.Card> reached;
                if (part.hasParam("Defined")) {
                    reached = forge.game.ability.AbilityUtils.getDefinedCards(host, part.getParam("Defined"), part);
                } else {
                    String valid = part.getParamOrDefault("ValidCards", part.getParamOrDefault("ChangeType", ""));
                    if (valid.isEmpty()) continue;
                    reached = forge.game.card.CardLists.getValidCards(host.getGame().getCardsIn(ZoneType.Battlefield), valid, part.getActivatingPlayer(), host, part);
                }
                for (var card : reached) {
                    if (card.isInZone(ZoneType.Battlefield) && seen.add(card.getId())) result.add(card.getId());
                }
            } catch (RuntimeException unreadable) {
                // The popup still announces the wipe; it just draws no lines.
            }
        }
        return result;
    }

    synchronized void record(StackItemView item, PlayerView localPlayer, forge.game.spellability.SpellAbility ability) {
        forge.game.player.Player local = null;
        if (ability != null && localPlayer != null && ability.getHostCard() != null && ability.getHostCard().getGame() != null) {
            local = ability.getHostCard().getGame().getPlayer(localPlayer);
        }
        boolean massRemoval = local != null ? massRemovalReaches(ability, local) : isMassRemoval(ability);
        // "Each opponent loses 1 life" / "each player draws": a notice for each affected seat, not a stop.
        boolean notice = !massRemoval && localPlayer != null && StackInteractionPolicy.noticePlayers(ability)
                .stream().anyMatch(player -> player.getId() == localPlayer.getId());
        if (item == null || localPlayer == null || item.getActivatingPlayer() == null
                || (!massRemoval && item.getActivatingPlayer().getId() == localPlayer.getId()) || events.containsKey(item.getId())) return;
        JsonArray targets = new JsonArray();
        collectTargets(item, localPlayer.getId(), targets, new HashSet<>());
        if ((!massRemoval && !notice && targets.isEmpty()) || item.getSourceCard() == null) return;
        CardView source = item.getSourceCard();
        boolean publicSource = isPublic(source);
        if (!publicSource && !source.isFaceDown() && ability != null && ability.getHostCard() != null && ability.getHostCard().getGame() != null) {
            // Delayed triggers carry a zoneless snapshot of their creator; show the real card if it is public.
            var live = ability.getHostCard().getGame().findById(source.getId());
            if (live != null && isPublic(live.getView())) {
                source = live.getView();
                publicSource = true;
            }
        }
        JsonObject event = new JsonObject();
        event.addProperty("id", ++sequence);
        event.addProperty("stackId", item.getId());
        event.addProperty("controller", item.getActivatingPlayer().getId());
        event.addProperty("controllerName", item.getActivatingPlayer().getName());
        event.addProperty("ability", item.isAbility());
        event.addProperty("effectText", item.getText());
        event.addProperty("kind", massRemoval ? "massRemoval" : (targets.isEmpty() ? "notice" : "targeted"));
        event.add("source", GameStateJson.describeCard(source, publicSource));
        event.add("targets", targets);
        Integer x = xPaid(ability);
        if (x != null) event.addProperty("xValue", x);
        if (massRemoval && ability != null) event.add("affected", affectedPermanents(ability));
        events.put(item.getId(), event);
        while (events.size() > 32) events.remove(events.keySet().iterator().next());
    }

    /** Another player revealed cards (search results, top of library): a "reveal" notice with the
     *  source card and the revealed faces as its targets. */
    synchronized void recordReveal(forge.game.spellability.SpellAbility effect, JsonArray shown) {
        if (effect == null || effect.getHostCard() == null || effect.getActivatingPlayer() == null) return;
        JsonArray revealed = new JsonArray();
        java.util.List<String> names = new java.util.ArrayList<>();
        for (var entry : shown) {
            var option = entry.getAsJsonObject();
            if (!option.has("card")) continue;
            var card = option.getAsJsonObject("card");
            JsonObject target = new JsonObject();
            target.addProperty("id", card.has("id") ? card.get("id").getAsInt() : -1);
            target.addProperty("kind", "card");
            target.addProperty("name", card.has("name") ? card.get("name").getAsString() : "Card");
            target.add("card", card.deepCopy());
            revealed.add(target);
            names.add(target.get("name").getAsString());
        }
        if (revealed.isEmpty()) return;
        CardView source = effect.getHostCard().getView();
        JsonObject event = new JsonObject();
        event.addProperty("id", ++sequence);
        event.addProperty("stackId", -1);
        event.addProperty("controller", effect.getActivatingPlayer().getId());
        event.addProperty("controllerName", effect.getActivatingPlayer().getName());
        event.addProperty("ability", true);
        event.addProperty("effectText", effect.getActivatingPlayer().getName() + " revealed " + String.join(", ", names) + ".");
        event.addProperty("kind", "reveal");
        event.add("source", GameStateJson.describeCard(source, isPublic(source)));
        event.add("targets", revealed);
        events.put(-sequence, event);
        while (events.size() > 32) events.remove(events.keySet().iterator().next());
    }

    private static boolean isPublic(CardView card) {
        return card != null && !card.isFaceDown() && card.getZone() != null
                && Set.of(ZoneType.Stack, ZoneType.Battlefield, ZoneType.Graveyard, ZoneType.Exile, ZoneType.Command).contains(card.getZone());
    }

    private static void collectTargets(StackItemView item, int localId, JsonArray result, Set<String> seen) {
        if (item.getTargetCards() != null) for (CardView card : item.getTargetCards()) {
            if ((card.getController() == null || card.getController().getId() != localId)
                    && (card.getOwner() == null || card.getOwner().getId() != localId)) continue;
            if (!seen.add("card:" + card.getId())) continue;
            JsonObject target = new JsonObject();
            target.addProperty("id", card.getId());
            target.addProperty("kind", "card");
            target.addProperty("name", card.isFaceDown() ? "Face-down card" : card.getName());
            target.add("card", GameStateJson.describeCard(card, !card.isFaceDown()));
            result.add(target);
        }
        if (item.getTargetPlayers() != null) for (PlayerView player : item.getTargetPlayers()) {
            if (player.getId() != localId || !seen.add("player:" + player.getId())) continue;
            JsonObject target = new JsonObject();
            target.addProperty("id", player.getId());
            target.addProperty("kind", "player");
            target.addProperty("name", "You");
            result.add(target);
        }
        if (item.getSubInstance() != null) collectTargets(item.getSubInstance(), localId, result, seen);
    }

    synchronized JsonArray snapshot() {
        JsonArray result = new JsonArray();
        events.values().forEach(event -> result.add(event.deepCopy()));
        return result;
    }
}
