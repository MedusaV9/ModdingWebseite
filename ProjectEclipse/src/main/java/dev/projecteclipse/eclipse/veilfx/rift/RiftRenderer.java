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
 * <p><b>FXTEAM-RIFT additions</b> (see {@code docs/plans_v3/plans_v5/fxteams/RIFT.md}):
 * a two-layer parallax VOID WELL behind structure tears (dark fans pushed along the view
 * direction — the tear reads as a hole, not a poster), a dashed EVENT-HORIZON lensing rim
 * counter-scrolling against the shells (geometry-faked refraction: the Veil post stack is
 * Iris-gated and world FX are the Iris fallback, so no fullscreen pass), FORKING edge arcs
 * (the first two arcs may split a dimmer branch), a periodic PULSE PING ring breathing off
 * portal stars, an IRIS-OPEN entry flash + radial streamers when a player steps through,
 * and a per-rift palette ({@code hot/mid/dim} triple from {@link RiftFx.Rift}) that maps
 * C18's backrooms style to the wax-gold read.</p>
 *
 * <p><b>VEIL-REPASS-2 additions</b>: a piece-launch RECOIL — the whole tear compresses
 * up to 4% at each delivery launch tick ({@link RiftFx.Rift#recoilScale} multiplied onto
 * the open scale at cull time: every layer squashes coherently, zero extra geometry) —
 * and a void-well depth STARFIELD ({@link #buildVoidStars}): {@value #VOID_STARS} tiny
 * per-star-parallaxed triangles inside the dark fans = infinite depth.</p>
 *
 * <p>Budgets (§3.5, FXTEAM-RIFT recount, N ≤ 14 arms → 28 perimeter points): STRUCTURE =
 * shells 5 × 28 = 140 + inner hot fans 3 × 28 = 84 + fringe 56 + arcs 30 + forks
 * ≤ 2 × {@value #FORK_SEGMENTS} × 2 = 12 + lensing 28 + void well 2 × {@value
 * #VOID_SEGMENTS} = 24 + void stars {@value #VOID_STARS} (VEIL-REPASS-2) → 386.
 * PORTAL/BACKROOMS = 140 + inner fan (center shell only) 28 +
 * fringe 56 + arcs 30 + forks 12 + lensing 28 + discs 48 = 342 steady, + ping ring 32 ⊕
 * entry flash 24 (mutually exclusive by construction) → ≤ 374. Both stay under the frozen
 * 400-tri cap. {@code reducedFx} collapses to ONE shell, no arcs/forks/lensing/void/ping —
 * the pre-C7 geometry and budget exactly — keeping only the 12-tri iris fan of the entry
 * flash (it is gameplay feedback, not candy). Zero per-frame heap allocations:
 * visibility/perimeter/arc/fork scratch lives in pre-sized static arrays, colors are
 * primitive floats.</p>
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

    // --- FXTEAM-RIFT: forking arcs ---
    /** Only the first N arcs may fork (budget: ≤ 2 forks × 3 segs × 2 tris = 12). */
    private static final int FORK_ARCS = 2;
    private static final int FORK_SEGMENTS = 3;
    /** A fork only appears while the parent arc's gate hash exceeds this (rarer than arcs). */
    private static final float FORK_GATE = 0.72F;
    /** Main-arc point index the fork branches from (fraction 0.4 of the arc). */
    private static final int FORK_BASE_INDEX = 2;
    /** Angular divergence of the fork tip away from the parent arc (radians). */
    private static final float FORK_SPREAD = 0.34F;

    // --- FXTEAM-RIFT: void depth well (STRUCTURE tears) ---
    /** Fan tessellation of one void layer (12 tris each; 2 layers = 24). */
    private static final int VOID_SEGMENTS = 12;
    /** Layer radii as fractions of the tear radius (inside the star's valley floor). */
    private static final float VOID_SCALE_0 = 0.34F;
    private static final float VOID_SCALE_1 = 0.21F;
    /** View-direction push of the two layers, scaled by tear width (parallax depth). */
    private static final float VOID_PUSH_0 = 0.35F;
    private static final float VOID_PUSH_1 = 0.80F;

    // --- VEIL-REPASS-2: void-well depth starfield (STRUCTURE tears) ---
    /** Tiny stars floating INSIDE the void well, one in-plane triangle each (12 tris). */
    private static final int VOID_STARS = 12;
    /** Star in-plane spread as a fraction of the tear radius (inside the outer void fan). */
    private static final float STAR_SPREAD = VOID_SCALE_0 * 0.85F;
    /** Per-star view-push range: from just past the outer fan to beyond the deep fan —
     *  deeper stars parallax more, sit dimmer and smaller: the infinite-depth read. */
    private static final float STAR_PUSH_MIN = VOID_PUSH_0 * 1.1F;
    private static final float STAR_PUSH_MAX = VOID_PUSH_1 * 1.3F;

    // --- FXTEAM-RIFT: event-horizon lensing rim ---
    /** Radial reach of the lensing dashes past the fringe, as a fraction of the width. */
    private static final float LENS_WIDTH_FRACTION = 0.075F;
    /**
     * Counter-scroll of the lensing brightness pattern, in whole cycles per 100 s so the
     * {@code swirlSeconds} wrap lands on a full revolution (the EVAL-POL-F #7 arc-drift
     * lesson) — negative: the pattern smears AGAINST the shell spin, the refraction tell.
     */
    private static final float LENS_SCROLL_CYCLES = -40.0F;

    // --- FXTEAM-RIFT: portal pulse ping ---
    private static final int PING_SEGMENTS = 16;
    /** Ping cadence and visible ring lifetime (ticks). */
    private static final int PING_PERIOD_TICKS = 90;
    private static final int PING_TICKS = 22;
    /** Ring travel past the star rim, as a fraction of the tear radius. */
    private static final float PING_REACH = 0.85F;
    /** Ring radial thickness as a fraction of the tear width. */
    private static final float PING_THICKNESS = 0.05F;

    // --- FXTEAM-RIFT: iris-open entry flash ---
    private static final int FLASH_SEGMENTS = 12;
    private static final int FLASH_STREAMERS = 6;
    /** Streamer half-width as a fraction of the tear width. */
    private static final float STREAMER_WIDTH_FRACTION = 0.014F;

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
    /** Fork-branch polyline scratch (base point + {@value #FORK_SEGMENTS} steps). */
    private static final float[] FORK_X = new float[FORK_SEGMENTS + 1];
    private static final float[] FORK_Y = new float[FORK_SEGMENTS + 1];
    private static final float[] FORK_Z = new float[FORK_SEGMENTS + 1];

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
            // VEIL-REPASS-2 piece-launch recoil: multiplying the open scale squashes the
            // WHOLE tear (shells, fringe, arcs, lensing, well) coherently by up to 4% at
            // each delivery launch tick; 1 while idle. Pure scale math — zero extra
            // geometry, so it stays live under reducedFx (launch feedback, not candy).
            VIS_OPEN[visible] = open * rift.recoilScale(now);
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

        // Pass A (alpha blend): void-depth well + dark edge fringe + portal void disc.
        BufferBuilder alpha = Tesselator.getInstance()
                .begin(VertexFormat.Mode.TRIANGLES, DefaultVertexFormat.POSITION_COLOR);
        for (int v = 0; v < visible; v++) {
            buildAlpha(VIS_RIFT[v], alpha, VIS_X[v], VIS_Y[v], VIS_Z[v], VIS_OPEN[v],
                    swirlSeconds, flickerFrame, reduced);
        }
        MeshData alphaMesh = alpha.build();
        if (alphaMesh != null) {
            RenderSystem.blendFuncSeparate(GlStateManager.SourceFactor.SRC_ALPHA,
                    GlStateManager.DestFactor.ONE_MINUS_SRC_ALPHA,
                    GlStateManager.SourceFactor.ONE, GlStateManager.DestFactor.ONE_MINUS_SRC_ALPHA);
            BufferUploader.drawWithShader(alphaMesh);
        }

        // Pass B (additive, on top): shells + arcs/forks + lensing + ping/flash + swirl disc.
        BufferBuilder additive = Tesselator.getInstance()
                .begin(VertexFormat.Mode.TRIANGLES, DefaultVertexFormat.POSITION_COLOR);
        for (int v = 0; v < visible; v++) {
            buildAdditive(VIS_RIFT[v], additive, VIS_X[v], VIS_Y[v], VIS_Z[v], VIS_OPEN[v],
                    swirlSeconds, flickerFrame, reduced, now);
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

    /**
     * Alpha pass: the STRUCTURE void-depth well (FXTEAM-RIFT), the dark edge fringe
     * extruded outward (center shell), and the PORTAL void ellipse. All darks read from
     * the rift's {@code dim} palette so backrooms tears go umber instead of violet.
     */
    private static void buildAlpha(RiftFx.Rift rift, BufferBuilder alpha,
            float cx, float cy, float cz, float open, float swirlSeconds, int flickerFrame,
            boolean reduced) {
        if (!reduced && !rift.portalLike) {
            buildVoidWell(rift, alpha, cx, cy, cz, open);
        }
        fillPerimeter(rift, cx, cy, cz, open, flickerFrame,
                shellRotation(CENTER_SHELL, swirlSeconds), 1.0F);
        int perim = rift.armCount * 2;
        float fringe = rift.width * FRINGE_FRACTION * open;
        float fringeAlpha = 0.78F * open;
        float outR = rift.dimR * 0.5F;
        float outG = rift.dimG * 0.5F;
        float outB = rift.dimB * 0.5F;
        for (int k = 0; k < perim; k++) {
            int k1 = k + 1 == perim ? 0 : k + 1;
            float ox0 = PERIM_X[k] + OUT_X[k] * fringe;
            float oy0 = PERIM_Y[k] + OUT_Y[k] * fringe;
            float oz0 = PERIM_Z[k] + OUT_Z[k] * fringe;
            float ox1 = PERIM_X[k1] + OUT_X[k1] * fringe;
            float oy1 = PERIM_Y[k1] + OUT_Y[k1] * fringe;
            float oz1 = PERIM_Z[k1] + OUT_Z[k1] * fringe;
            // Quad as two triangles: inner edge dark void tone, outer edge fully transparent.
            alpha.addVertex(PERIM_X[k], PERIM_Y[k], PERIM_Z[k]).setColor(rift.dimR, rift.dimG, rift.dimB, fringeAlpha);
            alpha.addVertex(PERIM_X[k1], PERIM_Y[k1], PERIM_Z[k1]).setColor(rift.dimR, rift.dimG, rift.dimB, fringeAlpha);
            alpha.addVertex(ox1, oy1, oz1).setColor(outR, outG, outB, 0.0F);
            alpha.addVertex(PERIM_X[k], PERIM_Y[k], PERIM_Z[k]).setColor(rift.dimR, rift.dimG, rift.dimB, fringeAlpha);
            alpha.addVertex(ox1, oy1, oz1).setColor(outR, outG, outB, 0.0F);
            alpha.addVertex(ox0, oy0, oz0).setColor(outR, outG, outB, 0.0F);
        }

        if (!rift.portalLike) {
            return;
        }
        // Void disc: near-black fan, edge brightness scrolling one way (the swirl disc in
        // the additive pass scrolls the other way — the counter-scroll sells the surface).
        // FXTEAM-RIFT: the disc breathes with the same eased sine as the hot core.
        float breathe = breathe(rift, swirlSeconds);
        float rx = rift.width * PORTAL_RX * open * breathe;
        float ry = rift.width * PORTAL_RY * open * breathe;
        float edgeR = rift.dimR + (rift.midR - rift.dimR) * 0.10F;
        float edgeG = rift.dimG + (rift.midG - rift.dimG) * 0.10F;
        float edgeB = rift.dimB + (rift.midB - rift.dimB) * 0.10F;
        float step = Mth.TWO_PI / DISC_SEGMENTS;
        for (int s = 0; s < DISC_SEGMENTS; s++) {
            float a0 = s * step;
            float a1 = a0 + step;
            float pulse0 = 0.70F + 0.30F * Mth.sin(a0 * 4.0F - swirlSeconds * 1.8F);
            float pulse1 = 0.70F + 0.30F * Mth.sin(a1 * 4.0F - swirlSeconds * 1.8F);
            alpha.addVertex(cx, cy, cz).setColor(rift.dimR * 0.7F, rift.dimG * 0.7F, rift.dimB * 0.75F, 0.88F * open);
            alpha.addVertex(ellipseX(rift, cx, a0, rx, ry), ellipseY(rift, cy, a0, rx, ry),
                    ellipseZ(rift, cz, a0, rx, ry))
                    .setColor(edgeR * pulse0, edgeG * pulse0, edgeB * pulse0, 0.75F * open);
            alpha.addVertex(ellipseX(rift, cx, a1, rx, ry), ellipseY(rift, cy, a1, rx, ry),
                    ellipseZ(rift, cz, a1, rx, ry))
                    .setColor(edgeR * pulse1, edgeG * pulse1, edgeB * pulse1, 0.75F * open);
        }
    }

    /**
     * FXTEAM-RIFT void-depth well (STRUCTURE tears, full quality only): two dark fans
     * inside the star's valley floor, each pushed along the camera→rift view direction
     * (the portal swirl's {@value #PARALLAX_BLOCKS}-block parallax trick, deeper) and the
     * deeper layer darker — walking past the tear makes the interior visibly recede.
     * 2 × {@value #VOID_SEGMENTS} = 24 tris.
     */
    private static void buildVoidWell(RiftFx.Rift rift, BufferBuilder alpha,
            float cx, float cy, float cz, float open) {
        float len = (float) Math.sqrt((double) cx * cx + (double) cy * cy + (double) cz * cz);
        if (len < 1.0E-3F) {
            return; // camera inside the tear: no meaningful parallax direction
        }
        float pushScale = Mth.clamp(rift.width * 0.10F, 0.25F, 1.4F);
        float step = Mth.TWO_PI / VOID_SEGMENTS;
        for (int layer = 0; layer < 2; layer++) {
            float scale = layer == 0 ? VOID_SCALE_0 : VOID_SCALE_1;
            float push = (layer == 0 ? VOID_PUSH_0 : VOID_PUSH_1) * pushScale / len;
            float wx = cx + cx * push;
            float wy = cy + cy * push;
            float wz = cz + cz * push;
            float radius = rift.width * 0.5F * open * scale;
            float coreAlpha = (layer == 0 ? 0.80F : 0.92F) * open;
            float r = rift.dimR * 0.6F;
            float g = rift.dimG * 0.6F;
            float b = rift.dimB * 0.6F;
            for (int s = 0; s < VOID_SEGMENTS; s++) {
                float a0 = s * step;
                float a1 = a0 + step;
                alpha.addVertex(wx, wy, wz).setColor(r, g, b, coreAlpha);
                alpha.addVertex(ellipseX(rift, wx, a0, radius, radius),
                        ellipseY(rift, wy, a0, radius, radius),
                        ellipseZ(rift, wz, a0, radius, radius)).setColor(r, g, b, 0.0F);
                alpha.addVertex(ellipseX(rift, wx, a1, radius, radius),
                        ellipseY(rift, wy, a1, radius, radius),
                        ellipseZ(rift, wz, a1, radius, radius)).setColor(r, g, b, 0.0F);
            }
        }
    }

    /** Shared eased breath of one rift (hot core + portal discs), phase-salted by seed. */
    private static float breathe(RiftFx.Rift rift, float swirlSeconds) {
        return 0.92F + 0.08F * Mth.sin(swirlSeconds * 2.6F + (rift.seed & 31) * 0.41F);
    }

    /**
     * VEIL-REPASS-2 void-well depth STARFIELD (STRUCTURE tears, full quality): {@value
     * #VOID_STARS} tiny in-plane triangles scattered over the void fans, each pushed its
     * own distance along the camera→rift view direction (the well's parallax trick, per
     * star). Deeper stars parallax more, sit dimmer and smaller — walking past the tear
     * makes the star layers shear apart: infinite depth from 12 triangles. Positions and
     * depths are seed-hashed once (frame 0 — stable, unlike the rim flicker); brightness
     * twinkles on slow per-star golden-angle phases, deliberately serene against the
     * tear's convulsing static. Skipped with the rest of the well under {@code reducedFx}.
     */
    private static void buildVoidStars(RiftFx.Rift rift, BufferBuilder additive,
            float cx, float cy, float cz, float open, float swirlSeconds) {
        float len = (float) Math.sqrt((double) cx * cx + (double) cy * cy + (double) cz * cz);
        if (len < 1.0E-3F) {
            return; // camera inside the tear: no meaningful parallax direction
        }
        float pushScale = Mth.clamp(rift.width * 0.10F, 0.25F, 1.4F);
        float r0 = rift.width * 0.5F * open;
        float starR = rift.midR + (rift.hotR - rift.midR) * 0.85F;
        float starG = rift.midG + (rift.hotG - rift.midG) * 0.85F;
        float starB = rift.midB + (rift.hotB - rift.midB) * 0.85F;
        for (int s = 0; s < VOID_STARS; s++) {
            float depth = hash01(rift.seed, 211 + s * 3, 0);
            float angle = hash01(rift.seed, 223 + s * 5, 0) * Mth.TWO_PI;
            // sqrt on the radius hash = uniform scatter over the disc, no center clump.
            float rad = Mth.sqrt(hash01(rift.seed, 227 + s * 7, 0)) * r0 * STAR_SPREAD;
            float push = Mth.lerp(depth, STAR_PUSH_MIN, STAR_PUSH_MAX) * pushScale / len;
            float cos = Mth.cos(angle);
            float sin = Mth.sin(angle);
            float px = cx + cx * push + (rift.tx * cos + rift.bx * sin) * rad;
            float py = cy + cy * push + (rift.ty * cos + rift.by * sin) * rad;
            float pz = cz + cz * push + (rift.tz * cos + rift.bz * sin) * rad;
            // Twinkle rate = whole cycles per 100 s (the EVAL-POL-F #7 wrap law), phases
            // golden-angle spread so no two stars ever pulse together.
            float twinkle = 0.60F + 0.40F
                    * Mth.sin(swirlSeconds * (Mth.TWO_PI * (11 + s) / 100.0F) + s * 2.399F);
            float alpha = (0.85F - 0.55F * depth) * open * twinkle;
            float size = r0 * (0.030F - 0.016F * depth);
            // One tiny equilateral triangle in the tear plane (vertex bearings 90°/210°/330°).
            additive.addVertex(px + rift.bx * size, py + rift.by * size, pz + rift.bz * size)
                    .setColor(starR, starG, starB, alpha);
            additive.addVertex(px + (rift.tx * -0.866F - rift.bx * 0.5F) * size,
                            py + (rift.ty * -0.866F - rift.by * 0.5F) * size,
                            pz + (rift.tz * -0.866F - rift.bz * 0.5F) * size)
                    .setColor(starR, starG, starB, alpha);
            additive.addVertex(px + (rift.tx * 0.866F - rift.bx * 0.5F) * size,
                            py + (rift.ty * 0.866F - rift.by * 0.5F) * size,
                            pz + (rift.tz * 0.866F - rift.bz * 0.5F) * size)
                    .setColor(starR, starG, starB, alpha);
        }
    }

    /**
     * Additive pass: the volumetric shell stack (outer core fan per shell in the rift's
     * {@code mid} tone, inner {@code hot} fan — 3 middle shells for STRUCTURE, center shell
     * only for portal-like styles whose center hides behind the discs anyway), the strobing
     * edge lightning arcs (+forks), the lensing rim, the portal pulse-ping / entry flash,
     * and the PORTAL swirl disc. {@code reducedFx} draws the center shell only, skips
     * arcs/forks/lensing/ping — exactly the pre-C7 geometry — and keeps the iris fan of the
     * entry flash (gameplay feedback).
     */
    private static void buildAdditive(RiftFx.Rift rift, BufferBuilder additive,
            float cx, float cy, float cz, float open, float swirlSeconds, int flickerFrame,
            boolean reduced, float now) {
        int perim = rift.armCount * 2;
        // Per-rift eased breath (VFXPOLISH-3): the hot core swells ±8% on a slow sine —
        // phase from the seed's low bits so neighbouring tears never pulse in lockstep.
        float breathe = breathe(rift, swirlSeconds);
        // Inner-fan edge tone: hot pulled slightly toward the mid saturation.
        float innR = rift.midR + (rift.hotR - rift.midR) * 0.55F;
        float innG = rift.midG + (rift.hotG - rift.midG) * 0.55F;
        float innB = rift.midB + (rift.hotB - rift.midB) * 0.55F;

        int firstShell = reduced ? CENTER_SHELL : 0;
        int lastShell = reduced ? CENTER_SHELL : SHELL_COUNT - 1;
        int innerShells = rift.portalLike ? 0 : 1;
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
                additive.addVertex(cx + dx, cy + dy, cz + dz)
                        .setColor(rift.hotR * 0.97F, rift.hotG * 0.93F, rift.hotB, coreAlpha);
                additive.addVertex(PERIM_X[k] + dx, PERIM_Y[k] + dy, PERIM_Z[k] + dz)
                        .setColor(rift.midR, rift.midG, rift.midB, 0.0F);
                additive.addVertex(PERIM_X[k1] + dx, PERIM_Y[k1] + dy, PERIM_Z[k1] + dz)
                        .setColor(rift.midR, rift.midG, rift.midB, 0.0F);
            }
            if (fromCenter <= innerShells) {
                float innerAlpha = 0.95F * open * fade;
                for (int k = 0; k < perim; k++) {
                    int k1 = k + 1 == perim ? 0 : k + 1;
                    additive.addVertex(cx + dx, cy + dy, cz + dz)
                            .setColor(rift.hotR, rift.hotG, rift.hotB, innerAlpha);
                    additive.addVertex(lerpToCenter(PERIM_X[k], cx) + dx, lerpToCenter(PERIM_Y[k], cy) + dy,
                            lerpToCenter(PERIM_Z[k], cz) + dz).setColor(innR, innG, innB, 0.25F * open * fade);
                    additive.addVertex(lerpToCenter(PERIM_X[k1], cx) + dx, lerpToCenter(PERIM_Y[k1], cy) + dy,
                            lerpToCenter(PERIM_Z[k1], cz) + dz).setColor(innR, innG, innB, 0.25F * open * fade);
                }
            }
        }

        if (!reduced) {
            buildArcs(rift, additive, cx, cy, cz, open, flickerFrame, swirlSeconds);
            buildLensing(rift, additive, cx, cy, cz, open, flickerFrame, swirlSeconds);
            if (!rift.portalLike) {
                // VEIL-REPASS-2: tiny stars inside the void well (drawn additively OVER
                // the alpha-pass dark fans, so they read as lights IN the depth).
                buildVoidStars(rift, additive, cx, cy, cz, open, swirlSeconds);
            }
        }

        float flashAge = now - rift.entryFlashTick;
        boolean flashing = flashAge >= 0.0F && flashAge < RiftFx.Rift.ENTRY_FLASH_TICKS;
        if (rift.portalLike) {
            if (flashing) {
                buildEntryFlash(rift, additive, cx, cy, cz, open,
                        flashAge / RiftFx.Rift.ENTRY_FLASH_TICKS, reduced);
            } else if (!reduced) {
                buildPing(rift, additive, cx, cy, cz, open, now);
            }
        }

        if (!rift.portalLike) {
            return;
        }
        // Swirl disc: scaled copy pushed along the view direction (parallax depth fake),
        // brightness scrolling against the void-edge pulse; breathes with the core.
        float rx = rift.width * PORTAL_RX * open * SWIRL_SCALE * breathe;
        float ry = rift.width * PORTAL_RY * open * SWIRL_SCALE * breathe;
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
            additive.addVertex(sx, sy, sz)
                    .setColor(rift.midR * 0.70F, rift.midG * 0.70F, rift.midB * 0.82F, 0.16F * open);
            additive.addVertex(ellipseX(rift, sx, a0, rx, ry), ellipseY(rift, sy, a0, rx, ry),
                    ellipseZ(rift, sz, a0, rx, ry))
                    .setColor(rift.midR * 0.90F, rift.midG * 0.95F, rift.midB * 0.97F, 0.38F * open * swirl0);
            additive.addVertex(ellipseX(rift, sx, a1, rx, ry), ellipseY(rift, sy, a1, rx, ry),
                    ellipseZ(rift, sz, a1, rx, ry))
                    .setColor(rift.midR * 0.90F, rift.midG * 0.95F, rift.midB * 0.97F, 0.38F * open * swirl1);
        }
    }

    /**
     * C7 edge lightning: up to {@value #ARC_COUNT} jagged filaments crawling outward off
     * the tear rim, jitter re-seeded on the flicker cadence and strobing on/off through a
     * gate hash. EVAL-POL-F #7 (two fixes):
     * <ul>
     *   <li><b>Continuity</b> — each arc's base angle is a fixed per-arc anchor plus a
     *       hash-picked continuous drift, so arcs genuinely CRAWL around the rim instead of
     *       teleporting to a fresh random bearing every 270 ms. Drift rates are integer
     *       multiples of 2π/100 s, so the {@code swirlSeconds} wrap (every 100 s) lands on
     *       a whole number of revolutions — no once-per-cycle jump.</li>
     *   <li><b>Billboard width</b> — each ribbon segment extrudes its width toward the
     *       camera ({@code StormWallRenderer.emitRibbon} pattern) instead of along the tear
     *       normal, so arcs stay readable from directly below a flat STRUCTURE rift, where
     *       normal-extruded quads projected edge-on and near-invisible.</li>
     * </ul>
     *
     * <p>FXTEAM-RIFT: the first {@value #FORK_ARCS} arcs FORK while their gate hash exceeds
     * {@value #FORK_GATE} — a thinner branch peels off at 40 % of the parent and diverges
     * {@value #FORK_SPREAD} rad past the tip (side picked per flicker frame). Colors come
     * from the rift's {@code mid→hot} palette so backrooms arcs strike gold.</p>
     */
    private static void buildArcs(RiftFx.Rift rift, BufferBuilder additive,
            float cx, float cy, float cz, float open, int flickerFrame, float swirlSeconds) {
        float r0 = rift.width * 0.5F * open;
        for (int a = 0; a < ARC_COUNT; a++) {
            float gate = hash01(rift.seed, 97 + a * 13, flickerFrame);
            if (gate < ARC_GATE) {
                continue; // this arc is dark this flicker frame (strobe)
            }
            float anchor = hash01(rift.seed, 41 + a * 7, 0) * Mth.TWO_PI;
            int cycles = 5 + (int) (hash01(rift.seed, 59 + a * 11, 0) * 8.0F); // 5..12 per 100 s
            float drift = cycles * (Mth.TWO_PI / 100.0F) * ((a & 1) == 0 ? 1.0F : -1.0F);
            float baseAngle = anchor + swirlSeconds * drift;
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
            float baseR = rift.midR + (rift.hotR - rift.midR) * 0.72F;
            float baseG = rift.midG + (rift.hotG - rift.midG) * 0.72F;
            float baseB = rift.midB + (rift.hotB - rift.midB) * 0.72F;
            float tipR = rift.midR + (rift.hotR - rift.midR) * 0.88F;
            float tipG = rift.midG + (rift.hotG - rift.midG) * 0.88F;
            float tipB = rift.midB + (rift.hotB - rift.midB) * 0.88F;
            for (int i = 0; i < ARC_SEGMENTS; i++) {
                float taper0 = 1.0F - i / (float) ARC_SEGMENTS;
                float taper1 = 1.0F - (i + 1) / (float) ARC_SEGMENTS;
                emitBillboardSegment(additive,
                        ARC_X[i], ARC_Y[i], ARC_Z[i], ARC_X[i + 1], ARC_Y[i + 1], ARC_Z[i + 1],
                        halfWidth * (0.4F + 0.6F * taper0), halfWidth * (0.4F + 0.6F * taper1),
                        baseR, baseG, baseB, 0.85F * open * gate * taper0,
                        tipR, tipG, tipB, 0.85F * open * gate * taper1);
            }

            // FXTEAM-RIFT fork: the first two arcs may SPLIT — a dimmer, thinner branch
            // peels off at 40 % of the arc and diverges past the tip. Fork presence rides
            // the same gate hash above a higher threshold, so forks strobe rarer than arcs.
            if (a < FORK_ARCS && gate > FORK_GATE) {
                float forkSign = hash01(rift.seed, 71 + a * 19, flickerFrame) > 0.5F ? 1.0F : -1.0F;
                FORK_X[0] = ARC_X[FORK_BASE_INDEX];
                FORK_Y[0] = ARC_Y[FORK_BASE_INDEX];
                FORK_Z[0] = ARC_Z[FORK_BASE_INDEX];
                float baseF = FORK_BASE_INDEX / (float) ARC_SEGMENTS;
                for (int j = 1; j <= FORK_SEGMENTS; j++) {
                    float f = baseF + (1.15F - baseF) * (j / (float) FORK_SEGMENTS);
                    float angle = baseAngle
                            + (hash01(rift.seed, a * 31 + j * 3 + 1, flickerFrame) - 0.5F) * 0.55F * f
                            + forkSign * FORK_SPREAD * (f - baseF);
                    float radius = r0 * (1.0F + ARC_LENGTH_FRACTION * f);
                    float wobble = (hash01(rift.seed, a * 29 + j * 7 + 4, flickerFrame) - 0.5F)
                            * rift.width * 0.08F * f;
                    float cos = Mth.cos(angle);
                    float sin = Mth.sin(angle);
                    FORK_X[j] = cx + (rift.tx * cos + rift.bx * sin) * radius + rift.nx * wobble;
                    FORK_Y[j] = cy + (rift.ty * cos + rift.by * sin) * radius + rift.ny * wobble;
                    FORK_Z[j] = cz + (rift.tz * cos + rift.bz * sin) * radius + rift.nz * wobble;
                }
                float forkAlpha = 0.60F * open * gate;
                for (int j = 0; j < FORK_SEGMENTS; j++) {
                    float taper0 = 1.0F - j / (float) FORK_SEGMENTS;
                    float taper1 = 1.0F - (j + 1) / (float) FORK_SEGMENTS;
                    emitBillboardSegment(additive,
                            FORK_X[j], FORK_Y[j], FORK_Z[j], FORK_X[j + 1], FORK_Y[j + 1], FORK_Z[j + 1],
                            halfWidth * 0.5F * (0.4F + 0.6F * taper0),
                            halfWidth * 0.5F * (0.4F + 0.6F * taper1),
                            baseR, baseG, baseB, forkAlpha * taper0,
                            tipR, tipG, tipB, forkAlpha * taper1);
                }
            }
        }
    }

    /**
     * One camera-extruded ribbon segment (arcs, forks, entry streamers): the side vector
     * is segment × toCamera — the camera sits at the origin in camera-relative space, so
     * the segment midpoint IS the view direction (StormWallRenderer.emitRibbon pattern).
     * Degenerate view-aligned segments emit nothing.
     */
    private static void emitBillboardSegment(BufferBuilder builder,
            float x0, float y0, float z0, float x1, float y1, float z1, float w0, float w1,
            float r0, float g0, float b0, float alpha0, float r1, float g1, float b1, float alpha1) {
        float dxs = x1 - x0;
        float dys = y1 - y0;
        float dzs = z1 - z0;
        float mx = (x0 + x1) * 0.5F;
        float my = (y0 + y1) * 0.5F;
        float mz = (z0 + z1) * 0.5F;
        float sx = dys * mz - dzs * my;
        float sy = dzs * mx - dxs * mz;
        float sz = dxs * my - dys * mx;
        float sLen = Mth.sqrt(sx * sx + sy * sy + sz * sz);
        if (sLen < 1.0E-4F) {
            return;
        }
        float ux = sx / sLen;
        float uy = sy / sLen;
        float uz = sz / sLen;
        float ax0 = x0 + ux * w0;
        float ay0 = y0 + uy * w0;
        float az0 = z0 + uz * w0;
        float bx0 = x0 - ux * w0;
        float by0 = y0 - uy * w0;
        float bz0 = z0 - uz * w0;
        float ax1 = x1 + ux * w1;
        float ay1 = y1 + uy * w1;
        float az1 = z1 + uz * w1;
        float bx1 = x1 - ux * w1;
        float by1 = y1 - uy * w1;
        float bz1 = z1 - uz * w1;
        builder.addVertex(ax0, ay0, az0).setColor(r0, g0, b0, alpha0);
        builder.addVertex(bx0, by0, bz0).setColor(r0, g0, b0, alpha0);
        builder.addVertex(bx1, by1, bz1).setColor(r1, g1, b1, alpha1);
        builder.addVertex(ax0, ay0, az0).setColor(r0, g0, b0, alpha0);
        builder.addVertex(bx1, by1, bz1).setColor(r1, g1, b1, alpha1);
        builder.addVertex(ax1, ay1, az1).setColor(r1, g1, b1, alpha1);
    }

    /**
     * FXTEAM-RIFT event-horizon lensing rim: a DASHED band of quads just past the fringe
     * whose brightness pattern scrolls at {@value #LENS_SCROLL}× the shell base rotation —
     * light appearing to smear around the rim against the spin is the classic refraction
     * tell, faked in geometry because the Veil post stack is Iris-gated (§7). Every other
     * perimeter pair gets a quad → 14 quads = 28 tris; skipped under {@code reducedFx}.
     */
    private static void buildLensing(RiftFx.Rift rift, BufferBuilder additive,
            float cx, float cy, float cz, float open, int flickerFrame, float swirlSeconds) {
        fillPerimeter(rift, cx, cy, cz, open, flickerFrame,
                shellRotation(CENTER_SHELL, swirlSeconds), 1.0F);
        int perim = rift.armCount * 2;
        float inset = rift.width * FRINGE_FRACTION * open * 0.15F;
        float reach = inset + rift.width * LENS_WIDTH_FRACTION * open;
        float scroll = swirlSeconds * (Mth.TWO_PI / 100.0F) * LENS_SCROLL_CYCLES;
        float r = rift.midR + (rift.hotR - rift.midR) * 0.35F;
        float g = rift.midG + (rift.hotG - rift.midG) * 0.35F;
        float b = rift.midB + (rift.hotB - rift.midB) * 0.35F;
        for (int k = 0; k < perim; k += 2) {
            int k1 = k + 1 == perim ? 0 : k + 1;
            float bright0 = 0.55F + 0.45F * Mth.sin(k * 0.9F + scroll);
            float bright1 = 0.55F + 0.45F * Mth.sin(k1 * 0.9F + scroll);
            float a0 = 0.34F * open * bright0;
            float a1 = 0.34F * open * bright1;
            float ix0 = PERIM_X[k] + OUT_X[k] * inset;
            float iy0 = PERIM_Y[k] + OUT_Y[k] * inset;
            float iz0 = PERIM_Z[k] + OUT_Z[k] * inset;
            float ix1 = PERIM_X[k1] + OUT_X[k1] * inset;
            float iy1 = PERIM_Y[k1] + OUT_Y[k1] * inset;
            float iz1 = PERIM_Z[k1] + OUT_Z[k1] * inset;
            float ox0 = PERIM_X[k] + OUT_X[k] * reach;
            float oy0 = PERIM_Y[k] + OUT_Y[k] * reach;
            float oz0 = PERIM_Z[k] + OUT_Z[k] * reach;
            float ox1 = PERIM_X[k1] + OUT_X[k1] * reach;
            float oy1 = PERIM_Y[k1] + OUT_Y[k1] * reach;
            float oz1 = PERIM_Z[k1] + OUT_Z[k1] * reach;
            additive.addVertex(ix0, iy0, iz0).setColor(r, g, b, a0);
            additive.addVertex(ix1, iy1, iz1).setColor(r, g, b, a1);
            additive.addVertex(ox1, oy1, oz1).setColor(r, g, b, 0.0F);
            additive.addVertex(ix0, iy0, iz0).setColor(r, g, b, a0);
            additive.addVertex(ox1, oy1, oz1).setColor(r, g, b, 0.0F);
            additive.addVertex(ox0, oy0, oz0).setColor(r, g, b, 0.0F);
        }
    }

    /**
     * FXTEAM-RIFT portal pulse ping: every {@value #PING_PERIOD_TICKS} ticks (seed-offset
     * so neighbouring portals never ping together) one thin ring detaches from the star rim
     * and expands {@value #PING_REACH}× the radius outward over {@value #PING_TICKS} ticks,
     * fading as it travels — the idle "sonar breath" of a live portal.
     * {@value #PING_SEGMENTS} quads = 32 tris, mutually exclusive with the entry flash.
     */
    private static void buildPing(RiftFx.Rift rift, BufferBuilder additive,
            float cx, float cy, float cz, float open, float now) {
        float phase = (now - rift.openTick + (rift.seed & 63)) % PING_PERIOD_TICKS;
        if (phase < 0.0F || phase >= PING_TICKS) {
            return;
        }
        float t = phase / PING_TICKS;
        float eased = 1.0F - (1.0F - t) * (1.0F - t);
        float r0 = rift.width * 0.5F * open;
        float rIn = r0 * (1.0F + PING_REACH * eased);
        float rOut = rIn + rift.width * PING_THICKNESS * (1.0F - 0.5F * t);
        float alpha = 0.5F * open * (1.0F - t) * (1.0F - t);
        float r = rift.midR + (rift.hotR - rift.midR) * 0.6F;
        float g = rift.midG + (rift.hotG - rift.midG) * 0.6F;
        float b = rift.midB + (rift.hotB - rift.midB) * 0.6F;
        float step = Mth.TWO_PI / PING_SEGMENTS;
        for (int s = 0; s < PING_SEGMENTS; s++) {
            float a0 = s * step;
            float a1 = a0 + step;
            float inX0 = ellipseX(rift, cx, a0, rIn, rIn);
            float inY0 = ellipseY(rift, cy, a0, rIn, rIn);
            float inZ0 = ellipseZ(rift, cz, a0, rIn, rIn);
            float inX1 = ellipseX(rift, cx, a1, rIn, rIn);
            float inY1 = ellipseY(rift, cy, a1, rIn, rIn);
            float inZ1 = ellipseZ(rift, cz, a1, rIn, rIn);
            float outX0 = ellipseX(rift, cx, a0, rOut, rOut);
            float outY0 = ellipseY(rift, cy, a0, rOut, rOut);
            float outZ0 = ellipseZ(rift, cz, a0, rOut, rOut);
            float outX1 = ellipseX(rift, cx, a1, rOut, rOut);
            float outY1 = ellipseY(rift, cy, a1, rOut, rOut);
            float outZ1 = ellipseZ(rift, cz, a1, rOut, rOut);
            additive.addVertex(inX0, inY0, inZ0).setColor(r, g, b, alpha);
            additive.addVertex(inX1, inY1, inZ1).setColor(r, g, b, alpha);
            additive.addVertex(outX1, outY1, outZ1).setColor(r, g, b, 0.0F);
            additive.addVertex(inX0, inY0, inZ0).setColor(r, g, b, alpha);
            additive.addVertex(outX1, outY1, outZ1).setColor(r, g, b, 0.0F);
            additive.addVertex(outX0, outY0, outZ0).setColor(r, g, b, 0.0F);
        }
    }

    /**
     * FXTEAM-RIFT iris-open entry flash ({@code t} in [0,1) over {@code
     * RiftFx.Rift.ENTRY_FLASH_TICKS}): a hot fan snapping open from the portal center plus
     * {@value #FLASH_STREAMERS} radial streamers whooshing off the rim (camera-extruded like
     * the arcs). 12 + 12 tris; {@code reducedFx} keeps the fan only — the flash doubles as
     * gameplay feedback that somebody stepped through.
     */
    private static void buildEntryFlash(RiftFx.Rift rift, BufferBuilder additive,
            float cx, float cy, float cz, float open, float t, boolean reduced) {
        float easeOut = 1.0F - (1.0F - t) * (1.0F - t);
        float fade = (1.0F - t) * (1.0F - t);
        float fanRadius = rift.width * (0.10F + 0.38F * easeOut) * open;
        float fanAlpha = 0.95F * fade * open;
        float step = Mth.TWO_PI / FLASH_SEGMENTS;
        for (int s = 0; s < FLASH_SEGMENTS; s++) {
            float a0 = s * step;
            float a1 = a0 + step;
            additive.addVertex(cx, cy, cz).setColor(rift.hotR, rift.hotG, rift.hotB, fanAlpha);
            additive.addVertex(ellipseX(rift, cx, a0, fanRadius, fanRadius),
                    ellipseY(rift, cy, a0, fanRadius, fanRadius),
                    ellipseZ(rift, cz, a0, fanRadius, fanRadius))
                    .setColor(rift.midR, rift.midG, rift.midB, 0.0F);
            additive.addVertex(ellipseX(rift, cx, a1, fanRadius, fanRadius),
                    ellipseY(rift, cy, a1, fanRadius, fanRadius),
                    ellipseZ(rift, cz, a1, fanRadius, fanRadius))
                    .setColor(rift.midR, rift.midG, rift.midB, 0.0F);
        }
        if (reduced) {
            return;
        }
        float rimIn = fanRadius * 0.8F;
        float rimOut = rimIn + rift.width * (0.25F + 0.45F * easeOut) * open;
        float halfWidth = rift.width * STREAMER_WIDTH_FRACTION;
        float streamAlpha = 0.9F * fade * open;
        float streamStep = Mth.TWO_PI / FLASH_STREAMERS;
        float spin = (rift.seed & 15) * 0.11F;
        for (int s = 0; s < FLASH_STREAMERS; s++) {
            float angle = s * streamStep + spin;
            float cos = Mth.cos(angle);
            float sin = Mth.sin(angle);
            float dirX = rift.tx * cos + rift.bx * sin;
            float dirY = rift.ty * cos + rift.by * sin;
            float dirZ = rift.tz * cos + rift.bz * sin;
            emitBillboardSegment(additive,
                    cx + dirX * rimIn, cy + dirY * rimIn, cz + dirZ * rimIn,
                    cx + dirX * rimOut, cy + dirY * rimOut, cz + dirZ * rimOut,
                    halfWidth, halfWidth * 0.3F,
                    rift.hotR, rift.hotG, rift.hotB, streamAlpha,
                    rift.midR, rift.midG, rift.midB, 0.0F);
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
