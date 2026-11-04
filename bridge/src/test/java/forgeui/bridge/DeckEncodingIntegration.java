package forgeui.bridge;

import com.google.gson.JsonObject;
import forge.gui.GuiBase;
import forge.model.FModel;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

/** Real Forge parsing/image resolution; optional argument reads a user deck without modifying it. */
public final class DeckEncodingIntegration {
    private static void require(boolean good, String message) {
        if (!good) throw new AssertionError(message);
    }

    public static void main(String[] args) throws Exception {
        System.setProperty("java.awt.headless", "true");
        GuiBase.setInterface(new HeadlessGuiBase(Path.of("../forge/forge-gui").toAbsolutePath().normalize().toString()));
        FModel.initialize(null, null);
        var directory = Files.createTempDirectory(Path.of("../client-godot/artifacts"), "deck-encoding-");
        String text = "[metadata]\nName=Encoding test\n[Commander]\n1 Sauron, the Dark Lord|LTR\n[Main]\n98 Swamp\n1 Troll of Khazad-d\u00fbm|LTR|[111]\n";
        var library = new DeckLibrary(directory);
        var encodings = List.of(StandardCharsets.UTF_8, Charset.forName("windows-1252"), StandardCharsets.UTF_16LE, StandardCharsets.UTF_16BE);
        for (var encoding : encodings) {
            String id = encoding.name() + ".dck";
            String source = encoding.name().startsWith("UTF-16") ? "\ufeff" + text : text;
            Files.write(directory.resolve(id), source.getBytes(encoding));
            JsonObject request = new JsonObject();
            request.addProperty("op", "open"); request.addProperty("id", id);
            var opened = library.handle(request);
            require(opened.get("legal").getAsBoolean(), "Encoding fixture remains a legal Commander deck: " + id);
            boolean found = false;
            for (var entry : opened.getAsJsonObject("sections").getAsJsonArray("Main")) {
                var card = entry.getAsJsonObject();
                require(!card.get("name").getAsString().contains("\ufffd"), "No replacement character in card names");
                if (!card.get("name").getAsString().equals("Troll of Khazad-d\u00fbm")) continue;
                found = true;
                require(!CardArtwork.urls(card.get("imageKey").getAsString()).isEmpty(), "Exact Troll image key resolves");
                JsonObject image = new JsonObject();
                image.addProperty("op", "image"); image.add("key", card.get("key"));
                var artwork = library.handle(image);
                require(artwork.has("data") || artwork.has("url"), "The library supplies Troll artwork");
            }
            require(found, "Accented card survives real Forge parsing: " + id);
            require(DeckFiles.read(directory.resolve(id).toFile()).getMain().countAll() == 99, "Match loader preserves the same deck");
        }
        if (args.length > 0) {
            Path userDeck = Path.of(args[0]);
            byte[] before = Files.readAllBytes(userDeck);
            var deck = DeckFiles.read(userDeck.toFile());
            var faces = deck.getMain().toFlatList();
            require(faces.stream().noneMatch(card -> card.getName().contains("\ufffd")), "User deck contains no replacement glyphs after loading");
            for (String name : List.of("Troll of Khazad-d\u00fbm", "Grishn\u00e1kh, Brash Instigator", "Gr\u00edma, Saruman's Footman", "Lord of the Nazg\u00fbl")) {
                var face = faces.stream().filter(card -> card.getName().equals(name)).findFirst();
                require(face.isPresent() && !CardArtwork.urls(face.get().getImageKey(false)).isEmpty(), "User deck resolves accented name and artwork: " + name);
            }
            require(java.util.Arrays.equals(before, Files.readAllBytes(userDeck)), "Reading leaves the user's deck bytes unchanged");
            System.out.println("PASS: user deck reads all four accented cards and artwork without changing its file");
        }
        System.out.println("PASS: real Forge UTF-8, CP1252 and UTF-16 Commander parsing, legality, image keys and match loading");
    }
}
