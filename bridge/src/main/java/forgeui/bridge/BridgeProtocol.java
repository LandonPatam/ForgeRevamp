package forgeui.bridge;

import com.google.gson.*;
import java.util.HashSet;
import java.util.Set;

/** Wire validation only. Magic legality remains Forge's responsibility. */
final class BridgeProtocol {
    static final int VERSION = 2;

    static byte manaColor(int code) {
        require(Set.of(0, 1, 2, 4, 8, 16).contains(code), "Invalid mana color");
        // The v2 wire uses 0 for C; Forge's pool keys use ManaAtom, not MagicColor.
        return (byte) (code == 0 ? forge.card.mana.ManaAtom.COLORLESS : code);
    }

    static String string(JsonObject object, String key) {
        JsonElement value = object.get(key);
        require(value != null && value.isJsonPrimitive() && value.getAsJsonPrimitive().isString(),
                key + " must be a string");
        return value.getAsString();
    }

    static int integer(JsonElement value) {
        require(value != null && value.isJsonPrimitive() && value.getAsJsonPrimitive().isNumber(),
                "Expected an integer");
        try {
            return value.getAsBigDecimal().intValueExact();
        } catch (ArithmeticException | NumberFormatException e) {
            throw new IllegalArgumentException("Expected a 32-bit integer");
        }
    }

    static long revision(JsonElement value) {
        require(value != null && value.isJsonPrimitive() && value.getAsJsonPrimitive().isNumber(),
                "revision must be an integer");
        try {
            long n = value.getAsBigDecimal().longValueExact();
            require(n >= 0, "revision must be nonnegative");
            return n;
        } catch (ArithmeticException | NumberFormatException e) {
            throw new IllegalArgumentException("Invalid revision");
        }
    }

    static void validateAnswer(JsonObject ask, JsonElement value) {
        require(value != null, "Missing answer value");
        String kind = ask.get("kind").getAsString();
        switch (kind) {
            case "choose", "order" -> {
                require(value.isJsonArray(), "Selection must be an array of indices");
                JsonArray array = value.getAsJsonArray();
                require(array.size() >= ask.get("min").getAsInt()
                        && array.size() <= ask.get("max").getAsInt(), "Invalid selection count");
                Set<Integer> seen = new HashSet<>();
                for (JsonElement item : array) {
                    int index = integer(item);
                    require(index >= 0 && index < ask.getAsJsonArray("options").size(), "Invalid option index");
                    require(seen.add(index), "Duplicate option index");
                }
            }
            case "distribute" -> {
                if (value.isJsonNull() && ask.has("maySkip") && ask.get("maySkip").getAsBoolean()) return;
                require(value.isJsonArray(), "Distribution must be an array of amounts");
                JsonArray array = value.getAsJsonArray();
                require(array.size() == ask.getAsJsonArray("options").size(), "Wrong number of recipients");
                long total = 0;
                int minimum = ask.get("atLeastOne").getAsBoolean() ? 1 : 0;
                for (JsonElement item : array) {
                    int amount = integer(item);
                    require(amount >= minimum, "Invalid recipient amount");
                    total += amount;
                }
                require(total == ask.get("amount").getAsInt(), "Assigned amounts must equal the total");
                // These thresholds and flags come from Forge views, following its stock dialog.
                if (ask.has("lethal") && !(ask.get("overrideOrder").getAsBoolean() && ask.get("divideDamage").getAsBoolean())) {
                    JsonArray lethal = ask.getAsJsonArray("lethal");
                    boolean previousNeedsDamage = false;
                    for (int i = 0; i < array.size(); i++) {
                        int assigned = integer(array.get(i));
                        if (previousNeedsDamage && (!ask.get("overrideOrder").getAsBoolean() || i >= lethal.size())) {
                            require(assigned == 0, "Assign lethal damage to preceding blockers first");
                        }
                        if (i < lethal.size()) previousNeedsDamage |= assigned < lethal.get(i).getAsInt();
                    }
                }
            }
            case "input" -> {
                if (value.isJsonNull()) return; // Explicit cancel.
                require(value.isJsonPrimitive() && value.getAsJsonPrimitive().isString(), "Input must be a string or null");
                if (ask.get("numeric").getAsBoolean()) {
                    try { Integer.parseInt(value.getAsString()); }
                    catch (NumberFormatException e) { throw new IllegalArgumentException("Input must be a 32-bit integer"); }
                }
            }
            case "message" -> { /* Any explicit JSON acknowledgment is accepted. */ }
            case "scry" -> {
                require(value.isJsonObject(), "Scry must be {top, bottom}");
                int count = ask.getAsJsonArray("options").size();
                Set<Integer> seen = new HashSet<>();
                for (String side : new String[] {"top", "bottom"}) {
                    JsonElement picks = value.getAsJsonObject().get(side);
                    if (picks == null) continue;
                    require(picks.isJsonArray(), "Scry sides must be arrays");
                    require(side.equals("top") ? ask.get("canTop").getAsBoolean() : ask.get("canBottom").getAsBoolean() || picks.getAsJsonArray().isEmpty(), "That side is not allowed");
                    for (JsonElement item : picks.getAsJsonArray()) {
                        int index = integer(item);
                        require(index >= 0 && index < count, "Invalid option index");
                        require(seen.add(index), "Duplicate option index");
                    }
                }
                require(seen.size() == count, "Place every card");
            }
            default -> throw new IllegalArgumentException("Unknown decision kind");
        }
    }

    /** A valid answer for a seat whose player has left, so the game thread is never left waiting on them. */
    static JsonElement fallbackAnswer(JsonObject ask) {
        String kind = ask.get("kind").getAsString();
        switch (kind) {
            case "choose", "order" -> {
                JsonArray picks = new JsonArray();
                int count = kind.equals("order") ? ask.get("max").getAsInt() : ask.get("min").getAsInt();
                for (int i = 0; i < count; i++) picks.add(i);
                return picks;
            }
            case "distribute" -> {
                JsonArray amounts = new JsonArray();
                int recipients = ask.getAsJsonArray("options").size();
                int minimum = ask.get("atLeastOne").getAsBoolean() ? 1 : 0;
                for (int i = 0; i < recipients; i++)
                    amounts.add(i == 0 ? ask.get("amount").getAsInt() - minimum * (recipients - 1) : minimum);
                return amounts;
            }
            case "input" -> { return JsonNull.INSTANCE; }
            case "scry" -> {
                JsonObject keep = new JsonObject();
                JsonArray top = new JsonArray();
                for (int i = 0; i < ask.getAsJsonArray("options").size(); i++) top.add(i);
                keep.add("top", top);
                keep.add("bottom", new JsonArray());
                return keep;
            }
            default -> { return new JsonPrimitive(true); }
        }
    }

    static void require(boolean condition, String message) {
        if (!condition) throw new IllegalArgumentException(message);
    }
}
