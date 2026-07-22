package dev.projecteclipse.eclipse.client.mixin;

import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

import net.minecraft.client.Camera;
import net.minecraft.client.renderer.LevelRenderer;
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
}
