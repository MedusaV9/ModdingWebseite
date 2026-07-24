package dev.projecteclipse.eclipse.client.sky;

import com.mojang.blaze3d.vertex.BufferBuilder;
import com.mojang.blaze3d.vertex.BufferUploader;
import com.mojang.blaze3d.vertex.DefaultVertexFormat;
import com.mojang.blaze3d.vertex.Tesselator;
import com.mojang.blaze3d.vertex.VertexFormat;

import org.joml.Matrix4f;

import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/** Small immediate-mode helpers shared by the Eclipse sky renderers. */
@OnlyIn(Dist.CLIENT)
final class SkyRenderUtil {
    private SkyRenderUtil() {}

    /**
     * Draws the vanilla sky disc (triangle fan, radius 512 at {@code |y|=16}) with the currently
     * bound position shader and shader color. Same geometry as {@code LevelRenderer#buildSkyDisc},
     * built immediate-mode so no vertex buffer bookkeeping is needed.
     */
    static void drawSkyDisc(Matrix4f pose, float y) {
        float edgeY = Math.signum(y) * 512.0F;
        BufferBuilder builder = Tesselator.getInstance().begin(VertexFormat.Mode.TRIANGLE_FAN, DefaultVertexFormat.POSITION);
        builder.addVertex(pose, 0.0F, y, 0.0F);
        for (int i = -180; i <= 180; i += 45) {
            builder.addVertex(pose,
                    edgeY * Mth.cos((float) i * ((float) Math.PI / 180.0F)), y,
                    512.0F * Mth.sin((float) i * ((float) Math.PI / 180.0F)));
        }
        BufferUploader.drawWithShader(builder.buildOrThrow());
    }

    /**
     * Draws a horizontal textured quad spanning {@code ±size} at the given height (the vanilla
     * sun/moon quad shape) with full 0..1 UVs; caller binds texture, shader and color first.
     */
    static void drawCelestialQuad(Matrix4f pose, float size, float height) {
        BufferBuilder builder = Tesselator.getInstance().begin(VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION_TEX);
        builder.addVertex(pose, -size, height, -size).setUv(0.0F, 0.0F);
        builder.addVertex(pose, size, height, -size).setUv(1.0F, 0.0F);
        builder.addVertex(pose, size, height, size).setUv(1.0F, 1.0F);
        builder.addVertex(pose, -size, height, size).setUv(0.0F, 1.0F);
        BufferUploader.drawWithShader(builder.buildOrThrow());
    }
}
