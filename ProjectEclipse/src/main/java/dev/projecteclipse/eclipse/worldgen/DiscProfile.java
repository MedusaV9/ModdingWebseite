package dev.projecteclipse.eclipse.worldgen;

import com.mojang.serialization.Codec;
import com.mojang.serialization.DataResult;

/**
 * Parameter set of one disc dimension. Two fixed profiles exist: {@link #OVERWORLD}
 * (grass/stone lens, surface y 65–90, mountain to y≈280, underside ~y −130) and
 * {@link #NETHER} (netherrack/blackstone lens, disc between y 32 and ~160, lava moat).
 *
 * <p>The lens thickness formula normalises against {@link #lensNormRadius} (the FINAL
 * stage radius), not the current stage radius, so the underside of a column never changes
 * when the world stage grows — only the rim taper zone is stage-dependent. This is what
 * keeps {@link DiscTerrainFunction} reproducible across stages for worker 4.</p>
 */
public final class DiscProfile {
    /** Overworld disc: build range −176…336, spawn disc surface ~y 70, mountain peak y≈280. */
    public static final DiscProfile OVERWORLD = new DiscProfile(
            "overworld", -176, 512, 63, 71.0D, -130.0D, -80.0D, 480.0D);

    /** Nether disc: vanilla build range 0…256, disc y 32–~150, thinner rim, lava moat ring. */
    public static final DiscProfile NETHER = new DiscProfile(
            "nether", 0, 256, 32, 138.0D, 32.0D, 56.0D, 160.0D);

    /** Serialised as a plain string ({@code "overworld"} / {@code "nether"}) in dimension JSONs. */
    public static final Codec<DiscProfile> CODEC = Codec.STRING.comapFlatMap(
            DiscProfile::byName, DiscProfile::name);

    private final String name;
    private final int minY;
    private final int height;
    private final int seaLevel;
    private final double surfaceBaseY;
    private final double centerBottomY;
    private final double rimBottomY;
    private final double lensNormRadius;

    private DiscProfile(String name, int minY, int height, int seaLevel, double surfaceBaseY,
            double centerBottomY, double rimBottomY, double lensNormRadius) {
        this.name = name;
        this.minY = minY;
        this.height = height;
        this.seaLevel = seaLevel;
        this.surfaceBaseY = surfaceBaseY;
        this.centerBottomY = centerBottomY;
        this.rimBottomY = rimBottomY;
        this.lensNormRadius = lensNormRadius;
    }

    public static DataResult<DiscProfile> byName(String name) {
        return switch (name) {
            case "overworld" -> DataResult.success(OVERWORLD);
            case "nether" -> DataResult.success(NETHER);
            default -> DataResult.error(() -> "Unknown eclipse disc profile: " + name);
        };
    }

    public String name() {
        return this.name;
    }

    /** Lowest world Y of the dimension (matches its dimension_type {@code min_y}). */
    public int minY() {
        return this.minY;
    }

    /** Total world height of the dimension (matches its dimension_type {@code height}). */
    public int height() {
        return this.height;
    }

    public int seaLevel() {
        return this.seaLevel;
    }

    /** Baseline surface Y before sector amplitude, mountain bump and detail noise. */
    public double surfaceBaseY() {
        return this.surfaceBaseY;
    }

    /** Lens bottom at the disc center (r = 0). */
    public double centerBottomY() {
        return this.centerBottomY;
    }

    /** Lens bottom at the FINAL rim (r = {@link #lensNormRadius}). */
    public double rimBottomY() {
        return this.rimBottomY;
    }

    /**
     * Fixed normalisation radius of the lens profile (the final stage radius). The
     * underside formula {@code bottomY(r) = centerBottom + (rimBottom − centerBottom) ·
     * (r / lensNormRadius)²} must never depend on the current stage.
     */
    public double lensNormRadius() {
        return this.lensNormRadius;
    }

    /** Lens bottom Y (excluding the stalactite fringe) at distance {@code r} from the origin. */
    public double lensBottomY(double r) {
        double t = Math.min(1.0D, r / this.lensNormRadius);
        return this.centerBottomY + (this.rimBottomY - this.centerBottomY) * t * t;
    }

    @Override
    public String toString() {
        return "DiscProfile[" + this.name + "]";
    }
}
