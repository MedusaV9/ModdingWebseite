package dev.projecteclipse.eclipse.veilfx;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * PH-EVENTS' {@link PhotonFxRegistry} row registrar ({@link PhotonFxRows} reference
 * pattern) — the event-sequence one-shots from
 * {@code docs/plans_v3/plans_v5/photon/IDEAS-events.md} (#2, #6, #3). All rows are
 * {@code Mode.LAYER} with a {@code null} Quasar leg (legal: each cue is NEW — the
 * pre-row baseline the sequences already broadcast keeps playing on every client,
 * photon-less or not). Assets are authored programmatically — {@code tools/photon/
 * events_fx.py} (fxlib) is the committed source.
 *
 * <p>Not here by design: the intro BURST ring (#1) rides the {@code FX_SHOCKWAVE
 * (1.0, 50)} giant signature client-locally in {@code FxPayloads.handleFxEvent}, and the
 * portal iris/loops (#5) live in {@code RiftFx.openRift}'s style branch — both are
 * sanctioned non-registry seams (INTEGRATION.md §3.5 law 4). Supply/flyover contrails
 * (#9) are PH-WORLD's.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class EventsPhotonFxRows {
    /**
     * IDEAS-events #2: the credits ladder ramps intensity 0.6→1.0 — mapped 1:1 onto the
     * executor scale (clamped to the ladder's own band; a missing/zero {@code a} plays
     * unscaled). Ladder stagger stays server-side: the strikes are already 12t apart.
     */
    private static final float STRIKE_SCALE_MIN = 0.6F;
    private static final float STRIKE_SCALE_MAX = 1.0F;
    /** IDEAS-events #3: the mushroom is authored at unit footprint — scale = footprint·0.05. */
    private static final float SLAM_SCALE_PER_FOOTPRINT = 0.05F;
    /** Footprint scale clamp (≈ footprints 8..64) so a bad payload can never grow absurd. */
    private static final float SLAM_SCALE_MIN = 0.4F;
    private static final float SLAM_SCALE_MAX = 3.2F;

    private EventsPhotonFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // IDEAS-events #2 — per-strike volumetric beam of the credits t=420 lightning
        // ladder (CUE_CREDITS_STRIKE, a = intensity → scale). Deliberately its own cue,
        // never a leg on FX_LIGHTNING_STRIKE (that id also fires at 15t cadence during
        // the intro's LIGHTNING hold — frequency law).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_CREDITS_STRIKE,
                fx("credits_strike_beam"),
                null,
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false,
                EventsPhotonFxRows::strikeBeam));
        // IDEAS-events #6 — DOOMSDAY confetti mesh shards at the credits t=650 burst.
        // Default leg (plain spawn at runnersCenter); every HDR glint in the asset dies
        // ≤ t=658 so the t=676 correction card gets its 500 ms of stillness.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_CREDITS_BURST,
                fx("credits_confetti_burst"),
                null,
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // IDEAS-events #3 — structure-slam dust mushroom with Collision sub-emitters
        // (CUE_STRUCTURE_SLAM, a = footprint → scale). Slams ride ExpansionSequence's
        // ≥50t BEAT_SPACING_TICKS cadence, so this can never become a high-frequency cue.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_STRUCTURE_SLAM,
                fx("structure_slam_mushroom"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                EventsPhotonFxRows::slamMushroom));
        // PH-IMPROVE-2 (IDEAS-events #8) — intro SUNRISE god-ray ribbons: 4 staggered ara
        // ribbons climbing sunward off the island rim + rim motes, one 230t one-shot at the
        // altar anchor (backlog_fx.py asset). Default position leg; fires once per intro
        // (plus SUNRISE replays), so SEQUENCE-grade. Null Quasar leg is legal — the cue is
        // NEW and photon-less clients keep the shipped ENDING grade + warm bloom baseline.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_INTRO_SUNRISE,
                fx("intro_sunrise_rays"),
                null,
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false));
    }

    /** {@code CUE_CREDITS_STRIKE} Photon leg: intensity ({@code a}) → executor scale. */
    private static boolean strikeBeam(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        float scale = a <= 0.0F ? 1.0F : Mth.clamp(a, STRIKE_SCALE_MIN, STRIKE_SCALE_MAX);
        return PhotonBridge.spawn(photonFx, pos,
                PhotonBridge.SpawnOptions.DEFAULT.withScale(scale, scale, scale));
    }

    /**
     * {@code CUE_STRUCTURE_SLAM} Photon leg: footprint ({@code a}) → executor scale.
     * {@code allowMulti} is required — bursty stages can slam two nearby sites whose
     * positions round to the same BlockPos while the first mushroom (30–50t clods) is
     * still alive; the default dedup would silently eat the second slam.
     */
    private static boolean slamMushroom(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        float scale = a <= 0.0F ? 1.0F
                : Mth.clamp(a * SLAM_SCALE_PER_FOOTPRINT, SLAM_SCALE_MIN, SLAM_SCALE_MAX);
        return PhotonBridge.spawn(photonFx, pos,
                PhotonBridge.SpawnOptions.DEFAULT.withScale(scale, scale, scale)
                        .withAllowMulti(true));
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
