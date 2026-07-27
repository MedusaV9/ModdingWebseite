package dev.projecteclipse.eclipse.client.sky;

import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.vertex.BufferBuilder;
import com.mojang.blaze3d.vertex.BufferUploader;
import com.mojang.blaze3d.vertex.DefaultVertexFormat;
import com.mojang.blaze3d.vertex.Tesselator;
import com.mojang.blaze3d.vertex.VertexFormat;

import org.joml.Matrix4f;

import dev.projecteclipse.eclipse.client.ClientStateCache;
import net.minecraft.client.Camera;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.renderer.FogRenderer;
import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * F-092 Layer A — the far-field rim-mountain silhouette ring (plan PLAN-F091-092 §3.2):
 * colossal dark mountains encircling the whole disc, visible from anywhere because they
 * are sky-pass geometry, not blocks. Drawn by {@link OverworldPurpleEffects} AFTER the
 * celestial pass and the stars (painter's algorithm — the ridgeline genuinely occludes
 * the rising eclipse sun and cuts a black ridge out of the star field at night) and
 * inherits the Iris guard (a shaderpack owns the sky, same degradation as the purple sun).
 *
 * <p><b>Geometry</b>: {@value #SEGMENTS} azimuth segments × 3 stacked ridge layers
 * (back tallest/darkest, front lighter with fog tint), one triangle strip each,
 * ≈1.5k vertices per frame — well inside the §5 budget. Peak heights come from a
 * FIXED-seed period-safe value noise over the azimuth ({@link #RIDGE}), precomputed
 * once per JVM, so every client renders the identical ridgeline without needing the
 * server's map seed.</p>
 *
 * <p><b>True-geometry parallax</b>: each layer is a virtual circle of radius
 * {@code ringRadius + LAYER_DIST[i]} around the synced border center. Per azimuth the
 * camera ray's ground distance to that circle is {@code t = −e·d + sqrt(R² − |e⊥|²)}
 * (camera offset {@code e}, ray direction {@code d}); every vertex keeps its true
 * elevation angle {@code atan((peakY − camY) / t)} and is projected onto a fixed
 * {@value #DOME_RADIUS}-unit sky dome (the sun-quad trick). The mountains therefore
 * genuinely LOOM as you approach the rim and flatten toward the horizon from the
 * center, although the layer is fake.</p>
 *
 * <p><b>Radius source</b>: {@link ClientStateCache#currentBorderRadius} — synced on
 * login and every stage commit and already area-proportionally lerped, so the
 * {@code SoftBorder} release lerp glides the whole ring outward on expansion day with
 * ZERO new networking ("langsam zurückweichen" for every player on the map).</p>
 *
 * <p><b>Crossfade</b> into the real Layer-B rim wall: per-vertex alpha ramps 0→1
 * between ground distance {@value #FADE_NEAR} and {@value #FADE_FAR} blocks, so inside
 * real render distance the fake layer yields exactly where the terrain wall
 * ({@code DiscTerrainFunction} rim uplift band) takes over. By night the vertex colors
 * dim with the day factor so the ring reads as a black cutout against the stars.</p>
 */
@OnlyIn(Dist.CLIENT)
final class RimMountainSilhouette {
    /** Azimuth resolution of every ridge strip. */
    private static final int SEGMENTS = 256;
    /** Sky-dome projection radius (the celestial quads live at ~100 units too). */
    private static final float DOME_RADIUS = 90.0F;
    /** Ground distance at which the silhouette is fully faded out (real wall visible). */
    private static final float FADE_NEAR = 80.0F;
    /** Ground distance at which the silhouette reaches full strength. */
    private static final float FADE_FAR = 200.0F;
    /** Elevation angle (radians) of the strip's bottom edge — safely below the horizon. */
    private static final float BOTTOM_ELEVATION = -0.12F;
    /** Fixed silhouette seed — NOT the map seed; every client shares the ridgeline. */
    private static final long RIDGE_SEED = 0x51_EC11_9E5EEDL;

    /** Distance of each virtual ridge circle beyond the synced ring radius (back→front). */
    private static final float[] LAYER_DIST = {64.0F, 40.0F, 18.0F};
    /** Base peak height (world blocks) of each layer. */
    private static final float[] LAYER_BASE_Y = {130.0F, 100.0F, 78.0F};
    /** Crest amplitude on top of the base height. */
    private static final float[] LAYER_AMP_Y = {90.0F, 72.0F, 55.0F};
    /** Deep-purple palette per layer, back darkest (matches OverworldPurpleEffects). */
    private static final float[][] LAYER_COLOR = {
            {0.075F, 0.030F, 0.110F},
            {0.110F, 0.050F, 0.160F},
            {0.160F, 0.085F, 0.225F}};
    /** How strongly each layer mixes toward the live fog color (front haziest). */
    private static final float[] LAYER_FOG_MIX = {0.06F, 0.18F, 0.34F};
    /** Peak opacity per layer. */
    private static final float[] LAYER_ALPHA = {0.98F, 0.92F, 0.85F};

    /**
     * Precomputed 0..1 crest profile per layer and azimuth segment: a sharp
     * {@code 1 − |2n − 1|} ridge octave (24 control points around the ring) plus a
     * high-frequency crag octave (96 points), both period-{@value #SEGMENTS} safe.
     */
    private static final float[][] RIDGE = buildRidges();

    private RimMountainSilhouette() {}

    /**
     * Draws the ring. Expects the sky pass state at the post-star point: depth writes
     * off, shader color white; enables standard alpha blending internally and leaves
     * blending disabled again. {@code setupFog} restores the sky fog afterwards (the
     * strips render fog-free like the stars — the fog tint is baked into the vertex
     * colors instead).
     */
    static void render(Matrix4f pose, ClientLevel level, Camera camera, float partialTick,
            Runnable setupFog) {
        double radius = ClientStateCache.currentBorderRadius(false, System.currentTimeMillis());
        if (radius <= 0.0D) {
            radius = ClientStateCache.stageRadiusOverworld;
        }
        if (radius <= 0.0D) {
            return;
        }
        Vec3 camPos = camera.getPosition();
        double ex = camPos.x - ClientStateCache.borderCenterX;
        double ez = camPos.z - ClientStateCache.borderCenterZ;
        double eLenSq = ex * ex + ez * ez;

        float day = OverworldPurpleEffects.dayFactor(level, partialTick);
        float bright = 0.30F + 0.70F * day; // night: near-black cutout against the stars
        float[] fog = RenderSystem.getShaderFogColor();

        RenderSystem.enableBlend();
        RenderSystem.defaultBlendFunc();
        RenderSystem.disableCull();
        RenderSystem.setShader(GameRenderer::getPositionColorShader);
        RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, 1.0F);
        FogRenderer.setupNoFog();

        float bottomCos = Mth.cos(BOTTOM_ELEVATION) * DOME_RADIUS;
        float bottomY = Mth.sin(BOTTOM_ELEVATION) * DOME_RADIUS;

        for (int layer = 0; layer < LAYER_DIST.length; layer++) {
            double ringR = radius + LAYER_DIST[layer];
            // Camera at or beyond this virtual circle (spectators past the border):
            // the ray solve below loses its "always inside" guarantee — skip the layer.
            double safeR = ringR - 8.0D;
            if (eLenSq >= safeR * safeR) {
                continue;
            }
            BufferBuilder builder = Tesselator.getInstance()
                    .begin(VertexFormat.Mode.TRIANGLE_STRIP, DefaultVertexFormat.POSITION_COLOR);
            for (int i = 0; i <= SEGMENTS; i++) {
                int seg = i % SEGMENTS;
                float az = (float) seg / SEGMENTS * ((float) Math.PI * 2.0F);
                float dx = Mth.cos(az);
                float dz = Mth.sin(az);
                // Ray-circle ground distance: t = −e·d + sqrt(R² − |e_perp|²).
                double ed = ex * dx + ez * dz;
                double disc = ringR * ringR - (eLenSq - ed * ed);
                float t = (float) (-ed + Math.sqrt(Math.max(0.0D, disc)));

                float peakY = LAYER_BASE_Y[layer] + RIDGE[layer][seg] * LAYER_AMP_Y[layer];
                float vy = (float) (peakY - camPos.y);
                float scale = DOME_RADIUS / (float) Math.sqrt((double) t * t + (double) vy * vy);

                // Atmospheric mix toward the live fog color grows with ground distance.
                float fogW = Math.min(0.55F, LAYER_FOG_MIX[layer] + 0.25F * t / 900.0F);
                float r = Mth.lerp(fogW, LAYER_COLOR[layer][0], fog[0]) * bright;
                float g = Mth.lerp(fogW, LAYER_COLOR[layer][1], fog[1]) * bright;
                float b = Mth.lerp(fogW, LAYER_COLOR[layer][2], fog[2]) * bright;
                // Crossfade with the real rim wall: gone within render distance.
                float alpha = LAYER_ALPHA[layer]
                        * Mth.clamp((t - FADE_NEAR) / (FADE_FAR - FADE_NEAR), 0.0F, 1.0F);

                builder.addVertex(pose, dx * bottomCos, bottomY, dz * bottomCos)
                        .setColor(r, g, b, alpha);
                builder.addVertex(pose, dx * t * scale, vy * scale, dz * t * scale)
                        .setColor(r, g, b, alpha);
            }
            BufferUploader.drawWithShader(builder.buildOrThrow());
        }

        setupFog.run();
        RenderSystem.enableCull();
        RenderSystem.disableBlend();
        RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, 1.0F);
    }

    /** Builds the per-layer crest tables once (fixed seed, wrap-safe over the ring). */
    private static float[][] buildRidges() {
        float[][] ridges = new float[LAYER_DIST.length][SEGMENTS];
        for (int layer = 0; layer < ridges.length; layer++) {
            for (int seg = 0; seg < SEGMENTS; seg++) {
                double az01 = (double) seg / SEGMENTS;
                double crestField = periodicValueNoise(layer, az01, 24, 0);
                double crest = 1.0D - Math.abs(2.0D * crestField - 1.0D); // sharp ridge lines
                double crag = periodicValueNoise(layer, az01, 96, 1);
                ridges[layer][seg] = (float) Mth.clamp(
                        0.72D * crest + 0.38D * crag, 0.0D, 1.05D);
            }
        }
        return ridges;
    }

    /** Smoothstep-interpolated value noise with an exact period of {@code cells} around the ring. */
    private static double periodicValueNoise(int layer, double az01, int cells, int octave) {
        double x = az01 * cells;
        int i0 = (int) Math.floor(x) % cells;
        double f = x - Math.floor(x);
        double v0 = cellValue(layer, octave, i0);
        double v1 = cellValue(layer, octave, (i0 + 1) % cells);
        double s = f * f * (3.0D - 2.0D * f);
        return v0 + (v1 - v0) * s;
    }

    /** Deterministic 0..1 hash of one noise control point (splitmix-style finalizer). */
    private static double cellValue(int layer, int octave, int cell) {
        long h = RIDGE_SEED + layer * 0x9E3779B97F4A7C15L + octave * 0xC2B2AE3D27D4EB4FL
                + cell * 0xD6E8FEB86659FD93L;
        h = (h ^ (h >>> 30)) * 0xBF58476D1CE4E5B9L;
        h = (h ^ (h >>> 27)) * 0x94D049BB133111EBL;
        h ^= h >>> 31;
        return (h >>> 11) * 0x1.0p-53D;
    }
}
