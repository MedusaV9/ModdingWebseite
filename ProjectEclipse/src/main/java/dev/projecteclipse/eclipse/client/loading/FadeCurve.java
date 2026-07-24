package dev.projecteclipse.eclipse.client.loading;

import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Shared easing curves for the loading/transition fades (Wave-5 A2): the smoothstep used by
 * {@link PortalTransitionController}'s black/glitch envelopes and the ease-out cubic used by
 * {@link EclipseLoadingScreen}'s dismissal fade. Inputs are clamped to {@code [0,1]}.
 */
@OnlyIn(Dist.CLIENT)
final class FadeCurve {
    private FadeCurve() {}

    /** Smoothstep {@code 3x² − 2x³}. */
    static float smooth01(float x) {
        x = Mth.clamp(x, 0.0F, 1.0F);
        return x * x * (3.0F - 2.0F * x);
    }

    /** Ease-out cubic {@code 1 − (1 − x)³}: fast start, gentle landing. */
    static float easeOutCubic(float x) {
        x = Mth.clamp(x, 0.0F, 1.0F);
        float inv = 1.0F - x;
        return 1.0F - inv * inv * inv;
    }
}
