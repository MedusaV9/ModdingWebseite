package dev.projecteclipse.eclipse.worldgen;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ThreadLocalRandom;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.config.ReloadHooks;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.worldgen.fog.FogStormSites;
import dev.projecteclipse.eclipse.worldgen.fog.StormLootData;
import dev.projecteclipse.eclipse.worldgen.ore.OreConfig;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.storage.LevelResource;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;

/**
 * Per-save freeze of all terrain-shaping worldgen parameters (D9). A plain JSON file at
 * {@code world/&lt;save&gt;/eclipse/worldgen.json} is written on first boot from global
 * {@code config/eclipse/*} templates and read on every {@link ServerAboutToStartEvent}
 * before dimensions deserialize. A volatile {@link Context} is published for worldgen
 * worker threads until {@link ServerStoppedEvent}.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class FrozenParams {
    /** Legacy overworld radii for pre-overhaul saves (SCAR_RADII + faint stage-0 weld). */
    public static final int[] LEGACY_OVERWORLD_RADII = {96, 225, 300, 360, 420, 480};
    /** Legacy nether radii for pre-overhaul saves. */
    public static final int[] LEGACY_NETHER_RADII = {0, 80, 120, 160};

    /** D8-rebalanced defaults for fresh saves (index 0 = stage-0 main disc / nether empty). */
    public static final int[] DEFAULT_OVERWORLD_RADII = {96, 150, 210, 280, 360, 440};
    public static final int[] DEFAULT_NETHER_RADII = {0, 64, 110, 150};

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final String WORLDGEN_FILE = "worldgen.json";

    private static volatile Context current;
    private static volatile Path saveEclipseDir;
    private static volatile MinecraftServer activeServer;

    static {
        ReloadHooks.register("frozen-worldgen", FrozenParams::restoreFrozenReloadState);
    }

    private FrozenParams() {}

    /** Active per-save context; {@code null} between server sessions. */
    public static Context current() {
        return current;
    }

    /** Frozen map seed for {@link DiscMapData} noise and the vanilla pipeline fixed seed. */
    public static long mapSeed() {
        Context ctx = current;
        return ctx != null ? ctx.mapSeed : DiscMapData.ECLIPSE_SEED;
    }

    /** Cached per-save stage radii (index = stage). Hot path — returns the live array, do not mutate. */
    public static int[] stageRadii(DiscProfile profile) {
        Context ctx = current;
        if (ctx == null) {
            return profile == DiscProfile.NETHER ? DEFAULT_NETHER_RADII : DEFAULT_OVERWORLD_RADII;
        }
        return profile == DiscProfile.NETHER ? ctx.netherRadii : ctx.overworldRadii;
    }

    /**
     * Annulus band index for {@code r} on the given profile's frozen radii table. Band {@code i}
     * is the region where {@code radii[i-1] < r <= radii[i]} (with {@code radii[-1] = 0}).
     */
    public static int annulusBand(DiscProfile profile, double r) {
        int[] radii = stageRadii(profile);
        if (radii.length == 0) {
            return 0;
        }
        for (int i = 0; i < radii.length; i++) {
            if (r <= radii[i]) {
                return i;
            }
        }
        return radii.length - 1;
    }

    /** Overworld-biased band lookup (§3.10 seam). Prefer {@link #annulusBand(DiscProfile, double)}. */
    public static int annulusBand(double r) {
        return annulusBand(DiscProfile.OVERWORLD, r);
    }

    /** Volatile mirror of {@code EclipseWorldgenState.breachOpen} for worker threads. */
    public static boolean breachOpen() {
        Context ctx = current;
        return ctx != null && ctx.breachOpen;
    }

    /** Volatile mirror of {@code EclipseWorldgenState.endDiscMaterialized} for worker threads. */
    public static boolean endDiscMaterialized() {
        Context ctx = current;
        return ctx != null && ctx.endDiscMaterialized;
    }

    /**
     * Publishes materialization flags into the worker-thread mirror. W1.7/W1.8 call this when
     * flipping {@code EclipseWorldgenState} flags (until W1.5 wires automatic sync).
     */
    public static void mirrorMaterializationFlags(boolean breachOpen, boolean endDiscMaterialized) {
        Context ctx = current;
        if (ctx != null) {
            ctx.breachOpen = breachOpen;
            ctx.endDiscMaterialized = endDiscMaterialized;
        }
    }

    /** Save-local eclipse directory ({@code null} when no server session is active). */
    public static Path saveEclipseDir() {
        return saveEclipseDir;
    }

    /**
     * Ordinary config reloads may refresh global templates, but an active save keeps its
     * frozen terrain parameters. Explicit {@link #refreeze} is the only path that replaces
     * this context from global config.
     */
    private static void restoreFrozenReloadState() {
        Context ctx = current;
        Path saveDir = saveEclipseDir;
        if (ctx == null || saveDir == null) {
            OreConfig.reload(FMLPaths.CONFIGDIR.get().resolve("eclipse"));
            return;
        }
        StageRadii.installFromFreeze(ctx.overworldRadii, ctx.netherRadii);
        OreConfig.reload(saveDir);
        assertInstalledRadii(DiscProfile.OVERWORLD, ctx.overworldRadii);
        assertInstalledRadii(DiscProfile.NETHER, ctx.netherRadii);
        EclipseMod.LOGGER.info("FrozenParams: ordinary reload retained this save's frozen stage radii");
    }

    private static void assertInstalledRadii(DiscProfile profile, int[] expected) {
        if (StageRadii.maxStage(profile) != expected.length - 1) {
            throw new IllegalStateException("Frozen " + profile + " radius table was not retained");
        }
        for (int stage = 0; stage < expected.length; stage++) {
            if (StageRadii.radius(profile, stage) != expected[stage]) {
                throw new IllegalStateException("Frozen " + profile + " radius diverged at stage " + stage);
            }
        }
    }

    /**
     * Re-copies a section from global config (P5 seam — requires an active server session).
     * Sections: {@code map|stages|ores|end|fogstorms|all}.
     */
    public static synchronized String refreeze(String section) {
        MinecraftServer server = activeServer;
        if (server == null) {
            return "ERROR: no active server session";
        }
        return refreeze(server, section);
    }

    /**
     * Re-copies a section from global {@code config/eclipse/*} into the save freeze file.
     * Sections: {@code map|stages|ores|end|fogstorms|all} (P5 {@code /eclipse-worldgen refreeze}).
     */
    public static synchronized String refreeze(MinecraftServer server, String section) {
        Path worldRoot = server.getWorldPath(LevelResource.ROOT);
        Path eclipseDir = worldRoot.resolve("eclipse");
        Path freezeFile = eclipseDir.resolve(WORLDGEN_FILE);
        if (!Files.isRegularFile(freezeFile)) {
            return "ERROR: no " + WORLDGEN_FILE + " — boot the save once first";
        }
        String key = section.toLowerCase(Locale.ROOT);
        JsonObject frozen;
        try {
            frozen = JsonParser.parseString(Files.readString(freezeFile, StandardCharsets.UTF_8)).getAsJsonObject();
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("FrozenParams: failed to read {}", freezeFile, e);
            return "ERROR: unreadable " + WORLDGEN_FILE;
        }
        Path globalDir = FMLPaths.CONFIGDIR.get().resolve("eclipse");
        if ("stages".equals(key) || "all".equals(key)) {
            // Refreeze is explicitly a disk-template refresh. Re-read stages.json first
            // so an operator does not have to run a separate global reload command.
            EclipseConfig.reload();
        }
        switch (key) {
            case "map" -> copyMapSection(globalDir, eclipseDir, frozen);
            case "stages" -> copyStageRadiiSection(frozen);
            case "ores" -> copyJsonFileSection(globalDir, frozen, "ores", "ores.json",
                    OreConfig::defaultRootJson);
            case "end" -> copyJsonFileSection(globalDir, frozen, "end", "end.json");
            case "fogstorms" -> copyJsonFileSection(globalDir, frozen, "fogstorms", "fogstorms.json",
                    () -> defaultFogstormsJson(frozen.getAsJsonObject("discMap")));
            case "all" -> {
                copyMapSection(globalDir, eclipseDir, frozen);
                copyStageRadiiSection(frozen);
                copyJsonFileSection(globalDir, frozen, "ores", "ores.json", OreConfig::defaultRootJson);
                copyJsonFileSection(globalDir, frozen, "end", "end.json");
                copyJsonFileSection(globalDir, frozen, "fogstorms", "fogstorms.json",
                        () -> defaultFogstormsJson(frozen.getAsJsonObject("discMap")));
            }
            default -> {
                return "ERROR: unknown refreeze section '" + section + "' (map|stages|ores|end|fogstorms|all)";
            }
        }
        try {
            Files.writeString(freezeFile, GSON.toJson(frozen), StandardCharsets.UTF_8);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("FrozenParams: failed to write {}", freezeFile, e);
            return "ERROR: failed to write " + WORLDGEN_FILE;
        }
        activateFromJson(server, eclipseDir, frozen, false);
        return "Refroze section '" + section + "' from global config into " + freezeFile;
    }

    @SubscribeEvent
    public static void onServerAboutToStart(ServerAboutToStartEvent event) {
        MinecraftServer server = event.getServer();
        Path worldRoot = server.getWorldPath(LevelResource.ROOT);
        Path eclipseDir = worldRoot.resolve("eclipse");
        Path freezeFile = eclipseDir.resolve(WORLDGEN_FILE);
        try {
            Files.createDirectories(eclipseDir);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("FrozenParams: failed to create {}", eclipseDir, e);
        }

        JsonObject frozen;
        boolean writeFreeze = false;
        if (!Files.isRegularFile(freezeFile)) {
            frozen = createInitialFreeze(server, eclipseDir);
            writeFreeze = true;
        } else {
            try {
                frozen = JsonParser.parseString(Files.readString(freezeFile, StandardCharsets.UTF_8)).getAsJsonObject();
            } catch (IOException | RuntimeException e) {
                EclipseMod.LOGGER.error("FrozenParams: corrupt {}; rebuilding from global templates", freezeFile, e);
                frozen = createInitialFreeze(server, eclipseDir);
                writeFreeze = true;
            }
        }
        if (writeFreeze) {
            try {
                Files.writeString(freezeFile, GSON.toJson(frozen), StandardCharsets.UTF_8);
                EclipseMod.LOGGER.info("FrozenParams: wrote per-save freeze at {}", freezeFile);
            } catch (IOException e) {
                EclipseMod.LOGGER.error("FrozenParams: failed to write initial/rebuilt {}", freezeFile, e);
            }
        }

        saveEclipseDir = eclipseDir;
        activeServer = server;
        activateFromJson(server, eclipseDir, frozen, true);
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        current = null;
        saveEclipseDir = null;
        activeServer = null;
        DiscMapData.clearInstance();
        StageRadii.resetDefaults();
        StormLootData.clearSession();
    }

    private static void activateFromJson(MinecraftServer server, Path eclipseDir, JsonObject frozen, boolean firstBoot) {
        long mapSeed = frozen.has("mapSeed") ? frozen.get("mapSeed").getAsLong() : DiscMapData.ECLIPSE_SEED;
        int[] overworldRadii = parseRadii(frozen, "overworld", server, DEFAULT_OVERWORLD_RADII, LEGACY_OVERWORLD_RADII);
        int[] netherRadii = parseRadii(frozen, "nether", server, DEFAULT_NETHER_RADII, LEGACY_NETHER_RADII);

        Context ctx = new Context(mapSeed, overworldRadii, netherRadii);
        current = ctx;

        StageRadii.installFromFreeze(overworldRadii, netherRadii);

        if (frozen.has("discMap")) {
            DiscMapData.install(DiscMapData.fromJsonRoot(frozen.getAsJsonObject("discMap")));
        } else {
            DiscMapData.reload();
        }

        writeExtractedJson(eclipseDir, frozen, "ores", "ores.json");
        writeExtractedJson(eclipseDir, frozen, "fogstorms", "fogstorms.json");
        writeExtractedJson(eclipseDir, frozen, "end", "end.json");

        OreConfig.reload(eclipseDir);
        StormLootData.reload(eclipseDir);
        FogStormSites.reloadFromSave();

        if (firstBoot) {
            EclipseMod.LOGGER.info("FrozenParams: mapSeed=0x{}, overworld radii {}, nether radii {}",
                    Long.toHexString(mapSeed), java.util.Arrays.toString(overworldRadii),
                    java.util.Arrays.toString(netherRadii));
        }
    }

    private static int[] parseRadii(JsonObject frozen, String dimension, MinecraftServer server,
            int[] freshDefault, int[] legacyDefault) {
        if (!frozen.has("stageRadii")) {
            return useLegacyIfNeeded(server, freshDefault, legacyDefault);
        }
        JsonObject radiiRoot = frozen.getAsJsonObject("stageRadii");
        if (!radiiRoot.has(dimension)) {
            return useLegacyIfNeeded(server, freshDefault, legacyDefault);
        }
        JsonArray array = radiiRoot.getAsJsonArray(dimension);
        int[] radii = new int[array.size()];
        for (int i = 0; i < array.size(); i++) {
            radii[i] = array.get(i).getAsInt();
        }
        return radii;
    }

    private static int[] useLegacyIfNeeded(MinecraftServer server, int[] freshDefault, int[] legacyDefault) {
        EclipseWorldState state = EclipseWorldState.get(server);
        if (state.getWorldStage(DiscProfile.OVERWORLD) > 0 || state.getWorldStage(DiscProfile.NETHER) > 0) {
            return legacyDefault.clone();
        }
        return freshDefault.clone();
    }

    private static JsonObject createInitialFreeze(MinecraftServer server, Path eclipseDir) {
        EclipseConfig.reload();
        Path globalDir = FMLPaths.CONFIGDIR.get().resolve("eclipse");
        OreConfig.reload(globalDir);

        final long mapSeed = EclipseConfig.general().randomizeMapSeed()
                ? ThreadLocalRandom.current().nextLong()
                : DiscMapData.ECLIPSE_SEED;

        JsonObject root = new JsonObject();
        root.addProperty("_comment", "Per-save frozen worldgen params (D9). Global config/eclipse/* "
                + "is the template for NEW saves only; edit this file or use /eclipse-worldgen refreeze "
                + "to re-copy sections from global config.");
        root.addProperty("mapSeed", mapSeed);
        root.add("stageRadii", buildStageRadiiJson());

        JsonObject discMap = readJsonFileOrDefault(globalDir.resolve("disc_map.json"), () -> {
            DiscMapData map = DiscMapData.reloadForSnapshot();
            return DiscMapData.toJsonRoot(map);
        });
        root.add("discMap", discMap);
        copyHeightmapSnapshot(globalDir, eclipseDir);

        root.add("ores", readJsonFileOrDefault(globalDir.resolve("ores.json"), OreConfig::defaultRootJson));
        root.add("end", readJsonFileOrDefault(globalDir.resolve("end.json"), FrozenParams::defaultEndJson));
        root.add("fogstorms", readJsonFileOrDefault(globalDir.resolve("fogstorms.json"),
                () -> defaultFogstormsJson(discMap)));

        return root;
    }

    private static JsonObject buildStageRadiiJson() {
        JsonObject radii = new JsonObject();
        radii.add("overworld", intArray(configuredRadii("overworld", DEFAULT_OVERWORLD_RADII)));
        radii.add("nether", intArray(configuredRadii("nether", DEFAULT_NETHER_RADII)));
        return radii;
    }

    /**
     * Builds the complete stage-indexed radius array from the currently loaded global
     * {@code stages.json}. Stage zero is implicit in that file, so it comes from the
     * profile's built-in geometry default; a sparse stage inherits the preceding radius,
     * exactly matching {@code EclipseConfig.applyStageRadii()}.
     */
    private static int[] configuredRadii(String dimension, int[] fallback) {
        List<EclipseConfig.StageEntry> entries = EclipseConfig.stages(dimension);
        int maxStage = entries.stream().mapToInt(EclipseConfig.StageEntry::stage)
                .max().orElse(0);
        if (maxStage <= 0) {
            return new int[] {fallback[0]};
        }
        int[] radii = new int[maxStage + 1];
        radii[0] = fallback[0];
        int previous = radii[0];
        for (int stage = 1; stage <= maxStage; stage++) {
            for (EclipseConfig.StageEntry entry : entries) {
                if (entry.stage() == stage) {
                    previous = entry.radius();
                    break;
                }
            }
            radii[stage] = previous;
        }
        return radii;
    }

    private static JsonArray intArray(int[] values) {
        JsonArray array = new JsonArray(values.length);
        for (int value : values) {
            array.add(value);
        }
        return array;
    }

    private static void copyMapSection(Path globalDir, Path eclipseDir, JsonObject frozen) {
        JsonObject discMap = readJsonFileOrDefault(globalDir.resolve("disc_map.json"), () -> {
            DiscMapData map = DiscMapData.reloadForSnapshot();
            return DiscMapData.toJsonRoot(map);
        });
        frozen.add("discMap", discMap);
        copyHeightmapSnapshot(globalDir, eclipseDir);
    }

    private static void copyStageRadiiSection(JsonObject frozen) {
        frozen.add("stageRadii", buildStageRadiiJson());
    }

    private static void copyJsonFileSection(Path globalDir, JsonObject frozen, String key, String fileName) {
        copyJsonFileSection(globalDir, frozen, key, fileName, JsonObject::new);
    }

    private static void copyJsonFileSection(Path globalDir, JsonObject frozen, String key, String fileName,
            java.util.function.Supplier<JsonObject> fallback) {
        frozen.add(key, readJsonFileOrDefault(globalDir.resolve(fileName), fallback));
    }

    /**
     * Copies the optional painted heightmap byte-for-byte into the save-local freeze.
     * Removing the global override before an explicit map refreeze removes the frozen
     * override as well, so the JSON and PNG snapshots always describe one map revision.
     */
    private static void copyHeightmapSnapshot(Path globalDir, Path eclipseDir) {
        Path source = globalDir.resolve("disc_heightmap.png");
        Path target = eclipseDir.resolve("disc_heightmap.png");
        try {
            if (Files.isRegularFile(source)) {
                Files.copy(source, target, StandardCopyOption.REPLACE_EXISTING);
            } else {
                Files.deleteIfExists(target);
            }
        } catch (IOException e) {
            EclipseMod.LOGGER.warn("FrozenParams: failed to snapshot heightmap {} -> {}", source, target, e);
        }
    }

    private static JsonObject readJsonFileOrDefault(Path file, java.util.function.Supplier<JsonObject> fallback) {
        if (Files.isRegularFile(file)) {
            try {
                return JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)).getAsJsonObject();
            } catch (IOException | RuntimeException e) {
                EclipseMod.LOGGER.warn("FrozenParams: failed to read {}; using built-in default", file, e);
            }
        }
        return fallback.get();
    }

    private static void writeExtractedJson(Path eclipseDir, JsonObject frozen, String key, String fileName) {
        if (!frozen.has(key)) {
            return;
        }
        Path target = eclipseDir.resolve(fileName);
        try {
            Files.writeString(target, GSON.toJson(frozen.get(key)), StandardCharsets.UTF_8);
        } catch (IOException e) {
            EclipseMod.LOGGER.warn("FrozenParams: failed to extract {} to {}", key, target, e);
        }
    }

    /** Minimal {@code end.json} defaults until W1.8's {@code EndConfig} owns the file. */
    static JsonObject defaultEndJson() {
        JsonObject end = new JsonObject();
        end.addProperty("trigger", "day:9");
        end.addProperty("radius", DiscProfile.END_DISC_RADIUS);
        end.addProperty("surfaceY", DiscProfile.END_DISC_SURFACE_Y);
        end.addProperty("simpleDragonAi", true);
        end.addProperty("allowElytra", false);
        end.addProperty("crystalRespawn", false);
        return end;
    }

    /**
     * Default fog-storm sites, anchored to the two authored fog landmarks in the frozen
     * disc map. The landmarks are the sole position authority, so structure protection,
     * map editing and storm placement cannot drift apart.
     */
    static JsonObject defaultFogstormsJson(JsonObject discMap) {
        JsonObject root = new JsonObject();
        root.addProperty("_comment", "Fog storm sites (frozen per save). Sites materialize at overworld "
                + "stage 3. mobSet entries are consumed by P6 storm spawners.");
        JsonArray sites = new JsonArray();

        for (int i = 1; i <= 2; i++) {
            String id = "eclipse:fog_storm_" + i;
            JsonObject landmark = findLandmark(discMap, id);
            if (landmark == null) {
                EclipseMod.LOGGER.warn("FrozenParams: authored fog landmark {} is absent; no default site emitted",
                        id);
                continue;
            }
            JsonObject site = new JsonObject();
            site.addProperty("id", id);
            site.addProperty("x", landmark.get("x").getAsInt());
            site.addProperty("z", landmark.get("z").getAsInt());
            site.addProperty("radius", 28);
            site.addProperty("stage", landmark.has("stage") ? landmark.get("stage").getAsInt() : 3);
            site.add("mobSet", new JsonArray());
            sites.add(site);
        }
        root.add("sites", sites);
        return root;
    }

    private static JsonObject findLandmark(JsonObject discMap, String id) {
        if (discMap == null || !discMap.has("overworld")) {
            return null;
        }
        JsonObject overworld = discMap.getAsJsonObject("overworld");
        if (!overworld.has("landmarks")) {
            return null;
        }
        for (JsonElement element : overworld.getAsJsonArray("landmarks")) {
            JsonObject landmark = element.getAsJsonObject();
            if (landmark.has("id") && id.equals(landmark.get("id").getAsString())) {
                return landmark;
            }
        }
        return null;
    }

    /** Mutable per-session context (volatile fields for worker-thread reads). */
    public static final class Context {
        private final long mapSeed;
        private final int[] overworldRadii;
        private final int[] netherRadii;
        volatile boolean breachOpen;
        volatile boolean endDiscMaterialized;

        Context(long mapSeed, int[] overworldRadii, int[] netherRadii) {
            this.mapSeed = mapSeed;
            this.overworldRadii = overworldRadii;
            this.netherRadii = netherRadii;
        }

        public long mapSeed() {
            return this.mapSeed;
        }

        public int[] overworldRadii() {
            return this.overworldRadii;
        }

        public int[] netherRadii() {
            return this.netherRadii;
        }
    }
}
