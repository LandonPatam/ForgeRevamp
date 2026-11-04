package forgeui.bridge;

import com.google.gson.JsonObject;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;

/** Reports actual initialization milestones before the WebSocket service exists. */
final class StartupStatus {
    private final Path file;

    StartupStatus(String filename) { file = filename == null ? null : Path.of(filename).toAbsolutePath().normalize(); }

    void write(String stage, String title, String detail) {
        System.out.println("Startup: " + title);
        if (file == null) return;
        JsonObject value = new JsonObject();
        value.addProperty("stage", stage); value.addProperty("title", title); value.addProperty("detail", detail);
        Path temp = null;
        try {
            Files.createDirectories(file.getParent());
            temp = Files.createTempFile(file.getParent(), ".startup-", ".tmp");
            Files.writeString(temp, value.toString(), StandardCharsets.UTF_8);
            try { Files.move(temp, file, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING); }
            catch (AtomicMoveNotSupportedException e) { Files.move(temp, file, StandardCopyOption.REPLACE_EXISTING); }
        } catch (Exception e) { System.err.println("Could not update startup status: " + e.getMessage()); }
        finally { if (temp != null) try { Files.deleteIfExists(temp); } catch (Exception ignored) {} }
    }
}
