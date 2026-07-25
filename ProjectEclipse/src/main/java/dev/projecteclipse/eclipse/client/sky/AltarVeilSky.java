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
 * <p><b>W-P-ALTAR2 per-tier MOTIFS</b> — each tier carries one signature behavior so
 * the layers never read as static decals:
 * <ul>
 *   <li><b>L1</b> — on its FIRST appearance (a mid-session 0→1 level-up; login syncs
 *       adopt silently) the ring "writes itself": an arc sweeps 360° over
 *       ~{@value #RING_WRITE_SECONDS} s behind a bright pen-tip spark.</li>
 *   <li><b>L2</b> — every ~{@value #REARRANGE_PERIOD_SECONDS} s the constellation
 *       RE-ARRANGES: glyphs glide to a permuted radius/angle row over ~2.6 s under a
 *       soft chime-like brightness pulse (deterministic rows, no render-loop RNG;
 *       tier 2 only).</li>
 *   <li><b>L3</b> — the aurora RESPONDS TO OFFERINGS: when the altar swallows an item
 *       ({@link AltarCeremonyFx#offeringSkyGlow}) the bands briefly brighten and their
 *       ripple deepens.</li>
 *   <li><b>L4</b> — the halo beams get a GROUND READ: {@code AltarIdleMotes} projects
 *       faint moving light patches onto the island, azimuth-synced to
 *       {@link #BEAM_SPIN_DEG_PER_SEC} (the fake "cast light" trick).</li>
 *   <li><b>L5</b> — a map-wide CROWN FLARE every ~{@value #FLARE_PERIOD_SECONDS} s:
 *       spikes lengthen, the crown blooms and one echo ring fires (half strength and
 *       echo-less at tier 1).</li>
 * </ul></p>
 *
 * <p><b>VEIL-REPASS-2</b>: two upgrades on the motif pass. (1) Tier-transition MORPH —
 * a mid-session level-up TRANSFORMS the signature over {@value #MORPH_SECONDS} s instead
 * of snapping: surviving layers swell once, the newborn layer grows out of the disc
 * (plane-scale 55% → 100% + alpha fade-in via {@link #layerPose}), and a bridge ring
 * carries the change from the L1 ring to the new layer's home radius. (2) The L2
 * rearrange now CONNECTS the gliding glyphs with hairline light ({@link #addHairline}),
 * flowing around the loop and dying with the chime.</p>
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
    /** L1 motif: the ring writes itself over this long on its first appearance. */
    private static final float RING_WRITE_SECONDS = 3.2F;
    /** Pen-tip spark size at the writing head (celestial-plane units). */
    private static final float RING_PEN_TIP_SIZE = 4.5F;

    // --- L2 glyph constellation ---
    private static final int GLYPH_COUNT = 7;
    private static final float GLYPH_ORBIT_RADIUS = 96.0F;
    private static final float GLYPH_ORBIT_DEG_PER_SEC = 0.9F;
    private static final float GLYPH_ALPHA = 0.30F;
    /** Deterministic per-glyph size/radius jitter rows (no RNG in the render loop). */
    private static final float[] GLYPH_SIZES = {3.4F, 2.4F, 4.2F, 2.8F, 3.8F, 2.2F, 3.0F};
    private static final float[] GLYPH_RADIUS_JITTER = {0.0F, 6.0F, -5.0F, 9.0F, -8.0F, 4.0F, -3.0F};
    /**
     * L2 motif: every {@value #REARRANGE_PERIOD_SECONDS} s the glyphs glide to the NEXT
     * permutation of the jitter/scatter rows over {@value #REARRANGE_LENGTH_SECONDS} s
     * with a soft chime-visual brightness pulse. Row walk is index-shift permutation —
     * cycle N holds row (i+N+1), so consecutive windows blend continuously.
     */
    private static final float REARRANGE_PERIOD_SECONDS = 34.0F;
    private static final float REARRANGE_LENGTH_SECONDS = 2.6F;
    /** Deterministic per-glyph angular scatter row (radians), permuted with the jitter. */
    private static final float[] GLYPH_ANGLE_SCATTER =
            {0.00F, 0.31F, -0.24F, 0.18F, -0.33F, 0.26F, -0.12F};

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
    /**
     * L5 motif: the big map-wide CROWN FLARE — rarer and stronger than the 12 s pulse
     * (co-prime-ish periods so the two beats rarely stack). Tier 1 keeps a half-strength
     * flare (its only crown beat, since the pulse is tier-2 gated); tier 0 never reaches
     * the crown at all.
     */
    private static final float FLARE_PERIOD_SECONDS = 45.0F;
    private static final float FLARE_LENGTH_SECONDS = 2.8F;

    private static final int RING_SEGMENTS = 48;

    /**
     * VEIL-REPASS-2: tier-transition MORPH — a mid-session level-up (from ≥ 1; the 0→1
     * moment keeps its write-in intro) no longer snaps the new layer on. Over
     * {@value #MORPH_SECONDS} s the old signature visibly TRANSFORMS: it swells while
     * "giving birth", the new layer grows out of the disc (radius 55% → 100% + alpha
     * fade-in), and one bridge ring carries the change outward from the L1 ring to the
     * new layer's home radius. Login/decrease syncs adopt silently, exactly like the
     * write-in.
     */
    private static final float MORPH_SECONDS = 3.0F;
    /** Bridge-ring arrival radius per NEW level (index = level − 2): L2 glyphs → L5 crown. */
    private static final float[] MORPH_TARGET_RADIUS = {
            GLYPH_ORBIT_RADIUS,
            AURORA_BASE_RADIUS + AURORA_BAND_SPACING,
            BEAM_ROOT_RADIUS + 80.0F,
            CROWN_MID_RADIUS + CROWN_SPIKE_LENGTH};

    /** VEIL-REPASS-2: hairline connect lines while the L2 constellation rearranges. */
    private static final float CONNECT_HALF_WIDTH = 0.55F;
    /** Endpoints pull back to the glyph rims so lines join, never stab through, diamonds. */
    private static final float CONNECT_TRIM = 5.0F;

    /** Last altar level this client SAW rendering-side ({@code MIN_VALUE} = adopt-only). */
    private static int lastSeenLevel = Integer.MIN_VALUE;
    /** Seconds-clock timestamp of the L1 write-in start; {@code NaN} = fully written. */
    private static float ringWriteStart = Float.NaN;
    /** Seconds-clock timestamp of a live tier morph; {@code NaN} = none. */
    private static float morphStart = Float.NaN;
    /** The level a live morph started FROM (layers above it are the "newborn" ones). */
    private static int morphFromLevel;
    /** Pre-allocated morph pose scratch (§3.5: no per-frame heap allocations). */
    private static final Matrix4f MORPH_POSE = new Matrix4f();
    /** Rearrange connect-line scratch: this frame's glyph centers (no render-loop alloc). */
    private static final float[] GLYPH_X = new float[GLYPH_COUNT];
    private static final float[] GLYPH_Z = new float[GLYPH_COUNT];

    private AltarVeilSky() {}

    /**
     * Draws the level signature in the celestial frame ({@code celestialPose} is the pose
     * the sun/moon quads use). Additive blend + depthMask(false) are already active.
     */
    static void render(Matrix4f celestialPose, float partialTick, float eclipse, float rainAlpha) {
        float seconds = (System.currentTimeMillis() % 3_600_000L) / 1000.0F;
        int level = Mth.clamp(ClientStateCache.altarLevel, 0, 5);
        trackLevel(level, seconds);
        if (level <= 0 || rainAlpha <= 0.01F) {
            return;
        }
        int tier = FxBudget.qualityTier();
        // Ceremony surge (L5 corona ignition) brightens the whole signature briefly.
        float surge = AltarCeremonyFx.skySurge(partialTick);
        float strength = rainAlpha * (0.75F + 0.25F * eclipse) * (1.0F + 2.2F * surge);
        strength *= tier >= 2 ? 1.0F : tier == 1 ? 0.6F : 0.5F;

        RenderSystem.setShader(GameRenderer::getPositionColorShader);

        // L1: faint violet ring, breathing slightly so it never reads as a decal.
        // W-P-ALTAR2 motif: on its first appearance it WRITES ITSELF — an arc sweeps
        // the full circle behind a bright pen-tip spark, then hands over to the breath.
        // VEIL-REPASS-2 tier morph: while live, layers ABOVE morphFromLevel are newborn
        // (they grow out of the disc and fade in), the surviving layers swell once (the
        // old signature "gives birth"), and a bridge ring carries the change outward.
        float morphT = morphProgress(seconds);
        boolean morphing = morphT < 1.0F;
        float birth = morphing ? smooth(morphT) : 1.0F;
        float oldSwell = morphing ? 1.0F + 0.35F * Mth.sin(morphT * (float) Math.PI) : 1.0F;

        float ringBreath = 1.0F + 0.12F * Mth.sin(seconds * 0.5F);
        float ringAlpha = RING_ALPHA * strength * (1.0F + 0.25F * level) * oldSwell;
        float writeT = ringWriteProgress(seconds);
        if (writeT >= 1.0F) {
            drawSoftRing(celestialPose, RING_MID_RADIUS * ringBreath, RING_HALF_WIDTH,
                    0.62F, 0.30F, 1.00F, ringAlpha);
        } else {
            drawRingWriteIn(celestialPose, seconds, RING_MID_RADIUS * ringBreath,
                    ringAlpha, writeT);
        }
        // Bridge ring: one soft ring sweeps from the L1 ring radius out to the newborn
        // layer's home radius, peaking mid-morph — the energy visibly CARRIES the change.
        if (morphing && tier >= 1 && level >= 2) {
            float target = MORPH_TARGET_RADIUS[Mth.clamp(level, 2, 5) - 2];
            drawSoftRing(celestialPose, Mth.lerp(birth, RING_MID_RADIUS, target), 5.0F,
                    0.82F, 0.55F, 1.00F,
                    0.28F * strength * Mth.sin(morphT * (float) Math.PI));
        }
        if (tier <= 0) {
            return; // minimal tier: the ring alone carries the tell
        }

        if (level >= 2) {
            boolean newborn = morphing && morphFromLevel < 2;
            drawGlyphConstellation(layerPose(celestialPose, newborn, birth), seconds,
                    strength * (newborn ? birth : oldSwell), tier);
        }
        if (level >= 3 && tier >= 2) {
            boolean newborn = morphing && morphFromLevel < 3;
            drawAuroraBands(layerPose(celestialPose, newborn, birth), seconds,
                    strength * (newborn ? birth : oldSwell),
                    AltarCeremonyFx.offeringSkyGlow(partialTick));
        }
        if (level >= 4) {
            boolean newborn = morphing && morphFromLevel < 4;
            drawHaloBeams(layerPose(celestialPose, newborn, birth), seconds,
                    strength * (newborn ? birth : oldSwell), tier);
        }
        if (level >= 5) {
            boolean newborn = morphing && morphFromLevel < 5;
            drawCoronaCrown(layerPose(celestialPose, newborn, birth), seconds,
                    strength * (newborn ? birth : oldSwell), surge,
                    AltarCeremonyFx.skySurgeEchoTravel(partialTick), tier);
        }
    }

    /**
     * The pose a layer draws with: newborn layers (mid-morph, above the from-level) grow
     * out of the disc — the celestial pose scaled 55% → 100% in the plane (Y untouched).
     * Returns the pre-allocated {@link #MORPH_POSE} scratch; draws are immediate, so
     * sequential reuse across layers is safe.
     */
    private static Matrix4f layerPose(Matrix4f base, boolean newborn, float birth) {
        if (!newborn) {
            return base;
        }
        float s = 0.55F + 0.45F * birth;
        return MORPH_POSE.set(base).scale(s, 1.0F, s);
    }

    // ------------------------------------------------------------------ level tracking

    /**
     * Watches the synced altar level from the render side. The FIRST observation of a
     * session (or any decrease — a world/server resync) is adopted silently; a genuine
     * mid-session increase from level 0 arms the L1 write-in intro. Login therefore
     * never replays the intro, but the community's 0→1 moment always gets it.
     */
    private static void trackLevel(int level, float seconds) {
        if (lastSeenLevel == Integer.MIN_VALUE || level < lastSeenLevel) {
            lastSeenLevel = level;
            ringWriteStart = Float.NaN;
            morphStart = Float.NaN;
            return;
        }
        if (level > lastSeenLevel) {
            if (lastSeenLevel < 1) {
                ringWriteStart = seconds;
            } else {
                // VEIL-REPASS-2: a genuine ≥1 → higher level-up arms the tier morph
                // (a multi-step jump morphs once, from the level the client last saw).
                morphStart = seconds;
                morphFromLevel = lastSeenLevel;
            }
            lastSeenLevel = level;
        }
    }

    /** Morph progress 0..1; 1 while no morph is live (or across the hourly clock wrap). */
    private static float morphProgress(float seconds) {
        if (Float.isNaN(morphStart)) {
            return 1.0F;
        }
        float t = (seconds - morphStart) / MORPH_SECONDS;
        if (t < 0.0F || t >= 1.0F) {
            morphStart = Float.NaN; // done (or the seconds clock wrapped) — steady state
            return 1.0F;
        }
        return t;
    }

    /** Write-in progress 0..1; 1 while no intro is live (or across the hourly clock wrap). */
    private static float ringWriteProgress(float seconds) {
        if (Float.isNaN(ringWriteStart)) {
            return 1.0F;
        }
        float t = (seconds - ringWriteStart) / RING_WRITE_SECONDS;
        if (t < 0.0F || t >= 1.0F) {
            ringWriteStart = Float.NaN; // done (or the seconds clock wrapped) — full ring
            return 1.0F;
        }
        return t;
    }

    /**
     * L1 write-in: the ring as a partial arc growing from a fixed start angle, slightly
     * over-bright while being written, with a bright pen-tip diamond at the writing head.
     */
    private static void drawRingWriteIn(Matrix4f pose, float seconds, float midRadius,
            float ringAlpha, float writeT) {
        float sweep = smooth(writeT) * ((float) Math.PI * 2.0F);
        float startAngle = -0.5F * (float) Math.PI; // "12 o'clock" over the disc
        drawSoftArc(pose, midRadius, RING_HALF_WIDTH, 0.62F, 0.30F, 1.00F,
                ringAlpha * 1.35F, startAngle, sweep);
        // Pen tip: a sparking bright head, flickering slightly as it writes.
        float head = startAngle + sweep;
        float spark = 0.75F + 0.25F * Mth.sin(seconds * 11.0F);
        BufferBuilder tip = Tesselator.getInstance().begin(
                VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_COLOR);
        addDiamond(tip, pose, Mth.cos(head) * midRadius, Mth.sin(head) * midRadius,
                RING_PEN_TIP_SIZE * (0.8F + 0.4F * spark),
                0.95F, 0.85F, 1.00F, Math.min(1.0F, ringAlpha * 6.0F) * spark);
        BufferUploader.drawWithShader(tip.buildOrThrow());
    }

    // ------------------------------------------------------------------ layers

    /**
     * Slow-orbiting diamond glyphs with one trailing companion spark each.
     *
     * <p>W-P-ALTAR2 motif (tier 2): the constellation periodically RE-ARRANGES — during
     * the first {@value #REARRANGE_LENGTH_SECONDS} s of every
     * {@value #REARRANGE_PERIOD_SECONDS} s cycle each glyph glides from its current
     * radius-jitter/angle-scatter row to the next permutation (index-shifted, so the end
     * of cycle N is exactly the start of cycle N+1 — no snapping), under a soft
     * chime-like brightness swell. Deterministic; zero render-loop RNG.</p>
     */
    private static void drawGlyphConstellation(Matrix4f pose, float seconds, float strength, int tier) {
        int count = tier >= 2 ? GLYPH_COUNT : 5;
        float orbit = seconds * GLYPH_ORBIT_DEG_PER_SEC * ((float) Math.PI / 180.0F);
        // Tier 1 pins cycle 0 / blend 1 — a STATIC arrangement (no rearrange, no snap).
        boolean rearranging = tier >= 2;
        int cycle = rearranging ? (int) (seconds / REARRANGE_PERIOD_SECONDS) : 0;
        float windowT = rearranging
                ? Math.min((seconds - cycle * REARRANGE_PERIOD_SECONDS) / REARRANGE_LENGTH_SECONDS, 1.0F)
                : 1.0F;
        float blend = smooth(windowT);
        float chime = rearranging && windowT < 1.0F ? Mth.sin(windowT * (float) Math.PI) : 0.0F;
        BufferBuilder builder = Tesselator.getInstance().begin(
                VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_COLOR);
        for (int i = 0; i < count; i++) {
            int from = (i + cycle) % GLYPH_COUNT;
            int to = (i + cycle + 1) % GLYPH_COUNT;
            float angle = orbit + i * ((float) Math.PI * 2.0F / GLYPH_COUNT)
                    + Mth.lerp(blend, GLYPH_ANGLE_SCATTER[from], GLYPH_ANGLE_SCATTER[to]);
            float radius = GLYPH_ORBIT_RADIUS
                    + Mth.lerp(blend, GLYPH_RADIUS_JITTER[from], GLYPH_RADIUS_JITTER[to]);
            float cx = Mth.cos(angle) * radius;
            float cz = Mth.sin(angle) * radius;
            // Per-glyph pulse, phase-offset so the constellation twinkles, never strobes;
            // the rearrange window adds the shared chime swell on top.
            float pulse = (0.75F + 0.25F * Mth.sin(seconds * 1.1F + i * 2.4F))
                    * (1.0F + 0.45F * chime);
            float alpha = GLYPH_ALPHA * strength * pulse;
            addDiamond(builder, pose, cx, cz, GLYPH_SIZES[i], 0.72F, 0.42F, 1.00F, alpha);
            GLYPH_X[i] = cx;
            GLYPH_Z[i] = cz;
            // Trailing companion spark just behind the glyph on its orbit.
            float trail = angle - 0.05F;
            addDiamond(builder, pose,
                    Mth.cos(trail) * (radius - 2.5F), Mth.sin(trail) * (radius - 2.5F),
                    GLYPH_SIZES[i] * 0.35F, 0.85F, 0.65F, 1.00F,
                    alpha * (0.6F + 0.25F * chime));
        }
        // VEIL-REPASS-2 (L2 motif upgrade): while the constellation rearranges, the
        // glyphs CONNECT — hairline light joins each glyph to the next around the loop,
        // rising and dying with the chime swell, brighter toward the destination end so
        // the light reads as FLOWING along the glide. chime is only nonzero on tier 2,
        // so the lines are automatically ladder-gated with the rearrange itself.
        if (chime > 0.01F) {
            float lineAlpha = GLYPH_ALPHA * strength * chime * 0.5F;
            for (int i = 0; i < count; i++) {
                int j = (i + 1) % count;
                addHairline(builder, pose, GLYPH_X[i], GLYPH_Z[i],
                        GLYPH_X[j], GLYPH_Z[j], lineAlpha);
            }
        }
        BufferUploader.drawWithShader(builder.buildOrThrow());
    }

    /**
     * One hairline connect quad from glyph 1 toward glyph 2 ({@value #CONNECT_HALF_WIDTH}
     * half-width), trimmed {@value #CONNECT_TRIM} units off both ends so it meets the
     * diamond rims, alpha ramping 35% → 100% toward the destination (directional flow).
     */
    private static void addHairline(BufferBuilder builder, Matrix4f pose,
            float x1, float z1, float x2, float z2, float alpha) {
        float dx = x2 - x1;
        float dz = z2 - z1;
        float len = Mth.sqrt(dx * dx + dz * dz);
        if (len < CONNECT_TRIM * 2.5F) {
            return; // glyphs practically touching — nothing worth drawing
        }
        dx /= len;
        dz /= len;
        x1 += dx * CONNECT_TRIM;
        z1 += dz * CONNECT_TRIM;
        x2 -= dx * CONNECT_TRIM;
        z2 -= dz * CONNECT_TRIM;
        float px = -dz * CONNECT_HALF_WIDTH;
        float pz = dx * CONNECT_HALF_WIDTH;
        builder.addVertex(pose, x1 - px, PLANE_Y, z1 - pz)
                .setColor(0.88F, 0.70F, 1.00F, alpha * 0.35F);
        builder.addVertex(pose, x1 + px, PLANE_Y, z1 + pz)
                .setColor(0.88F, 0.70F, 1.00F, alpha * 0.35F);
        builder.addVertex(pose, x2 + px, PLANE_Y, z2 + pz)
                .setColor(0.88F, 0.70F, 1.00F, alpha);
        builder.addVertex(pose, x2 - px, PLANE_Y, z2 - pz)
                .setColor(0.88F, 0.70F, 1.00F, alpha);
    }

    /**
     * Three undulating arc curtains, teal fading into violet, scrolling around the disc.
     *
     * <p>W-P-ALTAR2 motif: {@code offeringGlow} (0..1, armed when the altar swallows an
     * offering) briefly BRIGHTENS the curtains and deepens their ripple — the sky
     * acknowledging the meal. Value-agnostic: brightness never leaks offering worth.</p>
     */
    private static void drawAuroraBands(Matrix4f pose, float seconds, float strength,
            float offeringGlow) {
        float glowAlpha = 1.0F + 1.6F * offeringGlow;
        float glowWave = 1.0F + 0.4F * offeringGlow;
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
                        * AURORA_WAVE_AMPLITUDE * glowWave;
                float radius = bandRadius + wave;
                // Alpha fades to zero at both arc ends (soft curtain edges).
                float edge = Mth.sin(t * (float) Math.PI);
                float alpha = AURORA_ALPHA * strength * edge * glowAlpha;
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

    /**
     * Bright gold crown ring + twelve spikes + the periodic pulse-flash echo ring.
     *
     * <p>W-P-ALTAR2 motif: on top of the 12 s pulse, a rarer map-wide CROWN FLARE every
     * {@value #FLARE_PERIOD_SECONDS} s — spikes stretch, the crown blooms brighter than
     * any pulse, and (tier 2) the echo ring fires. Tier 1 keeps the flare at half
     * strength so reduced clients still get the map-wide L5 heartbeat.</p>
     */
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

        // Crown-flare envelope (independent long-period beat, tier-scaled).
        float flarePhase = seconds % FLARE_PERIOD_SECONDS;
        float flare = flarePhase < FLARE_LENGTH_SECONDS
                ? Mth.sin(flarePhase / FLARE_LENGTH_SECONDS * (float) Math.PI) : 0.0F;
        if (tier < 2) {
            flare *= 0.5F;
        }

        float crownRadius = CROWN_MID_RADIUS * (1.0F + 0.12F * pulse + 0.05F * flare);
        float crownAlpha = CROWN_ALPHA * strength * (1.0F + 1.6F * pulse + 1.15F * flare);
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
            float tipR = rootR + CROWN_SPIKE_LENGTH * (1.0F + 0.6F * pulse + 0.75F * flare);
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
        // W-P-ALTAR2: the crown flare fires the echo too (surge > pulse > flare priority).
        if (tier >= 2) {
            float travel;
            float echoStrength;
            if (surgeEchoTravel < 1.0F) {
                travel = surgeEchoTravel;
                echoStrength = 1.0F;
            } else if (pulse > 0.01F && phase < PULSE_LENGTH_SECONDS && surge < pulse) {
                travel = phase / PULSE_LENGTH_SECONDS;
                echoStrength = pulse;
            } else if (flare > 0.01F && flarePhase < FLARE_LENGTH_SECONDS) {
                travel = flarePhase / FLARE_LENGTH_SECONDS;
                echoStrength = flare;
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
        drawSoftArc(pose, midRadius, halfWidth, r, g, b, alpha,
                0.0F, (float) Math.PI * 2.0F);
    }

    /**
     * Partial soft annulus from {@code startAngle} over {@code sweep} radians (the L1
     * write-in path; a full 2π sweep is exactly the old soft ring). Segment count scales
     * with the sweep so short arcs stay cheap and full rings keep their roundness.
     */
    private static void drawSoftArc(Matrix4f pose, float midRadius, float halfWidth,
            float r, float g, float b, float alpha, float startAngle, float sweep) {
        if (alpha <= 0.001F || sweep <= 0.001F) {
            return;
        }
        int segments = Math.max(2,
                Math.round(RING_SEGMENTS * sweep / ((float) Math.PI * 2.0F)));
        BufferBuilder builder = Tesselator.getInstance().begin(
                VertexFormat.Mode.TRIANGLE_STRIP, DefaultVertexFormat.POSITION_COLOR);
        for (int seg = 0; seg <= segments; seg++) {
            float angle = startAngle + seg * (sweep / segments);
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
        for (int seg = 0; seg <= segments; seg++) {
            float angle = startAngle + seg * (sweep / segments);
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

    /** Smoothstep ease (the AltarCeremonyFx envelope curve). */
    private static float smooth(float x) {
        x = Mth.clamp(x, 0.0F, 1.0F);
        return x * x * (3.0F - 2.0F * x);
    }
}
