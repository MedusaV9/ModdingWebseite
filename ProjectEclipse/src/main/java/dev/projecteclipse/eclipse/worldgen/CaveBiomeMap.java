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
 * <p>Plans_v5 B12 adds two rarer DETAIL regions on a second noise channel: sculk-pocket
 * satellites of the deep dark (fold into the {@code minecraft:deep_dark} biome away from
 * the mountain, so sculk decoration fires there too) and a crystal region (folds into
 * {@code minecraft:lush_caves} biome-wise; {@code CaveDressings} keys its amethyst
 * sparkle nooks off {@link #detailRegionAt} directly).</p>
 *
 * <p>WG2 y-bands the underground into four custom biomes on top of the existing 2-D
 * fields (all pure position functions, no new noise): the deep half of a lush region
 * (below y {@value #FUNGAL_MAX_Y}) is {@code eclipse:fungal_hollows}, the deep half of
 * a dripstone region (below y {@value #EMBER_MAX_Y}) is {@code eclipse:ember_depths},
 * the B12 crystal detail region now reads its own {@code eclipse:crystal_chasms} id
 * (it used to fold into lush_caves biome-wise; {@code CaveDressings} keys its amethyst
 * nooks off {@link #detailRegionAt} directly and is unaffected), and the neutral band
 * below y {@value #UMBRAL_MAX_Y} — previously surface-biome all the way down — is
 * {@code eclipse:umbral_depths}. Deep dark still outranks everything under the
 * mountain.</p>
 *
 * <p>WG3 (F-059, 10 → 20 biomes) widens both existing fields — NO new noise salts, so
 * every pre-WG3 assignment keeps its value and only previously-neutral/edge samples
 * change (newly generated chunks only, exactly like the WG2 rollout):</p>
 *
 * <ul>
 *   <li><b>Region hearts</b>: the strongest cores of the base field become their own
 *       biomes — {@code v > }{@value #HEART_THRESHOLD} (heart of a dripstone region) →
 *       {@code eclipse:molten_veins}, {@code v < -}{@value #HEART_THRESHOLD} (heart of
 *       a lush region) → {@code eclipse:glowshroom_grotto}, both full-column.</li>
 *   <li><b>Detail shoulders</b>: the bands just inside the B12 thresholds —
 *       {@code ECHO_THRESHOLD < w <= SCULK_POCKET_THRESHOLD} →
 *       {@code eclipse:echoing_hollow} (satellites of the sculk pockets) and
 *       {@code CRYSTAL_THRESHOLD <= w < FROST_THRESHOLD} →
 *       {@code eclipse:frost_crystal_cavern} (satellites of the crystal region).
 *       {@link #detailRegionAt} (the {@code CaveDressings} decor key) is UNCHANGED.</li>
 *   <li><b>New y-bands</b>: the lush middle band ({@value #TANGLED_MAX_Y} &gt; y ≥
 *       {@value #FUNGAL_MAX_Y}) is {@code eclipse:tangled_roots}, and the deep half of
 *       a sculk-pocket fold (y &lt; {@value #SCULK_DEPTHS_MAX_Y}) is
 *       {@code eclipse:sculk_depths} (the mountain deep dark itself — the
 *       {@code deepDarkColumn} path — stays untouched for the Ancient City).</li>
 * </ul>
 *
 * <p>All lookups are pure functions of position + frozen map data (no stage, no world
 * seed) — chunks generated before a ring grows must already carry the same biomes the
 * grown terrain will expose. Noise salts 29 (region field) and 33 (B12 detail field) of
 * the frozen map-seed family live here (registry: {@code
 * docs/plans_v3/wiring/P1-W1.2_wiring.md}).</p>
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

    // --- WG2 y-bands (all exclusive "below": y < band) ---

    /** Lush-region samples below this Y read {@code eclipse:fungal_hollows}. */
    public static final int FUNGAL_MAX_Y = -64;
    /** Dripstone-region samples below this Y read {@code eclipse:ember_depths}. */
    public static final int EMBER_MAX_Y = -80;
    /** Neutral-band samples below this Y read {@code eclipse:umbral_depths}. */
    public static final int UMBRAL_MAX_Y = -96;
    /**
     * WG3: lush-region samples below this Y (and at/above {@link #FUNGAL_MAX_Y}) read
     * {@code eclipse:tangled_roots} — the root-riddled middle band between the shallow
     * lush caves and the fungal basement.
     */
    public static final int TANGLED_MAX_Y = -40;
    /** WG3: sculk-pocket samples below this Y read {@code eclipse:sculk_depths}. */
    public static final int SCULK_DEPTHS_MAX_Y = -64;

    /** Feature scale (blocks) of the dripstone/lush region field — big, contiguous regions. */
    private static final double REGION_SCALE = 176.0D;
    /** |noise| above this splits a region off the neutral band (~⅓ of area total). */
    private static final double REGION_THRESHOLD = 0.34D;
    /**
     * WG3: |region noise| above this marks the HEART of a region — the hottest core of
     * a dripstone region reads {@code eclipse:molten_veins}, the deepest-green core of
     * a lush region reads {@code eclipse:glowshroom_grotto}. Strictly inside the
     * {@link #REGION_THRESHOLD} area, so pre-WG3 neutral columns are never affected.
     */
    public static final double HEART_THRESHOLD = 0.62D;

    /** Feature scale of the B12 detail field — smaller pockets than the main regions. */
    private static final double DETAIL_SCALE = 132.0D;
    /** Detail noise above this → sculk-pocket satellite (rare). */
    private static final double SCULK_POCKET_THRESHOLD = 0.72D;
    /** Detail noise below this → crystal region (rare). */
    private static final double CRYSTAL_THRESHOLD = -0.70D;
    /**
     * WG3: detail noise in {@code (ECHO_THRESHOLD, SCULK_POCKET_THRESHOLD]} → the
     * {@code eclipse:echoing_hollow} shoulder ringing every sculk pocket.
     */
    public static final double ECHO_THRESHOLD = 0.58D;
    /**
     * WG3: detail noise in {@code [CRYSTAL_THRESHOLD, FROST_THRESHOLD)} → the
     * {@code eclipse:frost_crystal_cavern} shoulder ringing the crystal region.
     */
    public static final double FROST_THRESHOLD = -0.58D;

    /** The rarer B12 detail regions layered over the dripstone/lush field. */
    public enum DetailRegion {
        /** Deep-dark satellite: sculk pocket away from the mountain root. */
        SCULK_POCKET,
        /** Amethyst-heavy sparkle nook region ({@code CaveDressings} decor key). */
        CRYSTAL
    }

    /** Lifecycle-keyed region field (salt 29 of the frozen map-seed family). */
    private static volatile SeededNoise regionNoise;
    /** Lifecycle-keyed B12 detail field (salt 33 of the frozen map-seed family). */
    private static volatile SeededNoise detailNoise;

    private record SeededNoise(long seed, SimplexNoise noise) {}

    private static final ResourceLocation DEEP_DARK =
            ResourceLocation.withDefaultNamespace("deep_dark");

    private static final String DRIPSTONE_CAVES_ID = "minecraft:dripstone_caves";
    private static final String LUSH_CAVES_ID = "minecraft:lush_caves";
    /** Biome id of the deep-dark region ({@code DiscBiomeSource} holder key). */
    public static final String DEEP_DARK_ID = "minecraft:deep_dark";
    /** WG2 deep-lush band biome id ({@code DiscBiomeSource} holder key). */
    public static final String FUNGAL_HOLLOWS_ID = "eclipse:fungal_hollows";
    /** WG2 crystal detail-region biome id ({@code DiscBiomeSource} holder key). */
    public static final String CRYSTAL_CHASMS_ID = "eclipse:crystal_chasms";
    /** WG2 deep-dripstone band biome id ({@code DiscBiomeSource} holder key). */
    public static final String EMBER_DEPTHS_ID = "eclipse:ember_depths";
    /** WG2 neutral-band basement biome id ({@code DiscBiomeSource} holder key). */
    public static final String UMBRAL_DEPTHS_ID = "eclipse:umbral_depths";
    /** WG3 lush-heart biome id ({@code DiscBiomeSource} holder key). */
    public static final String GLOWSHROOM_GROTTO_ID = "eclipse:glowshroom_grotto";
    /** WG3 dripstone-heart biome id ({@code DiscBiomeSource} holder key). */
    public static final String MOLTEN_VEINS_ID = "eclipse:molten_veins";
    /** WG3 lush middle-band biome id ({@code DiscBiomeSource} holder key). */
    public static final String TANGLED_ROOTS_ID = "eclipse:tangled_roots";
    /** WG3 crystal-shoulder biome id ({@code DiscBiomeSource} holder key). */
    public static final String FROST_CRYSTAL_CAVERN_ID = "eclipse:frost_crystal_cavern";
    /** WG3 sculk-shoulder biome id ({@code DiscBiomeSource} holder key). */
    public static final String ECHOING_HOLLOW_ID = "eclipse:echoing_hollow";
    /** WG3 deep sculk-pocket band biome id ({@code DiscBiomeSource} holder key). */
    public static final String SCULK_DEPTHS_ID = "eclipse:sculk_depths";

    private CaveBiomeMap() {}

    /**
     * Cave biome at the block position, or {@code null} when the position is not
     * underground or lies in the (above-{@value #UMBRAL_MAX_Y}) neutral band, where the
     * surface biome continues downward. Self-contained §3.10 seam: gates on the pure
     * terrain-function surface itself. Overworld only — the nether disc keeps its
     * full-height wedges. Applies the WG2/WG3 y-bands, so this stays the single-call
     * equivalent of {@code DiscBiomeSource}'s per-column region + band resolution.
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
        if (region != null) {
            return ResourceLocation.parse(bandedBiome(region, y));
        }
        return y < UMBRAL_MAX_Y ? ResourceLocation.parse(UMBRAL_DEPTHS_ID) : null;
    }

    /**
     * Region id of the column — {@code minecraft:dripstone_caves},
     * {@code minecraft:lush_caves}, {@code minecraft:deep_dark} (a B12 sculk-pocket
     * satellite), {@code eclipse:crystal_chasms} (the B12 crystal region, its own biome
     * since WG2), the WG3 additions ({@code eclipse:echoing_hollow} /
     * {@code eclipse:frost_crystal_cavern} detail shoulders,
     * {@code eclipse:molten_veins} / {@code eclipse:glowshroom_grotto} region hearts)
     * or {@code null} (neutral band). 2-D on purpose so {@code DiscBiomeSource} can
     * fold it into its per-column cache; the y gates ({@link #SURFACE_MARGIN},
     * {@link #DEEP_DARK_MAX_Y}, the WG2/WG3 bands via {@link #bandedBiome}) are applied
     * per sample there. The B12 detail field outranks the base field (its thresholds
     * are far rarer); all outputs fold into biome ids the biome source resolves.
     * Threshold order matches {@link #detailRegionAt} exactly on the shared thresholds,
     * so the {@code CaveDressings} decor keys stay in sync.
     */
    @Nullable
    public static String regionAt(int x, int z) {
        double w = detailNoise().getValue(x / DETAIL_SCALE, z / DETAIL_SCALE);
        if (w > SCULK_POCKET_THRESHOLD) {
            return DEEP_DARK_ID;
        }
        if (w > ECHO_THRESHOLD) {
            return ECHOING_HOLLOW_ID;
        }
        if (w < CRYSTAL_THRESHOLD) {
            return CRYSTAL_CHASMS_ID;
        }
        if (w < FROST_THRESHOLD) {
            return FROST_CRYSTAL_CAVERN_ID;
        }
        double v = regionNoise().getValue(x / REGION_SCALE, z / REGION_SCALE);
        if (v > HEART_THRESHOLD) {
            return MOLTEN_VEINS_ID;
        }
        if (v > REGION_THRESHOLD) {
            return DRIPSTONE_CAVES_ID;
        }
        if (v < -HEART_THRESHOLD) {
            return GLOWSHROOM_GROTTO_ID;
        }
        return v < -REGION_THRESHOLD ? LUSH_CAVES_ID : null;
    }

    /**
     * WG2/WG3 y-banding of a {@link #regionAt} region id: a lush region splits into
     * shallow lush caves / {@code eclipse:tangled_roots} (y &lt;
     * {@value #TANGLED_MAX_Y}) / {@code eclipse:fungal_hollows} (y &lt;
     * {@value #FUNGAL_MAX_Y}); the deep half of a dripstone region (y &lt;
     * {@value #EMBER_MAX_Y}) reads {@code eclipse:ember_depths}; the deep half of a
     * sculk-pocket fold (y &lt; {@value #SCULK_DEPTHS_MAX_Y}) reads
     * {@code eclipse:sculk_depths}. Every other (region, y) pair — crystal chasms, the
     * WG3 detail shoulders and region hearts, and the shallow region halves — passes
     * through unchanged. Pure, worker-thread safe, cheap enough for the per-sample hot
     * path.
     */
    public static String bandedBiome(String region, int y) {
        if (LUSH_CAVES_ID.equals(region)) {
            if (y < FUNGAL_MAX_Y) {
                return FUNGAL_HOLLOWS_ID;
            }
            return y < TANGLED_MAX_Y ? TANGLED_ROOTS_ID : region;
        }
        if (y < EMBER_MAX_Y && DRIPSTONE_CAVES_ID.equals(region)) {
            return EMBER_DEPTHS_ID;
        }
        if (y < SCULK_DEPTHS_MAX_Y && DEEP_DARK_ID.equals(region)) {
            return SCULK_DEPTHS_ID;
        }
        return region;
    }

    /**
     * B12 detail region of the column ({@link DetailRegion#SCULK_POCKET} /
     * {@link DetailRegion#CRYSTAL}), or {@code null} almost everywhere. 2-D like
     * {@link #regionAt}; {@code CaveDressings} keys its amethyst nooks and extra sculk
     * skin off this directly (the biome fold-in above handles vanilla decoration).
     */
    @Nullable
    public static DetailRegion detailRegionAt(int x, int z) {
        double w = detailNoise().getValue(x / DETAIL_SCALE, z / DETAIL_SCALE);
        if (w > SCULK_POCKET_THRESHOLD) {
            return DetailRegion.SCULK_POCKET;
        }
        return w < CRYSTAL_THRESHOLD ? DetailRegion.CRYSTAL : null;
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

    private static SimplexNoise detailNoise() {
        long seed = FrozenParams.mapSeed();
        SeededNoise cached = detailNoise;
        if (cached == null || cached.seed() != seed) {
            synchronized (CaveBiomeMap.class) {
                cached = detailNoise;
                if (cached == null || cached.seed() != seed) {
                    cached = new SeededNoise(seed, DiscTerrainFunction.noise(33));
                    detailNoise = cached;
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
