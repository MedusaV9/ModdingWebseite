package dev.projecteclipse.eclipse.client.lives;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lives.GraveBlockEntity;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.core.BlockPos;
import net.minecraft.core.SectionPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.chunk.LevelChunk;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * FX-Wave-13 N4 — <b>Seelenlaterne am Grab</b>: a small, flickering ghost lantern hovers
 * over every player grave, a thin violet Ara thread dripping from it down onto the slab.
 * It goes out the moment the grave does.
 *
 * <p><b>Effect id</b>: {@code eclipse:grave_soul_lantern} (authored by
 * {@code tools/photon/grave_lantern_fx.py}; warm flame + cold violet rim motes, glow
 * dominating the baked lantern cube). The asset is authored in GRAVE-LOCAL space with the
 * lamp head at +1.35, so the loop anchors at the block CENTER and needs no offset.</p>
 *
 * <p><b>Why this is not a {@code PhotonFxRegistry} row.</b> {@code ensureLoop} manages
 * exactly ONE loop per logical id, and a hardcore map has many graves at once — so this
 * controller holds one {@link PhotonBridge.LoopHandle} per grave position, the
 * {@code StormFxClient} crown-halo shape. There is also no cue and no payload: a grave is
 * a BLOCK, and block entities ride the chunk packet, so the client can see every grave in
 * render distance on its own (zero wire).</p>
 *
 * <p><b>The window</b> (INTEGRATION.md §4 WINDOWED-loop law, the
 * {@code NetherPitPlume}/{@code SanctumLightfall} school):</p>
 * <ul>
 *   <li><b>Open</b>: a {@link GraveBlockEntity} within {@value #MATERIALIZE_DIST} blocks of
 *       the camera, found by the {@value #SCAN_CADENCE}-tick chunk scan.</li>
 *   <li><b>Distance hysteresis</b>: an open lantern only releases beyond
 *       {@value #RELEASE_DIST} blocks, so walking the edge of a graveyard cannot strobe
 *       it.</li>
 *   <li><b>Extinguish</b>: checked EVERY tick against {@code level.getBlockEntity} — the
 *       block vanishing is the "erlischt" beat. Every removal path ends there: the owner
 *       (or, after the grace period, anyone) looting it, the 3× grace-period scatter,
 *       mining, or a revived player emptying their own grave. The stop is graceful
 *       ({@code destroy(false)}), so the flame burns down over its own particle lifetimes
 *       instead of popping out.</li>
 *   <li><b>Hard gates</b>: {@link PhotonBridge#available()} (photon present +
 *       {@code photonFx} + NOT {@code reducedFx} — a {@code reducedFx} flip force-kills
 *       every lantern on the next tick), level change and logout.</li>
 * </ul>
 *
 * <p><b>Budget</b>: at most {@value #MAX_LANTERNS} lanterns burn at once (nearest first),
 * each one executor of ≤ 53 cull-boxed particles against
 * {@link PhotonBridge#MAX_LIVE_EXECUTORS}; a refused spawn backs that grave off by
 * {@value #RETRY_TICKS} ticks. The scan touches {@value #SCAN_CHUNK_RADIUS} chunks in each
 * direction, twice a second, and only reads already-loaded chunks' block-entity maps.
 * Photon absent or {@code reducedFx} ⇒ nothing spawns and the grave looks exactly like it
 * did before this class existed (pure garnish — there is no Quasar leg by design).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class GraveLanternFx {
    /** The one asset (authored grave-local, lamp head at +1.35 over the anchor). */
    public static final ResourceLocation GRAVE_SOUL_LANTERN =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "grave_soul_lantern");

    /** Lanterns light for graves within this camera distance (blocks)… */
    private static final double MATERIALIZE_DIST = 32.0D;
    /** …and only go dark beyond this one (hysteresis — no boundary thrash). */
    private static final double RELEASE_DIST = 40.0D;
    private static final double MATERIALIZE_DIST_SQ = MATERIALIZE_DIST * MATERIALIZE_DIST;
    private static final double RELEASE_DIST_SQ = RELEASE_DIST * RELEASE_DIST;
    /** Chunk-scan cadence in ticks (the per-tick work is the extinguish check only). */
    private static final int SCAN_CADENCE = 10;
    /** Chunk radius scanned around the camera — covers {@value #MATERIALIZE_DIST} blocks. */
    private static final int SCAN_CHUNK_RADIUS = 2;
    /** Hard cap on simultaneously burning lanterns (nearest graves win). */
    private static final int MAX_LANTERNS = 4;
    /** Refused-spawn (executor budget) backoff per grave, in ticks. */
    private static final int RETRY_TICKS = 40;

    /** Open windows: grave position → live loop state (client main thread only). */
    private static final Map<BlockPos, PhotonBridge.LoopHandle> LANTERNS = new HashMap<>();
    /** Earliest client tick a grave may retry after a refused spawn. */
    private static final Map<BlockPos, Integer> RETRY_AT = new HashMap<>();
    /** Scratch reused by the scan (no per-scan list allocation churn). */
    private static final List<BlockPos> CANDIDATES = new ArrayList<>();

    private static int clientTicks;
    private static int scanCountdown;

    private GraveLanternFx() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null) {
            LANTERNS.clear(); // executors died with the level (bridge sweep / logout reset)
            RETRY_AT.clear();
            scanCountdown = 0;
            return;
        }
        if (!PhotonBridge.available()) {
            // Global gate slammed (reducedFx flip, photonFx off, photon absent): kill every
            // lantern NOW — reducedFx must not have to wait out a graceful fade.
            stopAll(true);
            scanCountdown = 0;
            return;
        }
        if (minecraft.isPaused()) {
            return; // keep the windows, freeze the cadence
        }
        clientTicks++;
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        pruneOpen(level, camera);
        if (--scanCountdown > 0) {
            return;
        }
        scanCountdown = SCAN_CADENCE;
        light(level, camera);
    }

    /**
     * Per-tick close pass: a lantern goes out when its grave block is gone (the
     * "erlischt" beat — looted, scattered, mined, or emptied after a revive), when the
     * camera left the release band, or when the bridge already reaped the runtime.
     */
    private static void pruneOpen(ClientLevel level, Vec3 camera) {
        if (LANTERNS.isEmpty()) {
            return;
        }
        for (Iterator<Map.Entry<BlockPos, PhotonBridge.LoopHandle>> it =
                LANTERNS.entrySet().iterator(); it.hasNext(); ) {
            Map.Entry<BlockPos, PhotonBridge.LoopHandle> entry = it.next();
            BlockPos pos = entry.getKey();
            PhotonBridge.LoopHandle handle = entry.getValue();
            if (!handle.alive()) {
                it.remove(); // level change / bridge sweep already destroyed it
                continue;
            }
            boolean graveGone = !isLoadedGrave(level, pos);
            boolean walkedAway = anchor(pos).distanceToSqr(camera) > RELEASE_DIST_SQ;
            if (graveGone || walkedAway) {
                it.remove();
                PhotonBridge.stopLoop(handle, true); // graceful: the flame burns down
            }
        }
    }

    /** Open pass: light the {@value #MAX_LANTERNS} nearest unlit graves inside the band. */
    private static void light(ClientLevel level, Vec3 camera) {
        if (LANTERNS.size() >= MAX_LANTERNS) {
            return; // budget full — nothing to gain from the scan this cycle
        }
        CANDIDATES.clear();
        collectGraves(level, camera);
        if (CANDIDATES.isEmpty()) {
            RETRY_AT.keySet().removeIf(pos -> !LANTERNS.containsKey(pos));
            return;
        }
        CANDIDATES.sort((first, second) -> Double.compare(
                anchor(first).distanceToSqr(camera), anchor(second).distanceToSqr(camera)));
        for (BlockPos pos : CANDIDATES) {
            if (LANTERNS.size() >= MAX_LANTERNS) {
                break;
            }
            Integer retryAt = RETRY_AT.get(pos);
            if (retryAt != null && clientTicks < retryAt) {
                continue; // budget backoff
            }
            PhotonBridge.LoopHandle handle = PhotonBridge.spawnLoop(GRAVE_SOUL_LANTERN, anchor(pos));
            if (handle == null) {
                RETRY_AT.put(pos.immutable(), clientTicks + RETRY_TICKS);
            } else {
                LANTERNS.put(pos.immutable(), handle);
                RETRY_AT.remove(pos);
            }
        }
        CANDIDATES.clear();
    }

    /**
     * Collects unlit grave positions inside the materialize band from the LOADED chunks
     * around the camera. Block entities ride the chunk packet, so the client's own
     * {@code LevelChunk} block-entity map is authoritative enough for a cosmetic window —
     * no grave sync exists and none is needed.
     */
    private static void collectGraves(ClientLevel level, Vec3 camera) {
        int centerX = SectionPos.blockToSectionCoord(Math.floor(camera.x));
        int centerZ = SectionPos.blockToSectionCoord(Math.floor(camera.z));
        for (int dx = -SCAN_CHUNK_RADIUS; dx <= SCAN_CHUNK_RADIUS; dx++) {
            for (int dz = -SCAN_CHUNK_RADIUS; dz <= SCAN_CHUNK_RADIUS; dz++) {
                int chunkX = centerX + dx;
                int chunkZ = centerZ + dz;
                if (!level.hasChunk(chunkX, chunkZ)) {
                    continue;
                }
                LevelChunk chunk = level.getChunk(chunkX, chunkZ);
                for (Map.Entry<BlockPos, BlockEntity> entry : chunk.getBlockEntities().entrySet()) {
                    if (!(entry.getValue() instanceof GraveBlockEntity)) {
                        continue;
                    }
                    BlockPos pos = entry.getKey();
                    if (LANTERNS.containsKey(pos)) {
                        continue;
                    }
                    if (anchor(pos).distanceToSqr(camera) <= MATERIALIZE_DIST_SQ) {
                        CANDIDATES.add(pos.immutable());
                    }
                }
            }
        }
    }

    /** Whether a grave block entity still stands at {@code pos} in a loaded chunk. */
    private static boolean isLoadedGrave(ClientLevel level, BlockPos pos) {
        return level.hasChunk(SectionPos.blockToSectionCoord(pos.getX()),
                        SectionPos.blockToSectionCoord(pos.getZ()))
                && level.getBlockEntity(pos) instanceof GraveBlockEntity;
    }

    /** Loop anchor: the grave block CENTER (the asset is authored around it). */
    private static Vec3 anchor(BlockPos pos) {
        return Vec3.atCenterOf(pos);
    }

    /** Stops every live lantern ({@code force=true} = instant kill, the reducedFx path). */
    private static void stopAll(boolean force) {
        if (LANTERNS.isEmpty()) {
            RETRY_AT.clear();
            return;
        }
        for (PhotonBridge.LoopHandle handle : LANTERNS.values()) {
            PhotonBridge.stopLoop(handle, !force);
        }
        LANTERNS.clear();
        RETRY_AT.clear();
    }

    /** Disconnect reset — the bridge force-destroys the executors; drop the bookkeeping. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        LANTERNS.clear();
        RETRY_AT.clear();
        scanCountdown = 0;
    }

    /** Dev/QA introspection ({@code /dev photon status} style): lanterns currently burning. */
    public static int liveLanterns() {
        return LANTERNS.size();
    }

    /** The grave positions currently carrying a lantern (dev introspection; never mutated). */
    @Nullable
    public static BlockPos anyLitGrave() {
        Iterator<BlockPos> it = LANTERNS.keySet().iterator();
        return it.hasNext() ? it.next() : null;
    }
}
