package dev.projecteclipse.eclipse.client.sky;

import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.vertex.BufferBuilder;
import com.mojang.blaze3d.vertex.BufferUploader;
import com.mojang.blaze3d.vertex.DefaultVertexFormat;
import com.mojang.blaze3d.vertex.Tesselator;
import com.mojang.blaze3d.vertex.VertexFormat;

import org.joml.Matrix4f;

import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.drama.AltarCeremonyFx;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * W-P-ALTAR — the altar level's PERMANENT sky signature: a set of additive, untextured
 * layers drawn in the celestial plane around the purple sun, keyed off the synced
 * {@link ClientStateCache#altarLevel} (rides the existing {@code S2CDayStatePayload}
 * altar-level sync — login re-send included, no new packets). The veil visibly thickens
 * as the community levels the altar:
 * <ul>
 *   <li><b>Level 1</b> — a faint violet ring around the eclipse.</li>
 *   <li><b>Level 2</b> — + a slow-orbiting glyph constellation (seven diamond glyphs,
 *       each with a trailing companion spark).</li>
 *   <li><b>Level 3</b> — + aurora-like veil bands: three undulating teal→violet arc
 *       curtains scrolling around the disc.</li>
 *   <li><b>Level 4</b> — + rotating halo beams (two counter-rotating four-beam fans).</li>
 *   <li><b>Level 5</b> — + the full corona crown: a bright gold ring with twelve spikes
 *       and a periodic pulse flash (an expanding echo ring every ~12 s).</li>
 * </ul>
 *
 * <p><b>reducedFx degradation</b> ({@link FxBudget#qualityTier()}): tier 2 renders
 * everything; tier 1 drops the animated aurora bands and one beam layer, thins the
 * constellation and skips the pulse-flash echo (alphas ×0.6); tier 0 keeps only the
 * level-1 ring at half strength. No per-frame allocations beyond the shared
 * {@link Tesselator} buffers; total geometry is at most a few hundred vertices.</p>
 *
 * <p><b>Ceremony hook:</b> {@link AltarCeremonyFx#skySurge} multiplies every layer's
 * alpha during the level-5 "corona ignition" level-up beat, so the ceremony and the
 * permanent signature share one canvas. Caller ({@link OverworldPurpleEffects}) has the
 * additive celestial blend + depthMask(false) state set; this class only swaps the
 * shader to position-color and leaves it that way (the star pass that follows binds its
 * own shader).</p>
 */
@OnlyIn(Dist.CLIENT)
final class AltarVeilSky {
    /** Celestial plane height (vanilla sun/moon convention — matches the sun quad). */
    private static final float PLANE_Y = 100.0F;

    // --- L1 base ring ---
    private static final float RING_MID_RADIUS = 74.0F;
    private static final float RING_HALF_WIDTH = 7.0F;
    private static final float RING_ALPHA = 0.10F;

    // --- L2 glyph constellation ---
    private static final int GLYPH_COUNT = 7;
    private static final float GLYPH_ORBIT_RADIUS = 96.0F;
    private static final float GLYPH_ORBIT_DEG_PER_SEC = 0.9F;
    private static final float GLYPH_ALPHA = 0.30F;
    /** Deterministic per-glyph size/radius jitter rows (no RNG in the render loop). */
    private static final float[] GLYPH_SIZES = {3.4F, 2.4F, 4.2F, 2.8F, 3.8F, 2.2F, 3.0F};
    private static final float[] GLYPH_RADIUS_JITTER = {0.0F, 6.0F, -5.0F, 9.0F, -8.0F, 4.0F, -3.0F};

    // --- L3 aurora veil bands ---
    private static final int AURORA_BANDS = 3;
    private static final int AURORA_SEGMENTS = 26;
    private static final float AURORA_ARC_DEGREES = 130.0F;
    private static final float AURORA_BASE_RADIUS = 116.0F;
    private static final float AURORA_BAND_SPACING = 15.0F;
    private static final float AURORA_HALF_WIDTH = 9.0F;
    private static final float AURORA_WAVE_AMPLITUDE = 7.0F;
    private static final float AURORA_ALPHA = 0.085F;
    /** Band scroll rates (deg/s) — middle band drifts against its neighbors. */
    private static final float[] AURORA_DEG_PER_SEC = {1.6F, -1.1F, 0.7F};

    // --- L4 rotating halo beams ---
    private static final int BEAMS_PER_LAYER = 4;
    private static final float BEAM_ROOT_RADIUS = 58.0F;
    private static final float BEAM_ROOT_HALF_WIDTH = 5.5F;
    private static final float BEAM_TIP_HALF_WIDTH = 14.0F;
    private static final float BEAM_ALPHA = 0.11F;
    private static final float[] BEAM_LENGTHS = {104.0F, 76.0F, 92.0F, 66.0F};
    private static final float[] BEAM_SPIN_DEG_PER_SEC = {2.1F, -1.4F};

    // --- L5 corona crown ---
    private static final float CROWN_MID_RADIUS = 58.0F;
    private static final float CROWN_HALF_WIDTH = 5.0F;
    private static final float CROWN_ALPHA = 0.22F;
    private static final int CROWN_SPIKES = 12;
    private static final float CROWN_SPIKE_LENGTH = 24.0F;
    private static final float CROWN_SPIKE_HALF_WIDTH = 4.0F;
    /** Pulse flash: every {@value} s the crown flares and an echo ring expands outward. */
    private static final float PULSE_PERIOD_SECONDS = 12.0F;
    private static final float PULSE_LENGTH_SECONDS = 1.6F;

    private static final int RING_SEGMENTS = 48;

    private AltarVeilSky() {}

    /**
     * Draws the level signature in the celestial frame ({@code celestialPose} is the pose
     * the sun/moon quads use). Additive blend + depthMask(false) are already active.
     */
    static void render(Matrix4f celestialPose, float partialTick, float eclipse, float rainAlpha) {
        int level = Mth.clamp(ClientStateCache.altarLevel, 0, 5);
        if (level <= 0 || rainAlpha <= 0.01F) {
            return;
        }
        int tier = FxBudget.qualityTier();
        // Ceremony surge (L5 corona ignition) brightens the whole signature briefly.
        float surge = AltarCeremonyFx.skySurge(partialTick);
        float strength = rainAlpha * (0.75F + 0.25F * eclipse) * (1.0F + 2.2F * surge);
        strength *= tier >= 2 ? 1.0F : tier == 1 ? 0.6F : 0.5F;

        float seconds = (System.currentTimeMillis() % 3_600_000L) / 1000.0F;
        RenderSystem.setShader(GameRenderer::getPositionColorShader);

        // L1: faint violet ring, breathing slightly so it never reads as a decal.
        float ringBreath = 1.0F + 0.12F * Mth.sin(seconds * 0.5F);
        drawSoftRing(celestialPose, RING_MID_RADIUS * ringBreath, RING_HALF_WIDTH,
                0.62F, 0.30F, 1.00F, RING_ALPHA * strength * (1.0F + 0.25F * level));
        if (tier <= 0) {
            return; // minimal tier: the ring alone carries the tell
        }

        if (level >= 2) {
            drawGlyphConstellation(celestialPose, seconds, strength, tier);
        }
        if (level >= 3 && tier >= 2) {
            drawAuroraBands(celestialPose, seconds, strength);
        }
        if (level >= 4) {
            drawHaloBeams(celestialPose, seconds, strength, tier);
        }
        if (level >= 5) {
            drawCoronaCrown(celestialPose, seconds, strength, surge,
                    AltarCeremonyFx.skySurgeEchoTravel(partialTick), tier);
        }
    }

    // ------------------------------------------------------------------ layers

    /** Slow-orbiting diamond glyphs with one trailing companion spark each. */
    private static void drawGlyphConstellation(Matrix4f pose, float seconds, float strength, int tier) {
        int count = tier >= 2 ? GLYPH_COUNT : 5;
        float orbit = seconds * GLYPH_ORBIT_DEG_PER_SEC * ((float) Math.PI / 180.0F);
        BufferBuilder builder = Tesselator.getInstance().begin(
                VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_COLOR);
        for (int i = 0; i < count; i++) {
            float angle = orbit + i * ((float) Math.PI * 2.0F / GLYPH_COUNT);
            float radius = GLYPH_ORBIT_RADIUS + GLYPH_RADIUS_JITTER[i];
            float cx = Mth.cos(angle) * radius;
            float cz = Mth.sin(angle) * radius;
            // Per-glyph pulse, phase-offset so the constellation twinkles, never strobes.
            float pulse = 0.75F + 0.25F * Mth.sin(seconds * 1.1F + i * 2.4F);
            float alpha = GLYPH_ALPHA * strength * pulse;
            addDiamond(builder, pose, cx, cz, GLYPH_SIZES[i], 0.72F, 0.42F, 1.00F, alpha);
            // Trailing companion spark just behind the glyph on its orbit.
            float trail = angle - 0.05F;
            addDiamond(builder, pose,
                    Mth.cos(trail) * (radius - 2.5F), Mth.sin(trail) * (radius - 2.5F),
                    GLYPH_SIZES[i] * 0.35F, 0.85F, 0.65F, 1.00F, alpha * 0.6F);
        }
        BufferUploader.drawWithShader(builder.buildOrThrow());
    }

    /** Three undulating arc curtains, teal fading into violet, scrolling around the disc. */
    private static void drawAuroraBands(Matrix4f pose, float seconds, float strength) {
        for (int band = 0; band < AURORA_BANDS; band++) {
            float scroll = seconds * AURORA_DEG_PER_SEC[band] * ((float) Math.PI / 180.0F)
                    + band * 2.1F;
            float arc = AURORA_ARC_DEGREES * ((float) Math.PI / 180.0F);
            float bandRadius = AURORA_BASE_RADIUS + band * AURORA_BAND_SPACING;
            // Band color slides teal → violet across the three curtains.
            float mix = band / (float) (AURORA_BANDS - 1);
            float r = Mth.lerp(mix, 0.35F, 0.62F);
            float g = Mth.lerp(mix, 0.90F, 0.35F);
            float b = Mth.lerp(mix, 0.85F, 1.00F);
            BufferBuilder builder = Tesselator.getInstance().begin(
                    VertexFormat.Mode.TRIANGLE_STRIP, DefaultVertexFormat.POSITION_COLOR);
            for (int seg = 0; seg <= AURORA_SEGMENTS; seg++) {
                float t = seg / (float) AURORA_SEGMENTS;
                float angle = scroll + (t - 0.5F) * arc;
                // Radial sine wave slides along the arc — the aurora's slow ripple.
                float wave = Mth.sin(t * 9.0F + seconds * (0.8F + 0.3F * band) + band * 1.7F)
                        * AURORA_WAVE_AMPLITUDE;
                float radius = bandRadius + wave;
                // Alpha fades to zero at both arc ends (soft curtain edges).
                float edge = Mth.sin(t * (float) Math.PI);
                float alpha = AURORA_ALPHA * strength * edge;
                float cos = Mth.cos(angle);
                float sin = Mth.sin(angle);
                builder.addVertex(pose, cos * (radius - AURORA_HALF_WIDTH), PLANE_Y,
                        sin * (radius - AURORA_HALF_WIDTH)).setColor(r, g, b, 0.0F);
                builder.addVertex(pose, cos * (radius + AURORA_HALF_WIDTH), PLANE_Y,
                        sin * (radius + AURORA_HALF_WIDTH)).setColor(r, g, b, alpha);
            }
            BufferUploader.drawWithShader(builder.buildOrThrow());
        }
    }

    /** Two counter-rotating four-beam fans (tier 1 keeps only the first layer). */
    private static void drawHaloBeams(Matrix4f pose, float seconds, float strength, int tier) {
        int layers = tier >= 2 ? 2 : 1;
        BufferBuilder builder = Tesselator.getInstance().begin(
                VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_COLOR);
        for (int layer = 0; layer < layers; layer++) {
            float spin = seconds * BEAM_SPIN_DEG_PER_SEC[layer] * ((float) Math.PI / 180.0F)
                    + layer * 0.4F;
            for (int i = 0; i < BEAMS_PER_LAYER; i++) {
                float angle = spin + i * ((float) Math.PI * 2.0F / BEAMS_PER_LAYER);
                float length = BEAM_LENGTHS[(i + layer * 2) % BEAM_LENGTHS.length];
                float rootAlpha = BEAM_ALPHA * strength
                        * (0.85F + 0.15F * Mth.sin(seconds * 0.9F + i * 1.9F + layer));
                addBeam(builder, pose, angle, BEAM_ROOT_RADIUS, BEAM_ROOT_RADIUS + length,
                        BEAM_ROOT_HALF_WIDTH, BEAM_TIP_HALF_WIDTH,
                        0.58F - 0.08F * layer, 0.28F, 1.00F, rootAlpha);
            }
        }
        BufferUploader.drawWithShader(builder.buildOrThrow());
    }

    /** Bright gold crown ring + twelve spikes + the periodic pulse-flash echo ring. */
    private static void drawCoronaCrown(Matrix4f pose, float seconds, float strength,
            float surge, float surgeEchoTravel, int tier) {
        // Pulse envelope: a sine bump during the first PULSE_LENGTH of every period; the
        // ceremony surge forces a full flare so the L5 level-up ignites the crown at once.
        float phase = seconds % PULSE_PERIOD_SECONDS;
        float pulse = phase < PULSE_LENGTH_SECONDS
                ? Mth.sin(phase / PULSE_LENGTH_SECONDS * (float) Math.PI) : 0.0F;
        if (tier < 2) {
            pulse = 0.0F; // reduced: steady crown, no flash beats
        }
        pulse = Math.max(pulse, surge);

        float crownRadius = CROWN_MID_RADIUS * (1.0F + 0.12F * pulse);
        float crownAlpha = CROWN_ALPHA * strength * (1.0F + 1.6F * pulse);
        drawSoftRing(pose, crownRadius, CROWN_HALF_WIDTH, 1.00F, 0.82F, 0.45F, crownAlpha);

        // Twelve crown spikes riding just outside the ring.
        BufferBuilder spikes = Tesselator.getInstance().begin(
                VertexFormat.Mode.TRIANGLES, DefaultVertexFormat.POSITION_COLOR);
        float spikeSpin = seconds * 0.5F * ((float) Math.PI / 180.0F);
        for (int i = 0; i < CROWN_SPIKES; i++) {
            float angle = spikeSpin + i * ((float) Math.PI * 2.0F / CROWN_SPIKES);
            float cos = Mth.cos(angle);
            float sin = Mth.sin(angle);
            // Perpendicular (tangent) direction for the spike base width.
            float tx = -sin * CROWN_SPIKE_HALF_WIDTH;
            float tz = cos * CROWN_SPIKE_HALF_WIDTH;
            float rootR = crownRadius + CROWN_HALF_WIDTH * 0.5F;
            float tipR = rootR + CROWN_SPIKE_LENGTH * (1.0F + 0.6F * pulse);
            float alpha = crownAlpha * 0.8F;
            spikes.addVertex(pose, cos * rootR - tx, PLANE_Y, sin * rootR - tz)
                    .setColor(1.00F, 0.86F, 0.55F, alpha);
            spikes.addVertex(pose, cos * rootR + tx, PLANE_Y, sin * rootR + tz)
                    .setColor(1.00F, 0.86F, 0.55F, alpha);
            spikes.addVertex(pose, cos * tipR, PLANE_Y, sin * tipR)
                    .setColor(0.80F, 0.50F, 1.00F, 0.0F);
        }
        BufferUploader.drawWithShader(spikes.buildOrThrow());

        // Pulse echo: an expanding violet ring racing outward, dissipating as it travels.
        // EVAL-POL-F #6: the ceremony surge drives its own monotonic 0→1 clock (keyed off
        // surge start), so the echo fires outward ONCE and fades at the rim — it no longer
        // parks at max radius through the hold and retracts as skySurge decays.
        if (tier >= 2) {
            float travel;
            float echoStrength;
            if (surgeEchoTravel < 1.0F) {
                travel = surgeEchoTravel;
                echoStrength = 1.0F;
            } else if (pulse > 0.01F && phase < PULSE_LENGTH_SECONDS && surge < pulse) {
                travel = phase / PULSE_LENGTH_SECONDS;
                echoStrength = pulse;
            } else {
                travel = 1.0F;
                echoStrength = 0.0F;
            }
            if (echoStrength > 0.01F && travel < 1.0F) {
                float echoRadius = Mth.lerp(travel, crownRadius, 175.0F);
                drawSoftRing(pose, echoRadius, 4.0F, 0.75F, 0.50F, 1.00F,
                        0.30F * strength * echoStrength * (1.0F - travel));
            }
        }
    }

    // ------------------------------------------------------------------ geometry helpers

    /** Soft annulus: alpha peaks at the mid radius and fades to zero at both edges. */
    private static void drawSoftRing(Matrix4f pose, float midRadius, float halfWidth,
            float r, float g, float b, float alpha) {
        if (alpha <= 0.001F) {
            return;
        }
        BufferBuilder builder = Tesselator.getInstance().begin(
                VertexFormat.Mode.TRIANGLE_STRIP, DefaultVertexFormat.POSITION_COLOR);
        for (int seg = 0; seg <= RING_SEGMENTS; seg++) {
            float angle = seg * ((float) Math.PI * 2.0F / RING_SEGMENTS);
            float cos = Mth.cos(angle);
            float sin = Mth.sin(angle);
            builder.addVertex(pose, cos * (midRadius - halfWidth), PLANE_Y,
                    sin * (midRadius - halfWidth)).setColor(r, g, b, 0.0F);
            builder.addVertex(pose, cos * midRadius, PLANE_Y, sin * midRadius)
                    .setColor(r, g, b, alpha);
        }
        BufferUploader.drawWithShader(builder.buildOrThrow());
        builder = Tesselator.getInstance().begin(
                VertexFormat.Mode.TRIANGLE_STRIP, DefaultVertexFormat.POSITION_COLOR);
        for (int seg = 0; seg <= RING_SEGMENTS; seg++) {
            float angle = seg * ((float) Math.PI * 2.0F / RING_SEGMENTS);
            float cos = Mth.cos(angle);
            float sin = Mth.sin(angle);
            builder.addVertex(pose, cos * midRadius, PLANE_Y, sin * midRadius)
                    .setColor(r, g, b, alpha);
            builder.addVertex(pose, cos * (midRadius + halfWidth), PLANE_Y,
                    sin * (midRadius + halfWidth)).setColor(r, g, b, 0.0F);
        }
        BufferUploader.drawWithShader(builder.buildOrThrow());
    }

    /** One in-plane diamond quad (a "glyph") centered at (cx, cz). */
    private static void addDiamond(BufferBuilder builder, Matrix4f pose,
            float cx, float cz, float size, float r, float g, float b, float alpha) {
        builder.addVertex(pose, cx + size, PLANE_Y, cz).setColor(r, g, b, alpha);
        builder.addVertex(pose, cx, PLANE_Y, cz + size).setColor(r, g, b, alpha);
        builder.addVertex(pose, cx - size, PLANE_Y, cz).setColor(r, g, b, alpha);
        builder.addVertex(pose, cx, PLANE_Y, cz - size).setColor(r, g, b, alpha);
    }

    /** One trapezoid beam quad along the radial direction {@code angle}. */
    private static void addBeam(BufferBuilder builder, Matrix4f pose, float angle,
            float rootRadius, float tipRadius, float rootHalfWidth, float tipHalfWidth,
            float r, float g, float b, float rootAlpha) {
        float cos = Mth.cos(angle);
        float sin = Mth.sin(angle);
        float txRoot = -sin * rootHalfWidth;
        float tzRoot = cos * rootHalfWidth;
        float txTip = -sin * tipHalfWidth;
        float tzTip = cos * tipHalfWidth;
        builder.addVertex(pose, cos * rootRadius - txRoot, PLANE_Y, sin * rootRadius - tzRoot)
                .setColor(r, g, b, rootAlpha);
        builder.addVertex(pose, cos * rootRadius + txRoot, PLANE_Y, sin * rootRadius + tzRoot)
                .setColor(r, g, b, rootAlpha);
        builder.addVertex(pose, cos * tipRadius + txTip, PLANE_Y, sin * tipRadius + tzTip)
                .setColor(r, g, b, 0.0F);
        builder.addVertex(pose, cos * tipRadius - txTip, PLANE_Y, sin * tipRadius - tzTip)
                .setColor(r, g, b, 0.0F);
    }
}
