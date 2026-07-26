package dev.projecteclipse.eclipse.glitchzone;

import java.util.UUID;

import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceKey;
import net.minecraft.world.level.Level;

/**
 * One server-authoritative glitch area (GLITCHZONE): a sphere in {@code dim} around
 * {@code centre} that runs the Veil post pipeline {@code eclipse:glitch_<effect>} on every
 * client inside it until overworld game time {@code endGameTime}. The event is deliberately
 * SILENT — no announcement, no title, no boss bar; players discover the corruption by
 * walking into it. Immutable; {@link GlitchZoneState} persists the set of live zones and
 * {@link GlitchZoneService} ticks them.
 *
 * @param id             stable zone id ({@code /dev glitch remove <id>})
 * @param dim            dimension the sphere lives in
 * @param centre         sphere centre block (the sample point is the block centre)
 * @param radius         sphere radius in blocks ({@code > 0})
 * @param effect         one of {@link GlitchZoneEffects#IDS} ({@code outline}, {@code datamosh}, …)
 * @param colour         accent colour id from {@link GlitchColors} ({@code ""} = the
 *                       effect's shipped accent — F-049)
 * @param startGameTime  OVERWORLD game time the zone was created at; the anchor of the
 *                       {@code fadeInTicks} ramp
 * @param endGameTime    OVERWORLD game time at which the zone dies (one clock for all
 *                       dimensions — the {@link GlitchZoneState} house convention of keying
 *                       global schedules off overworld storage)
 * @param fadeInTicks    server-side fade-IN window after {@code startGameTime} (0 = the
 *                       shipped behaviour: full strength at once, softened only by the
 *                       client's own ease)
 * @param fadeTicks      server-side fade-OUT window before {@code endGameTime} (0 = hard cut)
 * @param originAtCentre {@code true} = the effect's impulse/sonar origin is {@code centre}
 *                       in WORLD space instead of the camera (F-048: the altar pings, not
 *                       the player). Only {@code void} reads it today; the uniform pair is
 *                       fed to every row and ignored by the shaders that do not declare it.
 */
public record GlitchZone(UUID id, ResourceKey<Level> dim, BlockPos centre, double radius,
        String effect, String colour, long startGameTime, long endGameTime,
        int fadeInTicks, int fadeTicks, boolean originAtCentre) {

    /**
     * Spatial strength 0..1 at squared distance {@code distSqr} from {@link #centre}:
     * 1 deep inside, smoothstepped down to 0 across the edge band (inner 25% of the
     * radius, clamped to 2–12 blocks) so entering/leaving is a gradient, never a pop.
     */
    public float spatialStrength(double distSqr) {
        double edgeBand = Math.min(Math.max(this.radius * 0.25D, 2.0D), 12.0D);
        double dist = Math.sqrt(distSqr);
        double linear = (this.radius - dist) / edgeBand;
        if (linear <= 0.0D) {
            return 0.0F;
        }
        if (linear >= 1.0D) {
            return 1.0F;
        }
        return (float) (linear * linear * (3.0D - 2.0D * linear));
    }

    /**
     * Temporal strength 0..1 at overworld game time {@code now}: the smoothstepped
     * {@link #fadeInTicks} ramp after {@link #startGameTime}, ANDed (minimum) with the
     * linear {@link #fadeTicks} ramp before {@link #endGameTime}. 0 at/after the end.
     *
     * <p>The out-ramp stays linear — that is the shipped {@code /dev glitch add} feel and
     * dev zones are cut, not composed. The in-ramp is smoothstepped because the only thing
     * that uses it is the ambient altar event, which must swell rather than switch on.</p>
     */
    public float temporalStrength(long now) {
        long remaining = this.endGameTime - now;
        if (remaining <= 0L) {
            return 0.0F;
        }
        float out = this.fadeTicks <= 0 || remaining >= this.fadeTicks
                ? 1.0F : remaining / (float) this.fadeTicks;

        long elapsed = now - this.startGameTime;
        if (elapsed < 0L) {
            return 0.0F; // scheduled ahead of the clock: not live yet
        }
        if (this.fadeInTicks <= 0 || elapsed >= this.fadeInTicks) {
            return out;
        }
        float linear = elapsed / (float) this.fadeInTicks;
        float in = linear * linear * (3.0F - 2.0F * linear);
        return Math.min(in, out);
    }

    /** Same zone with a different accent colour ({@code /dev glitch color}). */
    public GlitchZone withColour(String newColour) {
        return new GlitchZone(this.id, this.dim, this.centre, this.radius, this.effect,
                newColour, this.startGameTime, this.endGameTime, this.fadeInTicks,
                this.fadeTicks, this.originAtCentre);
    }
}
