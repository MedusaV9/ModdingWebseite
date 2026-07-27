package dev.projecteclipse.eclipse.woah.gravityrift.client;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry;
import dev.projecteclipse.eclipse.woah.gravityrift.GravityRiftCues;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * WOAH-02 {@link PhotonFxRegistry} row registrar (plan §4.3) — the
 * {@code FerrymanFinaleFxRows}/{@code ResonancePhotonFxRows} pattern: self-registering
 * on {@link FMLClientSetupEvent}, {@code Mode.LAYER} over existing Quasar baselines so
 * every telegraph stays readable on photon-less clients (the registry's degradation
 * law). Photon assets are authored programmatically by
 * {@code tools/photon/woah_gravity_fx.py} (fxlib) — re-run the script instead of
 * hand-editing the gzip-NBT.
 *
 * <p>The two LOOP rows ({@code MOTES}/{@code COLUMN}) are ensured/released by
 * {@link GravityRiftAmbience}'s hysteresis windows via
 * {@code PhotonFxRegistry.ensureLoop} — never spawned as one-shots.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class GravityRiftFxRows {
    private GravityRiftFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // Pulse (staged telegraph→beat inside the asset; arrives 30 t pre-beat). The
        // shared quasar ring is the photon-less fallback read.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                GravityRiftCues.CUE_GRAVITY_PULSE,
                fx("gravity_pulse_ring"),
                quasar("revive_thunderbloom_ring"),
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // Inversion start: a = 1 accepted (full shatter burst) / 0 cooldown dud (small
        // fizzle only) — one row, the leg scales the spawn (the CUE_GLITCH_POP law).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                GravityRiftCues.CUE_GRAVITY_INVERT,
                fx("gravity_invert_burst"),
                quasar("rift_spark"),
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                GravityRiftFxRows::invertLeg));
        // Inversion end: settling downward wave + heart re-light.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                GravityRiftCues.CUE_GRAVITY_RESOLVE,
                fx("gravity_resolve_wave"),
                quasar("unlock_burst"),
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // WINDOWED LOOPS (GravityRiftAmbience owns the hysteresis; loop=true).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                GravityRiftCues.CUE_GRAVITY_MOTES,
                fx("gravity_core_motes"),
                quasar("crater_updraft"),
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.LAYER,
                true));
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                GravityRiftCues.CUE_GRAVITY_COLUMN,
                fx("gravity_light_column"),
                quasar("summon_beacon_pillar"),
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.LAYER,
                true));
    }

    /** a ≥ 0.5 = accepted inversion (full burst); a < 0.5 = cooldown dud (0.35×). */
    private static boolean invertLeg(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        if (a >= 0.5F) {
            return PhotonBridge.spawn(photonFx, pos);
        }
        return PhotonBridge.spawn(photonFx, pos,
                PhotonBridge.SpawnOptions.DEFAULT.withScale(0.35D, 0.35D, 0.35D));
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }

    private static ResourceLocation quasar(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
