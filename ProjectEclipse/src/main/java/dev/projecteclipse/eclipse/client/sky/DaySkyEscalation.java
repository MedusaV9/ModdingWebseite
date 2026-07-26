package dev.projecteclipse.eclipse.client.sky;

import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.vertex.BufferBuilder;
import com.mojang.blaze3d.vertex.BufferUploader;
import com.mojang.blaze3d.vertex.DefaultVertexFormat;
import com.mojang.blaze3d.vertex.Tesselator;
import com.mojang.blaze3d.vertex.VertexFormat;

import org.joml.Matrix4f;

import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * SKYDAY — the DAY-driven half of the sky escalation: undulating aurora curtains (plus a
 * late-event ember ring) drawn in the celestial plane around the eclipse, keyed off
 * {@link EclipseSkyState#dayFxEscalation()} so the sky visibly "goes madder" every event
 * day and culminates on day 14. Distinct from {@link AltarVeilSky}'s LEVEL-driven aurora
 * (L3, radii 116–146): these curtains live further out (radius
 * {@value #BASE_RADIUS}+), ramp count 1 → {@value #MAX_BANDS}, widen their arcs and slide
 * violet → hot magenta as the days pass, so the two systems layer instead of stacking.
 *
 * <p>Escalation ladder (esc = tier-scaled day factor 0..1):</p>
 * <ul>
 *   <li><b>esc ≤ {@value #MIN_VISIBLE}</b> (≈ days 1–2, or tier 0) — nothing; the calm
 *       v1 sky.</li>
 *   <li><b>growing</b> — curtain count 1 → {@value #MAX_BANDS}, arc 95° → 165°, alpha and
 *       ripple depth scale with esc, hue slides toward magenta.</li>
 *   <li><b>esc &gt; {@value #EMBER_THRESHOLD}</b> (final stretch) — + the ember ring: one
 *       slow-breathing soft ring outside the curtains, the day-14 crown.</li>
 * </ul>
 *
 * <p>reducedFx: {@code dayFxEscalation} already halves (tier 1) or zeroes (tier 0) the
 * driver, which drops bands/alpha/ring automatically — no extra gating needed here.
 * Caller ({@link OverworldPurpleEffects}) has additive blend + depthMask(false) set; like
 * {@link AltarVeilSky} this only swaps the shader to position-color and leaves it (the
 * star pass rebinds its own). Worst case ≤ ~350 vertices, zero per-frame heap
 * allocations beyond the shared {@link Tesselator} buffers.</p>
 */
@OnlyIn(Dist.CLIENT)
final class DaySkyEscalation {
    /** Celestial plane height (matches the sun/moon quads and AltarVeilSky). */
    private static final float PLANE_Y = 100.0F;

    /** Below this the curtains stay off entirely (early days read as the calm v1 sky). */
    private static final float MIN_VISIBLE = 0.10F;

    // --- aurora curtains ---
    private static final int MAX_BANDS = 3;
    private static final int SEGMENTS = 24;
    /** Innermost curtain radius — outside AltarVeilSky's L3 bands (116–146). */
    private static final float BASE_RADIUS = 152.0F;
    private static final float BAND_SPACING = 16.0F;
    private static final float HALF_WIDTH = 10.0F;
    private static final float WAVE_AMPLITUDE = 8.0F;
    /** Peak per-curtain alpha at esc 1 (kept low — three additive strips stack). */
    private static final float MAX_ALPHA = 0.11F;
    /** Arc width ramp: narrow wisps early, near-half-circle curtains on the last days. */
    private static final float ARC_DEGREES_MIN = 95.0F;
    private static final float ARC_DEGREES_MAX = 165.0F;
    /** Band scroll rates (deg/s) — the middle curtain drifts against its neighbors. */
    private static final float[] BAND_DEG_PER_SEC = {1.3F, -0.9F, 0.6F};

    // --- ember ring (the final-stretch crown) ---
    private static final float EMBER_THRESHOLD = 0.60F;
    private static final float EMBER_RADIUS = 190.0F;
    private static final float EMBER_HALF_WIDTH = 6.0F;
    private static final float EMBER_ALPHA = 0.07F;
    private static final int EMBER_SEGMENTS = 40;

    private DaySkyEscalation() {}

    /**
     * Draws the day-escalation layers in the celestial frame ({@code celestialPose} is
     * the pose the eclipse quads use — the curtains ride the zenith hold with it).
     * Additive blend + depthMask(false) are already active.
     */
    static void render(Matrix4f celestialPose, float seconds, float rainAlpha) {
        float esc = EclipseSkyState.dayFxEscalation();
        if (esc <= MIN_VISIBLE || rainAlpha <= 0.01F) {
            return;
        }
        RenderSystem.setShader(GameRenderer::getPositionColorShader);

        int bands = 1 + Math.round(esc * (MAX_BANDS - 1));
        float arc = Mth.lerp(esc, ARC_DEGREES_MIN, ARC_DEGREES_MAX) * ((float) Math.PI / 180.0F);
        for (int band = 0; band < bands; band++) {
            float scroll = seconds * BAND_DEG_PER_SEC[band] * ((float) Math.PI / 180.0F)
                    + band * 2.4F;
            float bandRadius = BASE_RADIUS + band * BAND_SPACING;
            // Hue slides violet → hot magenta across bands AND days (deep late grading).
            float mix = Mth.clamp(band / (float) (MAX_BANDS - 1) * 0.5F + esc * 0.5F, 0.0F, 1.0F);
            float r = Mth.lerp(mix, 0.55F, 0.95F);
            float g = Mth.lerp(mix, 0.30F, 0.18F);
            float b = Mth.lerp(mix, 1.00F, 0.75F);
            BufferBuilder builder = Tesselator.getInstance().begin(
                    VertexFormat.Mode.TRIANGLE_STRIP, DefaultVertexFormat.POSITION_COLOR);
            for (int seg = 0; seg <= SEGMENTS; seg++) {
                float t = seg / (float) SEGMENTS;
                float angle = scroll + (t - 0.5F) * arc;
                // Radial ripple deepens with the days — the curtains churn, never sit.
                float wave = Mth.sin(t * 8.0F + seconds * (0.7F + 0.25F * band) + band * 1.9F)
                        * WAVE_AMPLITUDE * (0.5F + 0.5F * esc);
                float radius = bandRadius + wave;
                // Alpha fades to zero at both arc ends (soft curtain edges).
                float edge = Mth.sin(t * (float) Math.PI);
                float alpha = MAX_ALPHA * esc * edge * rainAlpha;
                float cos = Mth.cos(angle);
                float sin = Mth.sin(angle);
                builder.addVertex(celestialPose, cos * (radius - HALF_WIDTH), PLANE_Y,
                        sin * (radius - HALF_WIDTH)).setColor(r, g, b, 0.0F);
                builder.addVertex(celestialPose, cos * (radius + HALF_WIDTH), PLANE_Y,
                        sin * (radius + HALF_WIDTH)).setColor(r, g, b, alpha);
            }
            BufferUploader.drawWithShader(builder.buildOrThrow());
        }

        // Ember ring: the last days' crown — a slow ±20% breath so it reads as alive.
        if (esc > EMBER_THRESHOLD) {
            float crest = (esc - EMBER_THRESHOLD) / (1.0F - EMBER_THRESHOLD);
            float breath = 0.8F + 0.2F * Mth.sin(seconds * 0.4F);
            drawSoftRing(celestialPose, EMBER_ALPHA * crest * breath * rainAlpha);
        }
    }

    /**
     * Soft ember annulus (the {@link AltarVeilSky} two-strip idiom): alpha peaks at the
     * mid radius and fades to zero at both edges — no hard rim against the sky.
     */
    private static void drawSoftRing(Matrix4f pose, float alpha) {
        if (alpha <= 0.001F) {
            return;
        }
        for (int half = 0; half < 2; half++) {
            float edgeRadius = half == 0
                    ? EMBER_RADIUS - EMBER_HALF_WIDTH
                    : EMBER_RADIUS + EMBER_HALF_WIDTH;
            BufferBuilder builder = Tesselator.getInstance().begin(
                    VertexFormat.Mode.TRIANGLE_STRIP, DefaultVertexFormat.POSITION_COLOR);
            for (int seg = 0; seg <= EMBER_SEGMENTS; seg++) {
                float angle = seg * ((float) Math.PI * 2.0F / EMBER_SEGMENTS);
                float cos = Mth.cos(angle);
                float sin = Mth.sin(angle);
                builder.addVertex(pose, cos * edgeRadius, PLANE_Y, sin * edgeRadius)
                        .setColor(1.00F, 0.45F, 0.25F, 0.0F);
                builder.addVertex(pose, cos * EMBER_RADIUS, PLANE_Y, sin * EMBER_RADIUS)
                        .setColor(1.00F, 0.45F, 0.25F, alpha);
            }
            BufferUploader.drawWithShader(builder.buildOrThrow());
        }
    }
}
