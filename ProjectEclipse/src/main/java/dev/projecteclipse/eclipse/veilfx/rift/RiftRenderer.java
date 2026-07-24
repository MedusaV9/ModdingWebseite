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
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.client.Minecraft;
import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RenderLevelStageEvent;

/**
 * World-space renderer for {@link RiftFx}'s tears — C7 "rift 2.0": a real VOLUMETRIC tear
 * instead of the old single billboard star. Each rift is an extruded star-prism of
 * {@value #SHELL_COUNT} depth-stacked, slowly counter-rotating jagged shells (additive
 * white-violet emissive, radius tapering toward the prism ends), a dark alpha-blended edge
 * fringe on the center shell, and flickering edge LIGHTNING ARCS crawling off the rim.
 * The tear's size still comes from the payload {@code a} param — the server now computes
 * it from the revealed structure's bounds ({@code StructurePendingRegistry.revealRiftWidth}),
 * so a loot ruin opens a small tear and a trial chamber a massive one. For
 * {@link RiftFx#STYLE_PORTAL} the elliptical portal surface remains: a near-black void
 * disc and a counter-scrolling swirl disc scaled {@value #SWIRL_SCALE} and pushed
 * {@value #PARALLAX_BLOCKS} blocks along the camera view direction (parallax interior;
 * the {@code rift_glitch} screen pulse of {@code TransitionFx} supplies the rest).
 *
 * <p>Geometry is camera-relative {@code POSITION_COLOR} built with the vanilla-border draw
 * pattern proven by {@code border.client.BorderFxRenderer}, in <b>two sequential passes</b>
 * sharing one {@link Tesselator} (a Tesselator backs exactly one live {@link BufferBuilder}
 * at a time): first the alpha-blended fringe/void pass, then the additive shells/arcs/swirl
 * pass on top. "Procedural distortion" is vertex-color pulses + a per-point integer-hash
 * flicker re-seeded every ~90 ms — the tear must read as unstable static, not a solid
 * star. Everything renders regardless of the Iris shaderpack state — world-space FX are
 * the Iris fallback (§7).</p>
 *
 * <p>Budgets (§3.5, recounted for C7 with N ≤ 14 arms → 28 perimeter points): shells
 * 5 × 28 core tris = 140, inner hot fans on the 3 middle shells 3 × 28 = 84, fringe 56,
 * arcs ≤ 3 × {@value #ARC_SEGMENTS} × 2 = 30, portal discs 48 → ≤ 358 triangles per rift,
 * still under the frozen 400-tri cap. {@code reducedFx} collapses to ONE shell and no
 * arcs — the pre-C7 geometry and budget exactly. Zero per-frame heap allocations:
 * visibility/perimeter/arc scratch lives in pre-sized static arrays, colors are primitive
 * floats.</p>
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

    // --- C7 volumetric prism ---
    /** Depth-stacked jagged shells of the star-prism (odd so one shell sits centered). */
    private static final int SHELL_COUNT = 5;
    private static final int CENTER_SHELL = SHELL_COUNT / 2;
    /** Per-shell offset along the tear normal, as a fraction of the tear width. */
    private static final float SHELL_DEPTH_FRACTION = 0.055F;
    /** Radius shrink per shell away from the center — tapers the prism toward its ends. */
    private static final float SHELL_TAPER = 0.13F;
    /** Additive-alpha falloff per shell away from the center. */
    private static final float SHELL_FADE = 0.28F;
    /** Slow base rotation of the whole tear (radians/second). */
    private static final float ROTATION_SPEED = 0.22F;
    /** Odd shells rotate against the grain at this factor (counter-rotation). */
    private static final float COUNTER_ROTATION = -0.7F;
    /** Static in-plane phase offset between neighboring shells (radians). */
    private static final float SHELL_PHASE = 0.75F;

    // --- C7 edge lightning arcs ---
    private static final int ARC_COUNT = 3;
    private static final int ARC_SEGMENTS = 5;
    /** Arc reach past the rim, as a fraction of the tear radius. */
    private static final float ARC_LENGTH_FRACTION = 0.38F;
    /** Arc half-width as a fraction of the tear width (thin jagged filaments). */
    private static final float ARC_WIDTH_FRACTION = 0.018F;
    /** Arcs strobe: an arc only draws while its per-frame gate hash exceeds this. */
    private static final float ARC_GATE = 0.45F;

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

    /** Lightning-arc polyline scratch (camera-relative points). */
    private static final float[] ARC_X = new float[ARC_SEGMENTS + 1];
    private static final float[] ARC_Y = new float[ARC_SEGMENTS + 1];
    private static final float[] ARC_Z = new float[ARC_SEGMENTS + 1];

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
        boolean reduced = EclipseClientConfig.reducedFx();

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

        // Pass A (alpha blend): dark edge fringe (center shell) + portal void disc.
        BufferBuilder alpha = Tesselator.getInstance()
                .begin(VertexFormat.Mode.TRIANGLES, DefaultVertexFormat.POSITION_COLOR);
        for (int v = 0; v < visible; v++) {
            buildAlpha(VIS_RIFT[v], alpha, VIS_X[v], VIS_Y[v], VIS_Z[v], VIS_OPEN[v],
                    swirlSeconds, flickerFrame);
        }
        MeshData alphaMesh = alpha.build();
        if (alphaMesh != null) {
            RenderSystem.blendFuncSeparate(GlStateManager.SourceFactor.SRC_ALPHA,
                    GlStateManager.DestFactor.ONE_MINUS_SRC_ALPHA,
                    GlStateManager.SourceFactor.ONE, GlStateManager.DestFactor.ONE_MINUS_SRC_ALPHA);
            BufferUploader.drawWithShader(alphaMesh);
        }

        // Pass B (additive, on top): shell stack + edge arcs + portal swirl disc.
        BufferBuilder additive = Tesselator.getInstance()
                .begin(VertexFormat.Mode.TRIANGLES, DefaultVertexFormat.POSITION_COLOR);
        for (int v = 0; v < visible; v++) {
            buildAdditive(VIS_RIFT[v], additive, VIS_X[v], VIS_Y[v], VIS_Z[v], VIS_OPEN[v],
                    swirlSeconds, flickerFrame, reduced);
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

    /** In-plane rotation of one shell: slow base spin, odd shells counter-rotating. */
    private static float shellRotation(int shell, float swirlSeconds) {
        float base = swirlSeconds * ROTATION_SPEED;
        return (shell % 2 == 0 ? base : base * COUNTER_ROTATION) + shell * SHELL_PHASE;
    }

    /**
     * Fills the perimeter scratch for one rift shell: alternating star tips and valleys,
     * each with a flickering radius and slightly jittered angle. {@code cx/cy/cz} = rift
     * center relative to the camera; {@code rotation} spins the whole star in-plane and
     * {@code radiusScale} tapers it (prism shells).
     */
    private static void fillPerimeter(RiftFx.Rift rift, float cx, float cy, float cz,
            float open, int flickerFrame, float rotation, float radiusScale) {
        int arms = rift.armCount;
        float radius = rift.width * 0.5F * open * radiusScale;
        for (int i = 0; i < arms; i++) {
            float tipAngle = rift.armAngle[i] + rotation
                    + (hash01(rift.seed, i * 2, flickerFrame) - 0.5F) * 0.06F;
            // 0.82–1.0 tip flicker (VFXPOLISH-3, was 0.86): slightly deeper arm shudder so
            // the tear visibly convulses instead of shimmering — same budget, same cadence.
            float tipRadius = radius * rift.armLength[i]
                    * (0.82F + 0.18F * hash01(rift.seed, i * 5 + 1, flickerFrame));
            emitPerimeter(rift, i * 2, tipAngle, tipRadius, cx, cy, cz);
            float nextAngle = i + 1 < arms ? rift.armAngle[i + 1] : rift.armAngle[0] + Mth.TWO_PI;
            float valleyAngle = (rift.armAngle[i] + nextAngle) * 0.5F + rotation;
            float valleyRadius = radius * rift.valleyRadius[i]
                    * (0.90F + 0.10F * hash01(rift.seed, i * 7 + 3, flickerFrame));
            emitPerimeter(rift, i * 2 + 1, valleyAngle, valleyRadius, cx, cy, cz);
        }
    }

    /** Alpha pass: dark edge fringe extruded outward (center shell) + the PORTAL void ellipse. */
    private static void buildAlpha(RiftFx.Rift rift, BufferBuilder alpha,
            float cx, float cy, float cz, float open, float swirlSeconds, int flickerFrame) {
        fillPerimeter(rift, cx, cy, cz, open, flickerFrame,
                shellRotation(CENTER_SHELL, swirlSeconds), 1.0F);
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

    /**
     * Additive pass: the volumetric shell stack (outer violet core fan per shell, inner
     * near-white hot fan on the middle shells), the strobing edge lightning arcs, and the
     * PORTAL swirl disc. {@code reducedFx} draws the center shell only and skips the arcs
     * — exactly the pre-C7 geometry.
     */
    private static void buildAdditive(RiftFx.Rift rift, BufferBuilder additive,
            float cx, float cy, float cz, float open, float swirlSeconds, int flickerFrame,
            boolean reduced) {
        int perim = rift.armCount * 2;
        // Per-rift eased breath (VFXPOLISH-3): the hot core swells ±8% on a slow sine —
        // phase from the seed's low bits so neighbouring tears never pulse in lockstep.
        float breathe = 0.92F + 0.08F * Mth.sin(swirlSeconds * 2.6F + (rift.seed & 31) * 0.41F);

        int firstShell = reduced ? CENTER_SHELL : 0;
        int lastShell = reduced ? CENTER_SHELL : SHELL_COUNT - 1;
        for (int shell = firstShell; shell <= lastShell; shell++) {
            int fromCenter = Math.abs(shell - CENTER_SHELL);
            float depth = reduced ? 0.0F
                    : (shell - CENTER_SHELL) * rift.width * SHELL_DEPTH_FRACTION * open;
            float dx = rift.nx * depth;
            float dy = rift.ny * depth;
            float dz = rift.nz * depth;
            float fade = 1.0F - fromCenter * SHELL_FADE;
            fillPerimeter(rift, cx, cy, cz, open, flickerFrame,
                    shellRotation(shell, swirlSeconds), 1.0F - fromCenter * SHELL_TAPER);

            float coreAlpha = 0.75F * open * breathe * fade;
            for (int k = 0; k < perim; k++) {
                int k1 = k + 1 == perim ? 0 : k + 1;
                additive.addVertex(cx + dx, cy + dy, cz + dz).setColor(0.97F, 0.90F, 1.0F, coreAlpha);
                additive.addVertex(PERIM_X[k] + dx, PERIM_Y[k] + dy, PERIM_Z[k] + dz)
                        .setColor(0.62F, 0.30F, 0.98F, 0.0F);
                additive.addVertex(PERIM_X[k1] + dx, PERIM_Y[k1] + dy, PERIM_Z[k1] + dz)
                        .setColor(0.62F, 0.30F, 0.98F, 0.0F);
            }
            if (fromCenter <= 1) {
                float innerAlpha = 0.95F * open * fade;
                for (int k = 0; k < perim; k++) {
                    int k1 = k + 1 == perim ? 0 : k + 1;
                    additive.addVertex(cx + dx, cy + dy, cz + dz).setColor(1.0F, 0.98F, 1.0F, innerAlpha);
                    additive.addVertex(lerpToCenter(PERIM_X[k], cx) + dx, lerpToCenter(PERIM_Y[k], cy) + dy,
                            lerpToCenter(PERIM_Z[k], cz) + dz).setColor(0.85F, 0.55F, 1.0F, 0.25F * open * fade);
                    additive.addVertex(lerpToCenter(PERIM_X[k1], cx) + dx, lerpToCenter(PERIM_Y[k1], cy) + dy,
                            lerpToCenter(PERIM_Z[k1], cz) + dz).setColor(0.85F, 0.55F, 1.0F, 0.25F * open * fade);
                }
            }
        }

        if (!reduced) {
            buildArcs(rift, additive, cx, cy, cz, open, flickerFrame);
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

    /**
     * C7 edge lightning: up to {@value #ARC_COUNT} jagged filaments crawling outward off
     * the tear rim, re-seeded on the flicker cadence and strobing on/off through a gate
     * hash. Each arc is a {@value #ARC_SEGMENTS}-segment polyline of thin quads extruded
     * along the tear normal, near-white at the rim fading to nothing at the tip.
     */
    private static void buildArcs(RiftFx.Rift rift, BufferBuilder additive,
            float cx, float cy, float cz, float open, int flickerFrame) {
        float r0 = rift.width * 0.5F * open;
        for (int a = 0; a < ARC_COUNT; a++) {
            float gate = hash01(rift.seed, 97 + a * 13, flickerFrame);
            if (gate < ARC_GATE) {
                continue; // this arc is dark this flicker frame (strobe)
            }
            float baseAngle = hash01(rift.seed, 41 + a * 7, flickerFrame / 3) * Mth.TWO_PI;
            for (int i = 0; i <= ARC_SEGMENTS; i++) {
                float f = i / (float) ARC_SEGMENTS;
                float angle = baseAngle
                        + (hash01(rift.seed, a * 31 + i * 3 + 1, flickerFrame) - 0.5F) * 0.55F * f;
                float radius = r0 * (1.0F + ARC_LENGTH_FRACTION * f);
                float wobble = (hash01(rift.seed, a * 17 + i * 5 + 2, flickerFrame) - 0.5F)
                        * rift.width * 0.08F * f;
                float cos = Mth.cos(angle);
                float sin = Mth.sin(angle);
                ARC_X[i] = cx + (rift.tx * cos + rift.bx * sin) * radius + rift.nx * wobble;
                ARC_Y[i] = cy + (rift.ty * cos + rift.by * sin) * radius + rift.ny * wobble;
                ARC_Z[i] = cz + (rift.tz * cos + rift.bz * sin) * radius + rift.nz * wobble;
            }
            float halfWidth = rift.width * ARC_WIDTH_FRACTION;
            for (int i = 0; i < ARC_SEGMENTS; i++) {
                float taper0 = 1.0F - i / (float) ARC_SEGMENTS;
                float taper1 = 1.0F - (i + 1) / (float) ARC_SEGMENTS;
                float w0 = halfWidth * (0.4F + 0.6F * taper0);
                float w1 = halfWidth * (0.4F + 0.6F * taper1);
                float alpha0 = 0.85F * open * gate * taper0;
                float alpha1 = 0.85F * open * gate * taper1;
                float ax0 = ARC_X[i] + rift.nx * w0;
                float ay0 = ARC_Y[i] + rift.ny * w0;
                float az0 = ARC_Z[i] + rift.nz * w0;
                float bx0 = ARC_X[i] - rift.nx * w0;
                float by0 = ARC_Y[i] - rift.ny * w0;
                float bz0 = ARC_Z[i] - rift.nz * w0;
                float ax1 = ARC_X[i + 1] + rift.nx * w1;
                float ay1 = ARC_Y[i + 1] + rift.ny * w1;
                float az1 = ARC_Z[i + 1] + rift.nz * w1;
                float bx1 = ARC_X[i + 1] - rift.nx * w1;
                float by1 = ARC_Y[i + 1] - rift.ny * w1;
                float bz1 = ARC_Z[i + 1] - rift.nz * w1;
                additive.addVertex(ax0, ay0, az0).setColor(0.88F, 0.72F, 1.0F, alpha0);
                additive.addVertex(bx0, by0, bz0).setColor(0.88F, 0.72F, 1.0F, alpha0);
                additive.addVertex(bx1, by1, bz1).setColor(0.95F, 0.85F, 1.0F, alpha1);
                additive.addVertex(ax0, ay0, az0).setColor(0.88F, 0.72F, 1.0F, alpha0);
                additive.addVertex(bx1, by1, bz1).setColor(0.95F, 0.85F, 1.0F, alpha1);
                additive.addVertex(ax1, ay1, az1).setColor(0.95F, 0.85F, 1.0F, alpha1);
            }
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
