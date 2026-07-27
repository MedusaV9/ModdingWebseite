package dev.projecteclipse.eclipse.client.mixin;

import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

import dev.projecteclipse.eclipse.woah.chronostasis.client.ChronoZoneState;
import net.minecraft.client.Camera;
import net.minecraft.client.renderer.LevelRenderer;
import net.minecraft.client.renderer.LightTexture;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Hides the vanilla world border visuals entirely: since W7 the vanilla border is only a
 * hidden FAILSAFE at {@code soft ring + 48} (see {@code border.SoftBorder}) — the visible
 * boundary is the circular glitch strip drawn by {@code border.client.BorderFxRenderer}.
 * HEAD inject + cancel keeps the border's collision/clamping logic fully intact (that lives
 * in {@code WorldBorder}, not in the renderer).
 */
@OnlyIn(Dist.CLIENT)
@Mixin(LevelRenderer.class)
public abstract class LevelRendererMixin {
    @Inject(method = "renderWorldBorder", at = @At("HEAD"), cancellable = true)
    private void eclipse$hideVanillaBorder(Camera camera, CallbackInfo callbackInfo) {
        callbackInfo.cancel();
    }

    /**
     * WOAH-03 Chrono-Stasis (plan §4.4): inside the frozen clearing the vanilla rain
     * streaks are replaced by the frozen Photon droplets — suppress the renderer when
     * the eased inside-amount passes 0.6 (all-or-nothing; the ~5-block edge overlap
     * reads as the transition). Released during the DISCHARGE rain beat.
     */
    @Inject(method = "renderSnowAndRain", at = @At("HEAD"), cancellable = true)
    private void eclipse$chronoHideRain(LightTexture lightTexture, float partialTick,
            double camX, double camY, double camZ, CallbackInfo callbackInfo) {
        if (ChronoZoneState.suppressVanillaRain()) {
            callbackInfo.cancel();
        }
    }

    /** WOAH-03: same gate for ground splash particles + rain sounds. */
    @Inject(method = "tickRain", at = @At("HEAD"), cancellable = true)
    private void eclipse$chronoMuteRain(Camera camera, CallbackInfo callbackInfo) {
        if (ChronoZoneState.suppressVanillaRain()) {
            callbackInfo.cancel();
        }
    }
}
