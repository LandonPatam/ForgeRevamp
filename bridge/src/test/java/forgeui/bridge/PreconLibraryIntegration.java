package forgeui.bridge;

import com.google.gson.JsonObject;
import forge.deck.DeckFormat;
import forge.gui.GuiBase;
import forge.model.FModel;
import java.nio.file.Files;
import java.nio.file.Path;

/** Real Forge: bundled Commander precons appear in the library read-only, save as custom copies and launch from a deck file. */
public final class PreconLibraryIntegration {
    private static void require(boolean good, String message) {
        if (!good) throw new AssertionError(message);
    }

    private static JsonObject op(String name) {
        JsonObject request = new JsonObject(); request.addProperty("op", name); return request;
    }

    private static String rejection(DeckLibrary library, JsonObject request) {
        try { library.handle(request); return null; }
        catch (IllegalArgumentException e) { return e.getMessage(); }
        catch (Exception e) { throw new AssertionError(e); }
    }

    public static void main(String[] args) throws Exception {
        System.setProperty("java.awt.headless", "true");
        GuiBase.setInterface(new HeadlessGuiBase(Path.of("../forge/forge-gui").toAbsolutePath().normalize().toString()));
        FModel.initialize(null, null);
        var directory = Files.createTempDirectory(Path.of("../client-godot/artifacts"), "precon-library-");
        Files.writeString(directory.resolve("Mine.dck"), "[metadata]\nName=Mine\n[Commander]\n1 Sauron, the Dark Lord|LTR\n[Main]\n99 Swamp\n");
        var library = new DeckLibrary(directory);

        long started = System.nanoTime();
        var listed = library.handle(op("list")).getAsJsonArray("decks");
        long firstMs = (System.nanoTime() - started) / 1_000_000;
        started = System.nanoTime();
        library.handle(op("list"));
        long repeatMs = (System.nanoTime() - started) / 1_000_000;
        int custom = 0, precons = 0;
        JsonObject precon = null;
        for (var element : listed) {
            var deck = element.getAsJsonObject();
            String source = deck.get("source").getAsString();
            if (source.equals("custom")) { custom++; require(precons == 0, "Saved decks are listed before precons"); }
            else {
                precons++;
                require(deck.get("id").getAsString().startsWith(DeckLibrary.PRECON) && deck.get("readOnly").getAsBoolean(), "Precons are read-only precon: entries");
                if (precon == null && deck.get("legal").getAsBoolean() && deck.has("cover")) precon = deck;
            }
        }
        require(custom == 1, "The saved deck is listed once as custom");
        require(precons >= 150, "Forge's bundled Commander precons are listed: " + precons);
        require(precon != null, "At least one legal precon with a commander cover");
        String id = precon.get("id").getAsString();

        JsonObject open = op("open"); open.addProperty("id", id);
        var opened = library.handle(open);
        require(opened.get("readOnly").getAsBoolean() && opened.get("version").getAsString().isEmpty(), "An opened precon is read-only");
        require(opened.get("count").getAsInt() == 100 && opened.get("legal").getAsBoolean(), "The precon opens as a legal 100-card deck");

        JsonObject overwrite = op("save"); JsonObject draft = opened.deepCopy(); overwrite.add("deck", draft);
        String refused = rejection(library, overwrite);
        require(refused != null && refused.contains("read-only"), "Saving over a precon is refused: " + refused);
        JsonObject delete = op("delete"); delete.addProperty("id", id); delete.addProperty("version", "");
        require(rejection(library, delete) != null, "Deleting a precon is refused");

        JsonObject validate = op("validate"); validate.add("deck", opened.deepCopy());
        require(library.handle(validate).get("legal").getAsBoolean(), "A precon draft validates");

        JsonObject copy = opened.deepCopy();
        copy.addProperty("sourceId", id); copy.addProperty("id", ""); copy.addProperty("version", ""); copy.addProperty("name", "My precon copy");
        copy.remove("readOnly"); copy.remove("source");
        JsonObject saveCopy = op("save"); saveCopy.add("deck", copy);
        var saved = library.handle(saveCopy);
        require(saved.get("id").getAsString().equals("My precon copy.dck") && Files.isRegularFile(directory.resolve("My precon copy.dck")), "The copy is saved as a new custom deck");
        require(saved.get("count").getAsInt() == 100, "The copy keeps all 100 cards");

        Path playable = library.playableDeck(id);
        var loaded = DeckFiles.read(playable.toFile());
        require(!playable.startsWith(directory.toAbsolutePath().normalize()), "The match copy is written outside the library");
        require(loaded != null && DeckFormat.Commander.getDeckConformanceProblem(loaded) == null, "The match process can load the precon file as a legal deck");
        require(loaded.getCommanders().get(0).getName().equals(opened.getAsJsonObject("sections").getAsJsonArray("Commander").get(0).getAsJsonObject().get("name").getAsString()), "The match deck keeps the precon commander");

        var relisted = library.handle(op("list")).getAsJsonArray("decks");
        int customAfter = 0;
        for (var element : relisted) if (element.getAsJsonObject().get("source").getAsString().equals("custom")) customAfter++;
        require(customAfter == 2, "The saved copy is listed as custom; no other file was added to the library");
        System.out.println("PASS: " + precons + " precons listed (first list " + firstMs + " ms, repeat " + repeatMs + " ms); read-only, copy-on-save and match file checks");
    }
}
