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
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RenderLevelStageEvent;

/**
 * WOAH-01 §4.5 — the 200-block GREEN sky beam off the glitch emitter's antenna: the
 * dome's far-view signal. Deliberate CLONE of the frozen {@code veilfx/SupplyBeamRenderer}
 * (no refactor of the original — plan law), re-tuned:
 *
 * <ul>
 *   <li>base at the antenna top ({@code devicePos.y + 2.4}), height {@value #BEAM_HEIGHT}
 *       blocks; 4 crossed additive planes (0°/45°/90°/135°), core width
 *       {@value #CORE_WIDTH}, haze {@value #HAZE_WIDTH}, impact-glow disc on the ROOF
 *       (not the ground) — ≤ 16 quads near, 4 far;</li>
 *   <li>{@code border_glitch.png} scrolling upward, dome green; per-frame breathing;</li>
 *   <li>LOD: beyond {@value #CORE_ONLY_DISTANCE} blocks only the 4 core planes, beyond
 *       {@value #MAX_RENDER_DISTANCE} nothing (farther than the SupplyBeam — the beam IS
 *       the landmark);</li>
 *   <li>status coupling: ACTIVE full; COLLAPSING t0–t30 flicker (10&nbsp;Hz alpha noise),
 *       t30–t50 top-down collapse (height → 0); DESTROYED/absent zero-cost early-out.
 *       Shader-less → Iris-fest.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
@OnlyIn(Dist.CLIENT)
public final class DomeBeamRenderer {
    /** SupplyBeam stage; swap to AFTER_TRANSLUCENT_BLOCKS on Sodium sort artifacts. */
    private static final RenderLevelStageEvent.Stage STAGE =
            RenderLevelStageEvent.Stage.AFTER_PARTICLES;

    private static final ResourceLocation TEXTURE = ResourceLocation
            .fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/environment/border_glitch.png");

    private static final float BEAM_HEIGHT = 200.0F;
    /** Antenna top above the device stand (§7: knob at ≈ 39 model units ≈ 2.4 blocks). */
    private static final float ANTENNA_TOP = 2.4F;
    private static final float CORE_WIDTH = 0.5F;
    private static final float HAZE_WIDTH = 1.6F;
    private static final float DISC_RADIUS = 2.2F;
    private static final int DISC_SEGMENTS = 8;
    private static final double CORE_ONLY_DISTANCE = 192.0D;
    private static final double MAX_RENDER_DISTANCE = 640.0D;
    private static final float TEXTURE_TILE_BLOCKS = 16.0F;
    /** Top-down collapse window (t30 → t50, §5). */
    private static final float COLLAPSE_TICKS = 20.0F;

    /** Dome green (GlitchColors phosphor). */
    private static final float GREEN_R = 0.30F;
    private static final float GREEN_G = 0.95F;
    private static final float GREEN_B = 0.62F;

    private static final float[] PLANE_COS = new float[4];
    private static final float[] PLANE_SIN = new float[4];
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

    private DomeBeamRenderer() {}

    @SubscribeEvent
    static void onRenderLevelStage(RenderLevelStageEvent event) {
        if (event.getStage() != STAGE || Minecraft.getInstance().level == null
                || !MansionDomeClient.presentHere()) {
            return;
        }
        float partialTick = event.getPartialTick().getGameTimeDeltaPartialTick(false);
        float alpha = MansionDomeClient.visibility(partialTick);
        if (alpha <= 0.01F) {
            return;
        }
        float height = BEAM_HEIGHT;
        float time = MansionDomeClient.timeSeconds(partialTick);
        float elapsed = MansionDomeClient.collapseElapsed(partialTick);
        if (elapsed >= 0.0F) {
            if (elapsed < MansionDomeClient.COLLAPSE_SHATTER_TICK) {
                // t0–t30: 10 Hz alpha flicker — the device is dying.
                alpha *= 0.55F + 0.45F * flickerNoise(time * 10.0F);
            } else {
                // t30–t50: top-down collapse, the column sinks back into the antenna.
                float down = (elapsed - MansionDomeClient.COLLAPSE_SHATTER_TICK) / COLLAPSE_TICKS;
                if (down >= 1.0F) {
                    return;
                }
                height = BEAM_HEIGHT * (1.0F - down);
                alpha *= 1.0F - 0.5F * down;
            }
        }

        BlockPos devicePos = MansionDomeClient.devicePos();
        Vec3 camera = event.getCamera().getPosition();
        double baseX = devicePos.getX() + 0.5D;
        double baseY = devicePos.getY() + ANTENNA_TOP;
        double baseZ = devicePos.getZ() + 0.5D;
        double dx = baseX - camera.x;
        double dz = baseZ - camera.z;
        double distSq = dx * dx + dz * dz;
        if (distSq > MAX_RENDER_DISTANCE * MAX_RENDER_DISTANCE) {
            return;
        }

        long timeMillis = System.currentTimeMillis();
        float scrollCore = (timeMillis % 1400L) / 1400.0F;
        float scrollHaze = (timeMillis % 4600L) / 4600.0F;
        float pulse = 0.80F + 0.20F * Mth.sin(time * 5.0F);
        float strength = alpha * pulse;

        float x = (float) dx;
        float y = (float) (baseY - camera.y);
        float z = (float) dz;

        BufferBuilder buffer = Tesselator.getInstance()
                .begin(VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_TEX_COLOR);
        // Far presence: widen the core with distance (the SupplyBeam VFXPOLISH-3 law).
        float widthBoost = (float) Mth.clamp(Math.sqrt(distSq) / CORE_ONLY_DISTANCE, 1.0D, 2.5D);
        addPlanes(buffer, x, y, z, height, CORE_WIDTH * 0.5F * widthBoost, scrollCore,
                Math.min(1.0F, GREEN_R + 0.35F), Math.min(1.0F, GREEN_G + 0.05F),
                Math.min(1.0F, GREEN_B + 0.25F), 0.60F * strength);
        if (distSq <= CORE_ONLY_DISTANCE * CORE_ONLY_DISTANCE) {
            addPlanes(buffer, x, y, z, height, HAZE_WIDTH * 0.5F, scrollHaze,
                    GREEN_R, GREEN_G, GREEN_B, 0.20F * strength);
            addImpactDisc(buffer, x, y + 0.05F, z, GREEN_R, GREEN_G, GREEN_B,
                    0.45F * strength);
        }
        MeshData mesh = buffer.build();
        if (mesh == null) {
            return;
        }

        RenderSystem.enableBlend();
        RenderSystem.blendFuncSeparate(GlStateManager.SourceFactor.SRC_ALPHA,
                GlStateManager.DestFactor.ONE, GlStateManager.SourceFactor.ONE,
                GlStateManager.DestFactor.ZERO);
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

    /** Cheap deterministic 0..1 flicker (two incommensurate sines, no allocations). */
    private static float flickerNoise(float t) {
        float n = Mth.sin(t * Mth.TWO_PI) * 0.5F + Mth.sin(t * 4.73F + 1.7F) * 0.5F;
        return Mth.clamp(0.5F + 0.5F * n, 0.0F, 1.0F);
    }

    /** Four crossed vertical planes, alpha fading to zero toward the beam top. */
    private static void addPlanes(BufferBuilder buffer, float x, float y, float z,
            float height, float halfWidth, float scroll, float red, float green, float blue,
            float alpha) {
        float yTop = y + height;
        float v0 = -scroll;
        float v1 = v0 + height / TEXTURE_TILE_BLOCKS;
        for (int i = 0; i < 4; i++) {
            float dx = PLANE_COS[i] * halfWidth;
            float dz = PLANE_SIN[i] * halfWidth;
            float u0 = i * 0.23F;
            float u1 = u0 + 0.18F;
            buffer.addVertex(x - dx, y, z - dz).setUv(u0, v0).setColor(red, green, blue, alpha);
            buffer.addVertex(x + dx, y, z + dz).setUv(u1, v0).setColor(red, green, blue, alpha);
            buffer.addVertex(x + dx, yTop, z + dz).setUv(u1, v1).setColor(red, green, blue, 0.0F);
            buffer.addVertex(x - dx, yTop, z - dz).setUv(u0, v1).setColor(red, green, blue, 0.0F);
        }
    }

    /** Additive glow disc hugging the roof at the antenna base. */
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
