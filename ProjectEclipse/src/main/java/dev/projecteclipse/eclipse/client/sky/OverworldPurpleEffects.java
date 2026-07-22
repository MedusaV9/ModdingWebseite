package dev.projecteclipse.eclipse.client.sky;

import com.mojang.blaze3d.platform.GlStateManager;
import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.vertex.BufferBuilder;
import com.mojang.blaze3d.vertex.BufferUploader;
import com.mojang.blaze3d.vertex.DefaultVertexFormat;
import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.Tesselator;
import com.mojang.blaze3d.vertex.VertexFormat;
import com.mojang.math.Axis;

import org.joml.Matrix4f;

import net.minecraft.client.Camera;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.renderer.DimensionSpecialEffects;
import net.minecraft.client.renderer.FogRenderer;
import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.level.material.FogType;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Overworld sky for the Eclipse event ({@code eclipse:overworld} effects id): a close port of
 * the vanilla 1.21.1 {@code LevelRenderer#renderSky} NORMAL-sky path with a large purple sun
 * (from {@code eclipse:textures/environment/sun_purple.png}) plus a soft additive halo, and the
 * sky disc shifted toward purple during the day. Moon, sunrise band, stars and the below-horizon
 * dark disc are kept vanilla-like so nights stay intact.
 *
 * <p>Iris guard: while a shaderpack is active ({@link EclipseIrisState#shaderPackActive()}) this
 * returns {@code false} immediately so the shader pipeline owns the sky; the vanilla sun.png
 * override and the fog tint still apply in that case.</p>
 */
@OnlyIn(Dist.CLIENT)
public class OverworldPurpleEffects extends DimensionSpecialEffects {
    private static final ResourceLocation SUN_PURPLE =
            ResourceLocation.fromNamespaceAndPath("eclipse", "textures/environment/sun_purple.png");
    private static final ResourceLocation MOON_LOCATION =
            ResourceLocation.withDefaultNamespace("textures/environment/moon_phases.png");

    /** Purple target the day sky is blended toward (matches the fog tint). */
    private static final float PURPLE_R = 0.35F;
    private static final float PURPLE_G = 0.10F;
    private static final float PURPLE_B = 0.45F;
    private static final float SKY_BLEND = 0.35F;

    /** Vanilla star field (seed/count as in {@code LevelRenderer#drawStars}). */
    private static final StarField STARS = new StarField(10842L, 1500, 0.15F);

    public OverworldPurpleEffects() {
        // Overworld-like: cloudLevel 192, hasGround, NORMAL sky, no forced-bright lightmap,
        // no constant ambient light.
        super(192.0F, true, DimensionSpecialEffects.SkyType.NORMAL, false, false);
    }

    @Override
    public Vec3 getBrightnessDependentFogColor(Vec3 fogColor, float brightness) {
        // Same curve as vanilla OverworldEffects.
        return fogColor.multiply(brightness * 0.94F + 0.06F, brightness * 0.94F + 0.06F, brightness * 0.91F + 0.09F);
    }

    @Override
    public boolean isFoggyAt(int x, int y) {
        return false;
    }

    @Override
    public boolean renderSky(ClientLevel level, int ticks, float partialTick, Matrix4f modelViewMatrix,
            Camera camera, Matrix4f projectionMatrix, boolean isFoggy, Runnable setupFog) {
        if (EclipseIrisState.shaderPackActive()) {
            return false; // shaderpack owns the sky; sun.png override + fog tint still apply
        }
        setupFog.run();
        if (isFoggy) {
            return true; // vanilla draws no sky in this case either
        }
        FogType fogType = camera.getFluidInCamera();
        if (fogType == FogType.POWDER_SNOW || fogType == FogType.LAVA || mobEffectBlocksSky(camera)) {
            return true;
        }

        PoseStack poseStack = new PoseStack();
        poseStack.mulPose(modelViewMatrix);

        // --- sky disc, blended toward purple during the day -------------------------------
        Vec3 skyColor = level.getSkyColor(camera.getPosition(), partialTick);
        float day = dayFactor(level, partialTick);
        float blend = SKY_BLEND * day;
        float skyR = Mth.lerp(blend, (float) skyColor.x, PURPLE_R);
        float skyG = Mth.lerp(blend, (float) skyColor.y, PURPLE_G);
        float skyB = Mth.lerp(blend, (float) skyColor.z, PURPLE_B);
        FogRenderer.levelFogColor();
        RenderSystem.depthMask(false);
        RenderSystem.setShaderColor(skyR, skyG, skyB, 1.0F);
        RenderSystem.setShader(GameRenderer::getPositionShader);
        SkyRenderUtil.drawSkyDisc(poseStack.last().pose(), 16.0F);

        RenderSystem.enableBlend();

        // --- sunrise/sunset band (vanilla formula) -----------------------------------------
        float[] sunrise = this.getSunriseColor(level.getTimeOfDay(partialTick), partialTick);
        if (sunrise != null) {
            RenderSystem.setShader(GameRenderer::getPositionColorShader);
            RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, 1.0F);
            poseStack.pushPose();
            poseStack.mulPose(Axis.XP.rotationDegrees(90.0F));
            float sunDirection = Mth.sin(level.getSunAngle(partialTick)) < 0.0F ? 180.0F : 0.0F;
            poseStack.mulPose(Axis.ZP.rotationDegrees(sunDirection));
            poseStack.mulPose(Axis.ZP.rotationDegrees(90.0F));
            Matrix4f pose = poseStack.last().pose();
            BufferBuilder builder = Tesselator.getInstance().begin(VertexFormat.Mode.TRIANGLE_FAN, DefaultVertexFormat.POSITION_COLOR);
            builder.addVertex(pose, 0.0F, 100.0F, 0.0F).setColor(sunrise[0], sunrise[1], sunrise[2], sunrise[3]);
            for (int i = 0; i <= 16; i++) {
                float angle = (float) i * ((float) Math.PI * 2.0F) / 16.0F;
                float sin = Mth.sin(angle);
                float cos = Mth.cos(angle);
                builder.addVertex(pose, sin * 120.0F, cos * 120.0F, -cos * 40.0F * sunrise[3])
                        .setColor(sunrise[0], sunrise[1], sunrise[2], 0.0F);
            }
            BufferUploader.drawWithShader(builder.buildOrThrow());
            poseStack.popPose();
        }

        // --- celestial bodies (additive, like vanilla) ---------------------------------------
        RenderSystem.blendFuncSeparate(
                GlStateManager.SourceFactor.SRC_ALPHA, GlStateManager.DestFactor.ONE,
                GlStateManager.SourceFactor.ONE, GlStateManager.DestFactor.ZERO);
        poseStack.pushPose();
        float rainAlpha = 1.0F - level.getRainLevel(partialTick);
        poseStack.mulPose(Axis.YP.rotationDegrees(-90.0F));
        poseStack.mulPose(Axis.XP.rotationDegrees(level.getTimeOfDay(partialTick) * 360.0F));
        Matrix4f celestialPose = poseStack.last().pose();

        RenderSystem.setShader(GameRenderer::getPositionTexShader);

        // soft halo: the same texture drawn much larger at low alpha behind the sun
        RenderSystem.setShaderColor(0.72F, 0.35F, 0.95F, 0.40F * rainAlpha);
        RenderSystem.setShaderTexture(0, SUN_PURPLE);
        SkyRenderUtil.drawCelestialQuad(celestialPose, 60.0F, 100.0F);

        // the purple sun itself, slightly larger than the vanilla 30f sun
        RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, rainAlpha);
        SkyRenderUtil.drawCelestialQuad(celestialPose, 38.0F, 100.0F);

        // vanilla moon (phases from the shared moon sheet)
        RenderSystem.setShaderTexture(0, MOON_LOCATION);
        int moonPhase = level.getMoonPhase();
        int px = moonPhase % 4;
        int py = moonPhase / 4 % 2;
        float u0 = (float) (px + 0) / 4.0F;
        float v0 = (float) (py + 0) / 2.0F;
        float u1 = (float) (px + 1) / 4.0F;
        float v1 = (float) (py + 1) / 2.0F;
        float moonSize = 20.0F;
        BufferBuilder moon = Tesselator.getInstance().begin(VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_TEX);
        moon.addVertex(celestialPose, -moonSize, -100.0F, moonSize).setUv(u1, v1);
        moon.addVertex(celestialPose, moonSize, -100.0F, moonSize).setUv(u0, v1);
        moon.addVertex(celestialPose, moonSize, -100.0F, -moonSize).setUv(u0, v0);
        moon.addVertex(celestialPose, -moonSize, -100.0F, -moonSize).setUv(u1, v0);
        BufferUploader.drawWithShader(moon.buildOrThrow());

        // stars, faintly purple-tinted
        float starBrightness = level.getStarBrightness(partialTick) * rainAlpha;
        if (starBrightness > 0.0F) {
            RenderSystem.setShaderColor(starBrightness * 0.9F, starBrightness * 0.8F, starBrightness, starBrightness);
            FogRenderer.setupNoFog();
            STARS.draw(poseStack.last().pose(), projectionMatrix);
            setupFog.run();
        }

        RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.disableBlend();
        RenderSystem.defaultBlendFunc();
        poseStack.popPose();

        // --- dark disc below the horizon (vanilla behavior) ---------------------------------
        RenderSystem.setShaderColor(0.0F, 0.0F, 0.0F, 1.0F);
        double distanceAboveHorizon = camera.getPosition().y - level.getLevelData().getHorizonHeight(level);
        if (distanceAboveHorizon < 0.0) {
            poseStack.pushPose();
            poseStack.translate(0.0F, 12.0F, 0.0F);
            RenderSystem.setShader(GameRenderer::getPositionShader);
            SkyRenderUtil.drawSkyDisc(poseStack.last().pose(), -16.0F);
            poseStack.popPose();
        }

        RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.depthMask(true);
        return true;
    }

    /** 0 at night, 1 at midday — same cosine curve vanilla uses for sky brightness. */
    static float dayFactor(ClientLevel level, float partialTick) {
        float cos = Mth.cos(level.getTimeOfDay(partialTick) * ((float) Math.PI * 2.0F)) * 2.0F + 0.5F;
        return Mth.clamp(cos, 0.0F, 1.0F);
    }

    /** Mirror of the private {@code LevelRenderer#doesMobEffectBlockSky}. */
    static boolean mobEffectBlocksSky(Camera camera) {
        return camera.getEntity() instanceof LivingEntity living
                && (living.hasEffect(MobEffects.BLINDNESS) || living.hasEffect(MobEffects.DARKNESS));
    }
}
