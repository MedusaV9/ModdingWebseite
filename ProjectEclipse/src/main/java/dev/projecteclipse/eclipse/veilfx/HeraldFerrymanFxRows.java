package dev.projecteclipse.eclipse.veilfx;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * PH-BOSS-A's {@link PhotonFxRegistry} row registrar ({@link PhotonFxRows} reference
 * pattern) — the Herald + Ferryman concepts from
 * {@code docs/plans_v3/plans_v5/photon/IDEAS-boss.md} (#1, #4, #8, #9). The roar and
 * oar-sweep rows are one-shot {@code Mode.LAYER} garnish; the lantern-swarm and
 * kneel-corona rows are {@code Mode.REPLACE} (PHOTON-QUALITY §6 retirement — running
 * both was double-vision: {@code soul_leak} duplicates the Quasar mote read 1:1).
 * Photon-less clients (and {@code reducedFx}) keep the shipped vanilla/Quasar beats
 * bit-identical on every row: REPLACE re-enters the Quasar leg whenever the Photon
 * spawn did not play, and the Photon leg stays uncharged behind {@code PhotonBridge}'s
 * full guard chain and executor budget.
 *
 * <p>Assets are authored programmatically — {@code tools/photon/fx_boss_herald_ferryman.py}
 * (fxlib) is the committed source for the five {@code assets/eclipse/fx/boss/*.fx} blobs
 * and the {@code ring_soft} particle texture.</p>
 *
 * <p>The oar-sweep row carries the Ferryman's yaw in the payload's free {@code a} float;
 * its custom {@link PhotonFxRegistry.PhotonLeg} rotates the executor so the function-shape
 * half-circle aligns with the boss's forward (the same JOML derivation as
 * {@link BossPhotonFxRows#wardenEyeLaser}: the arc bulges toward local −Z, so rotate by
 * {@code 180° − yaw} about Y).</p>
 *
 * <p>Fallback deviation from the IDEAS-boss doc rows: the doc names {@code limbo_motes}
 * as the lantern-swarm/kneel-corona Quasar leg, but that emitter is {@code loop: true} and
 * {@code QuasarSpawner.spawnOrFallback} keeps no handle to position-anchored loops (Veil
 * never expires them — every re-fire would leak an immortal emitter). Both rows use small
 * NON-looping teal-mote emitters instead: {@code ferry_lantern_swarm} is a one-shot 30t
 * burst; {@code ferry_kneel_corona} is a 20t puff whose 20t payload re-fire cadence
 * sustains the read for the whole crew phase (1 AMBIENT spawn per budget window).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class HeraldFerrymanFxRows {
    /**
     * IDEAS-boss #5 — Herald shard ara-ribbon (direct client seam, not a registry row: the
     * trail is not payload-driven, same exemption as {@code RiftFx.openRift}). Consumed by
     * {@link #heraldShardTrail} from {@code HeraldShardProjectile.tick()}'s client branch.
     */
    public static final ResourceLocation HERALD_SHARD_TRAIL = fx("boss/herald_shard_trail");

    /**
     * IDEAS-boss #5 belt-and-braces gate: skip new shard ribbons when this many
     * entity-attached executors are already alive (3 ribbons per volley is the design
     * budget; the cap only trips when other entity effects pile up).
     */
    private static final int MAX_ENTITY_EXECUTORS_FOR_TRAIL = 6;

    private HeraldFerrymanFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // IDEAS-boss #1 — shared HDR roar ring + column + sparks over the shipped
        // boss_slam burst (Herald summon/P3 break, Ferryman summon).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_BOSS_ROAR,
                fx("boss/roar_shockwave"),
                fx("boss_slam"),
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // IDEAS-boss #4 — soul-lantern model swarm at the crew-phase kneel; the fallback
        // is a one-shot teal soul-mote burst (see the class doc for the limbo_motes swap).
        // REPLACE (PHOTON-QUALITY §6): the Model lanterns supersede the mote swarm and the
        // photon file's soul_leak emitter already duplicates the Quasar mote read.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_FERRY_LANTERN_SWARM,
                fx("boss/ferry_lantern_swarm"),
                fx("ferry_lantern_swarm"),
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.REPLACE,
                false));
        // IDEAS-boss #8 — oar water-tear arc, yaw-aimed via the custom Photon leg
        // (a = the Ferryman's yaw in degrees); glut_welle_ring is the house
        // expanding-wave fallback, vanilla SWEEP_ATTACK stays underneath.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_FERRY_OAR_SWEEP,
                fx("boss/ferry_oar_tear"),
                fx("glut_welle_ring"),
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                HeraldFerrymanFxRows::oarTearLeg));
        // IDEAS-boss #9 — kneel corona sustain (100t one-shot re-fired on the 20t crew
        // cadence; Photon dedups re-sends silently while the runtime lives).
        // REPLACE (PHOTON-QUALITY §6): 1:1 name/read overlap — corona_halo covers the
        // Quasar mote puff and photon adds the invuln dome on top.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_FERRY_KNEEL_CORONA,
                fx("boss/ferry_kneel_corona"),
                fx("ferry_kneel_corona"),
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.REPLACE,
                false));
    }

    /**
     * Custom Photon leg for {@code CUE_FERRY_OAR_SWEEP}: the tear arc's function shape
     * sweeps {@code x = −4.5·cos(t·π), z = −4.5·sin(t·π)} — bulge at local −Z — so rotate
     * the executor by {@code 180° − yaw} about Y to align −Z with the boss's facing
     * (Minecraft forward for yaw φ is (−sin φ, 0, cos φ); JOML rotationY(θ) maps −Z to
     * (−sin θ, 0, −cos θ) ⇒ θ = 180° − φ — the {@link BossPhotonFxRows#wardenEyeLaser}
     * derivation).
     */
    private static boolean oarTearLeg(ResourceLocation photonFx, Vec3 pos,
            @javax.annotation.Nullable Entity entity, float a, float b) {
        return PhotonBridge.spawn(photonFx, pos,
                PhotonBridge.SpawnOptions.DEFAULT.withRotationDeg(0.0D, 180.0D - a, 0.0D));
    }

    /**
     * IDEAS-boss #5 client seam ({@code HeraldShardProjectile.tick()}, client branch): one
     * looping ara ribbon riding the shard ({@code AutoRotate.NONE}; loop is safe — the
     * runtime is entity-bound and Photon auto-destroys it when the shard shatters).
     * Photon's per-entity CACHE dedup absorbs repeat calls; the vanilla END_ROD breadcrumb
     * in the same branch stays the photon-less baseline (LAYER semantics in code).
     *
     * @return {@code true} once a ribbon is live (or dedup'd) for this shard — callers stop
     *         retrying; {@code false} = refused/unavailable, retry next tick is free
     */
    public static boolean heraldShardTrail(Entity shard) {
        // >= : skip when the cap is already reached (a 7th executor slipped past the old
        // strict-greater check — EVAL-V6-PHOTON §7.6).
        if (PhotonBridge.liveEntityExecutors() >= MAX_ENTITY_EXECUTORS_FOR_TRAIL) {
            return false;
        }
        return PhotonBridge.spawnOnEntity(HERALD_SHARD_TRAIL, shard,
                PhotonBridge.AUTO_ROTATE_NONE, (Vec3) null);
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
