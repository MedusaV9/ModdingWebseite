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
 * Musiknote: steigt gemuetlich auf, pendelt dabei leicht wie eine Melodie
 * und verblasst oben. Zwei Glyphen-Varianten (Achtelnote, Doppelnote mit
 * Balken), Pastellfarbe ueber zufaelligen Farbton und variable Groesse —
 * die weissen Sprites werden pro Partikel getintet.
 *
 * <p>reducedMotion: kuerzer, langsamer Aufstieg, kein Pendeln.</p>
 */
public class MusicNoteParticle extends TextureSheetParticle {
    private final boolean calm;
    private final float swayPhase;

    protected MusicNoteParticle(ClientLevel level, double x, double y, double z,
            double xSpeed, double ySpeed, double zSpeed, SpriteSet sprites) {
        super(level, x, y, z);
        pickSprite(sprites);
        this.calm = GoobyClientConfig.reducedMotion();

        // Pastell-Tint: voller Farbkreis, gedeckte Saettigung, volle Helligkeit.
        int rgb = Mth.hsvToRgb(this.random.nextFloat(), 0.42F, 1.0F);
        setColor((rgb >> 16 & 0xFF) / 255.0F, (rgb >> 8 & 0xFF) / 255.0F, (rgb & 0xFF) / 255.0F);

        this.quadSize = 0.10F + this.random.nextFloat() * 0.07F;
        this.hasPhysics = false;
        this.gravity = 0.0F;
        this.friction = 0.96F;
        this.swayPhase = this.random.nextFloat() * Mth.TWO_PI;
        if (this.calm) {
            this.lifetime = 14 + this.random.nextInt(5);
            this.xd = 0.0;
            this.yd = 0.028;
            this.zd = 0.0;
        } else {
            this.lifetime = 26 + this.random.nextInt(10);
            this.xd = xSpeed * 0.2 + (this.random.nextDouble() - 0.5) * 0.01;
            this.yd = 0.055 + this.random.nextDouble() * 0.035;
            this.zd = zSpeed * 0.2 + (this.random.nextDouble() - 0.5) * 0.01;
        }
    }

    @Override
    public void tick() {
        super.tick();
        this.yd = Math.max(this.calm ? 0.012 : 0.02, this.yd);
        if (!this.calm) {
            this.xd = Mth.sin(this.swayPhase + this.age * 0.24F) * 0.011;
        }
        if (this.age > this.lifetime - 7) {
            this.alpha = Math.max(0.0F, this.alpha - 0.14F);
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
            return new MusicNoteParticle(level, x, y, z, xSpeed, ySpeed, zSpeed, this.sprites);
        }
    }
}
