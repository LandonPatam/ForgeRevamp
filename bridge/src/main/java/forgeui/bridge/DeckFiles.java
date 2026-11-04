package forgeui.bridge;

import forge.deck.Deck;
import forge.deck.io.DeckSerializer;
import forge.util.FileSection;
import java.io.File;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

/** Preserve accented names in native UTF-8 and legacy Windows deck files. */
final class DeckFiles {
    static String decode(byte[] bytes) {
        if (bytes.length >= 2 && bytes[0] == (byte) 0xff && bytes[1] == (byte) 0xfe)
            return new String(bytes, 2, bytes.length - 2, StandardCharsets.UTF_16LE);
        if (bytes.length >= 2 && bytes[0] == (byte) 0xfe && bytes[1] == (byte) 0xff)
            return new String(bytes, 2, bytes.length - 2, StandardCharsets.UTF_16BE);
        try {
            // A permissive UTF-8 decoder would silently turn CP1252 accents
            // into U+FFFD, losing the name before Forge can resolve the card.
            String text = StandardCharsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(bytes)).toString();
            return text.startsWith("\ufeff") ? text.substring(1) : text;
        } catch (CharacterCodingException legacyEncoding) {
            return new String(bytes, Charset.forName("windows-1252"));
        }
    }

    static Deck read(File file) {
        try {
            return DeckSerializer.fromSections(FileSection.parseSections(decode(Files.readAllBytes(file.toPath())).lines().toList()));
        } catch (IOException e) {
            throw new IllegalArgumentException("Could not read deck file: " + file.getName(), e);
        }
    }
}
