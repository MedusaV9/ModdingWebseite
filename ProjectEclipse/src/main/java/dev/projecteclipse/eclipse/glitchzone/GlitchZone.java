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
 * @param id          stable zone id ({@code /dev glitch remove <id>})
 * @param dim         dimension the sphere lives in
 * @param centre      sphere centre block (the sample point is the block centre)
 * @param radius      sphere radius in blocks ({@code > 0})
 * @param effect      one of {@link GlitchZoneEffects#IDS} ({@code outline}, {@code datamosh}, …)
 * @param endGameTime OVERWORLD game time at which the zone dies (one clock for all
 *                    dimensions — the {@link GlitchZoneState} house convention of keying
 *                    global schedules off overworld storage)
 * @param fadeTicks   server-side fade-OUT window before {@code endGameTime} (0 = hard cut;
 *                    fade-IN is free — the client eases every synced strength change)
 */
public record GlitchZone(UUID id, ResourceKey<Level> dim, BlockPos centre, double radius,
        String effect, long endGameTime, int fadeTicks) {

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
     * Temporal strength 0..1 at overworld game time {@code now}: 1 while running, ramping
     * linearly to 0 across the last {@link #fadeTicks} ticks, 0 at/after {@link #endGameTime}.
     */
    public float temporalStrength(long now) {
        long remaining = this.endGameTime - now;
        if (remaining <= 0L) {
            return 0.0F;
        }
        if (this.fadeTicks <= 0 || remaining >= this.fadeTicks) {
            return 1.0F;
        }
        return remaining / (float) this.fadeTicks;
    }
}
