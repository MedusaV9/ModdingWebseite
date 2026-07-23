package dev.projecteclipse.eclipse.worldgen.structure.dungeon;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.CopyOnWriteArrayList;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.ReloadHooks;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.entity.SpawnerBlockEntity;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;

/**
 * Config-driven spawner mobs of the custom dungeons ({@code config/eclipse/dungeons.json},
 * live-reloadable — the P6 seam of design D7). P6 drops {@code eclipse:*} mob ids into the
 * per-dungeon {@code "spawners"} arrays once its mobs exist; until then (or when an id is
 * missing/unloadable) the vanilla fallbacks below keep every spawner functional. Unknown
 * ids are skipped with one warning each — a typo can never break dungeon placement.
 *
 * <p>File schema (auto-written on first use):</p>
 * <pre>{@code
 * { "structure_phase": { "auto_delay_ticks": 100, "place_interval_ticks": 20 },
 *   "collapsed_vault": { "spawners": ["minecraft:zombie", "minecraft:skeleton"] },
 *   "umbral_warrens":  { "spawners": ["minecraft:cave_spider", "minecraft:zombie"] } }
 * }</pre>
 *
 * <p>{@code structure_phase} carries the two-phase pacing knobs of
 * {@code StructurePendingRegistry} (auto-place delay after the PENDING broadcast, and the
 * minimum tick spacing between two site placements). This file also registers a
 * {@link ReloadHooks} hook, so {@code /eclipse reload} re-reads mob ids AND re-applies
 * them to every spawner block placed this session (P6's iteration loop: edit json →
 * reload → spawners switch mobs in place).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DungeonSpawners {
    /** Dungeon id of the Collapsed Vault (loot + spawner config key). */
    public static final String COLLAPSED_VAULT = "collapsed_vault";
    /** Dungeon id of the Umbral Warrens (loot + spawner config key). */
    public static final String UMBRAL_WARRENS = "umbral_warrens";
    /** Dungeon id of the vanilla-style monster-room clusters ({@code UndergroundSites}). */
    public static final String MONSTER_ROOM = "monster_room";

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();

    /** Vanilla fallbacks per dungeon (used when config entries are absent or invalid). */
    private static final Map<String, List<EntityType<?>>> FALLBACKS = Map.of(
            COLLAPSED_VAULT, List.of(EntityType.ZOMBIE, EntityType.SKELETON),
            UMBRAL_WARRENS, List.of(EntityType.CAVE_SPIDER, EntityType.ZOMBIE),
            MONSTER_ROOM, List.of(EntityType.ZOMBIE, EntityType.SKELETON, EntityType.SPIDER));

    /** Parsed snapshot; volatile swap on reload. */
    private static volatile Snapshot snapshot;
    /** Ids already warned about (log once per unknown/missing mob id). */
    private static final Set<String> WARNED_IDS = Collections.synchronizedSet(new HashSet<>());
    /** Spawner blocks placed this session, re-targeted on reload. Cleared on server stop. */
    private static final List<PlacedSpawner> PLACED = new CopyOnWriteArrayList<>();

    private static volatile MinecraftServer activeServer;

    static {
        ReloadHooks.register("dungeons", () ->
                reload(FMLPaths.CONFIGDIR.get().resolve("eclipse")));
    }

    private record PlacedSpawner(ResourceKey<Level> dimension, BlockPos pos, String dungeonId, int index) {}

    private record Snapshot(Map<String, List<String>> spawnerIds, int autoDelayTicks, int placeIntervalTicks) {}

    private DungeonSpawners() {}

    /** Forces class-load (static ReloadHooks registration) — called once at server setup. */
    public static void ensureLoaded() {
        current();
    }

    /** Ticks between the PENDING broadcast and the automatic placement fallback (D7). */
    public static int autoDelayTicks() {
        return current().autoDelayTicks();
    }

    /** Minimum ticks between two pending-site placements (mansion-cost spacing, §5 risks). */
    public static int placeIntervalTicks() {
        return current().placeIntervalTicks();
    }

    /**
     * The spawner mob for slot {@code index} of a dungeon: config ids first (rotating
     * through the list), vanilla fallback when the list is empty or an id is unknown.
     */
    public static EntityType<?> spawnerTypeFor(String dungeonId, int index) {
        List<String> ids = current().spawnerIds().getOrDefault(dungeonId, List.of());
        if (!ids.isEmpty()) {
            String id = ids.get(Math.floorMod(index, ids.size()));
            EntityType<?> resolved = resolve(id);
            if (resolved != null) {
                return resolved;
            }
        }
        List<EntityType<?>> fallback = FALLBACKS.getOrDefault(dungeonId,
                List.of(EntityType.ZOMBIE, EntityType.SKELETON));
        return fallback.get(Math.floorMod(index, fallback.size()));
    }

    /**
     * Places a vanilla spawner block at {@code pos} targeting the configured mob of
     * {@code (dungeonId, index)} and records it for live re-targeting on reload.
     */
    public static void applyTo(ServerLevel level, BlockPos pos, String dungeonId, int index) {
        level.setBlock(pos, Blocks.SPAWNER.defaultBlockState(), 2);
        retarget(level, pos, dungeonId, index);
        PLACED.add(new PlacedSpawner(level.dimension(), pos.immutable(), dungeonId, index));
    }

    /**
     * Re-reads {@code dungeons.json} and re-targets every spawner placed this session
     * (registered as the {@code "dungeons"} {@link ReloadHooks} hook — runs on
     * {@code /eclipse reload}).
     */
    public static synchronized void reload(Path configDir) {
        snapshot = load(configDir);
        WARNED_IDS.clear();
        MinecraftServer server = activeServer;
        if (server == null) {
            return;
        }
        int retargeted = 0;
        for (PlacedSpawner placed : PLACED) {
            ServerLevel level = server.getLevel(placed.dimension());
            if (level == null || !level.isLoaded(placed.pos())) {
                continue;
            }
            if (level.getBlockState(placed.pos()).is(Blocks.SPAWNER)) {
                retarget(level, placed.pos(), placed.dungeonId(), placed.index());
                retargeted++;
            }
        }
        if (retargeted > 0) {
            EclipseMod.LOGGER.info("DungeonSpawners: re-targeted {} placed spawner(s) after reload", retargeted);
        }
    }

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        activeServer = event.getServer();
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        activeServer = null;
        PLACED.clear();
    }

    // --- internals ---

    private static void retarget(ServerLevel level, BlockPos pos, String dungeonId, int index) {
        if (level.getBlockEntity(pos) instanceof SpawnerBlockEntity spawner) {
            spawner.setEntityId(spawnerTypeFor(dungeonId, index), level.getRandom());
            spawner.setChanged();
        }
    }

    private static Snapshot current() {
        Snapshot loaded = snapshot;
        if (loaded == null) {
            synchronized (DungeonSpawners.class) {
                loaded = snapshot;
                if (loaded == null) {
                    loaded = load(FMLPaths.CONFIGDIR.get().resolve("eclipse"));
                    snapshot = loaded;
                }
            }
        }
        return loaded;
    }

    private static EntityType<?> resolve(String id) {
        ResourceLocation location = ResourceLocation.tryParse(id);
        Optional<EntityType<?>> type = location == null
                ? Optional.empty() : BuiltInRegistries.ENTITY_TYPE.getOptional(location);
        if (type.isEmpty() && WARNED_IDS.add(id)) {
            EclipseMod.LOGGER.warn("dungeons.json spawner id '{}' is not a registered entity type; "
                    + "using the vanilla fallback (P6 mob not merged yet?)", id);
        }
        return type.orElse(null);
    }

    private static Snapshot load(Path configDir) {
        try {
            Files.createDirectories(configDir);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to create config directory {}", configDir, e);
        }
        Path file = configDir.resolve("dungeons.json");
        if (!Files.isRegularFile(file)) {
            writeDefault(file);
        }
        Map<String, List<String>> spawnerIds = new HashMap<>();
        int autoDelay = 100;
        int placeInterval = 20;
        if (Files.isRegularFile(file)) {
            try {
                JsonObject root = JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8))
                        .getAsJsonObject();
                for (Map.Entry<String, JsonElement> entry : root.entrySet()) {
                    if (entry.getKey().startsWith("_") || !entry.getValue().isJsonObject()) {
                        continue;
                    }
                    JsonObject section = entry.getValue().getAsJsonObject();
                    if ("structure_phase".equals(entry.getKey())) {
                        if (section.has("auto_delay_ticks")) {
                            autoDelay = Math.max(0, section.get("auto_delay_ticks").getAsInt());
                        }
                        if (section.has("place_interval_ticks")) {
                            placeInterval = Math.max(1, section.get("place_interval_ticks").getAsInt());
                        }
                        continue;
                    }
                    if (section.has("spawners")) {
                        List<String> ids = new ArrayList<>();
                        section.getAsJsonArray("spawners").forEach(e -> ids.add(e.getAsString()));
                        spawnerIds.put(entry.getKey(), List.copyOf(ids));
                    }
                }
            } catch (IOException | RuntimeException e) {
                EclipseMod.LOGGER.error("Failed to read {}; using built-in dungeon spawner defaults", file, e);
            }
        }
        return new Snapshot(Map.copyOf(spawnerIds), autoDelay, placeInterval);
    }

    private static void writeDefault(Path file) {
        JsonObject root = new JsonObject();
        root.addProperty("_comment", "Custom-dungeon spawner mobs + two-phase structure pacing. "
                + "P6: drop eclipse:* mob ids into the per-dungeon spawners arrays — unknown ids "
                + "fall back to vanilla mobs with a warning. Live-reloadable via /eclipse reload "
                + "(placed spawner blocks re-target in place).");
        JsonObject phase = new JsonObject();
        phase.addProperty("auto_delay_ticks", 100);
        phase.addProperty("place_interval_ticks", 20);
        root.add("structure_phase", phase);
        // P6-W910: eclipse_cultist leads both custom-dungeon rotations (plan §2.3 — the
        // resolve() fallback keeps spawners on vanilla mobs until the registrar wiring lands).
        root.add(COLLAPSED_VAULT, spawnerSection("eclipse:eclipse_cultist", "minecraft:skeleton",
                "eclipse:eclipse_cultist", "minecraft:zombie"));
        root.add(UMBRAL_WARRENS, spawnerSection("eclipse:eclipse_cultist", "minecraft:cave_spider",
                "minecraft:zombie"));
        root.add(MONSTER_ROOM, spawnerSection("minecraft:zombie", "minecraft:skeleton", "minecraft:spider"));
        try {
            Files.writeString(file, GSON.toJson(root), StandardCharsets.UTF_8);
            EclipseMod.LOGGER.info("Created default Eclipse config {}", file);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to write default config {}", file, e);
        }
    }

    private static JsonObject spawnerSection(String... ids) {
        JsonObject section = new JsonObject();
        JsonArray array = new JsonArray();
        for (String id : ids) {
            array.add(id);
        }
        section.add("spawners", array);
        return section;
    }
}
