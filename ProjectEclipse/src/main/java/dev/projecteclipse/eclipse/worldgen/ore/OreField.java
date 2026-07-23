package dev.projecteclipse.eclipse.worldgen.ore;

import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import net.minecraft.world.level.block.state.BlockState;

/**
 * Config-driven, stage-annulus-gated ore blobs. One hashed vein candidate per 16³ cell per ore
 * type (same algorithm as legacy {@code DiscTerrainFunction.oreAt}), with unlock stages and
 * {@link FrozenParams#annulusBand(double)} whitelisting.
 */
public final class OreField {
    private static final int H_ORE = 17;

    private OreField() {}

    /**
     * Returns an ore block at world coordinates when the cell blob intersects {@code y}, or
     * {@code null} when no ore applies. {@code deepslate} selects the deepslate variant when
     * {@code true}, otherwise the stone (or nether) variant.
     */
    public static BlockState oreAt(DiscProfile profile, int x, int y, int z, boolean deepslate) {
        OreConfig.Snapshot snapshot = OreConfig.current();
        for (OreConfig.ResolvedOre ore : snapshot.oresOf(profile)) {
            BlockState state = tryOre(ore, profile, x, y, z, deepslate);
            if (state != null) {
                return state;
            }
        }
        return null;
    }

    private static BlockState tryOre(OreConfig.ResolvedOre ore, DiscProfile profile, int x, int y, int z,
            boolean deepslate) {
        if (y < ore.minY() || y > ore.maxY()) {
            return null;
        }

        int cx = x >> 4;
        int cz = z >> 4;
        int cy = Math.floorDiv(y, 16);
        double cellR = Math.hypot(cx * 16 + 8, cz * 16 + 8);
        int band = FrozenParams.annulusBand(cellR);
        if (band < ore.unlockStage()) {
            return null;
        }

        long h = hash3(H_ORE + ore.salt(), cx, cy, cz);
        double p = ore.cellP() * ore.bandFactor()[Math.min(band, ore.bandFactor().length - 1)];
        if (ore.centerBias()) {
            p *= Math.max(0.15D, 1.0D - cellR / profile.lensNormRadius());
        }
        if (to01(h) >= p) {
            return null;
        }

        int vx = (cx << 4) + 4 + (int) ((h >>> 12) & 7);
        int vy = cy * 16 + 4 + (int) ((h >>> 16) & 7);
        int vz = (cz << 4) + 4 + (int) ((h >>> 20) & 7);
        if (vy < ore.minY() || vy > ore.maxY()) {
            return null;
        }

        double radius = ore.radius() * (0.65D + 0.35D * ((h >>> 24 & 255) / 255.0D));
        double dx = x - vx;
        double dy = y - vy;
        double dz = z - vz;
        if (dx * dx + dy * dy * 1.6D + dz * dz <= radius * radius) {
            return (deepslate ? ore.deepOre() : ore.stoneOre()).defaultBlockState();
        }
        return null;
    }

    private static long mix(long z) {
        z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
        z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
        return z ^ (z >>> 31);
    }

    private static long hash3(int salt, int a, int b, int c) {
        long h = DiscMapData.ECLIPSE_SEED + salt * 0x9E3779B97F4A7C15L;
        h = mix(h ^ (a & 0xFFFFFFFFL));
        h = mix(h ^ (b & 0xFFFFFFFFL));
        return mix(h ^ (c & 0xFFFFFFFFL));
    }

    private static double to01(long hash) {
        return (hash >>> 11) * 0x1.0p-53D;
    }
}
