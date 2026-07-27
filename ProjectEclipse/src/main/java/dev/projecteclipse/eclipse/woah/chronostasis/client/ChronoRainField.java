package dev.projecteclipse.eclipse.woah.chronostasis.client;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.woah.chronostasis.ChronoSceneBuilder;
import dev.projecteclipse.eclipse.woah.chronostasis.ChronoStasisSite;
import net.minecraft.client.Minecraft;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * WOAH-03 Photon loop-window driver (plan §4.3/§4.5) — the
 * {@code EraDustMotes}/{@code StormInteriorFx} WINDOWED pattern. While the camera is
 * inside the zone (and Photon is available) it holds:
 *
 * <ul>
 *   <li>up to {@value #MAX_RAIN_HANDLES} {@code chrono_rain_frozen} loops on a
 *       {@value #RAIN_CELL}-block grid around the camera, clamped to the site circle
 *       (the {@code StormInteriorFx.tickRainSheets} turnover),</li>
 *   <li>one {@code chrono_dust_shimmer} loop riding the camera (re-anchored when the
 *       camera strays — loops cannot be moved, only released and re-ensured),</li>
 *   <li>one {@code chrono_sphere_idle} corona at the anchor and one
 *       {@code chrono_bolt_glow} column at the frozen bolt's foot.</li>
 * </ul>
 *
 * <p>Between 96 and 640 blocks it instead holds the {@code chrono_far_pillar} far-tell
 * loop (plan §4.5 — Photon executors are client-side and render distance-independent,
 * unlike display entities with their 10-chunk tracking horizon).</p>
 *
 * <p>On a discharge cue the frozen field is torn down, one {@code chrono_rain_release}
 * shot fires per live rain anchor and the loop window stays closed for
 * {@value #RELEASE_CLOSE_TICKS} ticks (the "rain falls all at once" beat). All handles
 * release on window close, {@code reducedFx} (via {@link PhotonBridge#available()}) and
 * disconnect — the loop law.</p>
 *
 * <p>Budget: ≤6 concurrent handles near + 1 far of {@code MAX_LIVE_EXECUTORS = 24}.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ChronoRainField {
    public static final ResourceLocation RAIN_FROZEN = fx("chrono_rain_frozen");
    public static final ResourceLocation DUST_SHIMMER = fx("chrono_dust_shimmer");
    public static final ResourceLocation SPHERE_IDLE = fx("chrono_sphere_idle");
    public static final ResourceLocation BOLT_GLOW = fx("chrono_bolt_glow");
    public static final ResourceLocation RAIN_RELEASE = fx("chrono_rain_release");
    public static final ResourceLocation FAR_PILLAR = fx("chrono_far_pillar");

    /** Rain emitter grid pitch; one emitter's box volume is ~24×18×24. */
    private static final int RAIN_CELL = 16;
    private static final int MAX_RAIN_HANDLES = 3;
    /** The frozen-rain window stays shut this long after a discharge cue (~5 s). */
    private static final int RELEASE_CLOSE_TICKS = 100;
    /** Far-tell window (camera→anchor distance). */
    private static final double FAR_MIN = 96.0D;
    private static final double FAR_MAX = 640.0D;
    /** Dust loop re-anchors when the camera strays this far from its spawn point. */
    private static final double DUST_REANCHOR_DIST = 8.0D;

    private record RainSlot(Vec3 pos, PhotonBridge.LoopHandle handle) {}

    private static final Map<Long, RainSlot> RAIN = new HashMap<>();
    @Nullable
    private static PhotonBridge.LoopHandle dust;
    @Nullable
    private static Vec3 dustAnchor;
    @Nullable
    private static PhotonBridge.LoopHandle sphereIdle;
    @Nullable
    private static PhotonBridge.LoopHandle boltGlow;
    @Nullable
    private static PhotonBridge.LoopHandle farPillar;
    private static int releaseCloseTicks;

    private ChronoRainField() {}

    /** Cue hook ({@code ChronoStasisFxRows}): swap frozen field → falling release shots. */
    public static void onDischargeCue() {
        releaseCloseTicks = RELEASE_CLOSE_TICKS;
        List<Vec3> anchors = new ArrayList<>(RAIN.size());
        for (RainSlot slot : RAIN.values()) {
            anchors.add(slot.pos());
            PhotonBridge.stopLoop(slot.handle(), true);
        }
        RAIN.clear();
        for (Vec3 pos : anchors) {
            PhotonBridge.spawn(RAIN_RELEASE, pos);
        }
        if (anchors.isEmpty()) {
            // Photon-less until now or first tick inside: still fire one release read.
            Vec3 anchor = ChronoZoneState.anchorPos();
            if (anchor != null) {
                PhotonBridge.spawn(RAIN_RELEASE, anchor);
            }
        }
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            releaseAll();
            return;
        }
        if (minecraft.isPaused()) {
            return;
        }
        Vec3 anchor = ChronoZoneState.anchorPos();
        if (anchor == null || !PhotonBridge.available()) {
            releaseAll();
            return;
        }
        if (releaseCloseTicks > 0) {
            releaseCloseTicks--;
        }
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        double distance = camera.distanceTo(anchor);

        // Far-tell window (§4.5): the shimmer pillar carries the read beyond tracking range.
        boolean wantFar = distance > FAR_MIN && distance < FAR_MAX;
        if (wantFar) {
            if (farPillar == null || !farPillar.alive()) {
                farPillar = PhotonBridge.spawnLoop(FAR_PILLAR, anchor);
            }
        } else if (farPillar != null) {
            PhotonBridge.stopLoop(farPillar, true);
            farPillar = null;
        }

        boolean wantNear = ChronoZoneState.amount() > 0.0F;
        if (!wantNear) {
            releaseNear();
            return;
        }
        tickNearLoops(anchor, camera);
    }

    private static void tickNearLoops(Vec3 anchor, Vec3 camera) {
        // Dust shimmer rides the camera; re-anchor by release + re-ensure (loop law).
        if (dust != null && (!dust.alive()
                || dustAnchor == null || camera.distanceTo(dustAnchor) > DUST_REANCHOR_DIST)) {
            PhotonBridge.stopLoop(dust, true);
            dust = null;
        }
        if (dust == null) {
            dustAnchor = camera;
            dust = PhotonBridge.spawnLoop(DUST_SHIMMER, camera);
        }
        // Fixed set-piece loops: corona at the anchor, glow column at the bolt foot.
        if (sphereIdle == null || !sphereIdle.alive()) {
            sphereIdle = PhotonBridge.spawnLoop(SPHERE_IDLE, anchor);
        }
        if (boltGlow == null || !boltGlow.alive()) {
            // Bolt foot ≈ anchor + local offset, dropped to the bowl floor (anchor sits
            // SPHERE_HOVER over the floor at the center) — ChronoSceneBuilder offsets.
            Vec3 foot = anchor.add(ChronoSceneBuilder.BOLT_DX,
                    -ChronoSceneBuilder.SPHERE_HOVER + 0.5D, ChronoSceneBuilder.BOLT_DZ);
            boltGlow = PhotonBridge.spawnLoop(BOLT_GLOW, foot);
        }
        // Frozen-rain grid (closed while a discharge release plays out).
        if (releaseCloseTicks > 0) {
            releaseRain();
            return;
        }
        reconcileRain(anchor, camera);
    }

    /**
     * Rolling {@value #RAIN_CELL}-block 2×2 grid around the camera, every emitter clamped
     * into the site circle; nearest {@value #MAX_RAIN_HANDLES} cells win, stale cells
     * release (the {@code tickRainSheets} turnover).
     */
    private static void reconcileRain(Vec3 anchor, Vec3 camera) {
        int baseX = Mth.floor(camera.x / RAIN_CELL);
        int baseZ = Mth.floor(camera.z / RAIN_CELL);
        // Emitter height: the rain volume (~18 tall) should straddle the clearing air.
        double emitterY = anchor.y + 4.0D;
        List<long[]> desired = new ArrayList<>(4);
        for (int dx = 0; dx <= 1; dx++) {
            for (int dz = 0; dz <= 1; dz++) {
                int cellX = baseX + dx;
                int cellZ = baseZ + dz;
                desired.add(new long[] {cellKey(cellX, cellZ), cellX, cellZ});
            }
        }
        desired.sort((left, right) -> Double.compare(
                cellDistSq(left, camera), cellDistSq(right, camera)));
        // Release cells that fell out of the desired set or whose loops died.
        Iterator<Map.Entry<Long, RainSlot>> iterator = RAIN.entrySet().iterator();
        while (iterator.hasNext()) {
            Map.Entry<Long, RainSlot> entry = iterator.next();
            boolean keep = entry.getValue().handle().alive();
            if (keep) {
                keep = false;
                for (int i = 0; i < Math.min(MAX_RAIN_HANDLES, desired.size()); i++) {
                    if (desired.get(i)[0] == entry.getKey()) {
                        keep = true;
                        break;
                    }
                }
            }
            if (!keep) {
                PhotonBridge.stopLoop(entry.getValue().handle(), true);
                iterator.remove();
            }
        }
        for (int i = 0; i < Math.min(MAX_RAIN_HANDLES, desired.size()); i++) {
            long[] cell = desired.get(i);
            if (RAIN.containsKey(cell[0])) {
                continue;
            }
            Vec3 pos = clampToSite(anchor,
                    (cell[1] + 0.5D) * RAIN_CELL, emitterY, (cell[2] + 0.5D) * RAIN_CELL);
            PhotonBridge.LoopHandle handle = PhotonBridge.spawnLoop(RAIN_FROZEN, pos);
            if (handle != null) {
                RAIN.put(cell[0], new RainSlot(pos, handle));
            }
        }
    }

    private static double cellDistSq(long[] cell, Vec3 camera) {
        double cx = (cell[1] + 0.5D) * RAIN_CELL;
        double cz = (cell[2] + 0.5D) * RAIN_CELL;
        double dx = cx - camera.x;
        double dz = cz - camera.z;
        return dx * dx + dz * dz;
    }

    private static long cellKey(int cellX, int cellZ) {
        return ((long) cellX << 32) ^ (cellZ & 0xFFFFFFFFL);
    }

    /** Clamps an emitter XZ into the {@link ChronoStasisSite#FX_RADIUS} circle. */
    private static Vec3 clampToSite(Vec3 anchor, double x, double y, double z) {
        double dx = x - anchor.x;
        double dz = z - anchor.z;
        double dist = Math.sqrt(dx * dx + dz * dz);
        double max = ChronoStasisSite.FX_RADIUS - 2.0D;
        if (dist > max && dist > 1.0E-4D) {
            double scale = max / dist;
            return new Vec3(anchor.x + dx * scale, y, anchor.z + dz * scale);
        }
        return new Vec3(x, y, z);
    }

    private static void releaseRain() {
        for (RainSlot slot : RAIN.values()) {
            PhotonBridge.stopLoop(slot.handle(), true);
        }
        RAIN.clear();
    }

    private static void releaseNear() {
        releaseRain();
        if (dust != null) {
            PhotonBridge.stopLoop(dust, true);
            dust = null;
            dustAnchor = null;
        }
        if (sphereIdle != null) {
            PhotonBridge.stopLoop(sphereIdle, true);
            sphereIdle = null;
        }
        if (boltGlow != null) {
            PhotonBridge.stopLoop(boltGlow, true);
            boltGlow = null;
        }
    }

    private static void releaseAll() {
        releaseNear();
        if (farPillar != null) {
            PhotonBridge.stopLoop(farPillar, true);
            farPillar = null;
        }
        releaseCloseTicks = 0;
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        releaseAll();
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
