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
 * FX-WAVE-13 team B7 {@link PhotonFxRegistry} row registrar — one cutscene beat per
 * sequence class, filling the census §5 "weakest beat" gaps. Assets are authored
 * programmatically by {@code tools/photon/wave13_cutscene_fx.py} (fxlib) into
 * {@code assets/eclipse/fx/beat_*.fx}; re-run the script instead of hand-editing the
 * gzip-NBT. Beat timings + trigger ticks:
 * {@code docs/plans_v3/session_0730/B7_CUTSCENE_REPORT.md}.
 *
 * <p>Every row here is Photon-only garnish ({@code Mode.LAYER}, Quasar leg
 * {@code null}): each sequence's pre-existing server-particle and sound baseline was
 * the photon-less read BEFORE these beats existed and keeps running unchanged
 * underneath, so there is nothing to REPLACE. Cue ids follow the CreditsSequence
 * precedent — both sides derive the same {@code FxCues.cue("beat_…")} id (the server
 * sequence holds a private constant, this registrar re-derives it), so
 * {@code FxCues.java} stays untouched.</p>
 *
 * <p>The three aimed rows carry a yaw in the payload's {@code a} float and use the
 * house yaw leg ({@code 180° − a} about Y, the {@code FerrymanFinaleFxRows}
 * convention): the flyover shadow runs its local −Z radially OUTWARD from the growth
 * front, the ember tear crawls its local −Z away from the crater, and the key glyphs
 * stand in the gate plane. The End-Arrival row re-cues the existing
 * {@code eclipse:end_crack_bleed} asset through a default-spawn leg with
 * {@code allowMulti=true} — deliberately NOT {@code FxCues.CUE_END_CRACK}'s row, whose
 * leg suppresses the structure glow via {@code RiftFx} (a side effect the CHARGE
 * countdown must not trigger).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class CutsceneBeatFxRows {
    /** Intro FLIGHT/APPROACH wind-shear sustain (660t, re-fired every 220t; dedup absorbs mid-run sends). */
    public static final ResourceLocation CUE_INTRO_WINDSHEAR = FxCues.cue("beat_intro_windshear");
    /** Expansion FLYOVER distant monolith flare (70t one-shot per frontier anchor). */
    public static final ResourceLocation CUE_MONOLITH_PULSE = FxCues.cue("beat_monolith_pulse");
    /** Expansion FLYOVER ground shadow run (110t; a = outward yaw of the growth front). */
    public static final ResourceLocation CUE_FLYOVER_SHADOW = FxCues.cue("beat_flyover_shadow");
    /** Nether AFTERMATH first ember tear (140t; a = crawl yaw away from the crater). */
    public static final ResourceLocation CUE_NETHER_EMBER_TEAR = FxCues.cue("beat_nether_ember_tear");
    /** End-Arrival CHARGE sky-crack countdown (re-cues {@code end_crack_bleed}, multi-instance). */
    public static final ResourceLocation CUE_ENDARRIVAL_CRACK = FxCues.cue("beat_endarrival_crack");
    /** Ferryman finale UNLOCK key-photon (60t; a = gate yaw; clicks at asset t=8/22/36). */
    public static final ResourceLocation CUE_FINALE_KEYGLYPHS = FxCues.cue("beat_finale_keyglyphs");
    /** Credits WHITEOUT→BEACH afterglow bridge (200t = the full 10 s, crossfade baked in). */
    public static final ResourceLocation CUE_CREDITS_AFTERGLOW = FxCues.cue("beat_credits_afterglow");

    private CutsceneBeatFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // B7-1 — Intro: streamers condensing onto the vortex column through the long
        // glide. Position-anchored at the vortex base; escalation lives in the asset's
        // emissionRate curve (world-anchored ⇒ distanceRate would never accumulate).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_INTRO_WINDSHEAR,
                fx("beat_intro_windshear"),
                null,
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // B7-2a — Expansion flyover: far monolith silhouettes pulse as the camera skims.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_MONOLITH_PULSE,
                fx("beat_monolith_pulse"),
                null,
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // B7-2b — Expansion flyover: the growth front's shadow band races outward under
        // the skim camera (a = outward yaw; asset marches local −Z).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_FLYOVER_SHADOW,
                fx("beat_flyover_shadow"),
                null,
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false,
                CutsceneBeatFxRows::yawAlignedLeg));
        // B7-3 — Nether aftermath: the first ember tear creeps away from the crater rim
        // (a = crawl yaw); its baked t=30 aftershock ring lands on the server's RUMBLE.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_NETHER_EMBER_TEAR,
                fx("beat_nether_ember_tear"),
                null,
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false,
                CutsceneBeatFxRows::yawAlignedLeg));
        // B7-4 — End-Arrival charge: end_crack_bleed instances ignite on the countdown
        // ladder. allowMulti: successive cracks overlap in time and may land close
        // enough to share an anchor — Photon's same-anchor dedup must not eat the beat.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_ENDARRIVAL_CRACK,
                fx("end_crack_bleed"),
                null,
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false,
                CutsceneBeatFxRows::multiInstanceLeg));
        // B7-5 — Ferryman finale unlock: three glyph click-beats + the veil indraw,
        // standing in the gate plane (a = gate yaw).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_FINALE_KEYGLYPHS,
                fx("beat_finale_keyglyphs"),
                null,
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false,
                CutsceneBeatFxRows::yawAlignedLeg));
        // B7-6 — Credits bridge: white ash motes trickle into the beach stillness for
        // the 10 s between whiteout release and the first beach beat.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_CREDITS_AFTERGLOW,
                fx("beat_credits_afterglow"),
                null,
                FxBudget.Channel.SEQUENCE,
                PhotonFxRegistry.Mode.LAYER,
                false));
    }

    /**
     * House yaw-aligned Photon leg: the payload's {@code a} float carries a yaw in
     * degrees; rotate the executor by {@code 180° − a} about Y so the asset's local −Z
     * aligns with that facing (the {@code FerrymanFinaleFxRows.yawAlignedLeg} /
     * {@code BossPhotonFxRows.wardenEyeLaser} JOML derivation).
     */
    private static boolean yawAlignedLeg(ResourceLocation photonFx, Vec3 pos,
            @javax.annotation.Nullable Entity entity, float a, float b) {
        return PhotonBridge.spawn(photonFx, pos,
                PhotonBridge.SpawnOptions.DEFAULT.withRotationDeg(0.0D, 180.0D - a, 0.0D));
    }

    /**
     * Default spawn with {@code allowMulti=true}: the CHARGE countdown fires the same
     * fx id up to six times inside 140 ticks — every instance must live, even if two
     * land on (nearly) the same anchor.
     */
    private static boolean multiInstanceLeg(ResourceLocation photonFx, Vec3 pos,
            @javax.annotation.Nullable Entity entity, float a, float b) {
        return PhotonBridge.spawn(photonFx, pos,
                PhotonBridge.SpawnOptions.DEFAULT.withAllowMulti(true));
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
