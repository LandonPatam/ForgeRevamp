package forgeui.bridge;

import com.google.gson.*;
import forge.StaticData;
import forge.ImageKeys;
import forge.card.CardDb;
import forge.deck.*;
import forge.deck.io.DeckSerializer;
import forge.game.GameType;
import forge.gui.interfaces.ICheckBox;
import forge.gui.interfaces.IComboBox;
import forge.item.PaperCard;
import forge.localinstance.properties.ForgeConstants;
import forge.util.FileSection;

import java.io.File;
import java.lang.reflect.Proxy;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.stream.Stream;

/** Deck operations use Forge's card rules, importer and native serializer; no game is started. */
final class DeckLibrary {
    private final Path root;
    private final List<PaperCard> catalog;
    private record SearchText(String name, String fullText) {}
    private final Map<String, SearchText> searchIndex = new HashMap<>();
    private static final java.util.regex.Pattern SEARCH_PUNCTUATION = java.util.regex.Pattern.compile("[^\\p{L}\\p{N}]+");
    private final Map<String, PaperCard> cards = new HashMap<>();
    private BotDecks botDecks;

    BotDecks botDecks() {
        if (botDecks == null) botDecks = new BotDecks();
        return botDecks;
    }

    DeckLibrary(Path root) throws Exception {
        this.root = root.toAbsolutePath().normalize();
        Files.createDirectories(this.root);
        var byName = new TreeMap<String, PaperCard>(String.CASE_INSENSITIVE_ORDER);
        for (CardDb db : databases()) {
            db.streamUniqueCards().forEach(c -> byName.putIfAbsent(c.getName(), c));
            for (PaperCard c : db.getAllCards()) cards.put(key(c), c);
        }
        catalog = new ArrayList<>(byName.values());
        for (PaperCard card : catalog) searchIndex.put(card.getName(), new SearchText(
                searchKey(card.getName()), searchKey(card.getName() + " " + card.getRules().getOracleText())));
    }

    private List<CardDb> databases() {
        return List.of(StaticData.instance().getCommonCards(), StaticData.instance().getVariantCards());
    }

    /** Forge's bundled Commander precons are listed beside saved decks under this read-only identifier prefix. */
    static final String PRECON = "precon:";
    private final Map<String, JsonObject> preconEntries = new HashMap<>();

    private static boolean isPrecon(String id) { return id.startsWith(PRECON); }

    private Deck precon(String id) {
        var proxy = botDecks().libraryPrecons().get(id.substring(PRECON.length()));
        BridgeProtocol.require(proxy != null, "This precon is not available in the installed Forge");
        return new Deck(proxy.getDeck());
    }

    Path playableDeck(String id) {
        if (isPrecon(id)) {
            Deck deck = precon(id);
            String problem = DeckFormat.Commander.getDeckConformanceProblem(deck);
            BridgeProtocol.require(problem == null, "This precon is not ready for Commander: " + problem);
            // The match process loads a deck file; give it an exact serialized copy outside the library.
            try {
                Path directory = Files.createDirectories(Path.of(System.getProperty("java.io.tmpdir"), "forgeui-precons"));
                Path file = directory.resolve(deck.getName().replaceAll("[^A-Za-z0-9 _\\-\\[\\]]", "_") + ".dck");
                Path temp = Files.createTempFile(directory, ".forgeui-", ".tmp");
                try {
                    DeckSerializer.writeDeck(deck, temp.toFile());
                    Files.move(temp, file, StandardCopyOption.REPLACE_EXISTING);
                } finally { Files.deleteIfExists(temp); }
                return file;
            } catch (java.io.IOException e) { throw new IllegalArgumentException("Could not prepare this precon for play", e); }
        }
        Path file = path(id);
        String problem = DeckFormat.Commander.getDeckConformanceProblem(read(file));
        BridgeProtocol.require(problem == null, "This deck is not ready for Commander: " + problem);
        return file;
    }

    JsonObject handle(JsonObject request) throws Exception {
        return switch (string(request, "op", "")) {
            case "list" -> list();
            case "open" -> open(string(request, "id", ""));
            case "catalog" -> search(request);
            case "printings" -> printings(string(request, "name", ""));
            case "bot.decks" -> botDecks().catalog();
            case "import" -> importDeck(request);
            case "validate" -> describe(fromDraft(request.getAsJsonObject("deck")), "", "");
            case "save" -> save(request);
            case "delete" -> delete(request);
            case "export" -> export(request);
            case "image" -> image(request);
            default -> throw new IllegalArgumentException("Unknown library operation");
        };
    }

    private Path path(String id) {
        BridgeProtocol.require(!id.isBlank() && !id.contains("\\") && !id.startsWith("/"), "Invalid deck identifier");
        Path result = root.resolve(id).normalize();
        BridgeProtocol.require(result.startsWith(root) && result.toString().toLowerCase(Locale.ROOT).endsWith(".dck"), "Invalid deck path");
        // Do not traverse a junction/symlink from the deck directory.
        try { BridgeProtocol.require(!Files.exists(result) || result.toRealPath().startsWith(root.toRealPath()), "Deck is outside the library"); }
        catch (java.io.IOException e) { throw new IllegalArgumentException("Cannot access deck", e); }
        return result;
    }

    private Deck read(Path file) {
        BridgeProtocol.require(Files.isRegularFile(file), "Deck no longer exists");
        Deck result = DeckFiles.read(file.toFile());
        BridgeProtocol.require(result != null, "Forge could not read this deck");
        result.getMain(); // resolve Forge's deferred section data
        return result;
    }

    private JsonObject open(String id) throws Exception {
        if (!isPrecon(id)) {
            JsonObject result = describe(read(path(id)), id, version(path(id)));
            result.addProperty("source", "custom");
            return result;
        }
        JsonObject result = describe(precon(id), id, "");
        result.addProperty("source", "precon"); result.addProperty("readOnly", true);
        return result;
    }

    private String version(Path file) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(file)));
    }

    private JsonObject list() throws Exception {
        JsonArray decks = new JsonArray(), warnings = new JsonArray();
        try (Stream<Path> files = Files.walk(root)) {
            for (Path file : files.filter(p -> Files.isRegularFile(p) && p.toString().toLowerCase(Locale.ROOT).endsWith(".dck")).sorted().toList()) {
                String id = root.relativize(file).toString().replace('\\', '/');
                try {
                    Deck d = read(path(id));
                    JsonObject item = new JsonObject();
                    item.addProperty("id", id); item.addProperty("name", d.getName());
                    item.addProperty("count", d.getMain().countAll() + d.getOrCreate(DeckSection.Commander).countAll());
                    item.addProperty("legal", DeckFormat.Commander.getDeckConformanceProblem(d) == null);
                    PaperCard cover = d.getCommanders().stream().findFirst().orElseGet(() -> d.getMain().iterator().hasNext() ? d.getMain().iterator().next().getKey() : null);
                    if (cover != null) item.add("cover", card(cover));
                    item.addProperty("source", "custom");
                    decks.add(item);
                } catch (Exception e) { warnings.add(id + ": " + e.getMessage()); }
            }
        }
        for (var precon : botDecks().libraryPrecons().entrySet()) {
            // Bundled decks do not change while the service runs; summarize each once.
            JsonObject item = preconEntries.computeIfAbsent(precon.getKey(), name -> {
                Deck d = precon.getValue().getDeck();
                JsonObject entry = new JsonObject();
                entry.addProperty("id", PRECON + name); entry.addProperty("name", d.getName());
                entry.addProperty("count", d.getMain().countAll() + d.getOrCreate(DeckSection.Commander).countAll());
                entry.addProperty("legal", DeckFormat.Commander.getDeckConformanceProblem(d) == null);
                d.getCommanders().stream().findFirst().ifPresent(c -> entry.add("cover", card(c)));
                entry.addProperty("source", "precon"); entry.addProperty("readOnly", true);
                return entry;
            });
            decks.add(item.deepCopy());
        }
        JsonObject result = new JsonObject(); result.add("decks", decks); result.add("warnings", warnings);
        result.addProperty("catalogCount", catalog.size());
        JsonArray sections = new JsonArray(); for (DeckSection s : DeckSection.values()) sections.add(s.name());
        result.add("sections", sections);
        return result;
    }

    static String key(PaperCard c) {
        return c.getName() + "|" + c.getEdition() + "|" + c.getArtIndex() + "|" + c.isFoil();
    }

    JsonObject card(PaperCard c) {
        var rules = c.getRules();
        JsonObject out = new JsonObject();
        out.addProperty("key", key(c)); out.addProperty("name", c.getName());
        out.addProperty("imageKey", c.getImageKey(false)); out.addProperty("edition", c.getEdition());
        if (c.hasBackFace()) out.addProperty("backImageKey", c.getImageKey(true));
        out.addProperty("collectorNumber", c.getCollectorNumber()); out.addProperty("foil", c.isFoil());
        out.addProperty("manaCost", rules.getManaCost().toString()); out.addProperty("manaValue", rules.getManaCost().getCMC());
        out.addProperty("typeLine", rules.getType().toString()); out.addProperty("text", rules.getOracleText());
        out.addProperty("rarity", c.getRarity().toString());
        out.addProperty("colorIdentity", rules.getColorIdentity().getColor());
        out.addProperty("color", color(rules.getColor().getColor()));
        out.addProperty("commanderEligible", DeckFormat.Commander.isLegalCommander(rules));
        out.addProperty("power", rules.getMainPart().getPower()); out.addProperty("toughness", rules.getMainPart().getToughness());
        out.addProperty("stats", rules.getType().isCreature() ? rules.getMainPart().getPower() + " / " + rules.getMainPart().getToughness() : "");
        return out;
    }

    private static String color(int mask) {
        for (int i = 0; i < 5; i++) if ((mask & (1 << i)) != 0) return "WUBRG".substring(i, i + 1);
        return "C";
    }

    private JsonObject describe(Deck deck, String id, String version) {
        JsonObject result = new JsonObject();
        result.addProperty("id", id); result.addProperty("version", version); result.addProperty("name", deck.getName());
        JsonObject sections = new JsonObject(); int total = 0, lands = 0; double mana = 0; int nonlands = 0;
        int[] curve = new int[8];
        for (var section : deck) {
            JsonArray entries = new JsonArray();
            for (var entry : section.getValue()) {
                JsonObject value = card(entry.getKey()); value.addProperty("quantity", entry.getValue());
                value.addProperty("commander", section.getKey() == DeckSection.Commander); entries.add(value);
                if (section.getKey() == DeckSection.Main || section.getKey() == DeckSection.Commander) {
                    total += entry.getValue();
                    if (entry.getKey().getRules().getType().isLand()) lands += entry.getValue();
                    else {
                        int cmc = Math.max(0, entry.getKey().getRules().getManaCost().getCMC());
                        nonlands += entry.getValue(); mana += cmc * entry.getValue(); curve[Math.min(7, cmc)] += entry.getValue();
                    }
                }
            }
            sections.add(section.getKey().name(), entries);
        }
        result.add("sections", sections); result.addProperty("count", total); result.addProperty("lands", lands);
        result.addProperty("averageMana", nonlands == 0 ? 0 : mana / nonlands);
        result.add("curve", new Gson().toJsonTree(curve));
        String problem = DeckFormat.Commander.getDeckConformanceProblem(deck);
        result.addProperty("legal", problem == null); result.addProperty("validation", problem == null ? "Ready for Commander" : problem);
        return result;
    }

    private PaperCard resolve(String key) {
        PaperCard result = cards.get(key);
        if (result == null && key.endsWith("|true")) {
            PaperCard normal = cards.get(key.substring(0, key.length() - 4) + "false");
            if (normal != null) { result = normal.getFoiled(); cards.put(key, result); }
        }
        BridgeProtocol.require(result != null, "Unknown card printing: " + key);
        return result;
    }

    private Deck fromDraft(JsonObject draft) {
        BridgeProtocol.require(draft != null, "Missing deck");
        String name = string(draft, "name", "Untitled deck").strip();
        BridgeProtocol.require(!name.isBlank() && name.length() <= 120 && name.chars().noneMatch(Character::isISOControl), "Use a deck name between 1 and 120 characters");
        String id = string(draft, "id", "");
        String importToken = string(draft, "importToken", "");
        BridgeProtocol.require(!id.isEmpty() || importToken.isEmpty() || imports.containsKey(importToken), "This import preview expired. Import the source again before saving.");
        String sourceId = string(draft, "sourceId", "");
        Deck result = !id.isEmpty() ? new Deck(isPrecon(id) ? precon(id) : read(path(id)), name)
                : !sourceId.isEmpty() ? new Deck(isPrecon(sourceId) ? precon(sourceId) : read(path(sourceId)), name)
                : imports.containsKey(importToken) ? new Deck(imports.get(importToken), name) : new Deck(name);
        JsonObject sections = draft.getAsJsonObject("sections");
        BridgeProtocol.require(sections != null && sections.size() <= DeckSection.values().length, "Missing deck sections");
        for (DeckSection section : DeckSection.values()) result.getOrCreate(section).clear();
        int count = 0;
        for (var section : sections.entrySet()) {
            DeckSection type = DeckSection.smartValueOf(section.getKey());
            BridgeProtocol.require(type != null, "Unknown deck section");
            for (JsonElement e : section.getValue().getAsJsonArray()) {
                JsonObject entry = e.getAsJsonObject();
                int quantity = entry.get("quantity").getAsInt();
                BridgeProtocol.require(quantity > 0 && quantity <= 999, "Card quantity must be 1 to 999");
                count += quantity; BridgeProtocol.require(count <= 5000, "Deck has too many cards");
                result.getOrCreate(type).add(resolve(entry.get("key").getAsString()), quantity);
            }
        }
        result.setDeckFormat(DeckFormat.Commander);
        return result;
    }

    private static String searchKey(String text) {
        return SEARCH_PUNCTUATION.matcher(text.toLowerCase(Locale.ROOT)).replaceAll("");
    }

    private JsonObject search(JsonObject request) {
        String query = searchKey(string(request, "query", ""));
        String type = string(request, "type", "").toLowerCase(Locale.ROOT);
        String color = string(request, "color", "");
        boolean commanderOnly = request.has("commanders") && request.get("commanders").getAsBoolean();
        int mana = request.has("mana") ? request.get("mana").getAsInt() : -1;
        int offset = Math.max(0, request.has("offset") ? request.get("offset").getAsInt() : 0);
        List<PaperCard> matches = catalog.stream().filter(c -> {
            var r = c.getRules();
            return (query.isEmpty() || searchIndex.get(c.getName()).fullText().contains(query))
                && (type.isEmpty() || r.getType().toString().toLowerCase(Locale.ROOT).contains(type))
                && (color.isEmpty() || (color.equals("C") ? r.getColorIdentity().isColorless() : (r.getColorIdentity().getColor() & (1 << "WUBRG".indexOf(color))) != 0))
                && (mana < 0 || r.getManaCost().getCMC() == mana)
                && (!commanderOnly || DeckFormat.Commander.isLegalCommander(r));
        }).sorted(Comparator.comparingInt((PaperCard c) -> searchIndex.get(c.getName()).name().equals(query) ? 0
                : searchIndex.get(c.getName()).name().contains(query) ? 1 : 2)
                .thenComparing(PaperCard::getName, String.CASE_INSENSITIVE_ORDER)).toList();
        int limit = Math.max(1, Math.min(60, request.has("limit") ? request.get("limit").getAsInt() : 60));
        JsonArray entries = new JsonArray(); matches.stream().skip(offset).limit(limit).forEach(c -> entries.add(card(c)));
        JsonObject result = new JsonObject(); result.add("cards", entries); result.addProperty("total", matches.size()); result.addProperty("offset", offset); return result;
    }

    private JsonObject printings(String name) {
        JsonArray entries = new JsonArray();
        for (CardDb db : databases()) for (PaperCard c : db.getAllCards(name)) entries.add(card(c));
        JsonObject result = new JsonObject(); result.add("cards", entries); return result;
    }

    private JsonObject importDeck(JsonObject request) throws Exception {
        String text = string(request, "text", "");
        String url = string(request, "url", "").strip();
        if (!url.isEmpty()) text = DeckUrlLoader.loadImportText(url);
        BridgeProtocol.require(!text.isBlank() && text.length() <= 900000, "Provide a deck list under 900 KB");
        Deck deck;
        JsonArray warnings = new JsonArray();
        if (text.toLowerCase(Locale.ROOT).contains("[metadata]")) {
            var sections = FileSection.parseSections(Arrays.asList(text.split("\\R")));
            for (var section : sections.entrySet()) {
                if (DeckSection.smartValueOf(section.getKey()) == null) continue;
                for (String line : section.getValue()) {
                    if (!line.isBlank() && !line.strip().startsWith("#") && CardPool.fromCardList(List.of(line)).isEmpty())
                        warnings.add("UNKNOWN_CARD: " + line);
                }
            }
            deck = DeckSerializer.fromSections(sections);
            BridgeProtocol.require(deck != null, "Invalid Forge deck file");
        } else {
            var importer = new DeckImportController(widget(ICheckBox.class, request.has("dateEnabled") && request.get("dateEnabled").getAsBoolean()), widget(IComboBox.class, request.has("month") ? request.get("month").getAsInt() : 0), widget(IComboBox.class, request.has("year") ? request.get("year").getAsInt() : java.time.LocalDate.now().getYear()), false);
            importer.setGameFormat(GameType.Commander);
            importer.setAllowedSections(Arrays.asList(DeckSection.values()));
            importer.setCardArtPreference(!string(request, "art", "latest").equals("original"), request.has("coreOnly") && request.get("coreOnly").getAsBoolean());
            importer.setSmartCardArtOptimisation(!request.has("smartArt") || request.get("smartArt").getAsBoolean());
            importer.importBannedAndRestrictedCards(!request.has("includeRestricted") || request.get("includeRestricted").getAsBoolean());
            for (var token : importer.parseInput(text)) {
                if (token.getType() == DeckRecognizer.TokenType.UNKNOWN_CARD || token.getType() == DeckRecognizer.TokenType.UNSUPPORTED_CARD
                    || token.getType() == DeckRecognizer.TokenType.CARD_FROM_NOT_ALLOWED_SET || token.getType() == DeckRecognizer.TokenType.CARD_FROM_INVALID_SET
                    || token.getType() == DeckRecognizer.TokenType.UNSUPPORTED_DECK_SECTION
                    || (token.getType() == DeckRecognizer.TokenType.LIMITED_CARD && !importer.importBannedAndRestrictedCards()))
                    warnings.add(token.getType() + ": " + token.getText());
            }
            if (importer.isSmartCardArtEnabled()) importer.optimiseCardArtInTokens();
            deck = importer.accept();
            BridgeProtocol.require(deck != null && !deck.isEmpty(), "No supported cards were recognized. Check the deck list or URL.");
        }
        if (!url.isEmpty()) deck.setSourceUrl(url);
        String name = string(request, "name", "").strip();
        if (!name.isEmpty()) deck.setName(name);
        if (deck.getName().isBlank()) deck.setName("Imported deck");
        // Store import metadata as an opaque draft token rather than discarding it on first save.
        String token = UUID.randomUUID().toString(); imports.put(token, deck);
        while (imports.size() > 20) imports.remove(imports.keySet().iterator().next());
        JsonObject out = describe(deck, "", ""); out.addProperty("importToken", token); out.add("warnings", warnings); return out;
    }

    private final Map<String, Deck> imports = new LinkedHashMap<>();

    @SuppressWarnings("unchecked")
    private static <T> T widget(Class<T> type, Object value) {
        return (T) Proxy.newProxyInstance(type.getClassLoader(), new Class<?>[]{type}, (p, method, args) -> switch (method.getName()) {
            case "isSelected" -> value instanceof Boolean b && b;
            case "getSelectedItem", "getSelectedIndex" -> value;
            case "isEnabled", "isVisible" -> true;
            case "getToolTipText", "toString" -> "";
            default -> null;
        });
    }

    private JsonObject delete(JsonObject request) throws Exception {
        String id = string(request, "id", "");
        BridgeProtocol.require(!isPrecon(id), "Forge precons cannot be deleted");
        Path source = path(id);
        BridgeProtocol.require(Files.isRegularFile(source), "Deck no longer exists");
        BridgeProtocol.require(version(source).equals(string(request, "version", "")), "This deck changed on disk. Reopen it before deleting.");
        Path trash = root.resolve(".forgeui-trash");
        Files.createDirectories(trash);
        BridgeProtocol.require(trash.toRealPath().startsWith(root.toRealPath()), "Deck archive is outside the library");
        Path destination = trash.resolve(source.getFileName() + "." + UUID.randomUUID() + ".deleted");
        Files.move(source, destination);
        JsonObject result = new JsonObject(); result.addProperty("id", id);
        return result;
    }

    private JsonObject save(JsonObject request) throws Exception {
        JsonObject draft = request.getAsJsonObject("deck");
        Deck edited = fromDraft(draft);
        String id = string(draft, "id", "");
        BridgeProtocol.require(!isPrecon(id), "Forge precons are read-only. Save a copy to keep your changes.");
        boolean existing = !id.isEmpty();
        Path destination;
        if (existing) {
            destination = path(id);
            BridgeProtocol.require(version(destination).equals(string(draft, "version", "")), "This deck changed on disk. Reopen it before saving to avoid overwriting those changes.");
        } else {
            String filename = edited.getName().replaceAll("[<>:\"/\\\\|?*\\p{Cntrl}]", "_").replaceAll("[ .]+$", "");
            BridgeProtocol.require(!filename.isEmpty() && !filename.matches("(?i)(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])"), "Choose another deck name");
            destination = path(filename + ".dck");
            BridgeProtocol.require(!Files.exists(destination), "A deck with this name already exists. Choose a different name.");
            String token = string(draft, "importToken", "");
            if (imports.containsKey(token)) {
                Deck original = new Deck(imports.get(token), edited.getName());
                for (DeckSection s : DeckSection.values()) original.putSection(s, edited.getOrCreate(s));
                edited = original;
            }
        }
        Path temp = Files.createTempFile(destination.getParent(), ".forgeui-", ".tmp");
        try {
            DeckSerializer.writeDeck(edited, temp.toFile());
            BridgeProtocol.require(Files.size(temp) > 0, "Could not write deck");
            if (existing) {
                BridgeProtocol.require(version(destination).equals(string(draft, "version", "")), "This deck changed on disk. Reopen it before saving.");
                try { Files.move(temp, destination, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE); }
                catch (AtomicMoveNotSupportedException e) { Files.move(temp, destination, StandardCopyOption.REPLACE_EXISTING); }
            }
            else Files.move(temp, destination);
        } finally { Files.deleteIfExists(temp); }
        return describe(read(destination), root.relativize(destination).toString().replace('\\', '/'), version(destination));
    }

    private JsonObject export(JsonObject request) throws Exception {
        Deck deck = fromDraft(request.getAsJsonObject("deck"));
        JsonObject result = new JsonObject();
        if (string(request, "format", "dck").equals("text")) result.addProperty("text", deck.generateTextExport());
        else {
            Path temp = Files.createTempFile("forgeui-export-", ".dck");
            try { DeckSerializer.writeDeck(deck, temp.toFile()); result.addProperty("text", Files.readString(temp)); }
            finally { Files.deleteIfExists(temp); }
        }
        return result;
    }

    private JsonObject image(JsonObject request) throws Exception {
        PaperCard c = resolve(string(request, "key", ""));
        boolean back = request.has("back") && request.get("back").getAsBoolean();
        BridgeProtocol.require(!back || c.hasBackFace(), "This card has no back face");
        File file = ImageKeys.getImageFile(back ? c.getCardAltImageKey() : c.getCardImageKey());
        JsonObject result = new JsonObject();
        if (file != null && file.isFile() && file.length() < 2500000) result.addProperty("data", Base64.getEncoder().encodeToString(Files.readAllBytes(file.toPath())));
        String url = CardArtwork.cardUrl(c, back);
        if (!url.isEmpty()) result.addProperty("url", url);
        return result;
    }

    static String string(JsonObject value, String key, String fallback) {
        return value.has(key) && !value.get(key).isJsonNull() ? value.get(key).getAsString() : fallback;
    }
}
