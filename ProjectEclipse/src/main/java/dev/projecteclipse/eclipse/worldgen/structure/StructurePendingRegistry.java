package dev.projecteclipse.eclipse.worldgen.structure;

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
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;

import javax.annotation.Nullable;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.S2CStructureRiftPayload;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import dev.projecteclipse.eclipse.worldgen.structure.dungeon.DungeonSpawners;
import net.minecraft.core.BlockPos;
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
 * <p><b>Persistence / restart resume</b>: pending rows and placed-site records are written
 * to {@code world/<save>/eclipse/pending_structures.json} on every mutation and reloaded
 * on server start — a restart mid-pending resumes the auto-delay clock (game time is
 * per-save, so aged rows place right away, still interval-spaced).
 * <b>W1.5 seam note</b>: the plan stores these rows in {@code EclipseWorldgenState}
 * (SavedData); that class has not landed in this wave, so storage is isolated behind
 * {@link #persist()}/{@link #loadFromDisk} — migrating is a two-method swap (see
 * {@code docs/plans_v3/wiring/P1-W1.6_wiring.md}).</p>
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

    /** Ticks between auto-delay scans (placement spacing itself is config-driven). */
    private static final int SCAN_INTERVAL_TICKS = 10;
    private static final String FILE_NAME = "pending_structures.json";
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();

    private static final Map<String, SitePlacer> PLACERS = new ConcurrentHashMap<>();
    private static final List<SiteListener> LISTENERS = new CopyOnWriteArrayList<>();
    private static final Set<String> WARNED_NO_PLACER = Collections.synchronizedSet(new HashSet<>());

    /** Pending rows in enqueue order; mutations on the server thread only. */
    private static final List<PendingSite> PENDING = new CopyOnWriteArrayList<>();
    /** siteId → stage of every already-placed site (dedup + erase-stage cleanup). */
    private static final Map<String, PlacedRecord> PLACED = new ConcurrentHashMap<>();
    /** Sites explicitly triggered (placed on the next scan even before their delay). */
    private static final Set<String> TRIGGERED = Collections.synchronizedSet(new HashSet<>());

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
        PLACERS.putIfAbsent(structureId, placer);
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
     * Places a pending site NOW (P2 calls this when its rift animation lands; also the
     * {@code /eclipse-worldgen structures trigger <siteId>} dev path). Synchronous on the
     * server thread. Returns {@code false} when no such pending site exists.
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
        loadFromDisk();
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
            boolean due = TRIGGERED.contains(site.siteId())
                    || gameTime - site.enqueuedGameTime() >= autoDelay
                    || gameTime < site.enqueuedGameTime(); // clock went backwards: treat as due
            if (due && place(server, site)) {
                return; // one placement per interval
            }
        }
    }

    // --- placement ---

    /** Runs the site's placer; true when the site left the pending list (placed or failed hard). */
    private static boolean place(MinecraftServer server, PendingSite site) {
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
            EclipseMod.LOGGER.error("Dimension {} of pending site {} is missing; dropping site",
                    site.dimension(), site.siteId());
            removeAndRecord(site, false);
            return true;
        }
        try {
            placer.place(level, site);
        } catch (Exception e) {
            EclipseMod.LOGGER.error("Structure placement of {} ({}) failed", site.siteId(),
                    site.structureId(), e);
            // Fall through: the site is consumed either way — a broken placer must never
            // wedge the queue (same "one structure must never break the others" contract).
        }
        removeAndRecord(site, true);
        lastPlaceGameTime = level.getGameTime();
        fire(level, site, Phase.PLACED);
        EclipseMod.LOGGER.info("Structure site PLACED: {} ({}) at {}", site.siteId(),
                site.structureId(), site.anchor().toShortString());
        return true;
    }

    private static void removeAndRecord(PendingSite site, boolean recordPlaced) {
        PENDING.removeIf(row -> row.siteId().equals(site.siteId()));
        TRIGGERED.remove(site.siteId());
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

    // --- persistence (isolated: swap these two methods for EclipseWorldgenState when W1.5 lands) ---

    private static synchronized void persist() {
        Path dir = FrozenParams.saveEclipseDir();
        if (dir == null) {
            return; // no save session (should not happen on the server thread mid-session)
        }
        JsonObject root = new JsonObject();
        root.addProperty("_comment", "Two-phase structure registry (W1.6). Pending rows place on "
                + "P2 trigger or after structure_phase.auto_delay_ticks; placed records dedupe "
                + "re-commits and are cleared per dimension by erase sweeps.");
        JsonArray pending = new JsonArray();
        for (PendingSite site : PENDING) {
            JsonObject row = new JsonObject();
            row.addProperty("siteId", site.siteId());
            row.addProperty("structureId", site.structureId());
            row.addProperty("dimension", site.dimension());
            row.addProperty("x", site.anchor().getX());
            row.addProperty("y", site.anchor().getY());
            row.addProperty("z", site.anchor().getZ());
            row.addProperty("stage", site.stage());
            row.addProperty("footprint", site.footprint());
            row.addProperty("enqueuedGameTime", site.enqueuedGameTime());
            pending.add(row);
        }
        root.add("pending", pending);
        JsonArray placed = new JsonArray();
        for (Map.Entry<String, PlacedRecord> entry : PLACED.entrySet()) {
            JsonObject row = new JsonObject();
            row.addProperty("siteId", entry.getKey());
            row.addProperty("dimension", entry.getValue().dimension());
            row.addProperty("stage", entry.getValue().stage());
            placed.add(row);
        }
        root.add("placed", placed);
        try {
            Files.writeString(dir.resolve(FILE_NAME), GSON.toJson(root), StandardCharsets.UTF_8);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to persist pending structure registry", e);
        }
    }

    private static void loadFromDisk() {
        PENDING.clear();
        PLACED.clear();
        TRIGGERED.clear();
        Path dir = FrozenParams.saveEclipseDir();
        if (dir == null || !Files.isRegularFile(dir.resolve(FILE_NAME))) {
            return;
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
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("Failed to read pending structure registry; starting empty", e);
        }
    }
}
