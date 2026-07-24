package dev.projecteclipse.eclipse.worldgen;

import javax.annotation.Nullable;

import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.level.levelgen.synth.SimplexNoise;

/**
 * 3-D cave biome regions of the overworld disc (D4.3): low-frequency fixed-seed noise
 * splits the underground into {@code minecraft:dripstone_caves} / {@code
 * minecraft:lush_caves} regions (the rest keeps the surface biome, vanilla-style), and
 * everything below y {@value #DEEP_DARK_MAX_Y} within {@value #DEEP_DARK_RADIUS} blocks
 * of the mountain center is {@code minecraft:deep_dark}. The ceiling includes the
 * authored Ancient City anchor at y −40 (D6/D7). Cave features (pointed dripstone, moss/glow berries,
 * sculk) then arrive from the real biome generation settings via the W1.1 pipeline.
 *
 * <p>All lookups are pure functions of position + frozen map data (no stage, no world
 * seed) — chunks generated before a ring grows must already carry the same biomes the
 * grown terrain will expose. Noise salt 29 of the frozen map-seed family lives
 * here (registry: {@code docs/plans_v3/wiring/P1-W1.2_wiring.md}).</p>
 */
public final class CaveBiomeMap {
    /**
     * A column counts as "underground" below {@code surfaceY − SURFACE_MARGIN} (D4.3:
     * cave biomes start 14 blocks under the surface, like vanilla's depth threshold).
     */
    public static final int SURFACE_MARGIN = 14;
    /** Deep dark below this Y (exclusive), including the Ancient City centered at y −40. */
    public static final int DEEP_DARK_MAX_Y = -32;
    /** …and only within this many blocks of the mountain center (Ancient City tie-in). */
    public static final int DEEP_DARK_RADIUS = 120;

    /** Feature scale (blocks) of the dripstone/lush region field — big, contiguous regions. */
    private static final double REGION_SCALE = 176.0D;
    /** |noise| above this splits a region off the neutral band (~⅓ of area total). */
    private static final double REGION_THRESHOLD = 0.34D;

    /** Lifecycle-keyed region field (salt 29 of the frozen map-seed family). */
    private static volatile SeededNoise regionNoise;

    private record SeededNoise(long seed, SimplexNoise noise) {}

    private static final ResourceLocation DRIPSTONE_CAVES =
            ResourceLocation.withDefaultNamespace("dripstone_caves");
    private static final ResourceLocation LUSH_CAVES =
            ResourceLocation.withDefaultNamespace("lush_caves");
    private static final ResourceLocation DEEP_DARK =
            ResourceLocation.withDefaultNamespace("deep_dark");

    private static final String DRIPSTONE_CAVES_ID = "minecraft:dripstone_caves";
    private static final String LUSH_CAVES_ID = "minecraft:lush_caves";
    /** Biome id of the deep-dark region ({@code DiscBiomeSource} holder key). */
    public static final String DEEP_DARK_ID = "minecraft:deep_dark";

    private CaveBiomeMap() {}

    /**
     * Cave biome at the block position, or {@code null} when the position is not
     * underground or lies in the neutral band (surface biome continues downward).
     * Self-contained §3.10 seam: gates on the pure terrain-function surface itself.
     * Overworld only — the nether disc keeps its full-height wedges.
     */
    @Nullable
    public static ResourceLocation at(int x, int y, int z) {
        if (y >= DiscTerrainFunction.surfaceY(DiscProfile.OVERWORLD, x, z) - SURFACE_MARGIN) {
            return null;
        }
        if (y < DEEP_DARK_MAX_Y && deepDarkColumn(
                DiscMapData.get().profile(DiscProfile.OVERWORLD).mountain(), x, z)) {
            return DEEP_DARK;
        }
        String region = regionAt(x, z);
        if (DRIPSTONE_CAVES_ID.equals(region)) {
            return DRIPSTONE_CAVES;
        }
        return LUSH_CAVES_ID.equals(region) ? LUSH_CAVES : null;
    }

    /**
     * Region id of the column — {@code minecraft:dripstone_caves},
     * {@code minecraft:lush_caves} or {@code null} (neutral band). 2-D on purpose so
     * {@code DiscBiomeSource} can fold it into its per-column cache; the y gates
     * ({@link #SURFACE_MARGIN}, {@link #DEEP_DARK_MAX_Y}) are applied per sample there.
     */
    @Nullable
    public static String regionAt(int x, int z) {
        double v = regionNoise().getValue(x / REGION_SCALE, z / REGION_SCALE);
        if (v > REGION_THRESHOLD) {
            return DRIPSTONE_CAVES_ID;
        }
        return v < -REGION_THRESHOLD ? LUSH_CAVES_ID : null;
    }

    private static SimplexNoise regionNoise() {
        long seed = FrozenParams.mapSeed();
        SeededNoise cached = regionNoise;
        if (cached == null || cached.seed() != seed) {
            synchronized (CaveBiomeMap.class) {
                cached = regionNoise;
                if (cached == null || cached.seed() != seed) {
                    cached = new SeededNoise(seed, DiscTerrainFunction.noise(29));
                    regionNoise = cached;
                }
            }
        }
        return cached.noise();
    }

    /**
     * Whether the column lies inside the deep-dark footprint (within
     * {@value #DEEP_DARK_RADIUS} blocks of the mountain center). Null-safe for maps
     * authored without a mountain. The y half of the predicate
     * ({@code y < }{@value #DEEP_DARK_MAX_Y}) is the caller's.
     */
    public static boolean deepDarkColumn(@Nullable DiscMapData.Mountain mountain, int x, int z) {
        if (mountain == null) {
            return false;
        }
        double dx = x - mountain.x();
        double dz = z - mountain.z();
        return dx * dx + dz * dz < (double) DEEP_DARK_RADIUS * DEEP_DARK_RADIUS;
    }
}
