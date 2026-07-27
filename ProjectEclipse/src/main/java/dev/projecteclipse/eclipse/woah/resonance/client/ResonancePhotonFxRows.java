package dev.projecteclipse.eclipse.woah.resonance.client;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry;
import dev.projecteclipse.eclipse.woah.resonance.ResonanceCues;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * WOAH-04 {@link PhotonFxRegistry} row registrar (§4.3) — the four one-shot cue rows
 * (STRIKE / PULSE / FAIL / FINALE), all {@code Mode.LAYER} over simple END_ROD/glow
 * Quasar baselines ({@code assets/eclipse/quasar/emitters/resonance_*}) so the puzzle
 * telegraphs stay readable on photon-less clients (the degradation law in the
 * {@code PhotonFxRegistry} javadoc). Assets are authored programmatically by
 * {@code tools/photon/resonance_fx.py} (fxlib) — re-run the script instead of
 * hand-editing the gzip-NBT.
 *
 * <p>The per-crystal aura / per-edge bahn / far-LOD loops deliberately have NO rows
 * here: those are WINDOWED loops owned by {@link ResonanceFieldFx}'s raw handles
 * (the {@code STORM_CROWN_HALO} "not a registry row" law).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class ResonancePhotonFxRows {
    private ResonancePhotonFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // Strike burst on a crystal top (a = toneIndex, b = 0 player / 1 teach). Custom
        // leg for allowMulti — melody volleys land < 10 t apart on the SAME crystal
        // during TEACH, dedup would eat them (the CUE_GLITCH_POP law). The leg also
        // drives the near-field post shimmer BEFORE the spawn so photon-less clients
        // keep the read.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                ResonanceCues.CUE_RESONANCE_STRIKE,
                fx("resonance_strike_burst"),
                quasar("resonance_strike"),
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                ResonancePhotonFxRows::strikeLeg));
        // Cascade hop bead: pos = SOURCE crystal top, a = yaw toward the target (deg),
        // b = hop length in blocks. The asset glides one block along local −Z, so the
        // executor rotates 180° − a about Y (the FerrymanFinaleFxRows.yawAlignedLeg
        // JOML derivation) and stretches Z by the hop length.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                ResonanceCues.CUE_RESONANCE_PULSE,
                fx("resonance_pulse_hop"),
                quasar("resonance_pulse"),
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                ResonancePhotonFxRows::pulseLeg));
        // Fail sting at the altar — GLITCH-palette dark pass + red ring flicker.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                ResonanceCues.CUE_RESONANCE_FAIL,
                fx("resonance_fail_flicker"),
                quasar("resonance_fail"),
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // Finale mega-cue at the altar: 120-block light column + glitter rain + ground
        // shock ring + crown starburst, pacing staged INSIDE the asset (the
        // CUE_DAWN_TOLL principle). The leg feeds the finale shimmer envelope.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                ResonanceCues.CUE_RESONANCE_FINALE,
                fx("resonance_finale_column"),
                quasar("resonance_finale"),
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                ResonancePhotonFxRows::finaleLeg));
    }

    private static boolean strikeLeg(ResourceLocation photonFx, Vec3 pos,
            @javax.annotation.Nullable Entity entity, float a, float b) {
        ResonanceFieldFx.onStrikeCue(pos);
        return PhotonBridge.spawn(photonFx, pos,
                PhotonBridge.SpawnOptions.DEFAULT.withAllowMulti(true));
    }

    private static boolean pulseLeg(ResourceLocation photonFx, Vec3 pos,
            @javax.annotation.Nullable Entity entity, float a, float b) {
        double hopLength = Math.max(1.0D, b);
        return PhotonBridge.spawn(photonFx, pos,
                PhotonBridge.SpawnOptions.DEFAULT
                        .withRotationDeg(0.0D, 180.0D - a, 0.0D)
                        .withScale(1.0D, 1.0D, hopLength)
                        .withAllowMulti(true));
    }

    private static boolean finaleLeg(ResourceLocation photonFx, Vec3 pos,
            @javax.annotation.Nullable Entity entity, float a, float b) {
        ResonanceFieldFx.onFinaleCue(pos);
        return PhotonBridge.spawn(photonFx, pos);
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }

    private static ResourceLocation quasar(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
