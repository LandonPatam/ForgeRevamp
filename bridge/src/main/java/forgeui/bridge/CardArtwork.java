package forgeui.bridge;

import forge.ImageKeys;
import forge.StaticData;
import forge.localinstance.properties.ForgeConstants;
import forge.util.FileUtil;
import forge.util.ImageUtil;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ConcurrentHashMap;

/** Resolve public token keys using Forge's token edition/collector-number mapping. */
final class CardArtwork {
    private static final ConcurrentHashMap<String, List<String>> CACHE = new ConcurrentHashMap<>();

    static List<String> urls(String imageKey) {
        if (imageKey == null || StaticData.instance() == null) return List.of();
        if (imageKey.startsWith(ImageKeys.CARD_PREFIX)) return CACHE.computeIfAbsent(imageKey, CardArtwork::resolveCard);
        if (!imageKey.startsWith(ImageKeys.TOKEN_PREFIX)) return List.of();
        return CACHE.computeIfAbsent(imageKey, CardArtwork::resolve);
    }

    private static List<String> resolveCard(String key) {
        var card = ImageUtil.getPaperCardFromImageKey(key);
        if (card == null || card.getRules().isCustom()) return List.of();
        String url = cardUrl(card, key.endsWith(ImageKeys.BACKFACE_POSTFIX));
        return url.isEmpty() ? List.of() : List.of(url);
    }

    static String cardUrl(forge.item.PaperCard card, boolean back) {
        var edition = StaticData.instance().getEditions().get(card.getEdition());
        if (edition == null || card.getRules().isCustom()) return "";
        String url = ForgeConstants.URL_PIC_SCRYFALL_DOWNLOAD
                + ImageUtil.getScryfallDownloadUrl(card, back ? "back" : "", edition.getScryfallCode(), "en", false);
        // Language is optional at Scryfall: prefer English when available, but
        // preserve Japanese-only (e.g. SLD 46/48) set/collector-number printings.
        return url.replace("/en?", "?");
    }

    private static List<String> resolve(String imageKey) {
        String key = imageKey.substring(ImageKeys.TOKEN_PREFIX.length());
        String face = key.endsWith(ImageKeys.BACKFACE_POSTFIX) ? "back" : "";
        if (!face.isEmpty()) key = key.substring(0, key.length() - ImageKeys.BACKFACE_POSTFIX.length());
        String[] parts = key.split("\\|");
        List<String> urls = new ArrayList<>();
        String filename = (parts.length > 1 ? parts[1] + "/" : "")
                + (parts.length > 2 ? parts[2] + "_" : "") + parts[0]
                + (parts.length <= 2 && !face.isEmpty() ? "_back" : "") + ".jpg";
        for (var entry : FileUtil.readNameUrlFile(ForgeConstants.IMAGE_LIST_TOKENS_FILE)) {
            if (filename.equalsIgnoreCase(entry.getLeft())) { urls.add(entry.getRight()); break; }
        }
        if (parts.length < 2) return List.copyOf(urls);
        var edition = StaticData.instance().getEditions().get(parts[1]);
        if (edition == null || edition.getType() == forge.card.CardEdition.Type.CUSTOM_SET) return List.copyOf(urls);
        if (parts.length > 2) {
            urls.add(ForgeConstants.URL_PIC_SCRYFALL_DOWNLOAD + ImageUtil.getScryfallTokenDownloadUrl(parts[2], edition.getTokensCode(), "en", face));
        } else {
            for (var token : edition.getTokens().get(parts[0])) {
                if (token.collectorNumber() != null && !token.collectorNumber().isEmpty()) {
                    urls.add(ForgeConstants.URL_PIC_SCRYFALL_DOWNLOAD + ImageUtil.getScryfallTokenDownloadUrl(token.collectorNumber(), edition.getTokensCode(), "en", face));
                }
            }
        }
        return urls.stream().distinct().toList();
    }
}
