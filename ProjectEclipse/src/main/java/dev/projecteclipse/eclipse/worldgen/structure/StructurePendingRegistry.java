package dev.projecteclipse.eclipse.worldgen.structure;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.function.Consumer;

import javax.annotation.Nullable;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldgenState;
import dev.projecteclipse.eclipse.network.S2CStructureRiftPayload;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import dev.projecteclipse.eclipse.worldgen.structure.dungeon.DungeonSpawners;
import net.minecraft.core.BlockPos;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The STRUCTURE-PENDING registry of the two-phase stage apply (design D7, req 16).
 * Terrain phase and structure phase are decoupled:
 *
 * <ol>
 *   <li><b>PENDING</b> — when a stage's terrain sweep completes, {@link StructureStamper}
 *       {@linkplain #enqueue enqueues} every site of the crossed stages here instead of
 *       placing immediately. The registry broadcasts {@link S2CStructureRiftPayload}
 *       {@code {siteId, structureId, anchor, footprint}} to the site's dimension (P2
 *       renders the rift tear over the build site) and fires
 *       {@link SiteListener#onSitePhase} with {@link Phase#PENDING}.</li>
 *   <li><b>PLACED</b> — placement happens on {@link #trigger}(siteId) — called by P2's
 *       expansion sequence the moment its rift animation lands — or automatically after
 *       {@code structure_phase.auto_delay_ticks} ({@code config/eclipse/dungeons.json},
 *       default 100) so a site is NEVER lost without a client/P2. At most one site
 *       places per {@code structure_phase.place_interval_ticks} (default 20) so a stage
 *       with many sites (mansion + ancient city + mineshafts) staggers its paste cost.</li>
 * </ol>
 *
 * <p><b>Persistence / restart resume</b>: pending rows and placed-site records live in
 * {@link EclipseWorldgenState} SavedData. A one-time reader imports the legacy
 * {@code eclipse/pending_structures.json}, persists it to SavedData and removes the JSON.
 * A restart mid-pending resumes the auto-delay clock (game time is per-save, so aged rows
 * place right away, still interval-spaced).</p>
 *
 * <p><b>Placement dispatch</b>: sites carry only ids + anchor; the actual build runs
 * through the {@link SitePlacer} registered for the site's {@code structureId}
 * ({@link StructureStamper} registers every id it owns at server start; W1.7/W1.8
 * register theirs — hanging court, bastion, end cities — the same way). A site whose
 * placer is missing stays queued (warned once) so sites enqueued before a sibling
 * package merges are placed after the next restart instead of being dropped.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class StructurePendingRegistry {
    /**
     * One enqueued site (compile seam §3.10). {@code siteId} is unique per instance
     * ({@code "eclipse:mansion"}, {@code "eclipse:mineshaft/o3_1"}); {@code structureId}
     * selects the {@link SitePlacer}; {@code dimension} is the disc profile name
     * ({@code "overworld"}/{@code "nether"}); {@code footprint} the expected full XZ
     * extent in blocks (P2 sizes the rift from it); {@code enqueuedGameTime} the game
     * time of the PENDING broadcast (auto-delay clock).
     */
    public record PendingSite(String siteId, String structureId, String dimension, BlockPos anchor,
            int stage, int footprint, long enqueuedGameTime) {}

    /** Two-phase lifecycle points observable via {@link #addListener}. */
    public enum Phase { PENDING, PLACED }

    /** Server-side phase observer (P2 sequences, P5 dev telemetry). Fired on the server thread. */
    @FunctionalInterface
    public interface SiteListener {
        void onSitePhase(ServerLevel level, PendingSite site, Phase phase);
    }

    /** Places one site's blocks (SitePrep + pieces/procedural build). Server thread. */
    @FunctionalInterface
    public interface SitePlacer {
        void place(ServerLevel level, PendingSite site);
    }

    /**
     * Tick-budgeted placer contract. The pending row remains persisted until exactly one
     * completion callback fires, so a shutdown mid-preparation safely retries next boot.
     */
    @FunctionalInterface
    public interface AsyncSitePlacer {
        void place(ServerLevel level, PendingSite site, Runnable onComplete,
                Consumer<Throwable> onFailure);
    }

    /** Ticks between auto-delay scans (placement spacing itself is config-driven). */
    private static final int SCAN_INTERVAL_TICKS = 10;
    /** Maximum failed attempts before the row is abandoned without a placed record. */
    private static final int MAX_PLACEMENT_FAILURES = 3;
    private static final String FILE_NAME = "pending_structures.json";
    private static final String STATUS_PENDING = "PENDING";
    private static final String STATUS_PLACED = "PLACED";

    private static final Map<String, SitePlacer> PLACERS = new ConcurrentHashMap<>();
    private static final Map<String, AsyncSitePlacer> ASYNC_PLACERS = new ConcurrentHashMap<>();
    private static final List<SiteListener> LISTENERS = new CopyOnWriteArrayList<>();
    private static final Set<String> WARNED_NO_PLACER = Collections.synchronizedSet(new HashSet<>());

    /** Pending rows in enqueue order; mutations on the server thread only. */
    private static final List<PendingSite> PENDING = new CopyOnWriteArrayList<>();
    /** siteId → stage of every already-placed site (dedup + erase-stage cleanup). */
    private static final Map<String, PlacedRecord> PLACED = new ConcurrentHashMap<>();
    /** Sites explicitly triggered (placed on the next scan even before their delay). */
    private static final Set<String> TRIGGERED = Collections.synchronizedSet(new HashSet<>());
    /** Pending ids whose async SitePrep cursor is currently running. */
    private static final Set<String> IN_FLIGHT = Collections.synchronizedSet(new HashSet<>());
    /** siteId → persisted failed placement attempts for the current pending row. */
    private static final Map<String, Integer> FAILURES = new ConcurrentHashMap<>();

    private record PlacedRecord(String dimension, int stage) {}

    private static volatile MinecraftServer activeServer;
    private static long lastPlaceGameTime = Long.MIN_VALUE;

    private StructurePendingRegistry() {}

    // --- registration (server-start time) ---

    /**
     * Registers the placer for a structure id (idempotent — first registration wins so a
     * JVM-static double boot cannot double-register). Call at {@code @EventBusSubscriber}
     * server-start time, before any site of that id can become due.
     */
    public static void registerPlacer(String structureId, SitePlacer placer) {
        if (!ASYNC_PLACERS.containsKey(structureId)) {
            PLACERS.putIfAbsent(structureId, placer);
        }
    }

    /**
     * Registers a tick-budgeted placer. Async registration supersedes a same-id sync
     * registration and keeps the SavedData row pending until its completion callback.
     */
    public static void registerAsyncPlacer(String structureId, AsyncSitePlacer placer) {
        ASYNC_PLACERS.putIfAbsent(structureId, placer);
        PLACERS.remove(structureId);
    }

    /** Registers a phase observer (P2 rift sequences hook here server-side). */
    public static void addListener(SiteListener listener) {
        LISTENERS.add(listener);
    }

    // --- the two-phase API (compile seam §3.10) ---

    /**
     * Enqueues a site into the PENDING phase: persists the row, broadcasts the rift
     * payload to the site's dimension and fires {@link Phase#PENDING}. Re-enqueues of a
     * site that is already pending or already placed at its stage are ignored (stage
     * erase clears placed records via {@link #clearPlacedAbove}, so a regrow re-enqueues
     * deterministically). Server thread only.
     */
    public static void enqueue(PendingSite site) {
        MinecraftServer server = activeServer;
        if (server == null) {
            EclipseMod.LOGGER.warn("StructurePendingRegistry.enqueue({}) with no active server; dropped",
                    site.siteId());
            return;
        }
        if (PLACED.containsKey(site.siteId())) {
            return;
        }
        for (PendingSite existing : PENDING) {
            if (existing.siteId().equals(site.siteId())) {
                return;
            }
        }
        FAILURES.remove(site.siteId());
        PENDING.add(site);
        persist();
        ServerLevel level = levelOf(server, site);
        if (level != null) {
            PacketDistributor.sendToPlayersInDimension(level, new S2CStructureRiftPayload(
                    site.siteId(), site.structureId(), site.anchor(), site.footprint()));
            fire(level, site, Phase.PENDING);
        }
        EclipseMod.LOGGER.info("Structure site PENDING: {} ({}) at {} [stage {}, footprint {}]",
                site.siteId(), site.structureId(), site.anchor().toShortString(), site.stage(),
                site.footprint());
    }

    /**
     * Triggers a pending site NOW (P2 calls this when its rift animation lands; also the
     * {@code /eclipse-worldgen structures place <siteId>} operator path). Synchronous
     * placers finish before return; async SitePrep placers are queued before return and
     * retain their SavedData row until completion.
     */
    public static boolean trigger(String siteId) {
        MinecraftServer server = activeServer;
        if (server == null) {
            return false;
        }
        for (PendingSite site : PENDING) {
            if (site.siteId().equals(siteId)) {
                if (place(server, site)) {
                    return true;
                }
                // Placer not merged yet: remember the request, retry on scans.
                TRIGGERED.add(siteId);
                return false;
            }
        }
        return false;
    }

    /** Immutable snapshot of the pending rows (P5 introspection, tests). */
    public static List<PendingSite> pending() {
        return List.copyOf(PENDING);
    }

    /** Whether a site was already placed this save (and not erased since). */
    public static boolean wasPlaced(String siteId) {
        return PLACED.containsKey(siteId);
    }

    /** Immutable sorted snapshot of placed site ids for operator diagnostics. */
    public static List<String> placedSiteIds() {
        return PLACED.keySet().stream().sorted().toList();
    }

    /**
     * Stage-erase bookkeeping (called by {@link StructureStamper} when an erase sweep
     * completes): forgets pending rows and placed records of the dimension above
     * {@code keepThroughStage}, so regrowing the stage re-enqueues them onto the fresh
     * terrain — matching the sweep contract ("lowering deliberately removes structures;
     * regrowing re-stamps deterministically").
     */
    public static void clearPlacedAbove(String dimension, int keepThroughStage) {
        boolean changed = PENDING.removeIf(site ->
                site.dimension().equals(dimension) && site.stage() > keepThroughStage);
        IN_FLIGHT.removeIf(siteId -> PENDING.stream().noneMatch(site -> site.siteId().equals(siteId)));
        FAILURES.keySet().removeIf(siteId ->
                PENDING.stream().noneMatch(site -> site.siteId().equals(siteId)));
        int before = PLACED.size();
        PLACED.entrySet().removeIf(entry -> entry.getValue().dimension().equals(dimension)
                && entry.getValue().stage() > keepThroughStage);
        if (changed || PLACED.size() != before) {
            persist();
            EclipseMod.LOGGER.info("Structure registry: cleared sites of {} above stage {} (erase sweep)",
                    dimension, keepThroughStage);
        }
    }

    // --- lifecycle + auto-delay ---

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        activeServer = event.getServer();
        lastPlaceGameTime = Long.MIN_VALUE;
        DungeonSpawners.ensureLoaded();
        loadFromState();
        if (!PENDING.isEmpty()) {
            EclipseMod.LOGGER.info("StructurePendingRegistry: resumed {} pending site(s) from save",
                    PENDING.size());
        }
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        activeServer = null;
        PENDING.clear();
        PLACED.clear();
        TRIGGERED.clear();
        IN_FLIGHT.clear();
        FAILURES.clear();
        WARNED_NO_PLACER.clear();
        lastPlaceGameTime = Long.MIN_VALUE;
    }

    /**
     * Auto-delay scan: places the first due site (explicitly triggered, or older than
     * {@code auto_delay_ticks}), at most one per {@code place_interval_ticks}.
     */
    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = activeServer;
        if (server != event.getServer() || PENDING.isEmpty()
                || server.getTickCount() % SCAN_INTERVAL_TICKS != 0) {
            return;
        }
        long gameTime = server.overworld().getGameTime();
        if (lastPlaceGameTime != Long.MIN_VALUE
                && gameTime - lastPlaceGameTime < DungeonSpawners.placeIntervalTicks()) {
            return;
        }
        int autoDelay = DungeonSpawners.autoDelayTicks();
        for (PendingSite site : PENDING) {
            if (IN_FLIGHT.contains(site.siteId())) {
                continue;
            }
            boolean due = TRIGGERED.contains(site.siteId())
                    || gameTime - site.enqueuedGameTime() >= autoDelay
                    || gameTime < site.enqueuedGameTime(); // clock went backwards: treat as due
            if (due && place(server, site)) {
                return; // one placement per interval
            }
        }
    }

    // --- placement ---

    /** Runs or starts the site's placer; false only when no implementation is registered. */
    private static boolean place(MinecraftServer server, PendingSite site) {
        AsyncSitePlacer asyncPlacer = ASYNC_PLACERS.get(site.structureId());
        if (asyncPlacer != null) {
            if (!IN_FLIGHT.add(site.siteId())) {
                return true;
            }
            ServerLevel level = levelOf(server, site);
            if (level == null) {
                IN_FLIGHT.remove(site.siteId());
                placementFailed(server, null, site,
                        new IllegalStateException("Dimension " + site.dimension() + " is missing"));
                return true;
            }
            try {
                asyncPlacer.place(level, site,
                        () -> completeAsync(server, level, site, null),
                        error -> completeAsync(server, level, site, error));
                lastPlaceGameTime = level.getGameTime();
                return true;
            } catch (Throwable error) {
                completeAsync(server, level, site, error);
                return true;
            }
        }
        SitePlacer placer = PLACERS.get(site.structureId());
        if (placer == null) {
            if (WARNED_NO_PLACER.add(site.structureId())) {
                EclipseMod.LOGGER.warn("No placer registered for structure id {} (site {}); "
                        + "site stays pending (sibling package not merged yet?)",
                        site.structureId(), site.siteId());
            }
            return false;
        }
        ServerLevel level = levelOf(server, site);
        if (level == null) {
            placementFailed(server, null, site,
                    new IllegalStateException("Dimension " + site.dimension() + " is missing"));
            return true;
        }
        try {
            placer.place(level, site);
        } catch (Exception e) {
            placementFailed(server, level, site, e);
            return true;
        }
        removeAndRecord(site, true);
        lastPlaceGameTime = level.getGameTime();
        fire(level, site, Phase.PLACED);
        EclipseMod.LOGGER.info("Structure site PLACED: {} ({}) at {}", site.siteId(),
                site.structureId(), site.anchor().toShortString());
        return true;
    }

    private static void completeAsync(MinecraftServer server, ServerLevel level, PendingSite site,
            @Nullable Throwable error) {
        if (activeServer != server || !IN_FLIGHT.remove(site.siteId())) {
            return;
        }
        if (error != null) {
            placementFailed(server, level, site, error);
            return;
        }
        removeAndRecord(site, true);
        lastPlaceGameTime = level.getGameTime();
        fire(level, site, Phase.PLACED);
        EclipseMod.LOGGER.info("Structure site PLACED: {} ({}) at {}",
                site.siteId(), site.structureId(), site.anchor().toShortString());
    }

    private static void placementFailed(MinecraftServer server, @Nullable ServerLevel level,
            PendingSite site, Throwable error) {
        int failures = FAILURES.merge(site.siteId(), 1, Integer::sum);
        lastPlaceGameTime = level != null ? level.getGameTime() : server.overworld().getGameTime();
        TRIGGERED.remove(site.siteId());
        if (failures >= MAX_PLACEMENT_FAILURES) {
            EclipseMod.LOGGER.error(
                    "Structure placement of {} ({}) failed {}/{} times; abandoning pending row without marking placed",
                    site.siteId(), site.structureId(), failures, MAX_PLACEMENT_FAILURES, error);
            removeAndRecord(site, false);
            return;
        }
        persist();
        EclipseMod.LOGGER.warn(
                "Structure placement of {} ({}) failed (attempt {}/{}); row remains pending for retry",
                site.siteId(), site.structureId(), failures, MAX_PLACEMENT_FAILURES, error);
    }

    private static void removeAndRecord(PendingSite site, boolean recordPlaced) {
        PENDING.removeIf(row -> row.siteId().equals(site.siteId()));
        TRIGGERED.remove(site.siteId());
        FAILURES.remove(site.siteId());
        if (recordPlaced) {
            PLACED.put(site.siteId(), new PlacedRecord(site.dimension(), site.stage()));
        }
        persist();
    }

    private static void fire(ServerLevel level, PendingSite site, Phase phase) {
        for (SiteListener listener : LISTENERS) {
            try {
                listener.onSitePhase(level, site, phase);
            } catch (Exception e) {
                EclipseMod.LOGGER.error("Structure phase listener failed for {} {}", site.siteId(), phase, e);
            }
        }
    }

    @Nullable
    private static ServerLevel levelOf(MinecraftServer server, PendingSite site) {
        DiscProfile profile = "nether".equals(site.dimension()) ? DiscProfile.NETHER : DiscProfile.OVERWORLD;
        return server.getLevel(WorldStageService.dimensionOf(profile));
    }

    // --- SavedData persistence + one-time legacy JSON migration ---

    private static synchronized void persist() {
        MinecraftServer server = activeServer;
        if (server == null) {
            return;
        }
        List<CompoundTag> rows = new ArrayList<>(PENDING.size() + PLACED.size());
        for (PendingSite site : PENDING) {
            CompoundTag row = siteToTag(site);
            row.putString("status", STATUS_PENDING);
            int failures = FAILURES.getOrDefault(site.siteId(), 0);
            if (failures > 0) {
                row.putInt("failures", failures);
            }
            rows.add(row);
        }
        for (Map.Entry<String, PlacedRecord> entry : PLACED.entrySet()) {
            CompoundTag row = new CompoundTag();
            row.putString("status", STATUS_PLACED);
            row.putString("siteId", entry.getKey());
            row.putString("dimension", entry.getValue().dimension());
            row.putInt("stage", entry.getValue().stage());
            rows.add(row);
        }
        EclipseWorldgenState.get(server).setPendingStructures(rows);
    }

    private static void loadFromState() {
        PENDING.clear();
        PLACED.clear();
        TRIGGERED.clear();
        FAILURES.clear();
        MinecraftServer server = activeServer;
        if (server == null) {
            return;
        }
        List<CompoundTag> rows = EclipseWorldgenState.get(server).pendingStructures();
        if (rows.isEmpty() && migrateLegacyJson()) {
            persist();
            deleteLegacyJson();
            return;
        }
        for (CompoundTag row : rows) {
            String status = row.getString("status");
            if (STATUS_PLACED.equals(status)) {
                PLACED.put(row.getString("siteId"), new PlacedRecord(
                        row.getString("dimension"), row.getInt("stage")));
            } else {
                PendingSite site = siteFromTag(row);
                if (site != null) {
                    PENDING.add(site);
                    int failures = Math.max(0, row.getInt("failures"));
                    if (failures > 0) {
                        FAILURES.put(site.siteId(), failures);
                    }
                }
            }
        }
    }

    private static CompoundTag siteToTag(PendingSite site) {
        CompoundTag row = new CompoundTag();
        row.putString("siteId", site.siteId());
        row.putString("structureId", site.structureId());
        row.putString("dimension", site.dimension());
        row.putLong("anchor", site.anchor().asLong());
        row.putInt("stage", site.stage());
        row.putInt("footprint", site.footprint());
        row.putLong("enqueuedGameTime", site.enqueuedGameTime());
        return row;
    }

    @Nullable
    private static PendingSite siteFromTag(CompoundTag row) {
        String siteId = row.getString("siteId");
        String structureId = row.getString("structureId");
        if (siteId.isEmpty() || structureId.isEmpty()) {
            EclipseMod.LOGGER.warn("Ignoring malformed pending-structure SavedData row");
            return null;
        }
        return new PendingSite(siteId, structureId, row.getString("dimension"),
                BlockPos.of(row.getLong("anchor")), row.getInt("stage"), row.getInt("footprint"),
                row.getLong("enqueuedGameTime"));
    }

    /**
     * Imports the pre-SavedData JSON schema into the in-memory tables. Returns true only
     * after a complete successful parse; the caller then persists and deletes the source.
     */
    private static boolean migrateLegacyJson() {
        Path dir = FrozenParams.saveEclipseDir();
        if (dir == null || !Files.isRegularFile(dir.resolve(FILE_NAME))) {
            return false;
        }
        try {
            JsonObject root = JsonParser.parseString(
                    Files.readString(dir.resolve(FILE_NAME), StandardCharsets.UTF_8)).getAsJsonObject();
            List<PendingSite> pending = new ArrayList<>();
            if (root.has("pending")) {
                for (JsonElement element : root.getAsJsonArray("pending")) {
                    JsonObject row = element.getAsJsonObject();
                    pending.add(new PendingSite(row.get("siteId").getAsString(),
                            row.get("structureId").getAsString(),
                            row.get("dimension").getAsString(),
                            new BlockPos(row.get("x").getAsInt(), row.get("y").getAsInt(),
                                    row.get("z").getAsInt()),
                            row.get("stage").getAsInt(), row.get("footprint").getAsInt(),
                            row.get("enqueuedGameTime").getAsLong()));
                }
            }
            PENDING.addAll(pending);
            if (root.has("placed")) {
                for (JsonElement element : root.getAsJsonArray("placed")) {
                    JsonObject row = element.getAsJsonObject();
                    PLACED.put(row.get("siteId").getAsString(), new PlacedRecord(
                            row.get("dimension").getAsString(), row.get("stage").getAsInt()));
                }
            }
            EclipseMod.LOGGER.info("Migrated legacy {} into {}", FILE_NAME, EclipseWorldgenState.DATA_NAME);
            return true;
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("Failed to migrate legacy pending structure registry; source retained", e);
            PENDING.clear();
            PLACED.clear();
            return false;
        }
    }

    private static void deleteLegacyJson() {
        Path dir = FrozenParams.saveEclipseDir();
        if (dir == null) {
            return;
        }
        try {
            Files.deleteIfExists(dir.resolve(FILE_NAME));
        } catch (IOException e) {
            EclipseMod.LOGGER.warn("Migrated {}, but could not remove the legacy file", FILE_NAME, e);
        }
    }
}
