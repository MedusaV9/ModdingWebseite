package de.sonic0810.goobymod.client;

import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.particle.Particle;
import net.minecraft.client.particle.ParticleProvider;
import net.minecraft.client.particle.ParticleRenderType;
import net.minecraft.client.particle.SpriteSet;
import net.minecraft.client.particle.TextureSheetParticle;
import net.minecraft.core.particles.SimpleParticleType;
import net.minecraft.util.Mth;

/**
 * Zzz — schwebt beim Schlafen niedlich schaukelnd nach oben und verblasst.
 */
public class ZzzParticle extends TextureSheetParticle {
    protected ZzzParticle(ClientLevel level, double x, double y, double z, boolean groupNap, SpriteSet sprites) {
        super(level, x, y, z);
        pickSprite(sprites);
        this.lifetime = 45 + this.random.nextInt(15);
        this.gravity = 0.0F;
        this.friction = 1.0F;
        this.quadSize = groupNap ? 0.28F : 0.16F;
        this.yd = 0.02;
        this.hasPhysics = false;
    }

    @Override
    public void tick() {
        super.tick();
        this.xd = Mth.sin(this.age * 0.18F) * 0.012;
        this.yd = 0.02;
        if (this.age > this.lifetime - 12) {
            this.alpha = Math.max(0.0F, this.alpha - 0.085F);
        }
    }

    @Override
    public ParticleRenderType getRenderType() {
        return ParticleRenderType.PARTICLE_SHEET_TRANSLUCENT;
    }

    public static class Provider implements ParticleProvider<SimpleParticleType> {
        private final SpriteSet sprites;

        public Provider(SpriteSet sprites) {
            this.sprites = sprites;
        }

        @Override
        public Particle createParticle(SimpleParticleType type, ClientLevel level, double x, double y, double z,
                double xSpeed, double ySpeed, double zSpeed) {
            return new ZzzParticle(level, x, y, z, xSpeed > 0.5, this.sprites);
        }
    }
}
