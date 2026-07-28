package dev.projecteclipse.eclipse.veilfx;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * PH-BOSS-B's {@link PhotonFxRegistry} row registrar ({@link PhotonFxRows} reference
 * pattern) — the Fog Tyrant + Rift Warden concepts from
 * {@code docs/plans_v3/plans_v5/photon/IDEAS-boss.md} (#2, #6, #3, #7). All rows are
 * one-shot {@code Mode.LAYER}: photon-less clients (and {@code reducedFx}) keep the
 * shipped vanilla/Quasar beats bit-identical; the Photon leg is uncharged garnish behind
 * {@code PhotonBridge}'s full guard chain and executor budget.
 *
 * <p>Assets are authored programmatically — {@code tools/photon/boss_b_fx.py} (fxlib) is
 * the committed source for the five {@code assets/eclipse/fx/boss/*.fx} blobs and the
 * three {@code beam_core/glitch_shard/noise_strip} particle textures.</p>
 *
 * <p>The warden eye-laser row is special-cased: its cue carries the warden's yaw in the
 * payload's free {@code a} float, and the generic {@code dispatch(id, pos)} tail cannot
 * apply a rotation — {@code FxPayloads.handleFxEvent} routes that cue to
 * {@link #wardenEyeLaser} instead, which resolves the SAME registered row (single source
 * of truth for legs/mode/budget) and adds the {@code SpawnOptions} yaw rotation. The row
 * has no Quasar fallback by design (IDEAS-boss #3: no matching Quasar shape — the shipped
 * WITCH-boil + resonate telegraph remains the base layer on every client).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class BossPhotonFxRows {
    private BossPhotonFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // IDEAS-boss #2 — C8 thunderclap death implosion (two-asset delivery: the debris
        // emitter's FirstCollision sub-emitters reference eclipse:boss/fog_debris_puff).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_TYRANT_DEATH_IMPLOSION,
                fx("boss/tyrant_death_implosion"),
                fx("boss_slam"),
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // IDEAS-boss #6 — blind-squall HDR flash over the shipped CLOUD rings.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_TYRANT_SQUALL,
                fx("boss/tyrant_blind_burst"),
                fx("boss_slam"),
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // IDEAS-boss #3 — volley-telegraph eye laser (yaw-aimed via wardenEyeLaser; null
        // Quasar leg per the doc row: the WITCH boil stays the photon-less base layer).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_WARDEN_VOLLEY_TELEGRAPH,
                fx("boss/warden_eye_laser"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // IDEAS-boss #7 — stagger glitch-shard orbit (REVERSE_SUB/MAX blend passes);
        // border_glitch is the house glitch vocabulary fallback.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_WARDEN_STAGGER,
                fx("boss/warden_glitch_orbit"),
                fx("border_glitch"),
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // PH-IMPROVE-2 (IDEAS-boss #10) — P3 fog-arm mesh tendrils: model particles along
        // the eclipse:item/fog_tendril claw (backlog_fx.py asset, 200t runtime). ENTITY
        // lane — the default leg's spawnOnEntity rides the stalking boss and entity death
        // auto-kills the rig (the C8 death implosion never fights a live arm). The server
        // re-sends the cue every 100t during P3; each re-send while the executor lives is
        // a silent dedup no-op, so the sustain is seamless. Null Quasar leg per the doc
        // row: mesh emission has no Quasar analogue — the shipped P3 fog-step vanilla
        // baseline stays untouched on photon-less clients.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_TYRANT_FOG_ARMS,
                fx("boss/tyrant_fog_arms"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // F-081 — tyrant statue idle aura (ember orbit + crown sparks, statue_fx.py
        // asset, 200t runtime). NOT a loop row: the server re-sends the cue every 40t
        // while the lair is armed (TyrantStatue.ensureArmed) and 40 divides 200, so
        // each mid-run re-send is a silent dedup no-op — the CUE_TYRANT_FOG_ARMS
        // sustain law, position lane. Null Quasar leg: the server-stamped ELECTRIC_SPARK
        // spiral IS the photon-less baseline (LAYER law), no Quasar analogue needed.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_TYRANT_STATUE_IDLE,
                fx("boss/tyrant_statue_idle"),
                null,
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // FX-Wave-10 — storm-step beats (tyrant_step_fx.py assets). LAYER law: the
        // shipped fogBurstFx CLOUD puffs remain the photon-less baseline on both ends;
        // null Quasar leg — the vanilla puffs ARE that fallback.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_TYRANT_STEP_OUT,
                fx("boss/tyrant_step_out"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false));
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_TYRANT_STEP_IN,
                fx("boss/tyrant_step_in"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false));
    }

    /**
     * {@code FxPayloads.handleFxEvent} branch for {@code CUE_WARDEN_VOLLEY_TELEGRAPH}
     * (client main thread): the beam asset fires along local −Z, so rotate the executor by
     * {@code 180° − yaw} about Y to align −Z with the warden's facing (Minecraft forward
     * for yaw φ is (−sin φ, 0, cos φ); JOML rotationY(θ) maps −Z to (−sin θ, 0, −cos θ) ⇒
     * θ = 180° − φ). Mirrors {@link PhotonFxRegistry#dispatch} semantics over the
     * registered row so mode/fallback/budget stay table-driven.
     *
     * @param pos    the warden's eye position (payload pos)
     * @param yawDeg the warden's Y rotation in degrees (payload {@code a})
     */
    public static void wardenEyeLaser(Vec3 pos, float yawDeg) {
        PhotonFxRegistry.Row row = PhotonFxRegistry.row(FxCues.CUE_WARDEN_VOLLEY_TELEGRAPH);
        if (row == null) {
            return;
        }
        boolean photonPlayed = PhotonBridge.spawn(row.photonFx(), pos,
                PhotonBridge.SpawnOptions.DEFAULT.withRotationDeg(0.0D, 180.0D - yawDeg, 0.0D));
        if (row.quasarEmitter() != null
                && (row.mode() == PhotonFxRegistry.Mode.LAYER || !photonPlayed)) {
            QuasarSpawner.spawnOrFallback(row.quasarEmitter(), pos, row.channel());
        }
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
