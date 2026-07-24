package dev.projecteclipse.eclipse.veilfx.rift;

import java.util.List;

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
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RenderLevelStageEvent;

/**
 * World-space renderer for {@link RiftFx}'s tears (P2 R17): a seeded star-polygon
 * <b>glitch tear</b> — additive white-violet core over a dark alpha-blended edge fringe —
 * plus, for {@link RiftFx#STYLE_PORTAL}, the elliptical portal surface: a near-black void
 * disc and a counter-scrolling swirl disc scaled {@value #SWIRL_SCALE} and pushed
 * {@value #PARALLAX_BLOCKS} blocks along the camera view direction (cheap parallax depth
 * fake, frozen in R17).
 *
 * <p>Geometry is camera-relative {@code POSITION_COLOR} built with the vanilla-border draw
 * pattern proven by {@code border.client.BorderFxRenderer}, in <b>two sequential passes</b>
 * sharing one {@link Tesselator} (a Tesselator backs exactly one live {@link BufferBuilder}
 * at a time): first the alpha-blended fringe/void pass, then the additive core/swirl pass
 * on top. "Procedural distortion" is vertex-color pulses + a per-point integer-hash flicker
 * re-seeded every ~90 ms — the tear must read as unstable static, not a solid star.
 * Everything renders regardless of the Iris shaderpack state — world-space FX are the Iris
 * fallback (§7).</p>
 *
 * <p>Budgets (§3.5): hard early-outs (no rifts, {@code d² > }{@value #RENDER_RANGE}²,
 * open amount ≈ 0); per rift ≤ 160 triangles (core fan 2N + inner fan 2N + fringe 4N with
 * N ≤ 14 arms, + 2 × {@value #DISC_SEGMENTS}-segment portal discs), comfortably under the
 * frozen 400-tri cap. Zero per-frame heap allocations: visibility/perimeter scratch lives
 * in pre-sized static arrays, colors are primitive floats.</p>
 *
 * <p>Render stage: {@link #STAGE} ({@code AFTER_PARTICLES}). If depth-sorting artifacts
 * appear under Sodium, swap the constant to {@code AFTER_TRANSLUCENT_BLOCKS} — both fire
 * with the same matrices (repo-documented fallback, §1.14/§7 risk 2).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class RiftRenderer {
    /** The one place to swap to {@code AFTER_TRANSLUCENT_BLOCKS} if Sodium sorting misbehaves. */
    private static final RenderLevelStageEvent.Stage STAGE = RenderLevelStageEvent.Stage.AFTER_PARTICLES;

    /** Rifts beyond this camera distance are skipped entirely (d² early-out). */
    private static final double RENDER_RANGE = 256.0D;
    /** Portal-disc tessellation (24 segments ⇒ 24 tris per disc). */
    private static final int DISC_SEGMENTS = 24;
    /** Swirl disc scale + view-direction push (R17 frozen: "scaled 0.85, offset by view dir · 0.4"). */
    private static final float SWIRL_SCALE = 0.85F;
    private static final float PARALLAX_BLOCKS = 0.4F;
    /** Dark fringe extrusion as a fraction of the tear width. */
    private static final float FRINGE_FRACTION = 0.10F;
    /** Inner hot-core fan scale relative to the tear. */
    private static final float INNER_SCALE = 0.45F;
    /** Portal ellipse radii as fractions of the tear width (taller than wide). */
    private static final float PORTAL_RX = 0.34F;
    private static final float PORTAL_RY = 0.46F;
    /** Flicker re-seed cadence (~11 updates/s, the BorderFxRenderer glitch cadence). */
    private static final long FLICKER_FRAME_MILLIS = 90L;
    /** Mirrors {@code RiftFx}'s cap; sizes the per-frame visibility scratch. */
    private static final int MAX_VISIBLE = 8;

    // Per-frame visibility scratch (filled by the cull loop, read by both passes).
    private static final RiftFx.Rift[] VIS_RIFT = new RiftFx.Rift[MAX_VISIBLE];
    private static final float[] VIS_X = new float[MAX_VISIBLE];
    private static final float[] VIS_Y = new float[MAX_VISIBLE];
    private static final float[] VIS_Z = new float[MAX_VISIBLE];
    private static final float[] VIS_OPEN = new float[MAX_VISIBLE];

    /** Perimeter scratch (star tips + valleys: 2 points per arm), camera-relative + in-plane dir. */
    private static final int MAX_PERIM = RiftFx.MAX_ARMS * 2;
    private static final float[] PERIM_X = new float[MAX_PERIM];
    private static final float[] PERIM_Y = new float[MAX_PERIM];
    private static final float[] PERIM_Z = new float[MAX_PERIM];
    private static final float[] OUT_X = new float[MAX_PERIM];
    private static final float[] OUT_Y = new float[MAX_PERIM];
    private static final float[] OUT_Z = new float[MAX_PERIM];

    private RiftRenderer() {}

    @SubscribeEvent
    static void onRenderLevelStage(RenderLevelStageEvent event) {
        if (event.getStage() != STAGE) {
            return;
        }
        List<RiftFx.Rift> rifts = RiftFx.rifts();
        if (rifts.isEmpty()) {
            return; // zero cost while idle: nothing built, no GL state touched
        }
        if (Minecraft.getInstance().level == null) {
            return;
        }
        float partialTick = event.getPartialTick().getGameTimeDeltaPartialTick(false);
        float now = RiftFx.timeNow(partialTick);
        Vec3 camera = event.getCamera().getPosition();
        long millis = System.currentTimeMillis();
        int flickerFrame = (int) (millis / FLICKER_FRAME_MILLIS);
        float swirlSeconds = (millis % 100_000L) / 1000.0F;

        // Cull once; both passes reuse the result.
        int visible = 0;
        for (int i = 0; i < rifts.size() && visible < MAX_VISIBLE; i++) {
            RiftFx.Rift rift = rifts.get(i);
            double dx = rift.pos.x - camera.x;
            double dy = rift.pos.y - camera.y;
            double dz = rift.pos.z - camera.z;
            if (dx * dx + dy * dy + dz * dz > RENDER_RANGE * RENDER_RANGE) {
                continue;
            }
            float open = rift.openAmount(now);
            if (open <= 0.005F) {
                continue;
            }
            VIS_RIFT[visible] = rift;
            VIS_X[visible] = (float) dx;
            VIS_Y[visible] = (float) dy;
            VIS_Z[visible] = (float) dz;
            VIS_OPEN[visible] = open;
            visible++;
        }
        if (visible == 0) {
            return;
        }

        RenderSystem.enableBlend();
        RenderSystem.setShader(GameRenderer::getPositionColorShader);
        RenderSystem.disableCull();
        RenderSystem.enableDepthTest();
        RenderSystem.depthMask(false);

        // Pass A (alpha blend): dark edge fringe + portal void disc.
        BufferBuilder alpha = Tesselator.getInstance()
                .begin(VertexFormat.Mode.TRIANGLES, DefaultVertexFormat.POSITION_COLOR);
        for (int v = 0; v < visible; v++) {
            fillPerimeter(VIS_RIFT[v], VIS_X[v], VIS_Y[v], VIS_Z[v], VIS_OPEN[v], flickerFrame);
            buildAlpha(VIS_RIFT[v], alpha, VIS_X[v], VIS_Y[v], VIS_Z[v], VIS_OPEN[v], swirlSeconds);
        }
        MeshData alphaMesh = alpha.build();
        if (alphaMesh != null) {
            RenderSystem.blendFuncSeparate(GlStateManager.SourceFactor.SRC_ALPHA,
                    GlStateManager.DestFactor.ONE_MINUS_SRC_ALPHA,
                    GlStateManager.SourceFactor.ONE, GlStateManager.DestFactor.ONE_MINUS_SRC_ALPHA);
            BufferUploader.drawWithShader(alphaMesh);
        }

        // Pass B (additive, on top): white-violet core fans + portal swirl disc.
        BufferBuilder additive = Tesselator.getInstance()
                .begin(VertexFormat.Mode.TRIANGLES, DefaultVertexFormat.POSITION_COLOR);
        for (int v = 0; v < visible; v++) {
            fillPerimeter(VIS_RIFT[v], VIS_X[v], VIS_Y[v], VIS_Z[v], VIS_OPEN[v], flickerFrame);
            buildAdditive(VIS_RIFT[v], additive, VIS_X[v], VIS_Y[v], VIS_Z[v], VIS_OPEN[v], swirlSeconds);
        }
        MeshData additiveMesh = additive.build();
        if (additiveMesh != null) {
            RenderSystem.blendFuncSeparate(GlStateManager.SourceFactor.SRC_ALPHA,
                    GlStateManager.DestFactor.ONE,
                    GlStateManager.SourceFactor.ONE, GlStateManager.DestFactor.ZERO);
            BufferUploader.drawWithShader(additiveMesh);
        }

        RenderSystem.depthMask(true);
        RenderSystem.enableCull();
        RenderSystem.disableBlend();
        RenderSystem.defaultBlendFunc();

        // Drop rift references so a closed rift is collectable between frames.
        for (int v = 0; v < visible; v++) {
            VIS_RIFT[v] = null;
        }
    }

    /**
     * Fills the perimeter scratch for one rift: alternating star tips and valleys, each
     * with a flickering radius and slightly jittered angle. {@code cx/cy/cz} = rift center
     * relative to the camera.
     */
    private static void fillPerimeter(RiftFx.Rift rift, float cx, float cy, float cz,
            float open, int flickerFrame) {
        int arms = rift.armCount;
        float radius = rift.width * 0.5F * open;
        for (int i = 0; i < arms; i++) {
            float tipAngle = rift.armAngle[i] + (hash01(rift.seed, i * 2, flickerFrame) - 0.5F) * 0.06F;
            // 0.82–1.0 tip flicker (VFXPOLISH-3, was 0.86): slightly deeper arm shudder so
            // the tear visibly convulses instead of shimmering — same budget, same cadence.
            float tipRadius = radius * rift.armLength[i]
                    * (0.82F + 0.18F * hash01(rift.seed, i * 5 + 1, flickerFrame));
            emitPerimeter(rift, i * 2, tipAngle, tipRadius, cx, cy, cz);
            float nextAngle = i + 1 < arms ? rift.armAngle[i + 1] : rift.armAngle[0] + Mth.TWO_PI;
            float valleyAngle = (rift.armAngle[i] + nextAngle) * 0.5F;
            float valleyRadius = radius * rift.valleyRadius[i]
                    * (0.90F + 0.10F * hash01(rift.seed, i * 7 + 3, flickerFrame));
            emitPerimeter(rift, i * 2 + 1, valleyAngle, valleyRadius, cx, cy, cz);
        }
    }

    /** Alpha pass: dark edge fringe extruded outward + the PORTAL void ellipse. */
    private static void buildAlpha(RiftFx.Rift rift, BufferBuilder alpha,
            float cx, float cy, float cz, float open, float swirlSeconds) {
        int perim = rift.armCount * 2;
        float fringe = rift.width * FRINGE_FRACTION * open;
        float fringeAlpha = 0.78F * open;
        for (int k = 0; k < perim; k++) {
            int k1 = k + 1 == perim ? 0 : k + 1;
            float ox0 = PERIM_X[k] + OUT_X[k] * fringe;
            float oy0 = PERIM_Y[k] + OUT_Y[k] * fringe;
            float oz0 = PERIM_Z[k] + OUT_Z[k] * fringe;
            float ox1 = PERIM_X[k1] + OUT_X[k1] * fringe;
            float oy1 = PERIM_Y[k1] + OUT_Y[k1] * fringe;
            float oz1 = PERIM_Z[k1] + OUT_Z[k1] * fringe;
            // Quad as two triangles: inner edge dark violet-black, outer edge fully transparent.
            alpha.addVertex(PERIM_X[k], PERIM_Y[k], PERIM_Z[k]).setColor(0.045F, 0.0F, 0.10F, fringeAlpha);
            alpha.addVertex(PERIM_X[k1], PERIM_Y[k1], PERIM_Z[k1]).setColor(0.045F, 0.0F, 0.10F, fringeAlpha);
            alpha.addVertex(ox1, oy1, oz1).setColor(0.02F, 0.0F, 0.05F, 0.0F);
            alpha.addVertex(PERIM_X[k], PERIM_Y[k], PERIM_Z[k]).setColor(0.045F, 0.0F, 0.10F, fringeAlpha);
            alpha.addVertex(ox1, oy1, oz1).setColor(0.02F, 0.0F, 0.05F, 0.0F);
            alpha.addVertex(ox0, oy0, oz0).setColor(0.02F, 0.0F, 0.05F, 0.0F);
        }

        if (rift.style != RiftFx.STYLE_PORTAL) {
            return;
        }
        // Void disc: near-black fan, edge brightness scrolling one way (the swirl disc in
        // the additive pass scrolls the other way — the counter-scroll sells the surface).
        float rx = rift.width * PORTAL_RX * open;
        float ry = rift.width * PORTAL_RY * open;
        float step = Mth.TWO_PI / DISC_SEGMENTS;
        for (int s = 0; s < DISC_SEGMENTS; s++) {
            float a0 = s * step;
            float a1 = a0 + step;
            float pulse0 = 0.70F + 0.30F * Mth.sin(a0 * 4.0F - swirlSeconds * 1.8F);
            float pulse1 = 0.70F + 0.30F * Mth.sin(a1 * 4.0F - swirlSeconds * 1.8F);
            alpha.addVertex(cx, cy, cz).setColor(0.03F, 0.008F, 0.075F, 0.88F * open);
            alpha.addVertex(ellipseX(rift, cx, a0, rx, ry), ellipseY(rift, cy, a0, rx, ry),
                    ellipseZ(rift, cz, a0, rx, ry))
                    .setColor(0.10F * pulse0, 0.03F * pulse0, 0.16F * pulse0, 0.75F * open);
            alpha.addVertex(ellipseX(rift, cx, a1, rx, ry), ellipseY(rift, cy, a1, rx, ry),
                    ellipseZ(rift, cz, a1, rx, ry))
                    .setColor(0.10F * pulse1, 0.03F * pulse1, 0.16F * pulse1, 0.75F * open);
        }
    }

    /** Additive pass: outer violet core fan + inner near-white hot fan + PORTAL swirl disc. */
    private static void buildAdditive(RiftFx.Rift rift, BufferBuilder additive,
            float cx, float cy, float cz, float open, float swirlSeconds) {
        int perim = rift.armCount * 2;
        // Per-rift eased breath (VFXPOLISH-3): the hot core swells ±8% on a slow sine —
        // phase from the seed's low bits so neighbouring tears never pulse in lockstep.
        float breathe = 0.92F + 0.08F * Mth.sin(swirlSeconds * 2.6F + (rift.seed & 31) * 0.41F);
        float coreAlpha = 0.75F * open * breathe;
        for (int k = 0; k < perim; k++) {
            int k1 = k + 1 == perim ? 0 : k + 1;
            additive.addVertex(cx, cy, cz).setColor(0.97F, 0.90F, 1.0F, coreAlpha);
            additive.addVertex(PERIM_X[k], PERIM_Y[k], PERIM_Z[k]).setColor(0.62F, 0.30F, 0.98F, 0.0F);
            additive.addVertex(PERIM_X[k1], PERIM_Y[k1], PERIM_Z[k1]).setColor(0.62F, 0.30F, 0.98F, 0.0F);
        }
        float innerAlpha = 0.95F * open;
        for (int k = 0; k < perim; k++) {
            int k1 = k + 1 == perim ? 0 : k + 1;
            additive.addVertex(cx, cy, cz).setColor(1.0F, 0.98F, 1.0F, innerAlpha);
            additive.addVertex(lerpToCenter(PERIM_X[k], cx), lerpToCenter(PERIM_Y[k], cy),
                    lerpToCenter(PERIM_Z[k], cz)).setColor(0.85F, 0.55F, 1.0F, 0.25F * open);
            additive.addVertex(lerpToCenter(PERIM_X[k1], cx), lerpToCenter(PERIM_Y[k1], cy),
                    lerpToCenter(PERIM_Z[k1], cz)).setColor(0.85F, 0.55F, 1.0F, 0.25F * open);
        }

        if (rift.style != RiftFx.STYLE_PORTAL) {
            return;
        }
        // Swirl disc: scaled copy pushed along the view direction (parallax depth fake),
        // brightness scrolling against the void-edge pulse.
        float rx = rift.width * PORTAL_RX * open * SWIRL_SCALE;
        float ry = rift.width * PORTAL_RY * open * SWIRL_SCALE;
        float len = (float) Math.sqrt((double) cx * cx + (double) cy * cy + (double) cz * cz);
        float push = len > 1.0E-3F ? PARALLAX_BLOCKS / len : 0.0F;
        float sx = cx + cx * push;
        float sy = cy + cy * push;
        float sz = cz + cz * push;
        float step = Mth.TWO_PI / DISC_SEGMENTS;
        for (int s = 0; s < DISC_SEGMENTS; s++) {
            float a0 = s * step;
            float a1 = a0 + step;
            float swirl0 = 0.5F + 0.5F * Mth.sin(a0 * 3.0F + swirlSeconds * 2.4F);
            float swirl1 = 0.5F + 0.5F * Mth.sin(a1 * 3.0F + swirlSeconds * 2.4F);
            additive.addVertex(sx, sy, sz).setColor(0.42F, 0.20F, 0.80F, 0.16F * open);
            additive.addVertex(ellipseX(rift, sx, a0, rx, ry), ellipseY(rift, sy, a0, rx, ry),
                    ellipseZ(rift, sz, a0, rx, ry)).setColor(0.55F, 0.30F, 0.95F, 0.38F * open * swirl0);
            additive.addVertex(ellipseX(rift, sx, a1, rx, ry), ellipseY(rift, sy, a1, rx, ry),
                    ellipseZ(rift, sz, a1, rx, ry)).setColor(0.55F, 0.30F, 0.95F, 0.38F * open * swirl1);
        }
    }

    /** Writes perimeter point {@code index} (position + unit in-plane outward dir) to the scratch arrays. */
    private static void emitPerimeter(RiftFx.Rift rift, int index, float angle, float radius,
            float cx, float cy, float cz) {
        float cos = Mth.cos(angle);
        float sin = Mth.sin(angle);
        float dirX = rift.tx * cos + rift.bx * sin;
        float dirY = rift.ty * cos + rift.by * sin;
        float dirZ = rift.tz * cos + rift.bz * sin;
        OUT_X[index] = dirX;
        OUT_Y[index] = dirY;
        OUT_Z[index] = dirZ;
        PERIM_X[index] = cx + dirX * radius;
        PERIM_Y[index] = cy + dirY * radius;
        PERIM_Z[index] = cz + dirZ * radius;
    }

    /** Ellipse point around a camera-relative center in the rift plane (tangent = rx, bitangent = ry). */
    private static float ellipseX(RiftFx.Rift rift, float cx, float angle, float rx, float ry) {
        return cx + rift.tx * Mth.cos(angle) * rx + rift.bx * Mth.sin(angle) * ry;
    }

    private static float ellipseY(RiftFx.Rift rift, float cy, float angle, float rx, float ry) {
        return cy + rift.ty * Mth.cos(angle) * rx + rift.by * Mth.sin(angle) * ry;
    }

    private static float ellipseZ(RiftFx.Rift rift, float cz, float angle, float rx, float ry) {
        return cz + rift.tz * Mth.cos(angle) * rx + rift.bz * Mth.sin(angle) * ry;
    }

    private static float lerpToCenter(float value, float center) {
        return center + (value - center) * INNER_SCALE;
    }

    /** Cheap deterministic per-point flicker noise in [0,1) (BorderFxRenderer hash pattern). */
    private static float hash01(int seed, int index, int frame) {
        int hash = seed ^ index * 668265261 ^ frame * 374761393;
        hash = (hash ^ (hash >>> 13)) * 1274126177;
        return ((hash ^ (hash >>> 16)) & 0xFFFF) / 65536.0F;
    }
}
