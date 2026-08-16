package de.sonic0810.goobymod.client.particle;

import de.sonic0810.goobymod.GoobyClientConfig;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.particle.Particle;
import net.minecraft.client.particle.ParticleProvider;
import net.minecraft.client.particle.ParticleRenderType;
import net.minecraft.client.particle.SpriteSet;
import net.minecraft.client.particle.TextureSheetParticle;
import net.minecraft.core.particles.SimpleParticleType;
import net.minecraft.util.Mth;

/**
 * Weicher Fellfussel: blendet sanft ein, driftet traege auseinander und
 * loest sich ueber die vier Sprite-Frames (dicht → zerfasert) auf, waehrend
 * er leicht waechst und ausblendet. Cremefarben wie Goobys Puschel-Fell,
 * mit leichtem Helligkeits-Jitter pro Fussel.
 *
 * <p>reducedMotion: kuerzer und fast bewegungslos — nur das weiche
 * Ein-/Ausblenden bleibt.</p>
 */
public class FluffPuffParticle extends TextureSheetParticle {
    private final SpriteSet sprites;
    private final boolean calm;
    private final float baseSize;
    private final float swayPhase;

    protected FluffPuffParticle(ClientLevel level, double x, double y, double z,
            double xSpeed, double ySpeed, double zSpeed, SpriteSet sprites) {
        super(level, x, y, z);
        this.sprites = sprites;
        this.calm = GoobyClientConfig.reducedMotion();

        float shade = 0.94F + this.random.nextFloat() * 0.06F;
        setColor(shade, shade * 0.985F, shade * 0.94F);

        this.baseSize = 0.10F + this.random.nextFloat() * 0.06F;
        this.quadSize = this.baseSize;
        this.hasPhysics = false;
        this.gravity = 0.015F;
        this.friction = 0.92F;
        this.swayPhase = this.random.nextFloat() * Mth.TWO_PI;
        this.alpha = 0.0F;
        if (this.calm) {
            this.lifetime = 16 + this.random.nextInt(6);
            this.xd = xSpeed * 0.1;
            this.yd = Math.abs(ySpeed) * 0.1 + 0.008;
            this.zd = zSpeed * 0.1;
        } else {
            this.lifetime = 30 + this.random.nextInt(12);
            this.xd = xSpeed * 0.4 + (this.random.nextDouble() - 0.5) * 0.03;
            this.yd = Math.abs(ySpeed) * 0.3 + 0.02 + this.random.nextDouble() * 0.025;
            this.zd = zSpeed * 0.4 + (this.random.nextDouble() - 0.5) * 0.03;
        }
        setSpriteFromAge(sprites);
    }

    @Override
    public void tick() {
        super.tick();
        setSpriteFromAge(this.sprites);
        if (!this.calm) {
            this.xd += Mth.sin(this.swayPhase + this.age * 0.22F) * 0.0016;
            this.zd += Mth.cos(this.swayPhase + this.age * 0.19F) * 0.0016;
        }
        // Sanft groesser werden, waehrend der Fussel zerfasert.
        this.quadSize = this.baseSize * (1.0F + 0.3F * (float) this.age / (float) this.lifetime);
        // Fade-in ueber vier Ticks (0.24er-Schritte) bis zum 0.9-Peak — age
        // ist hier bereits inkrementiert, daher inklusive Grenze (age <= 4).
        if (this.age <= 4) {
            this.alpha = Math.min(0.9F, this.alpha + 0.24F);
        } else if (this.age > this.lifetime - 9) {
            this.alpha = Math.max(0.0F, this.alpha - 0.11F);
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
            return new FluffPuffParticle(level, x, y, z, xSpeed, ySpeed, zSpeed, this.sprites);
        }
    }
}
