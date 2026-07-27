package dev.projecteclipse.eclipse.woah.mansiondome.client;

import com.mojang.blaze3d.platform.GlStateManager;
import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.vertex.BufferBuilder;
import com.mojang.blaze3d.vertex.BufferUploader;
import com.mojang.blaze3d.vertex.DefaultVertexFormat;
import com.mojang.blaze3d.vertex.MeshData;
import com.mojang.blaze3d.vertex.Tesselator;
import com.mojang.blaze3d.vertex.VertexFormat;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.Minecraft;
import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RenderLevelStageEvent;

/**
 * WOAH-01 §4.2 — the CPU dome shell, the BLICKDICHT guarantee: an OPAQUE,
 * depth-writing UV sphere over the mansion (near-black base), so "you cannot see in
 * from outside" never depends on the Veil post stack (Iris gate, {@code veilPostFx off},
 * budget eviction, failure fuse — the {@code SupplyBeamRenderer} shader-less law).
 *
 * <p>Three passes from ONE pooled {@link Tesselator}, all vanilla render state:</p>
 * <ol>
 *   <li><b>Base</b> — opaque (blend OFF, depth write ON, backface cull) near-black
 *       (0.01/0.03/0.02) with a Fresnel rim brightening baked into the vertex colour
 *       (2&nbsp;Hz pulse; accelerates + brightens over the collapse t0–t30). During the
 *       arm fade-in ({@code visibility < 1}) this pass runs translucent without depth
 *       write — full opacity is only claimed once the shield is fully up;</li>
 *   <li><b>Scanlines</b> — additive {@code noise_strip.png}, V-scroll ≈ 0.6 s/repeat,
 *       GlitchColors green (0.30/0.95/0.62), rim-weighted alpha, drawn at 99.7% radius
 *       so depth-test against the base pass never fights;</li>
 *   <li><b>Hex shimmer</b> — additive {@code border_glitch.png} on sphere UVs with a
 *       slow yaw drift, at 99.4% radius (near LOD only).</li>
 * </ol>
 *
 * <p>Geometry: upper hemisphere + 2 rings below the horizon (the rest is underground),
 * {@value #LON_NEAR}×{@value #LAT_NEAR} segments near, {@value #LON_FAR}×{@value #LAT_FAR}
 * beyond {@value #FAR_LOD_DIST} blocks from the hull, nothing past
 * {@value #MAX_RENDER_DISTANCE}. Camera INSIDE: the opaque passes are skipped entirely
 * (the interior read is the {@code glitch_dome} zone post) — only a faint additive
 * interior film (alpha ≤ {@value #INTERIOR_FILM_ALPHA}, cull off ≙ inverted cull on a
 * sphere) keeps the bubble rim legible from within. Active only while ACTIVE/COLLAPSING,
 * hard-off at the t30 shatter beat — from there the server's BlockDisplay shards own the
 * sky. Sodium/Embeddium depth-sort artifacts: swap {@link #STAGE} to
 * {@code AFTER_PARTICLES} (documented SupplyBeam fallback).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
@OnlyIn(Dist.CLIENT)
public final class DomeShellRenderer {
    /** Opaque + depth-writing ⇒ before translucents/particles composite over it. */
    private static final RenderLevelStageEvent.Stage STAGE =
            RenderLevelStageEvent.Stage.AFTER_ENTITIES;

    private static final ResourceLocation SCANLINE_TEXTURE = ResourceLocation
            .fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/particle/noise_strip.png");
    private static final ResourceLocation HEX_TEXTURE = ResourceLocation
            .fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/environment/border_glitch.png");

    /** Near LOD (~288 quads/pass); far LOD (~128) beyond {@value #FAR_LOD_DIST} blocks. */
    private static final int LON_NEAR = 24;
    private static final int LAT_NEAR = 12;
    private static final int LON_FAR = 16;
    private static final int LAT_FAR = 8;
    private static final double FAR_LOD_DIST = 300.0D;
    private static final double MAX_RENDER_DISTANCE = 640.0D;
    /** Lowest latitude (rad): two rings below the horizon, the rest is in the ground. */
    private static final float LAT_MIN = -0.38F;

    /** Near-black base (plan §4.2) + the GlitchColors phosphor green. */
    private static final float BASE_R = 0.01F;
    private static final float BASE_G = 0.03F;
    private static final float BASE_B = 0.02F;
    private static final float GREEN_R = 0.30F;
    private static final float GREEN_G = 0.95F;
    private static final float GREEN_B = 0.62F;

    /** Radius offsets keep the additive layers depth-inside the opaque hull. */
    private static final float SCAN_RADIUS_SCALE = 0.997F;
    private static final float HEX_RADIUS_SCALE = 0.994F;
    /** Interior film ceiling (plan: "Alpha ≤ 0.08"). */
    private static final float INTERIOR_FILM_ALPHA = 0.08F;

    private DomeShellRenderer() {}

    @SubscribeEvent
    static void onRenderLevelStage(RenderLevelStageEvent event) {
        if (event.getStage() != STAGE || Minecraft.getInstance().level == null
                || !MansionDomeClient.presentHere()) {
            return;
        }
        float partialTick = event.getPartialTick().getGameTimeDeltaPartialTick(false);
        float visibility = MansionDomeClient.visibility(partialTick);
        if (visibility <= 0.01F) {
            return;
        }
        float elapsed = MansionDomeClient.collapseElapsed(partialTick);
        if (elapsed >= MansionDomeClient.COLLAPSE_SHATTER_TICK) {
            return; // t30: hard off — the shard show takes over.
        }
        Vec3 camera = event.getCamera().getPosition();
        Vec3 centre = MansionDomeClient.centre();
        float radius = MansionDomeClient.shellRadius();
        double centreDist = camera.distanceTo(centre);
        if (centreDist - radius > MAX_RENDER_DISTANCE) {
            return;
        }

        // Collapse t0–t30: the 2 Hz pulse accelerates (→ ~7 Hz) and brightens ×1.8.
        float time = MansionDomeClient.timeSeconds(partialTick);
        float urgency = elapsed < 0.0F
                ? 0.0F : elapsed / MansionDomeClient.COLLAPSE_SHATTER_TICK;
        float pulseHz = 2.0F + 5.0F * urgency;
        float pulse = (0.75F + 0.25F * Mth.sin(time * pulseHz * Mth.TWO_PI))
                * (1.0F + 0.8F * urgency);

        float cx = (float) (centre.x - camera.x);
        float cy = (float) (centre.y - camera.y);
        float cz = (float) (centre.z - camera.z);
        boolean far = centreDist - radius > FAR_LOD_DIST;
        int lonSteps = far ? LON_FAR : LON_NEAR;
        int latSteps = far ? LAT_FAR : LAT_NEAR;

        if (MansionDomeClient.inside()) {
            // Interior film only: faint additive so the bubble rim reads from within.
            drawPass(buildSphere(cx, cy, cz, radius, lonSteps, latSteps,
                            8.0F, 12.0F, time / 0.6F, GREEN_R, GREEN_G, GREEN_B,
                            0.03F * pulse * visibility, INTERIOR_FILM_ALPHA * visibility,
                            pulse, visibility, true),
                    SCANLINE_TEXTURE, true, false, false);
            return;
        }

        // (1) Opaque near-black hull — THE guarantee (fade-in runs translucent).
        boolean solid = visibility >= 0.999F;
        drawPass(buildBase(cx, cy, cz, radius, lonSteps, latSteps,
                        solid ? 1.0F : visibility * 0.85F, pulse, urgency),
                SCANLINE_TEXTURE, false, solid, true);
        // (2) Scrolling scanlines, rim-weighted (V ≈ 0.6 s/repeat).
        drawPass(buildSphere(cx, cy, cz, radius * SCAN_RADIUS_SCALE, lonSteps, latSteps,
                        8.0F, 12.0F, time / 0.6F, GREEN_R, GREEN_G, GREEN_B,
                        0.05F * pulse * visibility, 0.30F * pulse * visibility,
                        pulse, visibility, false),
                SCANLINE_TEXTURE, true, false, true);
        // (3) Hex/cell shimmer with slow yaw drift (near LOD only — far away it aliases).
        if (!far) {
            drawPass(buildSphere(cx, cy, cz, radius * HEX_RADIUS_SCALE, lonSteps, latSteps,
                            6.0F, 3.0F, time * 0.05F * 6.0F, GREEN_R * 0.8F, GREEN_G * 0.8F,
                            GREEN_B * 0.8F, 0.04F * visibility, 0.16F * pulse * visibility,
                            pulse, visibility, false),
                    HEX_TEXTURE, true, false, true);
        }
    }

    // ------------------------------------------------------------------ geometry

    /**
     * The opaque base pass: near-black, alpha {@code alpha}, Fresnel rim (green) baked
     * into the vertex colour — {@code pow(1 − |dot(view, normal)|, 2)} × pulse.
     */
    private static MeshData buildBase(float cx, float cy, float cz, float radius,
            int lonSteps, int latSteps, float alpha, float pulse, float urgency) {
        BufferBuilder buffer = Tesselator.getInstance()
                .begin(VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_TEX_COLOR);
        float rimGain = (0.32F + 0.25F * urgency) * pulse;
        for (int lat = 0; lat < latSteps; lat++) {
            for (int lon = 0; lon < lonSteps; lon++) {
                for (int corner = 0; corner < 4; corner++) {
                    float[] v = corner(cx, cy, cz, radius, lonSteps, latSteps, lon, lat, corner);
                    float rim = rim(v, cx, cy, cz, radius);
                    buffer.addVertex(v[0], v[1], v[2]).setUv(0.5F, 0.5F).setColor(
                            Math.min(1.0F, BASE_R + GREEN_R * rim * rimGain),
                            Math.min(1.0F, BASE_G + GREEN_G * rim * rimGain),
                            Math.min(1.0F, BASE_B + GREEN_B * rim * rimGain),
                            alpha);
                }
            }
        }
        return buffer.build();
    }

    /**
     * One textured additive pass over the sphere: UVs are (longitude × {@code uRepeats}
     * + nothing, latitude × {@code vRepeats} − {@code vScroll}); alpha =
     * {@code alphaBase + alphaRim · rim}. {@code interior} flips the rim reference so the
     * film brightens toward the rim seen FROM INSIDE.
     */
    private static MeshData buildSphere(float cx, float cy, float cz, float radius,
            int lonSteps, int latSteps, float uRepeats, float vRepeats, float vScroll,
            float red, float green, float blue, float alphaBase, float alphaRim,
            float pulse, float visibility, boolean interior) {
        BufferBuilder buffer = Tesselator.getInstance()
                .begin(VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_TEX_COLOR);
        for (int lat = 0; lat < latSteps; lat++) {
            for (int lon = 0; lon < lonSteps; lon++) {
                for (int corner = 0; corner < 4; corner++) {
                    float[] v = corner(cx, cy, cz, radius, lonSteps, latSteps, lon, lat, corner);
                    float rim = rim(v, cx, cy, cz, radius);
                    if (interior) {
                        rim = 1.0F - rim; // from inside the "rim" is the glancing band too
                    }
                    float alpha = Math.min(alphaBase + alphaRim * rim,
                            interior ? INTERIOR_FILM_ALPHA : 1.0F);
                    buffer.addVertex(v[0], v[1], v[2])
                            .setUv(v[3] * uRepeats, v[4] * vRepeats - vScroll)
                            .setColor(red, green, blue, alpha);
                }
            }
        }
        return buffer.build();
    }

    /**
     * Camera-relative position + sphere UV of one quad corner. Corners wind CCW seen
     * from OUTSIDE (+lon then +lat), so backface culling keeps only the outward faces.
     * Returns the shared scratch {@code {x, y, z, u(lonFrac), v(latFrac)}}.
     */
    private static float[] corner(float cx, float cy, float cz, float radius,
            int lonSteps, int latSteps, int lon, int lat, int corner) {
        // Corner order: (lon,lat) → (lon+1,lat) → (lon+1,lat+1) → (lon,lat+1).
        int lonI = (corner == 1 || corner == 2) ? lon + 1 : lon;
        int latI = (corner == 2 || corner == 3) ? lat + 1 : lat;
        float lonFrac = lonI / (float) lonSteps;
        float latFrac = latI / (float) latSteps;
        float lonAngle = lonFrac * Mth.TWO_PI;
        float latAngle = LAT_MIN + latFrac * (Mth.HALF_PI - LAT_MIN);
        float cosLat = Mth.cos(latAngle);
        SCRATCH[0] = cx + radius * cosLat * Mth.cos(lonAngle);
        SCRATCH[1] = cy + radius * Mth.sin(latAngle);
        SCRATCH[2] = cz + radius * cosLat * Mth.sin(lonAngle);
        SCRATCH[3] = lonFrac;
        SCRATCH[4] = latFrac;
        return SCRATCH;
    }

    /** Shared corner scratch (render thread only — zero per-frame allocations). */
    private static final float[] SCRATCH = new float[5];

    /** Fresnel rim term of a camera-relative vertex: {@code pow(1 − |v̂·n̂|, 2)}. */
    private static float rim(float[] v, float cx, float cy, float cz, float radius) {
        float vx = v[0];
        float vy = v[1];
        float vz = v[2];
        float viewLen = Mth.sqrt(vx * vx + vy * vy + vz * vz);
        if (viewLen < 1.0E-4F) {
            return 0.0F;
        }
        // Normal = (vertex − centre) / radius; view = vertex / |vertex| (camera at origin).
        float nx = (vx - cx) / radius;
        float ny = (vy - cy) / radius;
        float nz = (vz - cz) / radius;
        float dot = Math.abs((vx * nx + vy * ny + vz * nz) / viewLen);
        float inv = 1.0F - Math.min(dot, 1.0F);
        return inv * inv;
    }

    // ------------------------------------------------------------------ draw

    /**
     * Uploads one mesh with the pass's render state. {@code additive} = SRC_ALPHA/ONE
     * blend + no depth write; {@code opaque} = blend OFF + depth write ON (the
     * guarantee); otherwise standard alpha blend (arm fade-in). {@code cull} off only
     * for the interior film (≙ inverted cull on a closed sphere).
     */
    private static void drawPass(MeshData mesh, ResourceLocation texture, boolean additive,
            boolean opaque, boolean cull) {
        if (mesh == null) {
            return;
        }
        RenderSystem.setShaderTexture(0, texture);
        RenderSystem.setShader(GameRenderer::getPositionTexColorShader);
        RenderSystem.enableDepthTest();
        if (cull) {
            RenderSystem.enableCull();
        } else {
            RenderSystem.disableCull();
        }
        if (opaque) {
            RenderSystem.disableBlend();
            RenderSystem.depthMask(true);
        } else {
            RenderSystem.enableBlend();
            RenderSystem.depthMask(false);
            if (additive) {
                RenderSystem.blendFuncSeparate(GlStateManager.SourceFactor.SRC_ALPHA,
                        GlStateManager.DestFactor.ONE, GlStateManager.SourceFactor.ONE,
                        GlStateManager.DestFactor.ZERO);
            } else {
                RenderSystem.defaultBlendFunc();
            }
        }
        BufferUploader.drawWithShader(mesh);
        // Restore the vanilla defaults we may have bent.
        RenderSystem.depthMask(true);
        RenderSystem.enableCull();
        RenderSystem.disableBlend();
        RenderSystem.defaultBlendFunc();
    }
}
