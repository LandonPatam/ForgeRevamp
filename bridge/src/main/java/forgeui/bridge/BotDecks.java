package forgeui.bridge;

import com.google.gson.*;
import forge.deck.*;
import java.util.*;
import java.util.stream.Collectors;

/** The same read-only precons and AI commander generator list as Forge's chooser. */
final class BotDecks {
    // Loaded separately: the deck library lists precons at startup, while the
    // commander generator list is only needed once match settings opens.
    private Map<String, DeckProxy> precons;
    private Map<String, DeckProxy> preconsByName;
    private Map<String, DeckProxy> commanders;
    private JsonObject catalog;

    private Map<String, DeckProxy> precons() {
        if (precons == null) {
            precons = new TreeMap<>();
            preconsByName = new TreeMap<>(String.CASE_INSENSITIVE_ORDER);
            for (DeckProxy proxy : DeckProxy.getAllCommanderPreconDecks()) {
                precons.put(proxy.getUniqueKey(), proxy);
                preconsByName.putIfAbsent(proxy.getName(), proxy);
            }
        }
        return precons;
    }

    private Map<String, DeckProxy> commanders() {
        if (commanders == null) {
            commanders = new TreeMap<>();
            for (DeckProxy proxy : CommanderDeckGenerator.getCommanderDecks(DeckFormat.Commander, true, false))
                commanders.put(proxy.getName(), proxy);
        }
        return commanders;
    }

    /** Precons by display name, in name order, for the deck library. Decks are Forge's shared read-only copies. */
    Map<String, DeckProxy> libraryPrecons() {
        precons();
        return preconsByName;
    }

    JsonObject catalog() {
        if (catalog != null) return catalog;
        catalog = new JsonObject();
        JsonArray fixed = new JsonArray(), generated = new JsonArray();
        precons().forEach((id, proxy) -> {
            Deck deck = proxy.getDeck();
            String problem = DeckFormat.Commander.getDeckConformanceProblem(deck);
            JsonObject entry = entry(id, proxy.getName());
            entry.addProperty("commander", deck.getCommanders().stream().map(c -> c.getName()).collect(Collectors.joining(" / ")));
            entry.addProperty("legal", problem == null);
            entry.addProperty("problem", problem == null ? "" : problem);
            fixed.add(entry);
        });
        commanders().forEach((id, proxy) -> generated.add(entry(id, proxy.getName())));
        catalog.add("precon", fixed); catalog.add("commander", generated);
        return catalog;
    }

    private static JsonObject entry(String id, String name) {
        JsonObject entry = new JsonObject(); entry.addProperty("id", id); entry.addProperty("name", name); return entry;
    }

    void validate(String mode, String id) {
        Map<String, DeckProxy> source = switch (mode) {
            case "precon" -> precons();
            case "commander" -> commanders();
            default -> throw new IllegalArgumentException("Unknown Forge deck source");
        };
        BridgeProtocol.require(source.containsKey(id), "Choose an available Forge " + (mode.equals("precon") ? "Commander precon" : "commander"));
        if (mode.equals("precon")) {
            String problem = DeckFormat.Commander.getDeckConformanceProblem(source.get(id).getDeck());
            BridgeProtocol.require(problem == null, "This precon is not ready for Commander: " + problem);
        }
    }

    /** Id of a random bundled precon that is legal for Commander. */
    String randomPrecon() {
        List<String> legal = precons().entrySet().stream()
            .filter(e -> DeckFormat.Commander.getDeckConformanceProblem(e.getValue().getDeck()) == null)
            .map(Map.Entry::getKey).collect(Collectors.toList());
        BridgeProtocol.require(!legal.isEmpty(), "No Commander precons are available");
        return legal.get(java.util.concurrent.ThreadLocalRandom.current().nextInt(legal.size()));
    }

    Deck create(String mode, String id) {
        validate(mode, id);
        Deck deck = (mode.equals("precon") ? precons() : commanders()).get(id).getDeck();
        return new Deck(deck);
    }
}
