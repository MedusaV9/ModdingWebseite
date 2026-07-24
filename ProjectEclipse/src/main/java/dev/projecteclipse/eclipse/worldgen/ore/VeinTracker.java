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
 * Stateless vein derivation for mining feel (W4-FEEL, IDEA-03 #2). Re-derives the
 * deterministic vein chains of a mined ore block's 16³ cell through the SAME
 * {@link OreVeinShape} helper {@link OreField} generates with (B2 — lockstep by
 * construction, the old duplicated hash mirrors are gone), finds the chain containing
 * the block, then counts how many of that vein's blocks are still present in the
 * (already-loaded) chunk. That makes "first break of an intact vein" and "this break
 * clears the vein" exact, cheap and cheat-proof: no chunk scans, no persistence, at
 * most one cell derivation + a few dozen in-cell block reads per ORE break.
 *
 * <p>Chain containment invariant: {@link OreVeinShape} anchors every vein at
 * {@code cell·16 + 4 + [0..7]} and caps sizes at {@link OreConfig#MAX_VEIN_SIZE}, so a
 * whole chain always lives inside the block's own 16³ cell — one cell derivation
 * covers the entire vein. Where two derived chains of the same ore overlap, the census
 * covers the first containing chain only (overlapping veins read as one bigger deposit
 * in-world, exactly like vanilla).</p>
 */
public final class VeinTracker {

    private VeinTracker() {}

    /**
     * One derived-vein snapshot at break time. {@code total} counts every chain position
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
     * {@code null} when the block is not part of a derivable vein (stage gate locked, no
     * chain contains it, Y outside the ore range — e.g. structure loot ore) — callers
     * just skip the vein feel then. Server thread only; reads blocks of one
     * already-loaded cell.
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

        // --- exact OreField derivation (shared OreVeinShape — lockstep by construction) ---
        int cellX = x >> 4;
        int cellZ = z >> 4;
        int cellY = Math.floorDiv(y, 16);
        double scale = OreVeinShape.gateScale(ore, profile, cellX, cellZ);
        if (scale < 0.0D) {
            return null;
        }
        OreVeinShape[] veins = OreVeinShape.veinsOf(FrozenParams.mapSeed(), ore, cellX, cellY, cellZ, scale);
        OreVeinShape hit = null;
        for (OreVeinShape vein : veins) {
            if (vein.contains(x, y, z)) {
                hit = vein;
                break;
            }
        }
        if (hit == null) {
            return null; // the broken block is not a member of any of this cell's veins
        }

        // --- vein census: total chain candidates vs ore blocks still in the world ---
        int[] counts = new int[2];
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        hit.forEachBlock((bx, by, bz) -> {
            if (by < ore.minY() || by > ore.maxY()) {
                return;
            }
            counts[0]++;
            Block block = level.getBlockState(cursor.set(bx, by, bz)).getBlock();
            if (block == ore.stoneOre() || block == ore.deepOre()) {
                counts[1]++;
            }
        });
        return new Scan(ore, counts[0], counts[1]);
    }
}
