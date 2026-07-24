package dev.projecteclipse.eclipse.worldgen.ore;

import java.util.Arrays;
import java.util.List;

import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import net.minecraft.world.level.block.state.BlockState;

/**
 * Config-driven, stage-annulus-gated ore VEINS (B2, PLAN-B plans_v5). Veins are derived
 * per 16³ cell per ore by {@link OreVeinShape} — the deterministic port of vanilla
 * {@code OreFeature.doPlace}'s segment + sine-ellipsoid chain — with unlock stages and
 * {@link FrozenParams#annulusBand(DiscProfile, double)} whitelisting unchanged from the
 * legacy blob field. {@link VeinTracker} re-derives the exact same chains through the
 * same helper, so mining feel / anti-xray stay in lockstep by construction.
 *
 * <p>Membership stays a pure per-block function of (mapSeed, ore table, cell): the
 * derived chain of a cell is reused for all ~4096 block lookups through a per-thread
 * direct-mapped cache (the {@code DiscBiomeSource.ColumnCache} pattern), keyed on the
 * live config snapshot + frozen seed so hot reloads and refreezes drop stale chains.</p>
 */
public final class OreField {

    /** Direct-mapped per-thread cell cache size (power of two). A chunk touches ~24 cells/ore. */
    private static final int CACHE_SIZE = 1024;

    private static final ThreadLocal<CellCache> CACHE = ThreadLocal.withInitial(CellCache::new);

    private OreField() {}

    /**
     * Returns an ore block at world coordinates when a derived vein chain of the cell
     * contains {@code (x, y, z)}, or {@code null} when no ore applies. {@code deepslate}
     * selects the deepslate variant when {@code true}, otherwise the stone (or nether)
     * variant.
     */
    public static BlockState oreAt(DiscProfile profile, int x, int y, int z, boolean deepslate) {
        OreConfig.Snapshot snapshot = OreConfig.current();
        List<OreConfig.ResolvedOre> ores = snapshot.oresOf(profile);
        if (ores.isEmpty()) {
            return null;
        }
        long seed = FrozenParams.mapSeed();
        CellCache cache = CACHE.get();
        if (cache.snapshot != snapshot || cache.seed != seed) {
            // Config hot reload / refreeze / save swap — drop every cached chain.
            Arrays.fill(cache.keys, Long.MIN_VALUE);
            Arrays.fill(cache.values, null);
            cache.snapshot = snapshot;
            cache.seed = seed;
        }
        int cellX = x >> 4;
        int cellZ = z >> 4;
        int cellY = Math.floorDiv(y, 16);
        for (OreConfig.ResolvedOre ore : ores) {
            if (y < ore.minY() || y > ore.maxY()) {
                continue;
            }
            OreVeinShape[] veins = cellVeins(cache, seed, ore, profile, cellX, cellY, cellZ);
            for (OreVeinShape vein : veins) {
                if (vein.contains(x, y, z)) {
                    return (deepslate ? ore.deepOre() : ore.stoneOre()).defaultBlockState();
                }
            }
        }
        return null;
    }

    private static OreVeinShape[] cellVeins(CellCache cache, long seed, OreConfig.ResolvedOre ore,
            DiscProfile profile, int cellX, int cellY, int cellZ) {
        long key = packKey(profile, ore.salt(), cellX, cellY, cellZ);
        int slot = (int) (OreVeinShape.mix(key) & (CACHE_SIZE - 1));
        if (cache.keys[slot] == key) {
            return cache.values[slot];
        }
        double scale = OreVeinShape.gateScale(ore, profile, cellX, cellZ);
        OreVeinShape[] veins = scale < 0.0D
                ? OreVeinShape.NO_VEINS
                : OreVeinShape.veinsOf(seed, ore, cellX, cellY, cellZ, scale);
        cache.keys[slot] = key;
        cache.values[slot] = veins;
        return veins;
    }

    /**
     * Collision-free key: 16-bit cell X/Z (disc radius ≪ ±32k cells), 8-bit cell Y,
     * 8-bit ore salt, 1 profile bit (salts restart at 1 per dimension list). Bit 63 is
     * never set, so the {@code Long.MIN_VALUE} empty-slot sentinel stays unreachable.
     */
    private static long packKey(DiscProfile profile, int salt, int cellX, int cellY, int cellZ) {
        return (cellX & 0xFFFFL)
                | ((cellZ & 0xFFFFL) << 16)
                | ((cellY & 0xFFL) << 32)
                | ((salt & 0xFFL) << 40)
                | ((profile == DiscProfile.NETHER ? 1L : 0L) << 48);
    }

    /** Per-thread direct-mapped cache; keyed to the live snapshot + frozen map seed. */
    private static final class CellCache {
        final long[] keys = new long[CACHE_SIZE];
        final OreVeinShape[][] values = new OreVeinShape[CACHE_SIZE][];
        OreConfig.Snapshot snapshot;
        long seed;

        CellCache() {
            Arrays.fill(this.keys, Long.MIN_VALUE);
        }
    }
}
