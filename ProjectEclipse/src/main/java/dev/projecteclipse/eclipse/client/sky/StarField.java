package dev.projecteclipse.eclipse.client.sky;

import com.mojang.blaze3d.vertex.BufferBuilder;
import com.mojang.blaze3d.vertex.DefaultVertexFormat;
import com.mojang.blaze3d.vertex.Tesselator;
import com.mojang.blaze3d.vertex.VertexBuffer;
import com.mojang.blaze3d.vertex.VertexFormat;

import org.joml.Matrix4f;
import org.joml.Quaternionf;
import org.joml.Vector3f;

import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.client.renderer.ShaderInstance;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Lazily-built static star mesh on the celestial sphere (same construction as vanilla
 * {@code LevelRenderer#drawStars}, parameterized seed/count/size). Tint/brightness is applied
 * at draw time via the shader color, so one buffer serves every sky that uses it.
 *
 * <p>Must only be touched from the render thread (created inside {@code renderSky}).</p>
 */
@OnlyIn(Dist.CLIENT)
final class StarField {
    private final long seed;
    private final int count;
    private final float baseSize;
    private VertexBuffer buffer;

    StarField(long seed, int count, float baseSize) {
        this.seed = seed;
        this.count = count;
        this.baseSize = baseSize;
    }

    /** Draws the stars with the given pose/projection; caller sets shader color, fog and blend state. */
    void draw(Matrix4f pose, Matrix4f projection) {
        if (buffer == null) {
            buffer = new VertexBuffer(VertexBuffer.Usage.STATIC);
            buffer.bind();
            buffer.upload(build());
            VertexBuffer.unbind();
        }
        ShaderInstance shader = GameRenderer.getPositionShader();
        buffer.bind();
        buffer.drawWithShader(pose, projection, shader);
        VertexBuffer.unbind();
    }

    private com.mojang.blaze3d.vertex.MeshData build() {
        RandomSource random = RandomSource.create(seed);
        BufferBuilder builder = Tesselator.getInstance().begin(VertexFormat.Mode.QUADS, DefaultVertexFormat.POSITION);
        for (int i = 0; i < count; i++) {
            float x = random.nextFloat() * 2.0F - 1.0F;
            float y = random.nextFloat() * 2.0F - 1.0F;
            float z = random.nextFloat() * 2.0F - 1.0F;
            float size = baseSize + random.nextFloat() * 0.1F;
            float lengthSq = Mth.lengthSquared(x, y, z);
            if (lengthSq <= 0.010000001F || lengthSq >= 1.0F) {
                continue;
            }
            Vector3f pos = new Vector3f(x, y, z).normalize(100.0F);
            float roll = (float) (random.nextDouble() * Math.PI * 2.0);
            Quaternionf rotation = new Quaternionf().rotateTo(new Vector3f(0.0F, 0.0F, -1.0F), pos).rotateZ(roll);
            builder.addVertex(new Vector3f(pos).add(new Vector3f(size, -size, 0.0F).rotate(rotation)));
            builder.addVertex(new Vector3f(pos).add(new Vector3f(size, size, 0.0F).rotate(rotation)));
            builder.addVertex(new Vector3f(pos).add(new Vector3f(-size, size, 0.0F).rotate(rotation)));
            builder.addVertex(new Vector3f(pos).add(new Vector3f(-size, -size, 0.0F).rotate(rotation)));
        }
        return builder.buildOrThrow();
    }
}
