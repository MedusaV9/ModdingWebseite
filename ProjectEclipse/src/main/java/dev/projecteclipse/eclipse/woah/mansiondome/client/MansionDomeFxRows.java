package dev.projecteclipse.eclipse.woah.mansiondome.client;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry;
import dev.projecteclipse.eclipse.woah.mansiondome.DomeCues;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * WOAH-01 {@link PhotonFxRegistry} row registrar (plan §4.4) — the
 * {@code FerrymanFinaleFxRows} self-registration pattern. Assets are authored by
 * {@code tools/photon/woah_dome_fx.py} (fxlib) into {@code assets/eclipse/fx/*.fx};
 * re-run the script instead of hand-editing the gzip-NBT.
 *
 * <p>All four cues are NEW, so the Quasar fallback is {@code null} (sanctioned: the
 * pre-row baseline was nothing — {@code PhotonFxRegistry} class doc). The two loops are
 * WINDOWED-only and driven exclusively by {@link MansionDomeClient}'s 48-block window;
 * payload-firing them would only hit the registry's one-time WARN.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class MansionDomeFxRows {
    /** {@code a} at/below this (≤ 3 hits left) doubles the hit-spark mass (plan: more broken = more sparks). */
    private static final float HIT_HEAVY_THRESHOLD = 0.375F;
    /** Shock-ring executor scale bounds ({@code a} = shellRadius 12–96 → ~1.5–12×). */
    private static final float SHATTER_SCALE_MIN = 1.0F;
    private static final float SHATTER_SCALE_MAX = 12.0F;

    private MansionDomeFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // Hit sparks + 1-frame glitch still. a = hitsRemaining/8, b = 1 on the death beat.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                DomeCues.CUE_DOME_DEVICE_HIT,
                fx("dome_device_hit"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                MansionDomeFxRows::hitSparks));
        // Shell-shatter burst: ring shock scaled to the real shell radius (a), shard
        // rain + afterglow ride the same executor (the CUE_STRUCTURE_SLAM scale law).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                DomeCues.CUE_DOME_SHATTER_BURST,
                fx("dome_shatter_burst"),
                null,
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.LAYER,
                false,
                MansionDomeFxRows::shatterBurst));
        // Device idle glimmer — WINDOWED loop (MansionDomeClient owns the window).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                DomeCues.CUE_DOME_DEVICE_IDLE,
                fx("dome_device_idle"),
                null,
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.LAYER,
                true));
        // Beam-base updraft — WINDOWED loop.
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                DomeCues.CUE_DOME_BEAM_BASE,
                fx("dome_beam_base"),
                null,
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.LAYER,
                true));
    }

    /**
     * {@code CUE_DOME_DEVICE_HIT} leg: the asset carries one authored spark burst; a
     * battered device ({@code a ≤} {@value #HIT_HEAVY_THRESHOLD}) or the death beat
     * ({@code b ≥ 0.5}) layers a SECOND, slightly larger instance — "je kaputter, desto
     * mehr" without dynamic emitter counts (Photon assets are static).
     */
    private static boolean hitSparks(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        boolean played = PhotonBridge.spawn(photonFx, pos);
        if (a <= HIT_HEAVY_THRESHOLD || b >= 0.5F) {
            played |= PhotonBridge.spawn(photonFx, pos,
                    PhotonBridge.SpawnOptions.DEFAULT
                            .withScale(1.35D, 1.35D, 1.35D)
                            .withAllowMulti(true));
        }
        return played;
    }

    /** {@code CUE_DOME_SHATTER_BURST} leg: shellRadius ({@code a}) → executor scale. */
    private static boolean shatterBurst(ResourceLocation photonFx, Vec3 pos,
            @Nullable Entity entity, float a, float b) {
        float scale = a <= 0.0F ? 1.0F
                : Mth.clamp(a / DomeCues.SHATTER_AUTHORED_RADIUS,
                        SHATTER_SCALE_MIN, SHATTER_SCALE_MAX);
        return PhotonBridge.spawn(photonFx, pos,
                PhotonBridge.SpawnOptions.DEFAULT.withScale(scale, scale, scale));
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
