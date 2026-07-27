package dev.projecteclipse.eclipse.woah.chronostasis.client;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry;
import dev.projecteclipse.eclipse.woah.chronostasis.ChronoCues;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * WOAH-03 {@link PhotonFxRegistry} row registrar (the {@code FerrymanFinaleFxRows}
 * pattern). Assets are authored programmatically by {@code tools/photon/chrono_fx.py}
 * (fxlib) into {@code assets/eclipse/fx/chrono_*.fx} — re-run the script instead of
 * hand-editing the gzip-NBT.
 *
 * <p>Both legs ALSO arm the client-side phase windows in {@link ChronoZoneState} /
 * {@link ChronoRainField} — the dispatch calls the Photon leg unconditionally (all
 * availability guards live inside {@link PhotonBridge}), so the window arming works on
 * photon-less clients too. Quasar fallbacks are {@code null} on purpose: both cues are
 * NEW garnish on top of display-scene + vanilla-bolt + sound reads that carry the moment
 * by themselves (FxCues baseline law — pre-row baseline was nothing).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class ChronoStasisFxRows {

    private ChronoStasisFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // Time-jolt pulse: a ≥ 1 = the real jolt (expanding ring + sparks, and the 60 t
        // client window arms); a < 0 = the scaled-down dust-puff reuse for tower-debris
        // impacts during DISCHARGE (no window).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                ChronoCues.CUE_CHRONO_JOLT,
                fx("chrono_jolt_pulse"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                ChronoStasisFxRows::joltLeg));
        // Discharge burst: arms the 230 t discharge window (grade white kick, tick-sound
        // mute, frozen-rain → release swap) and layers the shockwave burst.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                ChronoCues.CUE_CHRONO_DISCHARGE,
                fx("chrono_discharge_burst"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                ChronoStasisFxRows::dischargeLeg));
    }

    private static boolean joltLeg(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        ChronoZoneState.onJoltCue(a);
        if (a < 0.0F) {
            // Debris-impact dust puff: same asset, scaled down and ground-hugging.
            return PhotonBridge.spawn(photonFx, pos,
                    PhotonBridge.SpawnOptions.DEFAULT.withScale(0.45D, 0.25D, 0.45D));
        }
        return PhotonBridge.spawn(photonFx, pos);
    }

    private static boolean dischargeLeg(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        ChronoZoneState.onDischargeCue();
        ChronoRainField.onDischargeCue();
        return PhotonBridge.spawn(photonFx, pos);
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
