package dev.projecteclipse.eclipse.worldgen.ore;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockState;

/**
 * Stateless vein derivation for mining feel (W4-FEEL, IDEA-03 #2). Re-derives the ONE
 * deterministic vein candidate of a mined ore block's 16³ cell — center, radius and blob
 * membership — with the exact {@link OreField#tryOre} math, then counts how many blob
 * blocks are still present in the (already-loaded) chunk. That makes "first break of an
 * intact vein" and "this break clears the vein" exact, cheap and cheat-proof: no chunk
 * scans, no persistence, at most ~245 in-cell block reads per ORE break.
 *
 * <p>Blob containment invariant: {@code tryOre} places the vein center at
 * {@code cell*16 + 4 + [0..7]} with radius ≤ {@code ore.radius()} (≤ 3.2 in the shipped
 * {@code ores.json}), so the whole ellipsoid ({@code dy² × 1.6}) always lives inside the
 * block's own 16³ cell — one cell derivation covers the entire vein.</p>
 *
 * <p><b>Hash-parity warning:</b> {@link #hash3}/{@link #mix}/{@link #to01}/{@link #H_ORE}
 * MUST stay bit-identical to {@code OreField}'s private copies. The wiring doc asks the
 * OreField owner to expose a package-private {@code veinAt(...)} so this duplication can
 * collapse; until then, treat the two files as one frozen algorithm.</p>
 */
public final class VeinTracker {
    /** Mirror of {@code OreField.H_ORE} — the ore channel salt of the shared hash. */
    private static final int H_ORE = 17;
    /** Vertical ellipsoid squash from {@code OreField.tryOre}'s membership test. */
    private static final double Y_SQUASH = 1.6D;

    private VeinTracker() {}

    /**
     * One derived-vein snapshot at break time. {@code total} counts every blob position
     * inside the ore's Y-range (the vein's generated size, assuming no cave carving);
     * {@code present} counts positions still holding the ore block — INCLUDING the block
     * currently being broken ({@code BlockEvent.BreakEvent} fires pre-removal), so
     * {@code present == total} ⇒ first break of an intact vein and {@code present == 1}
     * ⇒ this break clears it.
     */
    public record Scan(OreConfig.ResolvedOre ore, int total, int present) {}

    /** Disc profile of a level, or {@code null} when the dimension has no ore field. */
    @Nullable
    public static DiscProfile profileOf(ServerLevel level) {
        if (level.dimension() == Level.OVERWORLD) {
            return DiscProfile.OVERWORLD;
        }
        if (level.dimension() == Level.NETHER) {
            return DiscProfile.NETHER;
        }
        return null;
    }

    /** The configured ore whose stone/deepslate block matches {@code state}, or null. */
    @Nullable
    public static OreConfig.ResolvedOre oreFor(DiscProfile profile, BlockState state) {
        Block block = state.getBlock();
        for (OreConfig.ResolvedOre ore : OreConfig.current().oresOf(profile)) {
            if (block == ore.stoneOre() || block == ore.deepOre()) {
                return ore;
            }
        }
        return null;
    }

    /**
     * Derives the vein containing {@code pos} and counts its remaining blocks. Returns
     * {@code null} when the block is not part of a derivable vein (hash gates fail, blob
     * misses, Y outside the ore range — e.g. structure loot ore) — callers just skip the
     * vein feel then. Server thread only; reads blocks of one already-loaded cell.
     */
    @Nullable
    public static Scan scan(ServerLevel level, BlockPos pos, DiscProfile profile,
            OreConfig.ResolvedOre ore) {
        int x = pos.getX();
        int y = pos.getY();
        int z = pos.getZ();
        if (y < ore.minY() || y > ore.maxY()) {
            return null;
        }

        // --- exact OreField.tryOre derivation (keep in lockstep) ---
        int cx = x >> 4;
        int cz = z >> 4;
        int cy = Math.floorDiv(y, 16);
        double cellR = Math.hypot(cx * 16 + 8, cz * 16 + 8);
        int band = FrozenParams.annulusBand(profile, cellR);
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
        double radiusSq = radius * radius;

        double dx = x - vx;
        double dy = y - vy;
        double dz = z - vz;
        if (dx * dx + dy * dy * Y_SQUASH + dz * dz > radiusSq) {
            return null; // the broken block is not a member of this cell's vein
        }

        // --- blob census: total candidates vs ore blocks still in the world ---
        int reachXz = (int) Math.floor(radius);
        int reachY = (int) Math.floor(radius / Math.sqrt(Y_SQUASH));
        int total = 0;
        int present = 0;
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        for (int oy = -reachY; oy <= reachY; oy++) {
            int wy = vy + oy;
            if (wy < ore.minY() || wy > ore.maxY()) {
                continue;
            }
            for (int ox = -reachXz; ox <= reachXz; ox++) {
                for (int oz = -reachXz; oz <= reachXz; oz++) {
                    if (ox * ox + oy * oy * Y_SQUASH + oz * oz > radiusSq) {
                        continue;
                    }
                    total++;
                    Block block = level.getBlockState(cursor.set(vx + ox, wy, vz + oz)).getBlock();
                    if (block == ore.stoneOre() || block == ore.deepOre()) {
                        present++;
                    }
                }
            }
        }
        return new Scan(ore, total, present);
    }

    // --- bit-identical mirrors of OreField's private hash helpers ---

    private static long mix(long z) {
        z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
        z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
        return z ^ (z >>> 31);
    }

    private static long hash3(int salt, int a, int b, int c) {
        long h = FrozenParams.mapSeed() + salt * 0x9E3779B97F4A7C15L;
        h = mix(h ^ (a & 0xFFFFFFFFL));
        h = mix(h ^ (b & 0xFFFFFFFFL));
        return mix(h ^ (c & 0xFFFFFFFFL));
    }

    private static double to01(long hash) {
        return (hash >>> 11) * 0x1.0p-53D;
    }
}
