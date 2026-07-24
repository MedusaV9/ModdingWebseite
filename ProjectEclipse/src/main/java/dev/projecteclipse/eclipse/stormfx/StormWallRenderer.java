package dev.projecteclipse.eclipse.stormfx;

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
import dev.projecteclipse.eclipse.network.fx.S2CStormStatePayload;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RenderLevelStageEvent;

/**
 * World-space storm wall/vortex geometry (P2 W9, R14/R15) — camera-relative, drawn at
 * {@link #RENDER_STAGE} with the vanilla-border draw pattern ({@code POSITION_COLOR} +
 * {@link BufferUploader#drawWithShader}); switch the stage constant to
 * {@code AFTER_TRANSLUCENT_BLOCKS} if Sodium depth-sort artifacts appear (§7 risk 2 — same
 * matrices). Everything is per-vertex procedural (hash noise gray/alpha, two scroll speeds) —
 * zero textures, zero per-frame heap allocations, and NO Iris gate: world-space geometry is
 * the Iris fallback tier (§7 risk 1), so the wall stays opaque under shaderpacks.
 *
 * <p><b>Never-see-inside guarantee:</b> an opaque, unlit, near-black occluder cylinder at
 * {@code r - }{@value #OCCLUDER_INSET} with a cone lid is drawn depth-writing BEFORE the
 * translucent shells. It covers every angle and height (including straight down from above),
 * so no camera position outside can resolve anything inside — independent of shaders, fog or
 * config (R14/R15 frozen decision: geometry, not post).</p>
 *
 * <p><b>LOD tiers</b> (distance {@code d} from the shell, crossfaded over ±{@value #LOD_FADE}
 * blocks so no step is harsher than a short fade):</p>
 * <ul>
 *   <li>near ({@code d < 160}): 4 shells (r+2 additive, r / r−2 alpha-blended, r−4 additive)
 *       × ≤ {@value #NEAR_SEGMENTS} segments, ragged crowns (wall) or a twisted swirl-cone cap
 *       (vortex), arcs/wisps live here (scheduled by {@link StormFxClient});</li>
 *   <li>far ({@code 160–320}): 2 shells × {@value #FAR_SEGMENTS} segments, no crowns/arcs;</li>
 *   <li>impostor ({@code > 320}): a single {@value #IMPOSTOR_SEGMENTS}-segment ring + lid.</li>
 * </ul>
 *
 * <p>Also draws every live lightning ribbon: sky strikes ({@link StormFxClient#bolts()}, 6
 * jittered sub-segments × core+glow layers + impact cross flash = ≤ 14 quads each, 2-tick
 * white core then violet decay) and small shell arc crackles ({@link StormFxClient#arcs()}).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class StormWallRenderer {
    /** Swap to {@code AFTER_TRANSLUCENT_BLOCKS} if Sodium depth-sorting artifacts appear (§7). */
    private static final RenderLevelStageEvent.Stage RENDER_STAGE =
            RenderLevelStageEvent.Stage.AFTER_PARTICLES;

    // --- LOD ---
    private static final float NEAR_LOD_END = 160.0F;
    private static final float FAR_LOD_END = 320.0F;
    private static final float LOD_FADE = 16.0F;
    private static final int NEAR_SEGMENTS = 96;
    private static final int FAR_SEGMENTS = 48;
    private static final int IMPOSTOR_SEGMENTS = 8;
    private static final int OCCLUDER_SEGMENTS_NEAR = 48;
    private static final int OCCLUDER_SEGMENTS_FAR = 24;
    /** Extra visible-arc margin (radians) beyond the geometric tangent arc when outside. */
    private static final double ARC_MARGIN = 0.5D;

    // --- shape ---
    /** The opaque occluder sits this far inside the nominal radius. */
    static final float OCCLUDER_INSET = 5.0F;
    /** Shell radial offsets and their blend pass (true = additive). */
    private static final float[] SHELL_OFFSETS = {2.0F, 0.0F, -2.0F, -4.0F};
    private static final boolean[] SHELL_ADDITIVE = {true, false, false, true};
    /**
     * Vortex shells lean inward 8° (R14): top radius shrinks by tan(8°) per block of height.
     * Package-visible so {@link StormInteriorFx} evaluates inside/outside against the TILTED
     * radius at camera height (IDEA-15 §6 — EVAL-4 post-eval interior over-reach).
     */
    static final float TAN_TILT = 0.1405F;
    /** Total geometric twist of a vortex shell column over its height (radians). */
    private static final float VORTEX_TWIST = 0.9F;
    /** Vortex swirl 0.35 rad/s (R14) at 20 ticks/s; walls only drift slowly. */
    private static final float SWIRL_RAD_PER_TICK = 0.0175F;
    private static final float WALL_DRIFT_RAD_PER_TICK = 0.002F;
    /** The wall band extends this far below the anchor Y (terrain irregularity skirt). */
    private static final float BASE_SKIRT = 4.0F;

    // --- palette (storm slate with the eclipse-violet cast) ---
    private static final float ALPHA_R = 0.10F;
    private static final float ALPHA_G = 0.075F;
    private static final float ALPHA_B = 0.145F;
    private static final float ADD_R = 0.30F;
    private static final float ADD_G = 0.20F;
    private static final float ADD_B = 0.47F;
    private static final float OCC_R = 0.014F;
    private static final float OCC_G = 0.010F;
    private static final float OCC_B = 0.026F;

    // --- bolts ---
    private static final int BOLT_SUB_SEGMENTS = 6;
    private static final int BOLT_CORE_TICKS = 2;
    /** Reused polyline scratch (7 points × xyz) — bolts allocate nothing per frame. */
    private static final float[] BOLT_PTS = new float[(BOLT_SUB_SEGMENTS + 1) * 3];

    private StormWallRenderer() {}

    @SubscribeEvent
    static void onRenderLevelStage(RenderLevelStageEvent event) {
        if (event.getStage() != RENDER_STAGE) {
            return;
        }
        List<StormFxClient.ClientStorm> storms = StormFxClient.storms();
        List<StormFxClient.Bolt> bolts = StormFxClient.bolts();
        List<StormFxClient.Bolt> arcs = StormFxClient.arcs();
        if (storms.isEmpty() && bolts.isEmpty() && arcs.isEmpty()) {
            return; // zero cost while no storm/bolt exists anywhere
        }
        ClientLevel level = Minecraft.getInstance().level;
        if (level == null) {
            return;
        }
        Vec3 camera = event.getCamera().getPosition();
        float partialTick = event.getPartialTick().getGameTimeDeltaPartialTick(false);
        float time = StormFxClient.ticks() + partialTick;

        // PASS 1 — opaque occluders (depth-writing; the never-see-inside guarantee).
        if (!storms.isEmpty()) {
            BufferBuilder buffer = Tesselator.getInstance()
                    .begin(VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_COLOR);
            for (int i = 0; i < storms.size(); i++) {
                buildOccluder(buffer, storms.get(i), camera, partialTick);
            }
            draw(buffer, false, true);
        }

        // PASS 2 — alpha-blended inner shells (+ impostor ring/lid).
        if (!storms.isEmpty()) {
            BufferBuilder buffer = Tesselator.getInstance()
                    .begin(VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_COLOR);
            for (int i = 0; i < storms.size(); i++) {
                buildShells(buffer, storms.get(i), camera, partialTick, time, false);
            }
            draw(buffer, false, false);
        }

        // PASS 3 — additive: outer/inner glow shells, caps, lightning ribbons, arc crackles.
        BufferBuilder buffer = Tesselator.getInstance()
                .begin(VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_COLOR);
        for (int i = 0; i < storms.size(); i++) {
            buildShells(buffer, storms.get(i), camera, partialTick, time, true);
        }
        for (int i = 0; i < bolts.size(); i++) {
            buildBolt(buffer, bolts.get(i), camera, partialTick);
        }
        for (int i = 0; i < arcs.size(); i++) {
            buildBolt(buffer, arcs.get(i), camera, partialTick);
        }
        draw(buffer, true, false);
    }

    // ------------------------------------------------------------------ occluder

    private static void buildOccluder(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float partialTick) {
        float vis = storm.visibility(partialTick);
        if (vis <= 0.01F) {
            return;
        }
        double dx = camera.x - storm.center.x;
        double dz = camera.z - storm.center.z;
        double centerDist = Math.sqrt(dx * dx + dz * dz);
        float shellDist = (float) Math.abs(centerDist - storm.radius);
        int segments = shellDist < NEAR_LOD_END + LOD_FADE ? OCCLUDER_SEGMENTS_NEAR : OCCLUDER_SEGMENTS_FAR;

        float radius = Math.max(1.5F, storm.radius - OCCLUDER_INSET);
        float heightScale = heightScale(storm, vis);
        float baseY = (float) (storm.center.y - camera.y) - BASE_SKIRT;
        float topY = (float) (storm.center.y - camera.y) + storm.height * heightScale;
        // Ramps briefly show the interior at low alpha — by design the reveal/intro places
        // content only once fully opaque (vis 1.6x → opaque at ~60% of the ramp).
        float alpha = Math.min(1.0F, vis * 1.6F);
        float cx = (float) (storm.center.x - camera.x);
        float cz = (float) (storm.center.z - camera.z);

        double step = Math.PI * 2.0D / segments;
        for (int i = 0; i < segments; i++) {
            float a0 = (float) (i * step);
            float a1 = (float) ((i + 1) * step);
            float x0 = cx + Mth.cos(a0) * radius;
            float z0 = cz + Mth.sin(a0) * radius;
            float x1 = cx + Mth.cos(a1) * radius;
            float z1 = cz + Mth.sin(a1) * radius;
            // Wall segment.
            buffer.addVertex(x0, baseY, z0).setColor(OCC_R, OCC_G, OCC_B, alpha);
            buffer.addVertex(x1, baseY, z1).setColor(OCC_R, OCC_G, OCC_B, alpha);
            buffer.addVertex(x1, topY, z1).setColor(OCC_R, OCC_G, OCC_B, alpha);
            buffer.addVertex(x0, topY, z0).setColor(OCC_R, OCC_G, OCC_B, alpha);
        }
        // Cone lid — blocks the view from above (vortexes get a taller spire, walls a low dome).
        float coneH = storm.height * heightScale
                * (storm.type == S2CStormStatePayload.TYPE_VORTEX ? 0.30F : 0.14F);
        float apexY = topY + coneH;
        for (int i = 0; i < segments; i++) {
            float a0 = (float) (i * step);
            float a1 = (float) ((i + 1) * step);
            float x0 = cx + Mth.cos(a0) * radius;
            float z0 = cz + Mth.sin(a0) * radius;
            float x1 = cx + Mth.cos(a1) * radius;
            float z1 = cz + Mth.sin(a1) * radius;
            buffer.addVertex(x0, topY, z0).setColor(OCC_R, OCC_G, OCC_B, alpha);
            buffer.addVertex(x1, topY, z1).setColor(OCC_R, OCC_G, OCC_B, alpha);
            buffer.addVertex(cx, apexY, cz).setColor(OCC_R, OCC_G, OCC_B, alpha);
            buffer.addVertex(cx, apexY, cz).setColor(OCC_R, OCC_G, OCC_B, alpha);
        }
    }

    // ------------------------------------------------------------------ shells

    private static void buildShells(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float partialTick, float time, boolean additivePass) {
        float vis = storm.visibility(partialTick);
        if (vis <= 0.01F) {
            return;
        }
        double dx = camera.x - storm.center.x;
        double dz = camera.z - storm.center.z;
        double centerDist = Math.sqrt(dx * dx + dz * dz);
        // Deep inside the occluder the shells are invisible anyway — the single d² early-out.
        if (centerDist < storm.radius - OCCLUDER_INSET - 2.0D) {
            return;
        }
        float shellDist = (float) Math.abs(centerDist - storm.radius);

        // LOD crossfade weights (±LOD_FADE blocks around each boundary — smoother than a pop).
        float nearW = 1.0F - smoothstep(NEAR_LOD_END - LOD_FADE, NEAR_LOD_END + LOD_FADE, shellDist);
        float farW = smoothstep(NEAR_LOD_END - LOD_FADE, NEAR_LOD_END + LOD_FADE, shellDist)
                * (1.0F - smoothstep(FAR_LOD_END - LOD_FADE, FAR_LOD_END + LOD_FADE, shellDist));
        float impW = smoothstep(FAR_LOD_END - LOD_FADE, FAR_LOD_END + LOD_FADE, shellDist);

        boolean inside = centerDist < storm.radius;
        double camAngle = Math.atan2(dz, dx); // bearing of the camera around the storm axis
        boolean vortex = storm.type == S2CStormStatePayload.TYPE_VORTEX;
        float heightScale = heightScale(storm, vis);

        if (nearW > 0.02F) {
            float tierAlpha = nearW * vis;
            for (int s = 0; s < SHELL_OFFSETS.length; s++) {
                if (SHELL_ADDITIVE[s] != additivePass) {
                    continue;
                }
                emitShell(buffer, storm, camera, time, s, NEAR_SEGMENTS, camAngle, centerDist,
                        inside, vortex, heightScale, tierAlpha, additivePass, true);
            }
            if (additivePass && vortex) {
                emitVortexCone(buffer, storm, camera, time, heightScale, tierAlpha);
            }
        }
        if (farW > 0.02F) {
            float tierAlpha = farW * vis;
            // Far tier: outer additive shell + main alpha shell only, no crowns.
            for (int s = 0; s < 2; s++) {
                if (SHELL_ADDITIVE[s] != additivePass) {
                    continue;
                }
                emitShell(buffer, storm, camera, time, s, FAR_SEGMENTS, camAngle, centerDist,
                        inside, vortex, heightScale, tierAlpha, additivePass, false);
            }
        }
        if (impW > 0.02F && !additivePass) {
            emitImpostor(buffer, storm, camera, time, heightScale, impW * vis, vortex);
        }
    }

    /**
     * One cylindrical shell: full circle when inside, otherwise the camera-facing tangent arc
     * (+margin) so segment budget goes where it is seen. Alpha shells carry two height bands
     * (dense base + ragged fading top, plus a crown at near LOD for wall storms); additive
     * shells are a single band fading to zero at the top.
     */
    private static void emitShell(BufferBuilder buffer, StormFxClient.ClientStorm storm, Vec3 camera,
            float time, int shellIndex, int fullSegments, double camAngle, double centerDist,
            boolean inside, boolean vortex, float heightScale, float alphaMul, boolean additive,
            boolean nearTier) {
        float radius = storm.radius + SHELL_OFFSETS[shellIndex];
        if (radius < 1.0F) {
            return;
        }
        double halfArc = Math.PI;
        if (!inside) {
            halfArc = Math.min(Math.PI, Math.acos(Mth.clamp(radius / (float) centerDist, 0.0F, 1.0F)) + ARC_MARGIN);
        }
        double step = Math.PI * 2.0D / fullSegments;
        int columns = Math.min(fullSegments, (int) Math.ceil(2.0D * halfArc / step));

        // Swirl/drift rotation: vortices spin one way at staggered speeds, walls slowly shear.
        float rot = vortex
                ? time * SWIRL_RAD_PER_TICK * (0.8F + shellIndex * 0.13F)
                : time * WALL_DRIFT_RAD_PER_TICK * ((shellIndex & 1) == 0 ? 1.0F : -1.0F);
        // Two scroll speeds for the churn noise (frozen R14 detail).
        int noiseT = (int) (time / ((shellIndex & 1) == 0 ? 3.0F : 5.0F));

        float height = storm.height * heightScale;
        float baseY = (float) (storm.center.y - camera.y) - BASE_SKIRT;
        float cx = (float) (storm.center.x - camera.x);
        float cz = (float) (storm.center.z - camera.z);
        float topRadius = vortex ? Math.max(radius * 0.25F, radius - height * TAN_TILT) : radius;
        float twist = vortex ? VORTEX_TWIST : 0.0F;

        float r = additive ? ADD_R : ALPHA_R;
        float g = additive ? ADD_G : ALPHA_G;
        float b = additive ? ADD_B : ALPHA_B;

        for (int i = 0; i < columns; i++) {
            double a0 = camAngle - halfArc + i * step + rot;
            double a1 = a0 + step;
            int noiseSeg = Mth.floor((float) (a0 / step)); // stable per column, moves with rot
            float churn = 0.45F + 0.55F * hash3(shellIndex, noiseSeg, noiseT);
            float churnHi = 0.45F + 0.55F * hash3(shellIndex, noiseSeg, noiseT + 7331);
            float gray0 = 0.72F + 0.28F * hash3(shellIndex + 8, noiseSeg, noiseT);
            float gray1 = 0.72F + 0.28F * hash3(shellIndex + 8, noiseSeg, noiseT + 977);

            if (additive) {
                // Single band, fading to zero at the (slightly ragged) top.
                float topJitter = hash3(shellIndex + 16, noiseSeg, noiseT / 2) * 4.0F;
                float aBot = 0.34F * churn * alphaMul;
                emitColumn(buffer, cx, cz, baseY, baseY + height * 1.02F + topJitter,
                        a0, a1, radius, topRadius, twist,
                        r * gray0, g * gray0, b * gray0, aBot,
                        r * gray1, g * gray1, b * gray1, 0.0F);
            } else {
                float split = height * 0.72F;
                float aBase = 0.86F * alphaMul;
                float aMid = 0.74F * churn * alphaMul;
                // Dense base band.
                emitColumn(buffer, cx, cz, baseY, baseY + split,
                        a0, a1, radius, Mth.lerp(0.72F, radius, topRadius), twist * 0.72F,
                        r * gray0, g * gray0, b * gray0, aBase,
                        r * gray1, g * gray1, b * gray1, aMid);
                // Ragged top band, jittered rim, fades to nothing.
                float topJitter = (hash3(shellIndex + 24, noiseSeg, noiseT / 2) - 0.3F) * 6.0F;
                emitColumn(buffer, cx, cz, baseY + split, baseY + height + topJitter,
                        a0, a1, Mth.lerp(0.72F, radius, topRadius), topRadius, twist,
                        r * gray1, g * gray1, b * gray1, aMid,
                        r, g, b, 0.0F);
                // Wall crown (near tier only): torn lip leaning inward above the rim.
                if (nearTier && !vortex) {
                    float crownH = 3.0F + churnHi * 5.0F;
                    emitColumn(buffer, cx, cz, baseY + height + topJitter,
                            baseY + height + topJitter + crownH,
                            a0, a1, topRadius, topRadius - 3.0F, 0.15F,
                            r * gray1, g * gray1, b * gray1, aMid * 0.55F,
                            r, g, b, 0.0F);
                }
            }
        }
    }

    /** Twisted additive swirl-cone cap of a vortex (R14 "top: swirl cone cap"). */
    private static void emitVortexCone(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float time, float heightScale, float alphaMul) {
        int segments = 48;
        float height = storm.height * heightScale;
        float radius = Math.max(storm.radius * 0.25F, (storm.radius + 2.0F) - height * TAN_TILT);
        float coneTop = height * 0.32F;
        float apexRadius = storm.radius * 0.2F;
        float cx = (float) (storm.center.x - camera.x);
        float cz = (float) (storm.center.z - camera.z);
        float baseY = (float) (storm.center.y - camera.y) + height;
        float rot = time * SWIRL_RAD_PER_TICK * 1.35F;
        int noiseT = (int) (time / 3.0F);
        double step = Math.PI * 2.0D / segments;
        for (int i = 0; i < segments; i++) {
            double a0 = i * step + rot;
            double a1 = a0 + step;
            float churn = 0.4F + 0.6F * hash3(31, i, noiseT);
            float alpha = 0.30F * churn * alphaMul;
            emitColumn(buffer, cx, cz, baseY, baseY + coneTop,
                    a0, a1, radius, apexRadius, 1.3F,
                    ADD_R, ADD_G, ADD_B, alpha,
                    ADD_R * 1.3F, ADD_G * 1.3F, ADD_B * 1.2F, 0.0F);
        }
    }

    /** Impostor ring + lid for storms beyond {@value #FAR_LOD_END} blocks (8 columns, dark). */
    private static void emitImpostor(BufferBuilder buffer, StormFxClient.ClientStorm storm,
            Vec3 camera, float time, float heightScale, float alphaMul, boolean vortex) {
        int segments = IMPOSTOR_SEGMENTS;
        float radius = storm.radius;
        float height = storm.height * heightScale;
        float cx = (float) (storm.center.x - camera.x);
        float cz = (float) (storm.center.z - camera.z);
        float baseY = (float) (storm.center.y - camera.y) - BASE_SKIRT;
        int noiseT = (int) (time / 6.0F);
        float topRadius = vortex ? radius * 0.6F : radius;
        double step = Math.PI * 2.0D / segments;
        for (int i = 0; i < segments; i++) {
            double a0 = i * step;
            double a1 = a0 + step;
            float churn = 0.7F + 0.3F * hash3(40, i, noiseT);
            float alpha = 0.85F * alphaMul;
            emitColumn(buffer, cx, cz, baseY, baseY + height,
                    a0, a1, radius, topRadius, 0.0F,
                    ALPHA_R * churn, ALPHA_G * churn, ALPHA_B * churn, alpha,
                    ALPHA_R, ALPHA_G, ALPHA_B, alpha * 0.35F);
            // Lid wedge toward the axis so the interior stays hidden from high vantage points.
            float x0 = cx + (float) Math.cos(a0) * topRadius;
            float z0 = cz + (float) Math.sin(a0) * topRadius;
            float x1 = cx + (float) Math.cos(a1) * topRadius;
            float z1 = cz + (float) Math.sin(a1) * topRadius;
            float lidY = baseY + height;
            float apexY = lidY + height * 0.12F;
            buffer.addVertex(x0, lidY, z0).setColor(ALPHA_R, ALPHA_G, ALPHA_B, alpha);
            buffer.addVertex(x1, lidY, z1).setColor(ALPHA_R, ALPHA_G, ALPHA_B, alpha);
            buffer.addVertex(cx, apexY, cz).setColor(ALPHA_R, ALPHA_G, ALPHA_B, alpha);
            buffer.addVertex(cx, apexY, cz).setColor(ALPHA_R, ALPHA_G, ALPHA_B, alpha);
        }
    }

    /** One vertical wall column quad between two angles, with independent bottom/top styling. */
    private static void emitColumn(BufferBuilder buffer, float cx, float cz, float y0, float y1,
            double a0, double a1, float radius0, float radius1, float twist,
            float r0, float g0, float b0, float alpha0,
            float r1, float g1, float b1, float alpha1) {
        float x00 = cx + (float) Math.cos(a0) * radius0;
        float z00 = cz + (float) Math.sin(a0) * radius0;
        float x10 = cx + (float) Math.cos(a1) * radius0;
        float z10 = cz + (float) Math.sin(a1) * radius0;
        float x01 = cx + (float) Math.cos(a0 + twist) * radius1;
        float z01 = cz + (float) Math.sin(a0 + twist) * radius1;
        float x11 = cx + (float) Math.cos(a1 + twist) * radius1;
        float z11 = cz + (float) Math.sin(a1 + twist) * radius1;
        buffer.addVertex(x00, y0, z00).setColor(r0, g0, b0, alpha0);
        buffer.addVertex(x10, y0, z10).setColor(r0, g0, b0, alpha0);
        buffer.addVertex(x11, y1, z11).setColor(r1, g1, b1, alpha1);
        buffer.addVertex(x01, y1, z01).setColor(r1, g1, b1, alpha1);
    }

    // ------------------------------------------------------------------ lightning ribbons

    /**
     * A jittered ribbon bolt: {@value #BOLT_SUB_SEGMENTS} camera-facing sub-segments, re-seeded
     * every 2 ticks, white core for the first {@value #BOLT_CORE_TICKS} ticks then violet
     * decay; sky strikes add an outer glow layer + impact cross flash (≤ 14 quads total).
     */
    private static void buildBolt(BufferBuilder buffer, StormFxClient.Bolt bolt, Vec3 camera,
            float partialTick) {
        int life = bolt.arc ? StormFxClient.ARC_LIFE_TICKS : StormFxClient.BOLT_LIFE_TICKS;
        float age = StormFxClient.ticks() + partialTick - bolt.startTick;
        if (age >= life) {
            return;
        }
        float lifeFrac = age / life;
        boolean core = age < BOLT_CORE_TICKS;
        int jitterFrame = (int) (age / 2.0F);

        // Build the jittered polyline into the shared scratch (camera-relative floats).
        float fx = (float) (bolt.from.x - camera.x);
        float fy = (float) (bolt.from.y - camera.y);
        float fz = (float) (bolt.from.z - camera.z);
        float tx = (float) (bolt.to.x - camera.x);
        float ty = (float) (bolt.to.y - camera.y);
        float tz = (float) (bolt.to.z - camera.z);
        float dxT = tx - fx;
        float dyT = ty - fy;
        float dzT = tz - fz;
        float len = Mth.sqrt(dxT * dxT + dyT * dyT + dzT * dzT);
        if (len < 0.01F) {
            return;
        }
        // Two axes perpendicular to the strike direction for the jitter plane.
        float ux;
        float uy;
        float uz;
        if (Math.abs(dyT) > 0.9F * len) {
            ux = 1.0F;
            uy = 0.0F;
            uz = 0.0F;
        } else {
            ux = 0.0F;
            uy = 1.0F;
            uz = 0.0F;
        }
        // v = normalize(dir × u), u' = normalize(dir × v)
        float vx = (dyT * uz - dzT * uy) / len;
        float vy = (dzT * ux - dxT * uz) / len;
        float vz = (dxT * uy - dyT * ux) / len;
        float vLen = Math.max(1.0E-4F, Mth.sqrt(vx * vx + vy * vy + vz * vz));
        vx /= vLen;
        vy /= vLen;
        vz /= vLen;
        float wx = (dyT * vz - dzT * vy) / len;
        float wy = (dzT * vx - dxT * vz) / len;
        float wz = (dxT * vy - dyT * vx) / len;

        float amp = len * (bolt.arc ? 0.10F : 0.055F) * (1.0F + bolt.intensity * 0.5F);
        int seedBase = (int) (bolt.seed ^ (bolt.seed >>> 32)) + jitterFrame * 7919;
        for (int j = 0; j <= BOLT_SUB_SEGMENTS; j++) {
            float t = j / (float) BOLT_SUB_SEGMENTS;
            float envelope = 4.0F * t * (1.0F - t); // pinned at both endpoints
            float o1 = (hashF(seedBase, j * 2) - 0.5F) * 2.0F * amp * envelope;
            float o2 = (hashF(seedBase, j * 2 + 1) - 0.5F) * 2.0F * amp * envelope;
            BOLT_PTS[j * 3] = fx + dxT * t + vx * o1 + wx * o2;
            BOLT_PTS[j * 3 + 1] = fy + dyT * t + vy * o1 + wy * o2;
            BOLT_PTS[j * 3 + 2] = fz + dzT * t + vz * o1 + wz * o2;
        }

        float decay = 1.0F - Math.max(0.0F, (age - BOLT_CORE_TICKS) / (float) (life - BOLT_CORE_TICKS));
        if (bolt.arc) {
            float width = 0.10F + 0.22F * bolt.intensity;
            float alpha = 0.8F * (1.0F - lifeFrac);
            emitRibbon(buffer, width, 0.85F, 0.72F, 1.0F, alpha);
        } else {
            // Outer violet glow layer.
            float coreWidth = (0.28F + 0.6F * bolt.intensity) * (core ? 1.0F : 0.55F + 0.45F * decay);
            emitRibbon(buffer, coreWidth * 2.6F, 0.62F, 0.42F, 1.0F, (core ? 0.55F : 0.42F * decay));
            // Core: white while hot, violet-white while decaying.
            float cr = core ? 1.0F : 0.88F;
            float cg = core ? 1.0F : 0.74F;
            emitRibbon(buffer, coreWidth, cr, cg, 1.0F, core ? 0.95F : 0.7F * decay);
            // Impact cross flash.
            float flashLife = Math.min(1.0F, age / 4.0F);
            float flashSize = (2.5F + 6.5F * bolt.intensity) * (1.0F - flashLife);
            if (flashSize > 0.05F) {
                emitCrossFlash(buffer, tx, ty + 0.5F, tz, flashSize, 0.9F, 0.8F, 1.0F,
                        0.75F * (1.0F - flashLife));
            }
        }
    }

    /** Camera-facing ribbon along the scratch polyline (one quad per sub-segment). */
    private static void emitRibbon(BufferBuilder buffer, float halfWidth,
            float r, float g, float b, float alpha) {
        if (alpha <= 0.01F) {
            return;
        }
        for (int j = 0; j < BOLT_SUB_SEGMENTS; j++) {
            float ax = BOLT_PTS[j * 3];
            float ay = BOLT_PTS[j * 3 + 1];
            float az = BOLT_PTS[j * 3 + 2];
            float bx = BOLT_PTS[j * 3 + 3];
            float by = BOLT_PTS[j * 3 + 4];
            float bz = BOLT_PTS[j * 3 + 5];
            float dx = bx - ax;
            float dy = by - ay;
            float dz = bz - az;
            // Camera at origin (camera-relative): view dir to the segment midpoint IS the midpoint.
            float mx = (ax + bx) * 0.5F;
            float my = (ay + by) * 0.5F;
            float mz = (az + bz) * 0.5F;
            // side = normalize(segment × toCamera) * halfWidth
            float sx = dy * mz - dz * my;
            float sy = dz * mx - dx * mz;
            float sz = dx * my - dy * mx;
            float sLen = Mth.sqrt(sx * sx + sy * sy + sz * sz);
            if (sLen < 1.0E-4F) {
                continue;
            }
            float scale = halfWidth / sLen;
            sx *= scale;
            sy *= scale;
            sz *= scale;
            buffer.addVertex(ax - sx, ay - sy, az - sz).setColor(r, g, b, alpha);
            buffer.addVertex(ax + sx, ay + sy, az + sz).setColor(r, g, b, alpha);
            buffer.addVertex(bx + sx, by + sy, bz + sz).setColor(r, g, b, alpha);
            buffer.addVertex(bx - sx, by - sy, bz - sz).setColor(r, g, b, alpha);
        }
    }

    /** Two crossed vertical quads at the impact point (cheap omnidirectional flash). */
    private static void emitCrossFlash(BufferBuilder buffer, float x, float y, float z,
            float size, float r, float g, float b, float alpha) {
        buffer.addVertex(x - size, y - size, z).setColor(r, g, b, alpha);
        buffer.addVertex(x + size, y - size, z).setColor(r, g, b, alpha);
        buffer.addVertex(x + size, y + size, z).setColor(r, g, b, alpha);
        buffer.addVertex(x - size, y + size, z).setColor(r, g, b, alpha);
        buffer.addVertex(x, y - size, z - size).setColor(r, g, b, alpha);
        buffer.addVertex(x, y - size, z + size).setColor(r, g, b, alpha);
        buffer.addVertex(x, y + size, z + size).setColor(r, g, b, alpha);
        buffer.addVertex(x, y + size, z - size).setColor(r, g, b, alpha);
    }

    // ------------------------------------------------------------------ draw + helpers

    private static void draw(BufferBuilder buffer, boolean additive, boolean depthWrite) {
        MeshData mesh = buffer.build();
        if (mesh == null) {
            return;
        }
        RenderSystem.enableBlend();
        if (additive) {
            RenderSystem.blendFuncSeparate(GlStateManager.SourceFactor.SRC_ALPHA, GlStateManager.DestFactor.ONE,
                    GlStateManager.SourceFactor.ONE, GlStateManager.DestFactor.ZERO);
        } else {
            RenderSystem.blendFuncSeparate(GlStateManager.SourceFactor.SRC_ALPHA,
                    GlStateManager.DestFactor.ONE_MINUS_SRC_ALPHA,
                    GlStateManager.SourceFactor.ONE, GlStateManager.DestFactor.ZERO);
        }
        RenderSystem.setShader(GameRenderer::getPositionColorShader);
        RenderSystem.disableCull();
        RenderSystem.enableDepthTest();
        RenderSystem.depthMask(depthWrite);
        BufferUploader.drawWithShader(mesh);
        RenderSystem.depthMask(true);
        RenderSystem.enableCull();
        RenderSystem.disableBlend();
        RenderSystem.defaultBlendFunc();
    }

    /** SPAWN grows the wall out of the ground; DISSIPATE stretches it upward as it thins. */
    private static float heightScale(StormFxClient.ClientStorm storm, float visibility) {
        if (storm.state == S2CStormStatePayload.STATE_DISSIPATE) {
            return 1.0F + 0.3F * (1.0F - visibility);
        }
        return 0.25F + 0.75F * visibility;
    }

    /** Cheap 3-int hash in [0,1) — the churn noise (BorderFxRenderer.flicker pattern). */
    private static float hash3(int a, int b, int c) {
        int h = a * 668265261 ^ b * 374761393 ^ c * 0x85EBCA77;
        h = (h ^ (h >>> 13)) * 1274126177;
        return ((h ^ (h >>> 16)) & 0xFFFF) / 65536.0F;
    }

    private static float hashF(int seed, int index) {
        return hash3(seed, index * 31 + 17, seed >>> 8);
    }

    private static float smoothstep(float edge0, float edge1, float x) {
        float t = Mth.clamp((x - edge0) / (edge1 - edge0), 0.0F, 1.0F);
        return t * t * (3.0F - 2.0F * t);
    }
}
