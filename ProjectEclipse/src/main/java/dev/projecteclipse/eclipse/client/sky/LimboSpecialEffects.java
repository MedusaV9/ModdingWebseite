package dev.projecteclipse.eclipse.client.sky;

import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.math.Axis;

import org.joml.Matrix4f;

import net.minecraft.client.Camera;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.renderer.DimensionSpecialEffects;
import net.minecraft.client.renderer.FogRenderer;
import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.level.material.FogType;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Sky for the Limbo dimension ({@code eclipse:limbo} effects id, referenced by
 * {@code data/eclipse/dimension_type/limbo.json}): a near-black dome, the eclipse disc
 * ({@code eclipse:textures/environment/eclipse.png}) fixed high in the sky (Limbo has
 * {@code fixed_time}, so it never moves), and a sparse field of green star points.
 *
 * <p>Same Iris guard as the overworld: with a shaderpack active this defers entirely.</p>
 */
@OnlyIn(Dist.CLIENT)
public class LimboSpecialEffects extends DimensionSpecialEffects {
    private static final ResourceLocation ECLIPSE_TEXTURE =
            ResourceLocation.fromNamespaceAndPath("eclipse", "textures/environment/eclipse.png");

    /** Sparse green stars; distinct seed so Limbo's sky differs from the overworld's. */
    private static final StarField GREEN_STARS = new StarField(20846L, 420, 0.18F);

    public LimboSpecialEffects() {
        // No clouds, no ground fog wrap, no vanilla sky shape; lightmap stays natural.
        super(Float.NaN, false, DimensionSpecialEffects.SkyType.NONE, false, false);
    }

    @Override
    public Vec3 getBrightnessDependentFogColor(Vec3 fogColor, float brightness) {
        // Crush fog toward black like the End so the horizon melts into the void.
        return fogColor.scale(0.15);
    }

    @Override
    public boolean isFoggyAt(int x, int y) {
        return false;
    }

    @Override
    public boolean renderSky(ClientLevel level, int ticks, float partialTick, Matrix4f modelViewMatrix,
            Camera camera, Matrix4f projectionMatrix, boolean isFoggy, Runnable setupFog) {
        if (IrisCompat.shadersActive()) {
            return false; // shaderpack owns the sky
        }
        setupFog.run();
        if (isFoggy) {
            return true;
        }
        FogType fogType = camera.getFluidInCamera();
        if (fogType == FogType.POWDER_SNOW || fogType == FogType.LAVA
                || OverworldPurpleEffects.mobEffectBlocksSky(camera)) {
            return true;
        }

        PoseStack poseStack = new PoseStack();
        poseStack.mulPose(modelViewMatrix);

        // near-black dome
        FogRenderer.levelFogColor();
        RenderSystem.depthMask(false);
        RenderSystem.setShader(GameRenderer::getPositionShader);
        RenderSystem.setShaderColor(0.015F, 0.02F, 0.03F, 1.0F);
        SkyRenderUtil.drawSkyDisc(poseStack.last().pose(), 16.0F);

        RenderSystem.enableBlend();

        // sparse green star points (no fog so they stay crisp)
        RenderSystem.setShaderColor(0.35F, 0.9F, 0.45F, 0.85F);
        FogRenderer.setupNoFog();
        GREEN_STARS.draw(poseStack.last().pose(), projectionMatrix);
        setupFog.run();

        // eclipse disc pinned high in the southern sky; alpha-blended so the black disc occludes
        poseStack.pushPose();
        poseStack.mulPose(Axis.XP.rotationDegrees(-25.0F));
        RenderSystem.defaultBlendFunc();
        RenderSystem.setShader(GameRenderer::getPositionTexShader);
        RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.setShaderTexture(0, ECLIPSE_TEXTURE);
        SkyRenderUtil.drawCelestialQuad(poseStack.last().pose(), 35.0F, 100.0F);
        poseStack.popPose();

        RenderSystem.setShaderColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.disableBlend();
        RenderSystem.defaultBlendFunc();
        RenderSystem.depthMask(true);
        return true;
    }
}
