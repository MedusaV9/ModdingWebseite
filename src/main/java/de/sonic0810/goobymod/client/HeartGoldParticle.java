package de.sonic0810.goobymod.client;

import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.particle.Particle;
import net.minecraft.client.particle.ParticleProvider;
import net.minecraft.client.particle.ParticleRenderType;
import net.minecraft.client.particle.SpriteSet;
import net.minecraft.client.particle.TextureSheetParticle;
import net.minecraft.core.particles.SimpleParticleType;

/** Warm gold heart used for best-friend celebrations. */
public final class HeartGoldParticle extends TextureSheetParticle {
    private HeartGoldParticle(ClientLevel level, double x, double y, double z,
            double xSpeed, double ySpeed, double zSpeed, SpriteSet sprites) {
        super(level, x, y, z, xSpeed, ySpeed, zSpeed);
        pickSprite(sprites);
        this.lifetime = 28 + this.random.nextInt(8);
        this.gravity = -0.02F;
        this.friction = 0.92F;
        this.quadSize = 0.14F + this.random.nextFloat() * 0.05F;
        this.hasPhysics = false;
    }

    @Override
    public void tick() {
        super.tick();
        if (this.age > this.lifetime - 8) {
            this.alpha = Math.max(0.0F, this.alpha - 0.12F);
        }
    }

    @Override
    public ParticleRenderType getRenderType() {
        return ParticleRenderType.PARTICLE_SHEET_TRANSLUCENT;
    }

    public static final class Provider implements ParticleProvider<SimpleParticleType> {
        private final SpriteSet sprites;

        public Provider(SpriteSet sprites) {
            this.sprites = sprites;
        }

        @Override
        public Particle createParticle(SimpleParticleType type, ClientLevel level,
                double x, double y, double z, double xSpeed, double ySpeed, double zSpeed) {
            return new HeartGoldParticle(level, x, y, z, xSpeed, ySpeed, zSpeed, this.sprites);
        }
    }
}
