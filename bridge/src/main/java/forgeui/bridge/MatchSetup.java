package forgeui.bridge;

import com.google.gson.*;
import java.util.Base64;
import java.io.ByteArrayInputStream;
import javax.imageio.ImageIO;

final class MatchSetup {
    static JsonObject profile(JsonObject input) throws Exception {
        BridgeProtocol.require(input != null, "Missing player profile");
        String name = DeckLibrary.string(input, "name", "").strip();
        BridgeProtocol.require(!name.isEmpty() && name.length() <= 32 && name.chars().noneMatch(Character::isISOControl), "Player names must contain 1–32 characters");
        int avatar = input.has("avatar") ? BridgeProtocol.integer(input.get("avatar")) : 0;
        // Forge's default sprite_avatars.png, assembled row-first, skipping
        // the top-left tile and tiles whose center pixel is transparent.
        BridgeProtocol.require(avatar >= 0 && avatar < 126, "Invalid portrait selection");
        String portrait = DeckLibrary.string(input, "portrait", "");
        if (!portrait.isEmpty()) {
            BridgeProtocol.require(portrait.length() <= 100000, "Portrait image is too large");
            byte[] bytes = Base64.getDecoder().decode(portrait);
            var image = ImageIO.read(new ByteArrayInputStream(bytes));
            BridgeProtocol.require(image != null && image.getWidth() <= 256 && image.getHeight() <= 256, "Use a portrait no larger than 256×256");
        }
        JsonObject result = new JsonObject(); result.addProperty("name", name); result.addProperty("avatar", avatar); result.addProperty("portrait", portrait);
        return result;
    }

    static JsonObject prepare(JsonObject input, DeckLibrary library, String humanDeck) throws Exception {
        return prepare(input, library, humanDeck, 0);
    }

    /** {@code remotePlayers} joined online and count toward the table alongside the bots. */
    static JsonObject prepare(JsonObject input, DeckLibrary library, String humanDeck, int remotePlayers) throws Exception {
        JsonObject result = new JsonObject(); result.add("human", profile(input.getAsJsonObject("human")));
        JsonArray bots = input.getAsJsonArray("bots");
        if (remotePlayers == 0) BridgeProtocol.require(bots != null && bots.size() >= 1 && bots.size() <= 3, "Choose one to three bots");
        else BridgeProtocol.require(bots != null && bots.size() + remotePlayers <= 3, "A table holds at most four players");
        JsonArray prepared = new JsonArray();
        for (JsonElement value : bots) {
            JsonObject bot = profile(value.getAsJsonObject());
            String mode = DeckLibrary.string(value.getAsJsonObject(), "mode", "saved");
            BridgeProtocol.require(java.util.Set.of("saved", "generated", "precon", "commander", "randomPrecon").contains(mode), "Choose an available bot deck source");
            if (mode.equals("randomPrecon")) {
                // Resolve to a concrete precon now so the match child sees an ordinary precon bot.
                mode = "precon";
                bot.addProperty("mode", mode);
                bot.addProperty("deckId", library.botDecks().randomPrecon());
                prepared.add(bot);
                continue;
            }
            bot.addProperty("mode", mode);
            if (mode.equals("saved")) {
                String id = DeckLibrary.string(value.getAsJsonObject(), "deckId", "");
                bot.addProperty("deckFile", library.playableDeck(id.isEmpty() ? humanDeck : id).toString());
            } else if (mode.equals("precon") || mode.equals("commander")) {
                String id = DeckLibrary.string(value.getAsJsonObject(), "deckId", "");
                BridgeProtocol.require(!id.isBlank(), "Choose a deck from the Forge list");
                library.botDecks().validate(mode, id);
                bot.addProperty("deckId", id);
            }
            prepared.add(bot);
        }
        result.add("bots", prepared);
        return result;
    }
}
