package dev.projecteclipse.eclipse.devtools;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.NbtAccounter;
import net.minecraft.nbt.NbtIo;
import net.minecraft.world.level.storage.LevelResource;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;

/**
 * Per-save live-terrain backups for destructive stage operations. Every backup is a
 * StageIO-format compressed NBT plus a JSON audit sidecar under
 * {@code <world>/eclipse/stages/backups/}. Both files use temp-write + rename.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class StageBackups {
    public static final int DEFAULT_RETENTION = 10;

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final DateTimeFormatter FILE_TIME =
            DateTimeFormatter.ofPattern("uuuuMMdd'T'HHmmss.SSS'Z'", Locale.ROOT).withZone(ZoneOffset.UTC);
    private static final AtomicBoolean LISTENER_REGISTERED = new AtomicBoolean();

    private StageBackups() {}

    public record BackupInfo(String id, Path file, DiscProfile profile, int stage,
            int innerRadius, int outerRadius, long savedAtEpochMillis, long sizeBytes,
            String source, String operator, String label, long gameDay) {}

    public record BackupResult(boolean success, BackupInfo info, String message) {
        static BackupResult failure(String message) {
            return new BackupResult(false, null, message);
        }
    }

    /** Installs the pre-growth hook once for the lifetime of the JVM. */
    @SubscribeEvent
    static void onServerAboutToStart(ServerAboutToStartEvent event) {
        if (LISTENER_REGISTERED.compareAndSet(false, true)) {
            WorldStageService.addGrowthStartListener(StageBackups::beforeGrowth);
            EclipseMod.LOGGER.info("StageBackups registered as a world-stage growth listener");
        }
    }

    private static void beforeGrowth(ServerLevel level, DiscProfile profile, int fromStage,
            int toStage, boolean animate) {
        int[] band = StageIO.growthBand(profile, fromStage, toStage);
        BackupResult result = create(level, profile, toStage, band[0], band[1],
                animate ? "growth-animated" : "growth-instant", "system", "");
        if (!result.success()) {
            // WorldStageService invokes listeners immediately before RingGrowthService.start.
            // Failing closed here preserves the live blocks even though the stage number was
            // already committed by the caller.
            throw new IllegalStateException("Refusing stage growth without a live backup: " + result.message());
        }
    }

    /** Called by StageIO after validating the source file and before exposing an apply job. */
    public static BackupResult beforeDestructiveLoad(ServerLevel level, DiscProfile profile,
            int stage, int innerRadius, int outerRadius, String source, String operator) {
        return create(level, profile, stage, innerRadius, outerRadius, source, operator, "");
    }

    /** Captures the current stage annulus with an optional operator label. */
    public static BackupResult backupNow(ServerLevel level, DiscProfile profile, String label,
            String source, String operator) {
        int stage = EclipseWorldState.get(level.getServer()).getWorldStage(profile);
        int[] band = stage <= 0
                ? StageIO.growthBand(profile, 0, 0)
                : StageIO.growthBand(profile, stage - 1, stage);
        return create(level, profile, stage, band[0], band[1], source, operator, label);
    }

    private static BackupResult create(ServerLevel level, DiscProfile profile, int stage,
            int innerRadius, int outerRadius, String source, String operator, String label) {
        String safeLabel = sanitize(label);
        String id = FILE_TIME.format(Instant.now()) + "_" + profile.name() + "_" + stage
                + (safeLabel.isEmpty() ? "" : "_" + safeLabel);
        Path file = backupsDir(level.getServer()).resolve(id + ".bin");
        try {
            StageIO.SnapshotCapture capture = StageIO.captureCurrent(
                    level, profile, stage, innerRadius, outerRadius, file);
            BackupInfo info = new BackupInfo(id, file, profile, stage, innerRadius, outerRadius,
                    capture.savedAtEpochMillis(), capture.sizeBytes(), source, operator, safeLabel,
                    EclipseWorldState.get(level.getServer()).getDay());
            try {
                writeMetadataAtomic(info);
            } catch (IOException e) {
                Files.deleteIfExists(file);
                throw e;
            }
            int removed = prune(level.getServer(), profile, retention(level.getServer()));
            EclipseMod.LOGGER.info(
                    "Stage backup {} captured before {}: {} stage {}, r {}..{}, {} chunks, {} KB{}",
                    id, source, profile.name(), stage, innerRadius, outerRadius, capture.chunks(),
                    capture.sizeBytes() / 1024, removed > 0 ? ", pruned " + removed : "");
            return new BackupResult(true, info, "ok");
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("Stage backup failed for {} stage {} before {}",
                    profile.name(), stage, source, e);
            return BackupResult.failure(e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage());
        }
    }

    /** Restores the newest backup for this profile; the restore itself first creates a new backup. */
    public static String restoreLatest(ServerLevel level, DiscProfile profile, String source, String operator) {
        List<BackupInfo> backups = list(level.getServer(), profile);
        if (backups.isEmpty()) {
            return "ERROR: no live backup exists for " + profile.name()
                    + " — see /dev stage list";
        }
        return restore(level, profile, backups.get(0).id(), source, operator);
    }

    /** Restores an exact backup id after containment and profile validation. */
    public static String restore(ServerLevel level, DiscProfile profile, String id,
            String source, String operator) {
        Optional<BackupInfo> found = find(level.getServer(), id);
        if (found.isEmpty()) {
            return "ERROR: unknown stage backup '" + id + "' — see /dev stage list";
        }
        BackupInfo info = found.get();
        if (info.profile() != profile) {
            return "ERROR: backup '" + id + "' belongs to " + info.profile().name()
                    + ", not the current " + profile.name() + " dimension";
        }
        return StageIO.loadSnapshotFile(level, profile, info.file(), source, operator);
    }

    public static Path backupsDir(MinecraftServer server) {
        return StageIO.stagesDir(server).resolve("backups");
    }

    /** Newest first; malformed sidecars/files are warned and omitted. */
    public static List<BackupInfo> list(MinecraftServer server) {
        Path dir = backupsDir(server);
        if (!Files.isDirectory(dir)) {
            return List.of();
        }
        List<BackupInfo> result = new ArrayList<>();
        try (var stream = Files.list(dir)) {
            stream.filter(path -> path.getFileName().toString().endsWith(".bin"))
                    .forEach(path -> readInfo(path).ifPresent(result::add));
        } catch (IOException e) {
            EclipseMod.LOGGER.warn("Could not list stage backups in {}", dir, e);
        }
        result.sort(Comparator.comparingLong(BackupInfo::savedAtEpochMillis).reversed());
        return List.copyOf(result);
    }

    public static List<BackupInfo> list(MinecraftServer server, DiscProfile profile) {
        return list(server).stream().filter(info -> info.profile() == profile).toList();
    }

    public static Optional<BackupInfo> find(MinecraftServer server, String id) {
        if (id == null || !id.matches("[A-Za-z0-9_.-]+")) {
            return Optional.empty();
        }
        Path root = backupsDir(server).normalize();
        Path file = root.resolve(id + ".bin").normalize();
        if (file.getParent().equals(root) && Files.isRegularFile(file)) {
            return readInfo(file);
        }
        // `/dev stage save <name>` remains ergonomic even though on-disk ids are timestamped:
        // a label resolves to its newest matching backup.
        return list(server).stream()
                .filter(info -> info.label().equalsIgnoreCase(id))
                .findFirst();
    }

    /** Keeps the newest {@code keep} backups for one profile and returns the files removed. */
    public static int prune(MinecraftServer server, DiscProfile profile, int keep) {
        List<BackupInfo> backups = list(server, profile);
        int removed = 0;
        for (int index = Math.max(0, keep); index < backups.size(); index++) {
            BackupInfo info = backups.get(index);
            try {
                if (Files.deleteIfExists(info.file())) {
                    removed++;
                }
                Files.deleteIfExists(sidecar(info.file()));
            } catch (IOException e) {
                EclipseMod.LOGGER.warn("Could not prune stage backup {}", info.id(), e);
            }
        }
        return removed;
    }

    /** Config key is optional until P1 adds it to EclipseConfig.General; fallback stays 10. */
    public static int retention(MinecraftServer server) {
        Path worldOverride = server.getWorldPath(LevelResource.ROOT)
                .resolve("eclipse").resolve("config").resolve("general.json");
        int value = readRetention(worldOverride);
        if (value < 0) {
            value = readRetention(FMLPaths.CONFIGDIR.get().resolve("eclipse").resolve("general.json"));
        }
        return value < 0 ? DEFAULT_RETENTION : Math.max(1, value);
    }

    private static int readRetention(Path file) {
        if (!Files.isRegularFile(file)) {
            return -1;
        }
        try {
            JsonObject root = JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)).getAsJsonObject();
            return root.has("stageBackupRetention") ? root.get("stageBackupRetention").getAsInt() : -1;
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.warn("Ignoring invalid stageBackupRetention in {}", file, e);
            return -1;
        }
    }

    private static Optional<BackupInfo> readInfo(Path file) {
        Path sidecar = sidecar(file);
        if (!Files.isRegularFile(sidecar)) {
            // A crash may occur after the atomic .bin rename but before its sidecar rename.
            // The terrain backup itself remains complete and restorable; recover core
            // metadata from its StageIO root instead of hiding or deleting it.
            try {
                CompoundTag root = NbtIo.readCompressed(file, NbtAccounter.unlimitedHeap());
                DiscProfile profile = "nether".equals(root.getString("profile"))
                        ? DiscProfile.NETHER : DiscProfile.OVERWORLD;
                return Optional.of(new BackupInfo(
                        stripExtension(file.getFileName().toString()), file, profile,
                        root.getInt("stage"), root.getInt("innerRadius"), root.getInt("outerRadius"),
                        root.getLong("savedAtEpochMillis"), Files.size(file),
                        "recovered-no-sidecar", "", "", -1L));
            } catch (IOException | RuntimeException e) {
                EclipseMod.LOGGER.warn("Ignoring unreadable stage backup without sidecar: {}", file, e);
                return Optional.empty();
            }
        }
        try {
            JsonObject json = JsonParser.parseString(Files.readString(sidecar, StandardCharsets.UTF_8))
                    .getAsJsonObject();
            String profileName = json.get("profile").getAsString();
            DiscProfile profile = "nether".equals(profileName) ? DiscProfile.NETHER : DiscProfile.OVERWORLD;
            return Optional.of(new BackupInfo(
                    stripExtension(file.getFileName().toString()), file, profile,
                    json.get("stage").getAsInt(), json.get("innerRadius").getAsInt(),
                    json.get("outerRadius").getAsInt(), json.get("savedAtEpochMillis").getAsLong(),
                    Files.size(file), stringOr(json, "source"), stringOr(json, "operator"),
                    stringOr(json, "label"), json.has("gameDay") ? json.get("gameDay").getAsLong() : -1L));
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.warn("Ignoring unreadable stage backup metadata {}", sidecar, e);
            return Optional.empty();
        }
    }

    private static String stringOr(JsonObject json, String key) {
        return json.has(key) ? json.get(key).getAsString() : "";
    }

    private static void writeMetadataAtomic(BackupInfo info) throws IOException {
        JsonObject json = new JsonObject();
        json.addProperty("formatVersion", 1);
        json.addProperty("id", info.id());
        json.addProperty("profile", info.profile().name());
        json.addProperty("stage", info.stage());
        json.addProperty("innerRadius", info.innerRadius());
        json.addProperty("outerRadius", info.outerRadius());
        json.addProperty("savedAtEpochMillis", info.savedAtEpochMillis());
        json.addProperty("source", info.source());
        json.addProperty("operator", info.operator());
        json.addProperty("gameDay", info.gameDay());
        if (!info.label().isEmpty()) {
            json.addProperty("label", info.label());
        }
        writeStringAtomic(sidecar(info.file()), GSON.toJson(json));
    }

    private static void writeStringAtomic(Path file, String value) throws IOException {
        Files.createDirectories(file.getParent());
        Path temporary = file.resolveSibling("." + file.getFileName() + "." + UUID.randomUUID() + ".tmp");
        try {
            Files.writeString(temporary, value, StandardCharsets.UTF_8);
            try {
                Files.move(temporary, file, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
            } catch (AtomicMoveNotSupportedException e) {
                Files.move(temporary, file, StandardCopyOption.REPLACE_EXISTING);
            }
        } finally {
            Files.deleteIfExists(temporary);
        }
    }

    private static Path sidecar(Path file) {
        return file.resolveSibling(stripExtension(file.getFileName().toString()) + ".json");
    }

    private static String stripExtension(String name) {
        int dot = name.lastIndexOf('.');
        return dot < 0 ? name : name.substring(0, dot);
    }

    private static String sanitize(String label) {
        if (label == null || label.isBlank()) {
            return "";
        }
        String cleaned = label.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9_-]+", "-")
                .replaceAll("^-+|-+$", "");
        return cleaned.length() <= 32 ? cleaned : cleaned.substring(0, 32);
    }
}
