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
 * Feier-Konfetti: kleiner Pop nach oben, dann taumelnder Fall mit
 * Seitwaerts-Flattern und Eigenrotation. Vier Sprite-Varianten (Schnipsel,
 * Streamer, Funkel-Stern, Dreieck) werden pro Partikel zufaellig gewaehlt
 * und aus einer Feier-Palette getintet — die Sprites selbst sind fast weiss.
 *
 * <p>reducedMotion (rein clientseitig): der Provider verwirft im Mittel die
 * Haelfte der Schnipsel, die verbleibenden fallen mit deutlich verkuerzter
 * Lebensdauer ruhig und ohne Pop/Spin/Flattern — zusammen bleibt also rund
 * ein Viertel der Partikel-Ticks eines normalen Bursts.</p>
 */
public class ConfettiParticle extends TextureSheetParticle {
    /** Feier-Palette — bewusst kraeftig, aber warm (kein grelles Neon). */
    private static final int[] COLORS = {
            0xE84D6F, 0xF6C13A, 0x58C05A, 0x5A8DEE, 0xB572AE, 0xF08A3C, 0x63D6D2, 0xF7AAC4};

    private final boolean calm;
    private final float flutterPhase;
    private final float flutterStrength;
    private final float spinSpeed;

    protected ConfettiParticle(ClientLevel level, double x, double y, double z,
            double xSpeed, double ySpeed, double zSpeed, SpriteSet sprites) {
        super(level, x, y, z);
        pickSprite(sprites);
        this.calm = GoobyClientConfig.reducedMotion();

        int color = COLORS[this.random.nextInt(COLORS.length)];
        float shade = 0.88F + this.random.nextFloat() * 0.12F;
        setColor((color >> 16 & 0xFF) / 255.0F * shade,
                (color >> 8 & 0xFF) / 255.0F * shade,
                (color & 0xFF) / 255.0F * shade);

        this.quadSize = 0.085F + this.random.nextFloat() * 0.05F;
        this.hasPhysics = true;
        this.friction = 0.96F;
        this.flutterPhase = this.random.nextFloat() * Mth.TWO_PI;
        if (this.calm) {
            // Ruhig: kurzer, gerader Fall ohne Pop, Spin oder Flattern.
            this.lifetime = 14 + this.random.nextInt(6);
            this.gravity = 0.10F;
            this.flutterStrength = 0.0F;
            this.spinSpeed = 0.0F;
            this.xd = xSpeed * 0.25;
            this.yd = Math.max(0.0, ySpeed) * 0.25;
            this.zd = zSpeed * 0.25;
        } else {
            this.lifetime = 38 + this.random.nextInt(20);
            this.gravity = 0.20F;
            this.flutterStrength = 0.008F + this.random.nextFloat() * 0.010F;
            this.spinSpeed = (this.random.nextBoolean() ? 1.0F : -1.0F)
                    * (0.18F + this.random.nextFloat() * 0.28F);
            this.roll = this.random.nextFloat() * Mth.TWO_PI;
            this.oRoll = this.roll;
            this.xd = xSpeed + (this.random.nextDouble() - 0.5) * 0.06;
            this.yd = ySpeed + 0.14 + this.random.nextDouble() * 0.10;
            this.zd = zSpeed + (this.random.nextDouble() - 0.5) * 0.06;
        }
    }

    @Override
    public void tick() {
        super.tick();
        if (!this.calm && !this.onGround) {
            float sway = this.flutterPhase + this.age * 0.32F;
            this.xd += Mth.sin(sway) * this.flutterStrength;
            this.zd += Mth.cos(sway * 0.8F) * this.flutterStrength;
            this.oRoll = this.roll;
            this.roll += this.spinSpeed;
        }
        int fadeWindow = this.calm ? 5 : 9;
        if (this.age > this.lifetime - fadeWindow) {
            this.alpha = Math.max(0.0F, this.alpha - 1.0F / fadeWindow);
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
            // reducedMotion verwirft im Mittel jeden zweiten Schnipsel; mit
            // der verkuerzten calm-Lebensdauer bleibt ~1/4 der Partikel-Ticks.
            // Rein clientseitig — der Server kennt die lokale
            // Barrierefreiheits-Option bewusst nicht.
            if (GoobyClientConfig.reducedMotion() && level.random.nextBoolean()) {
                return null;
            }
            return new ConfettiParticle(level, x, y, z, xSpeed, ySpeed, zSpeed, this.sprites);
        }
    }
}
