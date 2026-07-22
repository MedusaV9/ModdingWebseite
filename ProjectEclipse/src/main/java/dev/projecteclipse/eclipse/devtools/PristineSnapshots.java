package dev.projecteclipse.eclipse.devtools;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.StandardCopyOption;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.List;
import java.util.Locale;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.storage.LevelResource;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;

/**
 * Pristine world snapshots (W14, {@code docs/ideas/01_world_terrain.md} §C): whole-region
 * backups of the curated map. {@code /eclipse stage snapshot save <name>} flushes every
 * level ({@code ServerChunkCache.save(true)}) and copies the region-storage directories
 * ({@code region/ entities/ poi/}, plus the nether's {@code DIM-1/} equivalents when
 * present) to {@code <world>/eclipse/stage_snapshots/<name>/}.
 * {@code restore <name>} only writes a marker file — the copy-back runs at the NEXT boot's
 * {@link ServerAboutToStartEvent}, before any level opens (a running server holds the
 * region files, so a restore requires a restart; the command feedback says so).
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class PristineSnapshots {
    /** World-relative region-storage directories captured per snapshot (missing ones skipped). */
    private static final List<String> COPY_DIRS = List.of(
            "region", "entities", "poi", "DIM-1/region", "DIM-1/entities", "DIM-1/poi");
    private static final String MARKER_FILE = "RESTORE_PENDING";

    private PristineSnapshots() {}

    private static Path snapshotsDir(Path worldRoot) {
        return worldRoot.resolve("eclipse").resolve("stage_snapshots");
    }

    /** {@code true} for simple directory-safe names ({@code [a-z0-9_-]+}, ≤ 32 chars). */
    public static boolean isValidName(String name) {
        return !name.isEmpty() && name.length() <= 32 && name.matches("[a-z0-9_-]+");
    }

    /** Flush + copy. Returns a feedback line, or an {@code "ERROR: "}-prefixed failure. */
    public static String save(MinecraftServer server, String name) {
        if (!isValidName(name)) {
            return "ERROR: snapshot names must match [a-z0-9_-]+ (max 32 chars)";
        }
        long startNanos = System.nanoTime();
        for (ServerLevel level : server.getAllLevels()) {
            level.getChunkSource().save(true);
        }
        Path worldRoot = server.getWorldPath(LevelResource.ROOT);
        Path target = snapshotsDir(worldRoot).resolve(name);
        try {
            deleteRecursively(target);
            int copied = 0;
            for (String dir : COPY_DIRS) {
                Path source = worldRoot.resolve(dir);
                if (Files.isDirectory(source)) {
                    copyRecursively(source, target.resolve(dir));
                    copied++;
                }
            }
            double seconds = (System.nanoTime() - startNanos) / 1.0e9D;
            String result = String.format(Locale.ROOT,
                    "Pristine snapshot '%s' saved: %d region dirs copied to %s in %.1f s",
                    name, copied, target, seconds);
            EclipseMod.LOGGER.info("PristineSnapshots: {}", result);
            return result;
        } catch (IOException e) {
            EclipseMod.LOGGER.error("PristineSnapshots: failed to save '{}'", name, e);
            return "ERROR: failed to copy snapshot '" + name + "' — see the server log";
        }
    }

    /** Stages the restore (marker file); the copy-back happens at the next server start. */
    public static String requestRestore(MinecraftServer server, String name) {
        if (!isValidName(name)) {
            return "ERROR: snapshot names must match [a-z0-9_-]+ (max 32 chars)";
        }
        Path worldRoot = server.getWorldPath(LevelResource.ROOT);
        Path snapshot = snapshotsDir(worldRoot).resolve(name);
        if (!Files.isDirectory(snapshot)) {
            return "ERROR: no pristine snapshot '" + name + "' (see " + snapshotsDir(worldRoot) + ")";
        }
        try {
            Files.createDirectories(snapshotsDir(worldRoot));
            Files.writeString(snapshotsDir(worldRoot).resolve(MARKER_FILE), name, StandardCharsets.UTF_8);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("PristineSnapshots: failed to write restore marker for '{}'", name, e);
            return "ERROR: failed to write the restore marker — see the server log";
        }
        EclipseMod.LOGGER.info("PristineSnapshots: restore of '{}' staged — applies at the next server start", name);
        return "Restore of '" + name + "' staged — RESTART THE SERVER to apply "
                + "(region files are locked while the server runs)";
    }

    /** Consumes the marker before any level opens: wipe the live dirs, copy the snapshot back. */
    @SubscribeEvent
    static void onServerAboutToStart(ServerAboutToStartEvent event) {
        Path worldRoot = event.getServer().getWorldPath(LevelResource.ROOT);
        Path marker = snapshotsDir(worldRoot).resolve(MARKER_FILE);
        if (!Files.exists(marker)) {
            return;
        }
        String name;
        try {
            name = Files.readString(marker, StandardCharsets.UTF_8).trim();
        } catch (IOException e) {
            EclipseMod.LOGGER.error("PristineSnapshots: unreadable restore marker {} — ignoring", marker, e);
            return;
        }
        Path snapshot = snapshotsDir(worldRoot).resolve(name);
        try {
            Files.deleteIfExists(marker);
            if (!isValidName(name) || !Files.isDirectory(snapshot)) {
                EclipseMod.LOGGER.error("PristineSnapshots: staged snapshot '{}' is missing — restore skipped", name);
                return;
            }
            int restored = 0;
            for (String dir : COPY_DIRS) {
                Path source = snapshot.resolve(dir);
                Path target = worldRoot.resolve(dir);
                if (!Files.isDirectory(source)) {
                    continue;
                }
                deleteRecursively(target);
                copyRecursively(source, target);
                restored++;
            }
            EclipseMod.LOGGER.info("PristineSnapshots: restored pristine snapshot '{}' ({} region dirs) "
                    + "before level load", name, restored);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("PristineSnapshots: restore of '{}' FAILED — the world may be "
                    + "partially restored, check {} manually", name, snapshot, e);
        }
    }

    // --- fs helpers ---

    private static void copyRecursively(Path source, Path target) throws IOException {
        Files.walkFileTree(source, new SimpleFileVisitor<>() {
            @Override
            public FileVisitResult preVisitDirectory(Path dir, BasicFileAttributes attrs) throws IOException {
                Files.createDirectories(target.resolve(source.relativize(dir)));
                return FileVisitResult.CONTINUE;
            }

            @Override
            public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
                Files.copy(file, target.resolve(source.relativize(file)),
                        StandardCopyOption.REPLACE_EXISTING);
                return FileVisitResult.CONTINUE;
            }
        });
    }

    private static void deleteRecursively(Path target) throws IOException {
        if (!Files.exists(target)) {
            return;
        }
        Files.walkFileTree(target, new SimpleFileVisitor<>() {
            @Override
            public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
                Files.delete(file);
                return FileVisitResult.CONTINUE;
            }

            @Override
            public FileVisitResult postVisitDirectory(Path dir, IOException exc) throws IOException {
                Files.delete(dir);
                return FileVisitResult.CONTINUE;
            }
        });
    }
}
