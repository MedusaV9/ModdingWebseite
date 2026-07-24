package dev.projecteclipse.eclipse.client;

import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.particle.Particle;
import net.minecraft.client.particle.ParticleProvider;
import net.minecraft.client.particle.ParticleRenderType;
import net.minecraft.client.particle.SpriteSet;
import net.minecraft.client.particle.TextureSheetParticle;
import net.minecraft.core.particles.SimpleParticleType;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Client-side visual for {@code eclipse:purple_wisp}: a small translucent mote that drifts
 * upward and fades out. Sprite comes from {@code assets/eclipse/particles/purple_wisp.json}.
 */
@OnlyIn(Dist.CLIENT)
public class PurpleWispParticle extends TextureSheetParticle {
    protected PurpleWispParticle(ClientLevel level, double x, double y, double z,
            double xSpeed, double ySpeed, double zSpeed) {
        super(level, x, y, z);
        this.xd = xSpeed;
        this.yd = ySpeed;
        this.zd = zSpeed;
        this.lifetime = 18 + this.random.nextInt(12);
        this.quadSize = 0.07F + this.random.nextFloat() * 0.05F;
        this.gravity = -0.02F; // gentle upward drift
        this.friction = 0.92F;
        this.alpha = 0.9F;
        this.hasPhysics = false;
    }

    @Override
    public void tick() {
        super.tick();
        // Fade out over the last third of the lifetime.
        int remaining = this.lifetime - this.age;
        if (remaining < this.lifetime / 3) {
            this.alpha = 0.9F * remaining / (this.lifetime / 3.0F);
        }
    }

    @Override
    public ParticleRenderType getRenderType() {
        return ParticleRenderType.PARTICLE_SHEET_TRANSLUCENT;
    }

    /** Sprite-set provider registered in {@code EclipseClientParticles}. */
    @OnlyIn(Dist.CLIENT)
    public static class Provider implements ParticleProvider<SimpleParticleType> {
        private final SpriteSet sprites;

        public Provider(SpriteSet sprites) {
            this.sprites = sprites;
        }

        @Override
        public Particle createParticle(SimpleParticleType type, ClientLevel level,
                double x, double y, double z, double xSpeed, double ySpeed, double zSpeed) {
            PurpleWispParticle particle = new PurpleWispParticle(level, x, y, z, xSpeed, ySpeed, zSpeed);
            particle.pickSprite(this.sprites);
            return particle;
        }
    }
}
