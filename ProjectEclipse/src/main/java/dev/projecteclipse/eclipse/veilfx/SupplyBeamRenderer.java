package dev.projecteclipse.eclipse.veilfx;

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
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RenderLevelStageEvent;

/**
 * World-space supply-drop beam (P2 R7d, W5) — the proper Veil-era replacement for the v1
 * END_ROD particle column. Per beam:
 * <ul>
 *   <li><b>Core</b>: 4 crossed additive planes (0°/45°/90°/135°), width {@value #CORE_WIDTH},
 *       {@value #BEAM_HEIGHT} blocks tall, alpha fading to zero at the top;</li>
 *   <li><b>Haze</b>: the same 4 planes at width {@value #HAZE_WIDTH} and low alpha;</li>
 *   <li><b>Impact glow</b>: an 8-segment additive disc hugging the ground at the base;</li>
 *   <li>scrolling {@code border_glitch.png} noise + per-plane vertex-color pulses (shader-less
 *       by design — the beam is the Iris fallback and must render under shaderpacks, §7);</li>
 *   <li>distance LOD: beyond {@value #CORE_ONLY_DISTANCE} blocks only the 4 core planes
 *       (plan: readable from 200+ blocks), beyond {@value #MAX_RENDER_DISTANCE} nothing.</li>
 * </ul>
 *
 * <p>Vertex budget: 16 quads/beam near (4 core + 4 haze + 8 disc), 4 far — within the §3.5
 * "beam ≤ 16 quads" cap. Zero work while no beams are live (single early-out), zero per-frame
 * heap allocations beyond the pooled {@link Tesselator} buffer (the {@code BorderFxRenderer}
 * pattern). Everything is drawn camera-relative at {@link #STAGE}; if Sodium depth-sort
 * artifacts appear, switch the constant to {@code AFTER_TRANSLUCENT_BLOCKS} — both stages
 * fire with the same matrices (documented fallback, §7 risk 2). The single dynamic point
 * light lives in {@link SupplyBeamClient}, not here.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class SupplyBeamRenderer {
    /** Render stage; constant swap to AFTER_TRANSLUCENT_BLOCKS is the Sodium artifact fallback. */
    private static final RenderLevelStageEvent.Stage STAGE = RenderLevelStageEvent.Stage.AFTER_PARTICLES;

    private static final ResourceLocation TEXTURE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/environment/border_glitch.png");

    private static final float BEAM_HEIGHT = 64.0F;
    private static final float CORE_WIDTH = 0.35F;
    private static final float HAZE_WIDTH = 1.1F;
    private static final float DISC_RADIUS = 1.7F;
    private static final int DISC_SEGMENTS = 8;
    /** LOD: past this only the 4 core planes render (R7: "beyond 192 blocks only the 4 core quads"). */
    private static final double CORE_ONLY_DISTANCE = 192.0D;
    private static final double MAX_RENDER_DISTANCE = 512.0D;
    /** Vertical blocks per texture repeat (matches the border strip's chunky static). */
    private static final float TEXTURE_TILE_BLOCKS = 16.0F;

    /** Beam cross-plane directions (0°/45°/90°/135°), precomputed. */
    private static final float[] PLANE_COS = new float[4];
    private static final float[] PLANE_SIN = new float[4];
    /** Disc rim directions, precomputed ({@value #DISC_SEGMENTS} + wrap). */
    private static final float[] DISC_COS = new float[DISC_SEGMENTS + 1];
    private static final float[] DISC_SIN = new float[DISC_SEGMENTS + 1];

    static {
        for (int i = 0; i < 4; i++) {
            float angle = (float) (i * Math.PI / 4.0D);
            PLANE_COS[i] = Mth.cos(angle);
            PLANE_SIN[i] = Mth.sin(angle);
        }
        for (int i = 0; i <= DISC_SEGMENTS; i++) {
            float angle = (float) (i * (Math.PI * 2.0D) / DISC_SEGMENTS);
            DISC_COS[i] = Mth.cos(angle);
            DISC_SIN[i] = Mth.sin(angle);
        }
    }

    private SupplyBeamRenderer() {}

    @SubscribeEvent
    static void onRenderLevelStage(RenderLevelStageEvent event) {
        if (event.getStage() != STAGE) {
            return;
        }
        List<SupplyBeamClient.Beam> beams = SupplyBeamClient.beams();
        if (beams.isEmpty() || Minecraft.getInstance().level == null) {
            return; // zero cost while no drops are live
        }
        Vec3 camera = event.getCamera().getPosition();
        float partialTick = event.getPartialTick().getGameTimeDeltaPartialTick(false);
        long timeMillis = System.currentTimeMillis();
        float scrollCore = (timeMillis % 1800L) / 1800.0F;     // fast upward crawl
        float scrollHaze = (timeMillis % 5200L) / 5200.0F;     // slow drift for the haze
        float pulseTime = (timeMillis % 100_000L) / 1000.0F;

        BufferBuilder buffer = null;
        for (int i = 0; i < beams.size(); i++) {
            SupplyBeamClient.Beam beam = beams.get(i);
            float alpha = Mth.lerp(partialTick, beam.prevAlpha, beam.alpha);
            if (alpha <= 0.01F) {
                continue;
            }
            double distSq = camera.distanceToSqr(beam.baseCenter);
            if (distSq > MAX_RENDER_DISTANCE * MAX_RENDER_DISTANCE) {
                continue;
            }
            if (buffer == null) {
                buffer = Tesselator.getInstance()
                        .begin(VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_TEX_COLOR);
            }
            float x = (float) (beam.baseCenter.x - camera.x);
            float y = (float) (beam.pos.getY() - camera.y);
            float z = (float) (beam.baseCenter.z - camera.z);
            // Per-beam breathing so simultaneous drops don't throb in lockstep.
            float pulse = 0.78F + 0.22F * Mth.sin(pulseTime * 5.0F + beam.pulsePhase);
            float strength = alpha * pulse;

            // Far presence (VFXPOLISH-3): a 0.35-block core is ~1–2 px beyond the core-only
            // LOD, so the core widens continuously with distance (capped ×2.5 at ~480) —
            // the beam stays a readable landmark out to the 512-block cutoff.
            float widthBoost = (float) Mth.clamp(Math.sqrt(distSq) / CORE_ONLY_DISTANCE, 1.0D, 2.5D);
            addPlanes(buffer, x, y, z, CORE_WIDTH * 0.5F * widthBoost, scrollCore,
                    0.85F, 0.62F, 1.0F, 0.55F * strength);
            if (distSq <= CORE_ONLY_DISTANCE * CORE_ONLY_DISTANCE) {
                addPlanes(buffer, x, y, z, HAZE_WIDTH * 0.5F, scrollHaze,
                        0.62F, 0.30F, 1.0F, 0.22F * strength);
                addImpactDisc(buffer, x, y + 0.06F, z, 0.70F, 0.38F, 1.0F, 0.50F * strength);
            }
        }
        if (buffer == null) {
            return;
        }
        MeshData mesh = buffer.build();
        if (mesh == null) {
            return;
        }

        RenderSystem.enableBlend();
        RenderSystem.blendFuncSeparate(GlStateManager.SourceFactor.SRC_ALPHA, GlStateManager.DestFactor.ONE,
                GlStateManager.SourceFactor.ONE, GlStateManager.DestFactor.ZERO);
        RenderSystem.setShaderTexture(0, TEXTURE);
        RenderSystem.setShader(GameRenderer::getPositionTexColorShader);
        RenderSystem.disableCull();
        RenderSystem.enableDepthTest();
        RenderSystem.depthMask(false);
        BufferUploader.drawWithShader(mesh);
        RenderSystem.depthMask(true);
        RenderSystem.enableCull();
        RenderSystem.disableBlend();
        RenderSystem.defaultBlendFunc();
    }

    /** Four crossed vertical planes; alpha runs bottom → 0 at the top so the beam dissolves skyward. */
    private static void addPlanes(BufferBuilder buffer, float x, float y, float z,
            float halfWidth, float scroll, float red, float green, float blue, float alpha) {
        float yTop = y + BEAM_HEIGHT;
        float v0 = -scroll;
        float v1 = v0 + BEAM_HEIGHT / TEXTURE_TILE_BLOCKS;
        for (int i = 0; i < 4; i++) {
            float dx = PLANE_COS[i] * halfWidth;
            float dz = PLANE_SIN[i] * halfWidth;
            // Slight per-plane UV shift so the four planes never show the same noise column.
            float u0 = i * 0.23F;
            float u1 = u0 + 0.18F;
            buffer.addVertex(x - dx, y, z - dz).setUv(u0, v0).setColor(red, green, blue, alpha);
            buffer.addVertex(x + dx, y, z + dz).setUv(u1, v0).setColor(red, green, blue, alpha);
            buffer.addVertex(x + dx, yTop, z + dz).setUv(u1, v1).setColor(red, green, blue, 0.0F);
            buffer.addVertex(x - dx, yTop, z - dz).setUv(u0, v1).setColor(red, green, blue, 0.0F);
        }
    }

    /**
     * Flat 8-segment additive glow disc at the beam base (bright center, transparent rim).
     * All vertices sample one texel, so the radial falloff comes purely from vertex alpha.
     */
    private static void addImpactDisc(BufferBuilder buffer, float x, float y, float z,
            float red, float green, float blue, float alpha) {
        for (int i = 0; i < DISC_SEGMENTS; i++) {
            float x0 = x + DISC_COS[i] * DISC_RADIUS;
            float z0 = z + DISC_SIN[i] * DISC_RADIUS;
            float x1 = x + DISC_COS[i + 1] * DISC_RADIUS;
            float z1 = z + DISC_SIN[i + 1] * DISC_RADIUS;
            buffer.addVertex(x, y, z).setUv(0.5F, 0.5F).setColor(red, green, blue, alpha);
            buffer.addVertex(x0, y, z0).setUv(0.5F, 0.5F).setColor(red, green, blue, 0.0F);
            buffer.addVertex(x1, y, z1).setUv(0.5F, 0.5F).setColor(red, green, blue, 0.0F);
            buffer.addVertex(x, y, z).setUv(0.5F, 0.5F).setColor(red, green, blue, alpha);
        }
    }
}
