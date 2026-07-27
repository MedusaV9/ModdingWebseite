package dev.projecteclipse.eclipse.woah.gravityrift;

import java.util.function.Consumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import dev.projecteclipse.eclipse.worldgen.structure.SitePrep;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.block.AmethystClusterBlock;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import net.minecraft.world.level.block.RotatedPillarBlock;
import net.minecraft.world.level.block.entity.RandomizableContainerBlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.storage.loot.LootTable;

/**
 * WOAH-02 terraform + static islands (plan §2.3/§5.3): the terraced crater (r
 * {@value GravityRiftZone#CRATER_RADIUS}, {@value GravityRiftZone#MAX_DEPTH} deep), the
 * REAL walkable block islands (8-step parkour spiral, two ambient mega floes with real
 * mini jungle trees, the loot floe with its chest), the heart pedestal and the buried
 * sentinel block that makes the build idempotent + self-healing.
 *
 * <p>Composition follows the {@code SanctumCrater} recipe (parabolic depth + hash
 * roughness + terraced strata, everything deterministic over
 * {@link GravityRiftZone#hash01} — ZERO {@code RandomSource}), jungle-adjusted: mossy
 * outer strata, tuff/deepslate mid, a torn polished-deepslate/sculk/amethyst floor.
 * All bulk writes ride the {@link BudgetedBlockWriter} rail; the pass ends with
 * {@link SitePrep#touchBounds} + {@link SitePrep#finish} (heightmap re-prime +
 * relight/resend — a large carve must never spike a tick).</p>
 */
public final class GravityRiftBuilder {
    /** Loot table of the loot-floe chest ({@code data/eclipse/loot_table/chests/…}). */
    public static final ResourceKey<LootTable> LOOT = ResourceKey.create(Registries.LOOT_TABLE,
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "chests/gravity_rift_loft"));

    /** Sentinel buried under the heart pedestal (idempotence probe, plan §2.3). */
    private static final BlockState SENTINEL = Blocks.CRYING_OBSIDIAN.defaultBlockState();
    /** Sentinel depth below the crater-floor anchor. */
    private static final int SENTINEL_DEPTH = 2;

    /** Plateau/carve footprint half-extent (rim ring + skirt margin). */
    private static final int FOOTPRINT_HALF = (int) Math.ceil(GravityRiftZone.RIM_OUTER_RADIUS) + 3;

    private GravityRiftBuilder() {}

    // ------------------------------------------------------------------ materialize

    /**
     * Two-phase materialization ({@code ChronoStasisSite.materialize} shape): plateau
     * prep over the footprint (canopy sweep clears the bamboo jungle), then a budgeted
     * bowl carve, then the synchronous island/pedestal/chest stamp, then
     * relight/resend + SavedData + service wake. Exactly one of
     * {@code onComplete}/{@code onFailure} fires.
     */
    public static void materialize(ServerLevel level, Runnable onComplete,
            Consumer<Throwable> onFailure) {
        GravityRiftState state = GravityRiftState.get(level.getServer());
        if (state.built() && isBuiltSentinel(level, state.anchor())) {
            onComplete.run();
            return;
        }
        BlockPos center = GravityRiftZone.surfaceCenter(level);
        int surfaceY = center.getY();
        BlockPos anchor = new BlockPos(center.getX(), surfaceY - GravityRiftZone.MAX_DEPTH,
                center.getZ());
        SitePrep.PreparedGround prepared = SitePrep.preparePlateau(level, DiscProfile.OVERWORLD,
                center.getX() - FOOTPRINT_HALF, center.getZ() - FOOTPRINT_HALF,
                center.getX() + FOOTPRINT_HALF, center.getZ() + FOOTPRINT_HALF, center);
        prepared.whenReady(() -> carveCrater(level, center, surfaceY, () -> {
            placeStaticIslands(level, anchor);
            placeHeartPedestal(level, anchor);
            placeLootChest(level, anchor, state);
            SitePrep.touchBounds(prepared,
                    center.getX() - FOOTPRINT_HALF, center.getZ() - FOOTPRINT_HALF,
                    center.getX() + FOOTPRINT_HALF, center.getZ() + FOOTPRINT_HALF);
            SitePrep.finish(level, prepared);
            state.setAnchor(anchor);
            state.setBuiltVersion(GravityRiftState.VERSION_V1);
            GravityRiftService.onSiteBuilt(level, anchor);
            EclipseMod.LOGGER.info("GravityRiftBuilder: crater v{} built at {} (floor y{})",
                    GravityRiftState.VERSION_V1, anchor.toShortString(), anchor.getY());
            onComplete.run();
        }, onFailure), onFailure);
    }

    /** Whether the buried sentinel still stands (self-heal probe, risk R2). */
    public static boolean isBuiltSentinel(ServerLevel level, BlockPos anchor) {
        if (anchor == null) {
            return false;
        }
        return level.getBlockState(anchor.below(SENTINEL_DEPTH)).is(SENTINEL.getBlock());
    }

    // ------------------------------------------------------------------ crater carve

    /**
     * Budgeted column sweep over the (2·{@value #FOOTPRINT_HALF}+1)² footprint: bowl
     * air-out, strata floor + sub-floor, terraces, rim rubble with the kept-clear
     * inward walk sector.
     */
    private static void carveCrater(ServerLevel level, BlockPos center, int surfaceY,
            Runnable onComplete, Consumer<Throwable> onFailure) {
        int half = FOOTPRINT_HALF;
        int span = half * 2 + 1;
        int total = span * span;
        int[] cursor = {0};
        BudgetedBlockWriter.enqueue(level, budget -> {
            int end = Math.min(total, cursor[0] + budget);
            for (; cursor[0] < end; cursor[0]++) {
                int dx = cursor[0] % span - half;
                int dz = cursor[0] / span - half;
                carveColumn(level, center, surfaceY, dx, dz);
            }
            return cursor[0] >= total;
        }, onComplete, onFailure);
    }

    private static void carveColumn(ServerLevel level, BlockPos center, int surfaceY,
            int dx, int dz) {
        double rr = Math.sqrt(dx * dx + dz * dz);
        if (rr > GravityRiftZone.RIM_OUTER_RADIUS) {
            return;
        }
        int x = center.getX() + dx;
        int z = center.getZ() + dz;
        level.getChunk(x >> 4, z >> 4);
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        if (rr <= GravityRiftZone.CRATER_RADIUS) {
            int depth = GravityRiftZone.roughDepth(x, z, dx, dz);
            int floorY = surfaceY - depth;
            // Air the bowl out (also clears plateau fill + stray bamboo above grade).
            for (int y = floorY + 1; y <= surfaceY + 10; y++) {
                cursor.set(x, y, z);
                if (!level.getBlockState(cursor).isAir()) {
                    level.setBlock(cursor, Blocks.AIR.defaultBlockState(), 2);
                }
            }
            set(level, new BlockPos(x, floorY, z), floorMix(x, floorY, z, rr));
            if (depth > 0 && GravityRiftZone.hash01(x, 111, z) < 0.6D) {
                set(level, new BlockPos(x, floorY - 1, z), subFloorMix(x, z));
            }
            // Sparse glow lichen across the mid bowl (readable at night).
            if (rr > 4.0D && rr < 24.0D && GravityRiftZone.hash01(x, 119, z) < 0.045D) {
                BlockPos pip = new BlockPos(x, floorY + 1, z);
                if (level.getBlockState(pip).isAir()
                        && level.getBlockState(pip.below()).isSolidRender(level, pip.below())) {
                    set(level, pip, Blocks.GLOW_LICHEN.defaultBlockState()
                            .setValue(BlockStateProperties.DOWN, true));
                }
            }
        } else if (!GravityRiftZone.inWalkSector(dx, dz)
                && GravityRiftZone.hash01(x, 103, z) < 0.38D) {
            // Broken blast-rubble ring on the lip (walk sector kept clear).
            set(level, new BlockPos(x, surfaceY + 1, z), rubbleMix(x, surfaceY + 1, z));
            if (GravityRiftZone.hash01(x, 104, z) < 0.16D) {
                set(level, new BlockPos(x, surfaceY + 2, z), rubbleMix(x, surfaceY + 2, z));
            }
        }
    }

    /** Exposed strata by ring: torn floor core → tuff/deepslate mid → mossy outer. */
    private static BlockState floorMix(int x, int y, int z, double rr) {
        double h = GravityRiftZone.hash01(x, 109, z);
        if (rr < 4.0D) {
            // The "torn-open world" heart floor.
            if (h < 0.12D) return Blocks.CRYING_OBSIDIAN.defaultBlockState();
            if (h < 0.34D) return Blocks.SCULK.defaultBlockState();
            if (h < 0.52D) return Blocks.AMETHYST_BLOCK.defaultBlockState();
            return Blocks.POLISHED_DEEPSLATE.defaultBlockState();
        }
        if (rr < 17.0D) {
            if (h < 0.16D && GravityRiftZone.hash01(x, 121, z) < 0.4D) {
                return Blocks.SCULK.defaultBlockState(); // sculk flecks bleeding outward
            }
            if (h < 0.34D) return Blocks.TUFF.defaultBlockState();
            if (h < 0.58D) return Blocks.DEEPSLATE.defaultBlockState();
            if (h < 0.78D) return Blocks.COBBLED_DEEPSLATE.defaultBlockState();
            return Blocks.COARSE_DIRT.defaultBlockState();
        }
        // Mossy jungle-side outer ring.
        if (h < 0.28D) return Blocks.MOSS_BLOCK.defaultBlockState();
        if (h < 0.52D) return Blocks.MOSSY_COBBLESTONE.defaultBlockState();
        if (h < 0.74D) return Blocks.STONE.defaultBlockState();
        if (h < 0.88D) return Blocks.TUFF.defaultBlockState();
        return Blocks.COARSE_DIRT.defaultBlockState();
    }

    private static BlockState subFloorMix(int x, int z) {
        return GravityRiftZone.hash01(x, 113, z) < 0.55D
                ? Blocks.DEEPSLATE.defaultBlockState()
                : Blocks.TUFF.defaultBlockState();
    }

    private static BlockState rubbleMix(int x, int y, int z) {
        double h = GravityRiftZone.hash01(x, y, z);
        if (h < 0.34D) return Blocks.MOSSY_COBBLESTONE.defaultBlockState();
        if (h < 0.62D) return Blocks.COBBLED_DEEPSLATE.defaultBlockState();
        if (h < 0.84D) return Blocks.TUFF.defaultBlockState();
        return Blocks.MOSS_BLOCK.defaultBlockState();
    }

    // ------------------------------------------------------------------ static islands

    /**
     * The REAL block islands (plan §5.3, jungle palette): the 8 parkour decks, the two
     * ambient mega floes with real mini jungle trees + bamboo accents, the loot floe
     * deck. Everything hangs on air — displays are scenery, these are the ground truth.
     */
    private static void placeStaticIslands(ServerLevel level, BlockPos anchor) {
        for (GravityRiftZone.Step step : GravityRiftZone.STEPS) {
            int cx = anchor.getX() + (int) Math.round(
                    GravityRiftZone.polarX(step.angleDeg(), step.radius()));
            int cz = anchor.getZ() + (int) Math.round(
                    GravityRiftZone.polarZ(step.angleDeg(), step.radius()));
            placeDeck(level, cx, anchor.getY() + step.height(), cz, step.half(), false);
        }
        // Loot floe: 5×2×5 deck.
        int lx = anchor.getX() + (int) Math.round(
                GravityRiftZone.polarX(GravityRiftZone.LOOT_ANGLE_DEG, GravityRiftZone.LOOT_RADIUS));
        int lz = anchor.getZ() + (int) Math.round(
                GravityRiftZone.polarZ(GravityRiftZone.LOOT_ANGLE_DEG, GravityRiftZone.LOOT_RADIUS));
        placeDeck(level, lx, anchor.getY() + GravityRiftZone.LOOT_HEIGHT, lz, 2, true);
        // Two ambient mega floes (7×5×7 + tree) — the 200-block silhouette.
        for (GravityRiftZone.MegaFloe floe : GravityRiftZone.MEGA_FLOES) {
            int fx = anchor.getX() + (int) Math.round(
                    GravityRiftZone.polarX(floe.angleDeg(), floe.radius()));
            int fz = anchor.getZ() + (int) Math.round(
                    GravityRiftZone.polarZ(floe.angleDeg(), floe.radius()));
            placeMegaFloe(level, fx, anchor.getY() + floe.height(), fz);
        }
    }

    /**
     * One floating deck: walkable top layer at {@code topY} (moss/grass), a dirt belly
     * below, a hash-nibbled stone keel under that. {@code half} 1 → 3×3, 2 → 5×5.
     */
    private static void placeDeck(ServerLevel level, int cx, int topY, int cz, int half,
            boolean loot) {
        for (int dx = -half; dx <= half; dx++) {
            for (int dz = -half; dz <= half; dz++) {
                int x = cx + dx;
                int z = cz + dz;
                boolean corner = Math.abs(dx) == half && Math.abs(dz) == half;
                if (corner && !loot && GravityRiftZone.hash01(x, topY, z) < 0.5D) {
                    continue; // nibbled corners: floes, not tiles
                }
                double h = GravityRiftZone.hash01(x, topY + 1, z);
                BlockState top = h < 0.55D ? Blocks.MOSS_BLOCK.defaultBlockState()
                        : Blocks.GRASS_BLOCK.defaultBlockState();
                set(level, new BlockPos(x, topY, z), top);
                set(level, new BlockPos(x, topY - 1, z),
                        h < 0.4D ? Blocks.ROOTED_DIRT.defaultBlockState()
                                : Blocks.DIRT.defaultBlockState());
                if (!corner && GravityRiftZone.hash01(x, topY - 2, z) < 0.55D) {
                    set(level, new BlockPos(x, topY - 2, z),
                            GravityRiftZone.hash01(x, topY - 3, z) < 0.5D
                                    ? Blocks.STONE.defaultBlockState()
                                    : Blocks.COBBLED_DEEPSLATE.defaultBlockState());
                }
            }
        }
    }

    /**
     * One 7×5×7 ambient mega floe: grass/moss cap, dirt body, stone keel tapering to a
     * point, plus a REAL mini jungle tree (2×2-less trunk, leaf blob) and 2–3 bamboo
     * stalks — visible to render distance, the far-field hook (plan §1).
     */
    private static void placeMegaFloe(ServerLevel level, int cx, int topY, int cz) {
        for (int dx = -3; dx <= 3; dx++) {
            for (int dz = -3; dz <= 3; dz++) {
                double rr = Math.sqrt(dx * dx + dz * dz);
                if (rr > 3.4D) {
                    continue;
                }
                int x = cx + dx;
                int z = cz + dz;
                double h = GravityRiftZone.hash01(x, topY, z);
                set(level, new BlockPos(x, topY, z),
                        h < 0.5D ? Blocks.GRASS_BLOCK.defaultBlockState()
                                : Blocks.MOSS_BLOCK.defaultBlockState());
                // Belly + keel: depth tapers with radius (5 deep at center).
                int keel = (int) Math.round(4.0D * (1.0D - rr / 3.6D));
                for (int dy = 1; dy <= keel; dy++) {
                    BlockState body;
                    if (dy == 1) {
                        body = h < 0.5D ? Blocks.DIRT.defaultBlockState()
                                : Blocks.ROOTED_DIRT.defaultBlockState();
                    } else if (GravityRiftZone.hash01(x, topY - dy, z) < 0.6D) {
                        body = Blocks.STONE.defaultBlockState();
                    } else {
                        body = Blocks.COBBLED_DEEPSLATE.defaultBlockState();
                    }
                    set(level, new BlockPos(x, topY - dy, z), body);
                }
                // Hanging vines off the keel edge (Pandora read).
                if (rr > 2.2D && GravityRiftZone.hash01(x, topY + 7, z) < 0.3D) {
                    set(level, new BlockPos(x, topY - keel - 1, z),
                            Blocks.HANGING_ROOTS.defaultBlockState());
                }
            }
        }
        // Real mini jungle tree: 4-block trunk + 3×3×2 leaf blob with a crown.
        int tx = cx + 1;
        int tz = cz - 1;
        for (int dy = 1; dy <= 4; dy++) {
            set(level, new BlockPos(tx, topY + dy, tz),
                    Blocks.JUNGLE_LOG.defaultBlockState()
                            .setValue(RotatedPillarBlock.AXIS, Direction.Axis.Y));
        }
        for (int dx = -1; dx <= 1; dx++) {
            for (int dz = -1; dz <= 1; dz++) {
                for (int dy = 4; dy <= 5; dy++) {
                    BlockPos leaf = new BlockPos(tx + dx, topY + dy, tz + dz);
                    if (level.getBlockState(leaf).isAir()
                            && GravityRiftZone.hash01(leaf.getX(), leaf.getY(), leaf.getZ()) < 0.85D) {
                        set(level, leaf, Blocks.JUNGLE_LEAVES.defaultBlockState()
                                .setValue(BlockStateProperties.PERSISTENT, true));
                    }
                }
            }
        }
        set(level, new BlockPos(tx, topY + 6, tz), Blocks.JUNGLE_LEAVES.defaultBlockState()
                .setValue(BlockStateProperties.PERSISTENT, true));
        // Bamboo accents: two short stalks on the deck.
        for (int b = 0; b < 2; b++) {
            int bx = cx - 2 + b * 3;
            int bz = cz + 2 - b;
            BlockPos base = new BlockPos(bx, topY + 1, bz);
            if (level.getBlockState(base.below()).is(Blocks.GRASS_BLOCK)
                    || level.getBlockState(base.below()).is(Blocks.MOSS_BLOCK)) {
                int stalks = 2 + (int) (GravityRiftZone.hash01(bx, topY, bz) * 2.0D);
                for (int dy = 0; dy < stalks; dy++) {
                    set(level, base.above(dy), Blocks.BAMBOO.defaultBlockState());
                }
            }
        }
    }

    // ------------------------------------------------------------------ heart + loot

    /** 3×3 polished-deepslate pedestal, amethyst center, buried sentinel (floor − 2). */
    private static void placeHeartPedestal(ServerLevel level, BlockPos anchor) {
        for (int dx = -1; dx <= 1; dx++) {
            for (int dz = -1; dz <= 1; dz++) {
                BlockState state = dx == 0 && dz == 0
                        ? Blocks.AMETHYST_BLOCK.defaultBlockState()
                        : Blocks.POLISHED_DEEPSLATE.defaultBlockState();
                set(level, anchor.offset(dx, 0, dz), state);
            }
        }
        set(level, anchor.below(1), Blocks.POLISHED_DEEPSLATE.defaultBlockState());
        set(level, anchor.below(SENTINEL_DEPTH), SENTINEL);
    }

    /** Chest (loot table {@link #LOOT}) + amethyst cluster + lantern on the loot floe. */
    private static void placeLootChest(ServerLevel level, BlockPos anchor,
            GravityRiftState state) {
        int lx = anchor.getX() + (int) Math.round(
                GravityRiftZone.polarX(GravityRiftZone.LOOT_ANGLE_DEG, GravityRiftZone.LOOT_RADIUS));
        int lz = anchor.getZ() + (int) Math.round(
                GravityRiftZone.polarZ(GravityRiftZone.LOOT_ANGLE_DEG, GravityRiftZone.LOOT_RADIUS));
        int deckY = anchor.getY() + GravityRiftZone.LOOT_HEIGHT;
        BlockPos chestPos = new BlockPos(lx, deckY + 1, lz);
        if (!state.lootChestPlaced()) {
            set(level, chestPos, Blocks.CHEST.defaultBlockState()
                    .setValue(HorizontalDirectionalBlock.FACING, Direction.WEST));
            if (level.getBlockEntity(chestPos) instanceof RandomizableContainerBlockEntity chest) {
                chest.setLootTable(LOOT, FrozenParams.mapSeed() ^ chestPos.asLong());
            }
            state.setLootChestPlaced(true);
        }
        set(level, new BlockPos(lx + 2, deckY + 1, lz - 2),
                Blocks.AMETHYST_CLUSTER.defaultBlockState()
                        .setValue(AmethystClusterBlock.FACING, Direction.UP));
        set(level, new BlockPos(lx - 2, deckY + 1, lz + 2), Blocks.LANTERN.defaultBlockState());
    }

    /** Silent write; SitePrep.finish() relights + resends the touched chunks after. */
    private static void set(ServerLevel level, BlockPos pos, BlockState state) {
        level.setBlock(pos, state, Block.UPDATE_CLIENTS | Block.UPDATE_KNOWN_SHAPE);
    }
}
