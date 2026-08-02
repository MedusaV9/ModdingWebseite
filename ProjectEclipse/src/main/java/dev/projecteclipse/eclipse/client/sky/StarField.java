package dev.projecteclipse.eclipse.client.sky;

import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.vertex.BufferBuilder;
import com.mojang.blaze3d.vertex.DefaultVertexFormat;
import com.mojang.blaze3d.vertex.Tesselator;
import com.mojang.blaze3d.vertex.VertexBuffer;
import com.mojang.blaze3d.vertex.VertexFormat;

import org.joml.Matrix4f;
import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.client.drama.NightDreadFx;
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
    // WAVE6 (F-106 A) A3 — Umbral-night star grade: overall brightness ×~0.55 with a
    // warm red lean (per-channel r×0.70 / g×0.50 / b×0.45, alpha ×0.55 — "the sky holds
    // its breath"), multiplied on TOP of whatever colour the caller set, so the eclipse/
    // credits star boosts keep working underneath. Pale Nights are deliberately ±0 (the
    // pale night belongs to the moon, plan §3 A3). NightDreadFx.isUmbral() is overworld-
    // gated, so the Limbo sky (LimboSpecialEffects shares this mesh class) never dims.
    private static final float UMBRAL_STAR_R = 0.70F;
    private static final float UMBRAL_STAR_G = 0.50F;
    private static final float UMBRAL_STAR_B = 0.45F;
    private static final float UMBRAL_STAR_A = 0.55F;

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
        // WAVE6 (F-106 A) A3: Umbral star dimming — constants-only math in the existing
        // shader-colour path; the caller's colour is restored afterwards so the star pass
        // stays a pure function of its inputs on every other night.
        boolean umbral = NightDreadFx.isUmbral();
        float callerR = 0.0F;
        float callerG = 0.0F;
        float callerB = 0.0F;
        float callerA = 0.0F;
        if (umbral) {
            float[] shaderColor = RenderSystem.getShaderColor();
            callerR = shaderColor[0];
            callerG = shaderColor[1];
            callerB = shaderColor[2];
            callerA = shaderColor[3];
            RenderSystem.setShaderColor(callerR * UMBRAL_STAR_R, callerG * UMBRAL_STAR_G,
                    callerB * UMBRAL_STAR_B, callerA * UMBRAL_STAR_A);
        }
        ShaderInstance shader = GameRenderer.getPositionShader();
        buffer.bind();
        buffer.drawWithShader(pose, projection, shader);
        VertexBuffer.unbind();
        if (umbral) {
            RenderSystem.setShaderColor(callerR, callerG, callerB, callerA);
        }
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
