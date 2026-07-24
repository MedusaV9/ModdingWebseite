package dev.projecteclipse.eclipse.xboxevent;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Comparator;
import java.util.HexFormat;
import java.util.Locale;
import java.util.stream.Stream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.storage.LevelResource;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;

/**
 * Lazy per-save installer for the bundled Xbox tutorial world payloads (plan §2.13.2).
 * Runs at {@link ServerAboutToStartEvent} — before any chunk is read, so region files are
 * never touched while handles are open (risk R7). For each manifest world it extracts the
 * bundled zip into {@code <world>/dimensions/eclipse/xbox_<id>/} when the region payload is
 * absent or a staged reset marker ({@code <world>/eclipse/xbox_reset_<id>}) exists.
 *
 * <p>Zip layout is frozen by P5-W7: {@code region/*.mca}, optional {@code entities/*.mca},
 * {@code level.dat} at the archive root. Only the {@code .mca} payload is extracted
 * ({@code level.dat} is dev-client sugar per the W7 wiring notes). The zip bytes are
 * sha256-verified against the manifest before anything is deleted or written.</p>
 *
 * <p>Resets are STAGED, never live: {@code /dev xboxevent reset <world>} writes the marker
 * and announces "applies on next restart" (§2.13.2).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class XboxWorldInstaller {

    private XboxWorldInstaller() {}

    @SubscribeEvent
    public static void onServerAboutToStart(ServerAboutToStartEvent event) {
        MinecraftServer server = event.getServer();
        for (XboxWorldsManifest.WorldEntry entry : XboxWorldsManifest.all().values()) {
            try {
                installIfNeeded(server, entry);
            } catch (IOException e) {
                EclipseMod.LOGGER.error("Xbox world install failed for {} — event start for it will be refused",
                        entry.worldId(), e);
            }
        }
    }

    /** Region payload present = at least one {@code region/*.mca} under the dimension dir. */
    public static boolean isInstalled(MinecraftServer server, String worldId) {
        Path regionDir = dimensionDir(server, worldId).resolve("region");
        if (!Files.isDirectory(regionDir)) {
            return false;
        }
        try (Stream<Path> files = Files.list(regionDir)) {
            return files.anyMatch(file -> file.getFileName().toString().endsWith(".mca"));
        } catch (IOException e) {
            EclipseMod.LOGGER.warn("Cannot inspect {}", regionDir, e);
            return false;
        }
    }

    /** Writes the staged reset marker; the wipe+reinstall happens on the next boot. */
    public static void stageReset(MinecraftServer server, String worldId) throws IOException {
        Path marker = resetMarker(server, worldId);
        Files.createDirectories(marker.getParent());
        Files.writeString(marker, "staged by /dev xboxevent reset — applied on next server start\n");
    }

    public static boolean isResetStaged(MinecraftServer server, String worldId) {
        return Files.exists(resetMarker(server, worldId));
    }

    // ------------------------------------------------------------------ internals

    private static Path dimensionDir(MinecraftServer server, String worldId) {
        return server.getWorldPath(LevelResource.ROOT)
                .resolve("dimensions").resolve("eclipse").resolve("xbox_" + worldId);
    }

    private static Path resetMarker(MinecraftServer server, String worldId) {
        return server.getWorldPath(LevelResource.ROOT)
                .resolve("eclipse").resolve("xbox_reset_" + worldId);
    }

    private static void installIfNeeded(MinecraftServer server, XboxWorldsManifest.WorldEntry entry)
            throws IOException {
        String worldId = entry.worldId();
        Path dimensionDir = dimensionDir(server, worldId);
        boolean installed = isInstalled(server, worldId);
        boolean resetStaged = isResetStaged(server, worldId);
        if (installed && !resetStaged) {
            return;
        }

        byte[] zipBytes = readBundledZip(entry);
        if (zipBytes == null) {
            return; // already logged; service refuses to start this world
        }
        String actualSha = sha256Hex(zipBytes);
        if (!actualSha.equalsIgnoreCase(entry.sha256())) {
            EclipseMod.LOGGER.error(
                    "Bundled xbox world zip {} fails sha256 verification (expected {}, got {}) — NOT installing",
                    entry.zipResourcePath(), entry.sha256(), actualSha);
            return;
        }

        long startNanos = System.nanoTime();
        deleteRecursively(dimensionDir);
        int extracted = extract(zipBytes, dimensionDir);
        Files.deleteIfExists(resetMarker(server, worldId));
        EclipseMod.LOGGER.info(
                "Installed xbox world {} into {} ({} region/entity files, sha256 OK, {} ms{})",
                worldId, dimensionDir, extracted,
                (System.nanoTime() - startNanos) / 1_000_000L,
                resetStaged ? ", staged reset applied" : "");
    }

    private static byte[] readBundledZip(XboxWorldsManifest.WorldEntry entry) throws IOException {
        try (InputStream in = XboxWorldInstaller.class.getClassLoader()
                .getResourceAsStream(entry.zipResourcePath())) {
            if (in == null) {
                EclipseMod.LOGGER.error(
                        "Bundled xbox world zip missing from jar: {} (worlds not committed yet?)",
                        entry.zipResourcePath());
                return null;
            }
            return in.readAllBytes();
        }
    }

    /** Extracts only the frozen {@code region/*.mca} + {@code entities/*.mca} payload. */
    private static int extract(byte[] zipBytes, Path targetDir) throws IOException {
        int count = 0;
        // Normalize the base first: in dev the server root is "." so an un-normalized
        // targetDir (e.g. ./world/dimensions/...) never prefix-matches its normalized
        // children and the zip-slip guard rejects every entry.
        Path base = targetDir.toAbsolutePath().normalize();
        try (ZipInputStream zip = new ZipInputStream(new ByteArrayInputStream(zipBytes))) {
            ZipEntry zipEntry;
            while ((zipEntry = zip.getNextEntry()) != null) {
                if (zipEntry.isDirectory() || !isWantedEntry(zipEntry.getName())) {
                    continue;
                }
                Path target = base.resolve(zipEntry.getName()).normalize();
                if (!target.startsWith(base)) { // zip-slip guard
                    throw new IOException("Illegal zip entry path: " + zipEntry.getName());
                }
                Files.createDirectories(target.getParent());
                Files.copy(zip, target);
                count++;
            }
        }
        return count;
    }

    private static boolean isWantedEntry(String name) {
        String normalized = name.toLowerCase(Locale.ROOT);
        return (normalized.startsWith("region/") || normalized.startsWith("entities/"))
                && normalized.endsWith(".mca");
    }

    private static void deleteRecursively(Path dir) throws IOException {
        if (!Files.exists(dir)) {
            return;
        }
        try (Stream<Path> walk = Files.walk(dir)) {
            for (Path path : walk.sorted(Comparator.reverseOrder()).toList()) {
                Files.delete(path);
            }
        }
    }

    private static String sha256Hex(byte[] bytes) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("JVM without SHA-256", e);
        }
    }
}
