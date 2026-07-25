package dev.projecteclipse.eclipse.veilfx;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Predicate;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.backrooms.GlitchedWandererEntity;
import dev.projecteclipse.eclipse.entity.GazerEntity;
import dev.projecteclipse.eclipse.entity.TheOtherEntity;
import dev.projecteclipse.eclipse.entity.dungeon.ShadowBoltProjectile;
import dev.projecteclipse.eclipse.entity.pale.PaleSentinelEntity;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * PH-MOBS — the entity-attached Photon LOOP tier (IDEAS-mobs.md §0.2), the ONE owner
 * class the doc calls for: a table of {@code entity class → (fxId, autoRotate, offset,
 * attach predicate, range, nearest-N cap)} walked from a cheap client-tick scan of the
 * tracked entities. No wire traffic at all — attach is client-local, keyed off synced
 * state the client already has ({@code PaleSentinelEntity.isFrozen()}, entity existence,
 * camera distance). No per-mob seams: mob classes stay untouched.
 *
 * <p><b>Loop-tier laws</b> (do not renegotiate):</p>
 * <ul>
 *   <li>{@code allowMulti=false} — {@link PhotonBridge#ensureAttachedFx} keeps exactly one
 *       live runtime per (fx, entity); a re-attach while the loop lives is a silent no-op
 *       (Photon's per-entity CACHE dedup is the bookkeeping).</li>
 *   <li>graceful {@code destroy(false)} on state edges — thaw, range exit, cap eviction
 *       all release via {@link PhotonBridge#stopAttachedFx}{@code (…, force=false)} so
 *       petals/auras fade instead of popping; death/dimension-change hard-cleanup is the
 *       bridge sweep's job (entity executors auto-destroy with their entity).</li>
 *   <li>nearest-N caps + attach ranges per row (with a {@value #RELEASE_MARGIN}-block
 *       release band so a player strafing on the range edge never strobes a loop);
 *       every loop asset carries its own {@code renderer.cull} box and small
 *       {@code maxParticles}.</li>
 *   <li>the whole tier sits behind {@link PhotonBridge#available()} — {@code reducedFx}
 *       or {@code photonFx=false} kills every managed loop wholesale, instantly.</li>
 * </ul>
 *
 * <p><b>Table rows</b> (all budgets from the doc): #7 pale sentinel petal orbit while
 * {@code DATA_FROZEN} (plus the {@code sentinel_alert} one-shot on the freeze RISING
 * edge — the falling edge just fades the orbit), #9 gazer gaze thread ({@code
 * AutoRotate.LOOK}: the executor re-aims the raycast beam along the hood-tracking look
 * every frame), #8 The Other dread aura (24-block gate — attaching at range would defeat
 * the mimicry design), #10 wanderer static shroud ({@code shade:1b} lightmap flicker
 * sync), #6 shadow-bolt ara ribbon (nearest-8; past the cap the vanilla WITCH trail
 * carries it; projectile removal auto-destroys the executor).</p>
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class PhotonMobFx {
    /** Hysteresis: attached loops release only this many blocks PAST their attach range. */
    private static final double RELEASE_MARGIN = 2.0D;

    /**
     * One attach-table row.
     *
     * @param type        client entity class to watch (instanceof match)
     * @param fxId        looping {@code assets/eclipse/fx/<id>.fx}
     * @param autoRotate  {@link PhotonBridge} AutoRotate ordinal
     * @param offset      anchor offset from the entity EYE position (executors re-anchor
     *                    to eye + offset every frame), or {@code null}
     * @param attachRange camera distance gate in blocks (release at + margin)
     * @param maxAttached nearest-N cap for this row
     * @param attachWhen  synced-state predicate (loop lives only while true)
     * @param edgeFx      optional one-shot fired on the predicate's RISING edge
     * @param edgeOffset  eye offset for the edge one-shot
     */
    private record LoopRow(Class<? extends Entity> type, ResourceLocation fxId,
            int autoRotate, @Nullable Vec3 offset, double attachRange, int maxAttached,
            Predicate<Entity> attachWhen, @Nullable ResourceLocation edgeFx,
            @Nullable Vec3 edgeOffset) {}

    private static final Predicate<Entity> ALWAYS = entity -> true;

    private static final List<LoopRow> ROWS = List.of(
            // IDEAS-mobs #7 — frozen-statue petal halo + freeze-flash on the rising edge.
            // Anchor at the statue's center (0.8x2.4 box, eye ~2.0): eye - 0.85.
            new LoopRow(PaleSentinelEntity.class, fx("sentinel_petal_orbit"),
                    PhotonBridge.AUTO_ROTATE_NONE, new Vec3(0.0D, -0.85D, 0.0D),
                    24.0D, 3, entity -> ((PaleSentinelEntity) entity).isFrozen(),
                    fx("sentinel_alert"), new Vec3(0.0D, -0.85D, 0.0D)),
            // IDEAS-mobs #9 — gaze thread + hypnosis rings; LOOK re-aims the raycast beam
            // along the hood-tracking every frame. 20-block intimacy gate: far gazers
            // stay bare silhouettes (the dread IS the understatement).
            new LoopRow(GazerEntity.class, fx("gazer_gaze_beam"),
                    PhotonBridge.AUTO_ROTATE_LOOK, null,
                    20.0D, 2, ALWAYS, null, null),
            // IDEAS-mobs #8 — dread aura. The 24-block gate is mob DESIGN, not budget:
            // at distance the doppelganger must stay indistinguishable from a teammate.
            new LoopRow(TheOtherEntity.class, fx("other_dread_aura"),
                    PhotonBridge.AUTO_ROTATE_NONE, new Vec3(0.0D, -0.6D, 0.0D),
                    24.0D, 3, ALWAYS, null, null),
            // IDEAS-mobs #10 — flicker-synced static shroud (shade:1b does the sync).
            new LoopRow(GlitchedWandererEntity.class, fx("wanderer_static_shroud"),
                    PhotonBridge.AUTO_ROTATE_NONE, new Vec3(0.0D, -0.7D, 0.0D),
                    24.0D, 4, ALWAYS, null, null),
            // IDEAS-mobs #6 — bolt ara ribbon; World-space ara follows the eye anchor
            // each frame (exactly what a homing bolt needs). Nearest-8 guard rail:
            // dungeon spawner rooms re-supply cultists indefinitely.
            new LoopRow(ShadowBoltProjectile.class, fx("shadow_bolt_ribbon"),
                    PhotonBridge.AUTO_ROTATE_NONE, null,
                    48.0D, 8, ALWAYS, null, null));

    /** Per-row attached entities (client main thread only), parallel to {@link #ROWS}. */
    private static final List<Map<Integer, Entity>> ATTACHED = buildPerRow();
    /** Per-row previous predicate value for rising-edge one-shots, parallel to ROWS. */
    private static final List<Map<Integer, Boolean>> EDGE_STATE = buildPerRow();

    private PhotonMobFx() {}

    private static <V> List<Map<Integer, V>> buildPerRow() {
        List<Map<Integer, V>> list = new ArrayList<>(ROWS.size());
        for (int i = 0; i < ROWS.size(); i++) {
            list.add(new HashMap<>());
        }
        return list;
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null || minecraft.player == null) {
            clearBookkeeping(); // executors already died with the level (bridge sweep)
            return;
        }
        if (!PhotonBridge.available()) {
            // reducedFx / photonFx off / photon gone: kill the whole tier wholesale.
            detachAll(true);
            return;
        }
        Vec3 camera = minecraft.player.position();

        // One pass over the tracked entities, bucketed per row (release band included).
        List<List<Entity>> candidates = new ArrayList<>(ROWS.size());
        for (int i = 0; i < ROWS.size(); i++) {
            candidates.add(new ArrayList<>());
        }
        for (Entity entity : level.entitiesForRendering()) {
            if (!entity.isAlive()) {
                continue;
            }
            for (int i = 0; i < ROWS.size(); i++) {
                LoopRow row = ROWS.get(i);
                if (row.type().isInstance(entity)) {
                    double release = row.attachRange() + RELEASE_MARGIN;
                    if (entity.distanceToSqr(camera) <= release * release) {
                        candidates.get(i).add(entity);
                    }
                }
            }
        }

        for (int i = 0; i < ROWS.size(); i++) {
            tickRow(ROWS.get(i), candidates.get(i), ATTACHED.get(i), EDGE_STATE.get(i), camera);
        }
    }

    private static void tickRow(LoopRow row, List<Entity> candidates,
            Map<Integer, Entity> attached, Map<Integer, Boolean> edgeState, Vec3 camera) {
        // Rising-edge one-shots (sentinel freeze flash). Entities first seen while the
        // flag is ALREADY true get no flash — the edge happened before we could see it.
        if (row.edgeFx() != null) {
            Set<Integer> seen = new HashSet<>(candidates.size());
            double rangeSq = row.attachRange() * row.attachRange();
            for (Entity entity : candidates) {
                boolean now = row.attachWhen().test(entity);
                Boolean was = edgeState.put(entity.getId(), now);
                seen.add(entity.getId());
                if (now && Boolean.FALSE.equals(was)
                        && entity.distanceToSqr(camera) <= rangeSq) {
                    PhotonBridge.spawnOnEntity(row.edgeFx(), entity,
                            PhotonBridge.AUTO_ROTATE_NONE, row.edgeOffset());
                }
            }
            edgeState.keySet().retainAll(seen);
        }

        // Eligibility + nearest-N: sort by camera distance, keep the closest cap-many
        // that pass the predicate and their (hysteresis-aware) range gate.
        candidates.sort((left, right) -> Double.compare(
                left.distanceToSqr(camera), right.distanceToSqr(camera)));
        Map<Integer, Entity> want = new HashMap<>();
        for (Entity entity : candidates) {
            if (want.size() >= row.maxAttached()) {
                break;
            }
            double gate = attached.containsKey(entity.getId())
                    ? row.attachRange() + RELEASE_MARGIN : row.attachRange();
            if (entity.distanceToSqr(camera) > gate * gate
                    || !row.attachWhen().test(entity)) {
                continue;
            }
            want.put(entity.getId(), entity);
        }

        // State edges (thaw / range exit / cap eviction / gone): graceful destroy(false).
        Iterator<Map.Entry<Integer, Entity>> iterator = attached.entrySet().iterator();
        while (iterator.hasNext()) {
            Map.Entry<Integer, Entity> entry = iterator.next();
            if (!want.containsKey(entry.getKey())) {
                PhotonBridge.stopAttachedFx(row.fxId(), entry.getValue(), false);
                iterator.remove();
            }
        }

        // Keepalive: while a runtime is live this is a cheap LIVE-scan no-op (CACHE
        // dedup = bookkeeping); it also self-heals after entity untrack/re-track. The
        // fresh entity object replaces any stale ref from a previous track cycle.
        for (Entity entity : want.values()) {
            if (PhotonBridge.ensureAttachedFx(row.fxId(), entity, row.autoRotate(), row.offset())) {
                attached.put(entity.getId(), entity);
            } else {
                attached.remove(entity.getId()); // refused (budget/missing) — retry next tick
            }
        }
    }

    /** Stops every managed loop ({@code force} = instant kill) and forgets everything. */
    private static void detachAll(boolean force) {
        for (int i = 0; i < ROWS.size(); i++) {
            Map<Integer, Entity> attached = ATTACHED.get(i);
            if (!attached.isEmpty()) {
                for (Entity entity : attached.values()) {
                    PhotonBridge.stopAttachedFx(ROWS.get(i).fxId(), entity, force);
                }
                attached.clear();
            }
            EDGE_STATE.get(i).clear();
        }
    }

    /** Bookkeeping-only reset (level gone: the bridge already destroyed the executors). */
    private static void clearBookkeeping() {
        for (int i = 0; i < ROWS.size(); i++) {
            ATTACHED.get(i).clear();
            EDGE_STATE.get(i).clear();
        }
    }

    /** Live managed loops right now (dev/QA introspection). */
    public static int attachedCount() {
        int count = 0;
        for (Map<Integer, Entity> map : ATTACHED) {
            count += map.size();
        }
        return count;
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        clearBookkeeping(); // PhotonBridge.destroyAll force-kills the executors
    }
}
