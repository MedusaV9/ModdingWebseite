package de.sonic0810.goobymod.client;

import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.particle.Particle;
import net.minecraft.client.particle.ParticleProvider;
import net.minecraft.client.particle.ParticleRenderType;
import net.minecraft.client.particle.SpriteSet;
import net.minecraft.client.particle.TextureSheetParticle;
import net.minecraft.core.particles.SimpleParticleType;

/** A short-lived flat paw mark for soft-ground footsteps. */
public final class PawPrintParticle extends TextureSheetParticle {
    private PawPrintParticle(ClientLevel level, double x, double y, double z, SpriteSet sprites) {
        super(level, x, y, z);
        pickSprite(sprites);
        this.lifetime = 36;
        this.gravity = 0.0F;
        this.friction = 1.0F;
        this.quadSize = 0.18F;
        this.hasPhysics = false;
        this.roll = this.random.nextFloat() * (float) Math.PI * 2.0F;
        this.oRoll = this.roll;
    }

    @Override
    public void tick() {
        super.tick();
        this.yd = 0.0;
        if (this.age > this.lifetime - 10) {
            this.alpha = Math.max(0.0F, this.alpha - 0.1F);
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
            return new PawPrintParticle(level, x, y, z, this.sprites);
        }
    }
}
