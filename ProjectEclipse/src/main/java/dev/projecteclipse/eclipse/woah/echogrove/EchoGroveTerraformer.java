package dev.projecteclipse.eclipse.woah.echogrove;

import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;

import com.mojang.math.Transformation;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.PaleGardenBlocks;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import dev.projecteclipse.eclipse.worldgen.stage.DisplayBrightnessFx;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.LanternBlock;
import net.minecraft.world.level.block.RotatedPillarBlock;
import net.minecraft.world.level.block.SlabBlock;
import net.minecraft.world.level.block.StairBlock;
import net.minecraft.world.level.block.TrapDoorBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.Half;
import net.minecraft.world.level.block.state.properties.SlabType;
import org.joml.Quaternionf;
import org.joml.Vector3f;

/**
 * WOAH-05 mist-hollow terraforming (plan §2.2) — one-time and final, deterministic
 * from the frozen map seed. Runs INSIDE the {@code SitePrep.preparePlateau} window
 * opened by {@link EchoGroveSites}: the bowl+palette column sweep goes through
 * {@link BudgetedBlockWriter} (the FogStormSites {@code carveGrove} discipline);
 * trees, props, probe block, static glimmer displays and orb spawns run in the
 * completion callback (a few hundred writes — the FogStorm camp/chest scale).
 *
 * <p>No runtime block swaps ever follow (plan §5: the past is BlockDisplay overlays,
 * never terrain), so the {@code RingGrowthService} "terrain = f(seed, stage)"
 * contract stays intact — the grove is a site like FogStorm/Mansion.</p>
 */
public final class EchoGroveTerraformer {
    /** Persistent glimmer displays at the memory tree (plan §2.2 no. 4). */
    public static final String STATIC_DISPLAY_TAG = "eclipse_echo_static";

    private static final int RADIUS = EchoGroveLayout.RADIUS;
    private static final int BOWL_DEPTH = EchoGroveLayout.BOWL_DEPTH;

    /** Scene anchors + tree center keep a clear radius during tree placement. */
    private static final int[][] KEEP_CLEAR = {
            {0, 0}, {-14, 6}, {18, -10}, {10, 16}, {-6, -18},
            EchoScenes.LANTERN_POSTS[0], EchoScenes.LANTERN_POSTS[1], EchoScenes.LANTERN_POSTS[2]};

    private EchoGroveTerraformer() {}

    /**
     * Terraforms the grove around {@code center} (plateau-Y center column).
     * {@code onComplete} runs after ALL writes and entity spawns have landed.
     */
    public static void terraform(ServerLevel level, BlockPos center, Runnable onComplete,
            Consumer<Throwable> onFailure) {
        long seed = FrozenParams.mapSeed() ^ 0x0EC0_6807EL;
        int span = RADIUS * 2 + 1;
        int total = span * span;
        int[] cursor = {0};
        BudgetedBlockWriter.enqueue(level, budget -> {
            int end = Math.min(total, cursor[0] + budget);
            for (; cursor[0] < end; cursor[0]++) {
                int dx = cursor[0] % span - RADIUS;
                int dz = cursor[0] / span - RADIUS;
                carveColumn(level, center, dx, dz, seed);
            }
            return cursor[0] >= total;
        }, () -> {
            try {
                placeFeatures(level, center, seed);
                onComplete.run();
            } catch (Throwable t) {
                onFailure.accept(t);
            }
        }, onFailure);
    }

    // ------------------------------------------------------------------ bowl + palette

    /** Cosine bowl profile: rim 0 → center −{@value #BOWL_DEPTH} (plan §2.2 no. 1). */
    static int bowlDepth(double dist) {
        if (dist >= RADIUS) {
            return 0;
        }
        return (int) Math.round(BOWL_DEPTH * 0.5D * (1.0D + Math.cos(Math.PI * dist / RADIUS)));
    }

    private static void carveColumn(ServerLevel level, BlockPos center, int dx, int dz, long seed) {
        double dist = Math.hypot(dx, dz);
        if (dist > RADIUS) {
            return;
        }
        int x = center.getX() + dx;
        int z = center.getZ() + dz;
        int plateauY = center.getY();
        int depth = bowlDepth(dist);
        int floorY = plateauY - depth;
        for (int y = plateauY; y > floorY; y--) {
            level.setBlock(new BlockPos(x, y, z), Blocks.AIR.defaultBlockState(), 3);
        }
        int h = hash(seed, dx, dz, 0);
        BlockState ground;
        if (dist < 18.0D) {
            int roll = Math.floorMod(h, 100);
            if (roll < 55) {
                ground = Blocks.CALCITE.defaultBlockState();
            } else if (roll < 75) {
                ground = Blocks.DIORITE.defaultBlockState();
            } else if (roll < 90) {
                ground = PaleGardenBlocks.PALE_MOSS_BLOCK.get().defaultBlockState();
            } else {
                ground = Blocks.GRAVEL.defaultBlockState();
            }
        } else {
            // Rim blend back to the biome ground (grass); calcite fingers thin outwards.
            double blend = (dist - 18.0D) / (RADIUS - 18.0D);
            ground = (Math.floorMod(h, 100) / 100.0D) > blend
                    ? Blocks.CALCITE.defaultBlockState()
                    : Blocks.GRASS_BLOCK.defaultBlockState();
        }
        level.setBlock(new BlockPos(x, floorY, z), ground, 3);
        // Pale moss carpet strewn over ~8% of surfaces (rim-weighted).
        if (Math.floorMod(hash(seed, dx, dz, 1), 100) < 8 && dist >= 6.0D) {
            level.setBlock(new BlockPos(x, floorY + 1, z),
                    PaleGardenBlocks.PALE_MOSS_CARPET.get().defaultBlockState(), 3);
        }
    }

    // ------------------------------------------------------------------ features

    private static void placeFeatures(ServerLevel level, BlockPos center, long seed) {
        placePuddles(level, center);
        placeBoneRoots(level, center, seed);
        placeDeadBushIslands(level, center, seed);
        List<int[]> trees = placeBleachedTrees(level, center, seed);
        placeMemoryTree(level, center, seed);
        placeSceneProps(level, center);
        spawnStaticGlimmer(level, center, seed);
        spawnOrbs(level, center);
        EclipseMod.LOGGER.info("EchoGroveTerraformer: bowl + {} pale trees + memory tree placed",
                trees.size());
    }

    /** Floor Y at a grove offset (mirrors the carve pass). */
    static int floorY(BlockPos center, int dx, int dz) {
        return center.getY() - bowlDepth(Math.hypot(dx, dz));
    }

    /** 2–3 shallow rest puddles (water 1 deep, calcite rim); one is the dog puddle. */
    private static void placePuddles(ServerLevel level, BlockPos center) {
        int[][] puddles = {{-6, -18}, {14, -18}, {-20, 12}};
        for (int[] p : puddles) {
            int fy = floorY(center, p[0], p[1]);
            for (int dx = -1; dx <= 1; dx++) {
                for (int dz = -1; dz <= 1; dz++) {
                    BlockPos pos = new BlockPos(center.getX() + p[0] + dx, fy,
                            center.getZ() + p[1] + dz);
                    boolean rim = Math.abs(dx) == 1 || Math.abs(dz) == 1;
                    level.setBlock(pos, rim ? Blocks.CALCITE.defaultBlockState()
                            : Blocks.WATER.defaultBlockState(), 3);
                    if (!rim) {
                        level.setBlock(pos.below(), Blocks.CALCITE.defaultBlockState(), 3);
                    }
                    // Clear any moss carpet the palette pass strewed here.
                    if (level.getBlockState(pos.above()).is(
                            PaleGardenBlocks.PALE_MOSS_CARPET.get())) {
                        level.setBlock(pos.above(), Blocks.AIR.defaultBlockState(), 3);
                    }
                }
            }
        }
    }

    /** ~14 flat bone-block "petrified root" runs of 2–4 blocks (plan §2.2 no. 2). */
    private static void placeBoneRoots(ServerLevel level, BlockPos center, long seed) {
        for (int i = 0; i < 14; i++) {
            int dx = Math.floorMod(hash(seed, i, 3, 2), 44) - 22;
            int dz = Math.floorMod(hash(seed, i, 7, 2), 44) - 22;
            if (Math.hypot(dx, dz) > 26.0D || nearKeepClear(dx, dz, 3.0D)) {
                continue;
            }
            int len = 2 + Math.floorMod(hash(seed, i, 11, 2), 3);
            boolean alongX = (hash(seed, i, 13, 2) & 1) == 0;
            BlockState bone = Blocks.BONE_BLOCK.defaultBlockState().setValue(
                    RotatedPillarBlock.AXIS, alongX ? Direction.Axis.X : Direction.Axis.Z);
            for (int j = 0; j < len; j++) {
                int rx = dx + (alongX ? j : 0);
                int rz = dz + (alongX ? 0 : j);
                level.setBlock(new BlockPos(center.getX() + rx,
                        floorY(center, rx, rz), center.getZ() + rz), bone, 3);
            }
        }
    }

    /** ~10 coarse-dirt islets with a dead bush (deliberately NO cobwebs — not horror). */
    private static void placeDeadBushIslands(ServerLevel level, BlockPos center, long seed) {
        for (int i = 0; i < 10; i++) {
            int dx = Math.floorMod(hash(seed, i, 17, 3), 48) - 24;
            int dz = Math.floorMod(hash(seed, i, 19, 3), 48) - 24;
            if (Math.hypot(dx, dz) > 27.0D || nearKeepClear(dx, dz, 3.0D)) {
                continue;
            }
            int fy = floorY(center, dx, dz);
            BlockPos ground = new BlockPos(center.getX() + dx, fy, center.getZ() + dz);
            level.setBlock(ground, Blocks.COARSE_DIRT.defaultBlockState(), 3);
            level.setBlock(ground.above(), Blocks.DEAD_BUSH.defaultBlockState(), 3);
        }
    }

    /**
     * Deterministic pale-tree offsets, Poisson-ish (min spacing 6). Pure function of
     * the seed — the overlay builder derives crown positions from the SAME list, so
     * flood crowns sit exactly on the real trees. Index 0 is the guaranteed old tree
     * of {@code children_chase}; a tree {@code t} is "old" iff {@code t == 0} or
     * {@code (t + 1) % 5 == 0}.
     */
    static List<int[]> treeOffsets(long seed) {
        List<int[]> placed = new ArrayList<>();
        placed.add(new int[] {-14, 6}); // the guaranteed old tree of children_chase
        int attempts = 0;
        int i = 0;
        while (placed.size() < 26 && attempts < 300) {
            attempts++;
            i++;
            int dx = Math.floorMod(hash(seed, i, 23, 4), 52) - 26;
            int dz = Math.floorMod(hash(seed, i, 29, 4), 52) - 26;
            double dist = Math.hypot(dx, dz);
            if (dist < 6.0D || dist > 27.0D || nearKeepClear(dx, dz, 4.0D)) {
                continue;
            }
            boolean tooClose = false;
            for (int[] other : placed) {
                if (Math.hypot(dx - other[0], dz - other[1]) < 6.0D) {
                    tooClose = true;
                    break;
                }
            }
            if (tooClose) {
                continue;
            }
            placed.add(new int[] {dx, dz});
        }
        return placed;
    }

    /** Trunk height of the tree at {@code (dx, dz)} — mirrors {@link #placeTree}. */
    static int treeHeight(long seed, int dx, int dz, boolean old) {
        int h = hash(seed, dx, dz, 5);
        return old ? 8 + Math.floorMod(h, 3) : 4 + Math.floorMod(h, 4);
    }

    /** ~26 dead pale trees from {@link #treeOffsets}; returns the placed offsets. */
    private static List<int[]> placeBleachedTrees(ServerLevel level, BlockPos center, long seed) {
        List<int[]> placed = treeOffsets(seed);
        for (int t = 0; t < placed.size(); t++) {
            int[] offset = placed.get(t);
            boolean old = t == 0 || (t + 1) % 5 == 0;
            placeTree(level, center, offset[0], offset[1], seed, old);
        }
        return placed;
    }

    /** One dead tree: bare trunk, branch stubs, hanging moss, bone root flare. */
    private static void placeTree(ServerLevel level, BlockPos center, int dx, int dz,
            long seed, boolean old) {
        int fy = floorY(center, dx, dz);
        BlockPos base = new BlockPos(center.getX() + dx, fy + 1, center.getZ() + dz);
        BlockState log = PaleGardenBlocks.STRIPPED_PALE_OAK_LOG.get().defaultBlockState();
        BlockState wood = PaleGardenBlocks.STRIPPED_PALE_OAK_WOOD.get().defaultBlockState();
        int height = treeHeight(seed, dx, dz, old);
        if (old) {
            for (int y = 0; y < height; y++) {
                for (int tx = 0; tx <= 1; tx++) {
                    for (int tz = 0; tz <= 1; tz++) {
                        level.setBlock(base.offset(tx, y, tz), wood, 3);
                    }
                }
            }
        } else {
            for (int y = 0; y < height; y++) {
                level.setBlock(base.above(y), log, 3);
            }
        }
        // Branch stubs on the upper two thirds — NO leaves, the trees are dead.
        int branches = 2 + Math.floorMod(hash(seed, dx, dz, 6), 3);
        for (int b = 0; b < branches; b++) {
            int bh = hash(seed, dx + b, dz, 7);
            int by = height / 3 + Math.floorMod(bh, Math.max(1, height * 2 / 3));
            Direction dir = Direction.from2DDataValue(Math.floorMod(bh >> 4, 4));
            int len = 1 + Math.floorMod(bh >> 8, 2);
            BlockState branch = wood.setValue(RotatedPillarBlock.AXIS, dir.getAxis());
            BlockPos tip = base.above(by);
            for (int j = 1; j <= len; j++) {
                tip = base.above(by).relative(dir, j);
                level.setBlock(tip, branch, 3);
            }
            // ~30% of branch ends: a single pale hanging moss strand (1–2 long).
            if (Math.floorMod(bh >> 12, 10) < 3) {
                BlockPos moss = tip.below();
                if (level.getBlockState(moss).isAir()) {
                    level.setBlock(moss,
                            PaleGardenBlocks.PALE_HANGING_MOSS.get().defaultBlockState(), 3);
                    if ((bh & 1) == 0 && level.getBlockState(moss.below()).isAir()) {
                        level.setBlock(moss.below(),
                                PaleGardenBlocks.PALE_HANGING_MOSS.get().defaultBlockState(), 3);
                    }
                }
            }
        }
        // Root flare: 3–5 bone/wood diagonals at the foot.
        int roots = 3 + Math.floorMod(hash(seed, dx, dz, 8), 3);
        for (int r = 0; r < roots; r++) {
            Direction dir = Direction.from2DDataValue(r & 3);
            BlockPos rootPos = base.relative(dir);
            BlockState root = (r & 1) == 0 ? Blocks.BONE_BLOCK.defaultBlockState() : wood;
            if (!level.getBlockState(rootPos).is(Blocks.WATER)) {
                level.setBlock(rootPos, root, 3);
            }
        }
    }

    /**
     * The memory tree (plan §2.2 no. 4): 3×3 trunk (wood shell, bone core) 12 high,
     * four rising main branches from height 7, a crown wreath, 4 chain hangers and the
     * client build-probe ({@code waxed_oxidized_copper_bulb}) as the topmost center
     * block ({@link EchoGroveLayout#probePos}).
     */
    private static void placeMemoryTree(ServerLevel level, BlockPos center, long seed) {
        BlockPos treeBase = center.below(BOWL_DEPTH); // bowl floor center block
        BlockState wood = PaleGardenBlocks.STRIPPED_PALE_OAK_WOOD.get().defaultBlockState();
        BlockState bone = Blocks.BONE_BLOCK.defaultBlockState();
        for (int y = 1; y <= EchoGroveLayout.TREE_HEIGHT; y++) {
            boolean full = y <= 8; // taper: 3×3 to height 8, single column above
            for (int tx = -1; tx <= 1; tx++) {
                for (int tz = -1; tz <= 1; tz++) {
                    if (!full && (tx != 0 || tz != 0)) {
                        continue;
                    }
                    BlockState state = (tx == 0 && tz == 0) ? bone : wood;
                    level.setBlock(treeBase.offset(tx, y, tz), state, 3);
                }
            }
        }
        // Four main branches from height 7, 3–5 blocks, gently rising.
        for (int b = 0; b < 4; b++) {
            Direction dir = Direction.from2DDataValue(b);
            int len = 3 + Math.floorMod(hash(seed, b, 31, 9), 3);
            BlockPos cursor = treeBase.offset(0, 7 + (b & 1), 0).relative(dir, 1);
            for (int j = 0; j < len; j++) {
                level.setBlock(cursor,
                        wood.setValue(RotatedPillarBlock.AXIS, dir.getAxis()), 3);
                cursor = cursor.relative(dir);
                if (j == len / 2) {
                    cursor = cursor.above(); // the rise
                }
            }
            // Crown wreath knuckle at the branch end.
            level.setBlock(cursor, wood, 3);
            level.setBlock(cursor.above(), wood, 3);
            // A chain hanger below every branch end (real aufhänger, plan §2.2 no. 4).
            if (level.getBlockState(cursor.below()).isAir()) {
                level.setBlock(cursor.below(), Blocks.CHAIN.defaultBlockState(), 3);
            }
        }
        // The build probe: topmost center block — never redstone-lit, never natural.
        level.setBlock(treeBase.above(EchoGroveLayout.TREE_HEIGHT),
                Blocks.WAXED_OXIDIZED_COPPER_BULB.defaultBlockState(), 3);
    }

    /** Scene props (real blocks, plan §2.2 no. 5). */
    private static void placeSceneProps(ServerLevel level, BlockPos center) {
        // Bench at (10, 16): two dark-oak stairs side by side + a slab "armrest".
        int by = floorY(center, 10, 16) + 1;
        BlockState stair = Blocks.DARK_OAK_STAIRS.defaultBlockState()
                .setValue(StairBlock.FACING, Direction.SOUTH);
        level.setBlock(new BlockPos(center.getX() + 9, by, center.getZ() + 16), stair, 3);
        level.setBlock(new BlockPos(center.getX() + 10, by, center.getZ() + 16), stair, 3);
        level.setBlock(new BlockPos(center.getX() + 11, by, center.getZ() + 16),
                Blocks.DARK_OAK_SLAB.defaultBlockState().setValue(SlabBlock.TYPE, SlabType.BOTTOM), 3);

        // Miner's rock at (18, −10): 4×3×3 deepslate block with two calcite veins.
        int ry = floorY(center, 18, -10) + 1;
        for (int rx = 0; rx < 4; rx++) {
            for (int rz = 0; rz < 3; rz++) {
                for (int yy = 0; yy < 3; yy++) {
                    if (yy == 2 && (rx == 0 || rx == 3)) {
                        continue; // rounded top
                    }
                    boolean vein = (rx + yy * 2 + rz) % 7 == 0;
                    BlockState rock = vein ? Blocks.CALCITE.defaultBlockState()
                            : ((rx + rz + yy) % 3 == 0
                                    ? Blocks.COBBLED_DEEPSLATE.defaultBlockState()
                                    : Blocks.DEEPSLATE.defaultBlockState());
                    level.setBlock(new BlockPos(center.getX() + 17 + rx, ry + yy,
                            center.getZ() - 11 + rz), rock, 3);
                }
            }
        }

        // Cart hull near the rock at (20, −6): planks bed + trapdoor sides.
        int cy = floorY(center, 20, -6) + 1;
        BlockPos cart = new BlockPos(center.getX() + 20, cy, center.getZ() - 6);
        level.setBlock(cart, Blocks.DARK_OAK_PLANKS.defaultBlockState(), 3);
        level.setBlock(cart.relative(Direction.EAST), Blocks.DARK_OAK_PLANKS.defaultBlockState(), 3);
        BlockState side = Blocks.DARK_OAK_TRAPDOOR.defaultBlockState()
                .setValue(TrapDoorBlock.OPEN, true).setValue(TrapDoorBlock.HALF, Half.BOTTOM);
        level.setBlock(cart.relative(Direction.NORTH),
                side.setValue(TrapDoorBlock.FACING, Direction.NORTH), 3);
        level.setBlock(cart.relative(Direction.SOUTH),
                side.setValue(TrapDoorBlock.FACING, Direction.SOUTH), 3);

        // Three lantern posts (the lantern_walk route; orb 4 tops post 3).
        for (int[] post : EchoScenes.LANTERN_POSTS) {
            int py = floorY(center, post[0], post[1]);
            BlockPos foot = new BlockPos(center.getX() + post[0], py + 1, center.getZ() + post[1]);
            for (int y = 0; y < 3; y++) {
                level.setBlock(foot.above(y),
                        PaleGardenBlocks.STRIPPED_PALE_OAK_LOG.get().defaultBlockState(), 3);
            }
            level.setBlock(foot.above(3), Blocks.LANTERN.defaultBlockState()
                    .setValue(LanternBlock.HANGING, false), 3);
        }

        // The dog's fetch ground: a pale-moss-carpet circle at (−6, −18).
        for (int dx = -2; dx <= 2; dx++) {
            for (int dz = -2; dz <= 2; dz++) {
                if (dx * dx + dz * dz > 5) {
                    continue;
                }
                int gx = -6 + dx;
                int gz = -18 + dz;
                BlockPos pos = new BlockPos(center.getX() + gx,
                        floorY(center, gx, gz) + 1, center.getZ() + gz);
                if (level.getBlockState(pos).isAir()
                        && level.getBlockState(pos.below()).isSolidRender(level, pos.below())) {
                    level.setBlock(pos,
                            PaleGardenBlocks.PALE_MOSS_CARPET.get().defaultBlockState(), 3);
                }
            }
        }
    }

    /**
     * 10 persistent glimmer displays (pearlescent froglight, scale 0.25, brightness
     * 12/8, viewRange 2.0) hanging 1–3 under the memory-tree branch ends. Spawned
     * ONCE at materialization; uuids persist in {@link EchoGroveState} for repair.
     */
    private static void spawnStaticGlimmer(ServerLevel level, BlockPos center, long seed) {
        EchoGroveState state = EchoGroveState.get(level.getServer());
        BlockPos treeBase = center.below(BOWL_DEPTH);
        for (int i = 0; i < 10; i++) {
            int h = hash(seed, i, 41, 10);
            double angle = (i / 10.0D) * Math.PI * 2.0D + (h & 15) / 40.0D;
            double radius = 2.2D + Math.floorMod(h >> 4, 20) / 10.0D;
            double hang = 1.0D + Math.floorMod(h >> 8, 3);
            double x = treeBase.getX() + 0.5D + Math.cos(angle) * radius;
            double z = treeBase.getZ() + 0.5D + Math.sin(angle) * radius;
            double y = treeBase.getY() + 8.5D - hang;
            Display.BlockDisplay glimmer = EntityType.BLOCK_DISPLAY.create(level);
            if (glimmer == null) {
                continue;
            }
            glimmer.moveTo(x, y, z, 0.0F, 0.0F);
            glimmer.setBlockState(Blocks.PEARLESCENT_FROGLIGHT.defaultBlockState());
            glimmer.addTag(STATIC_DISPLAY_TAG);
            glimmer.setTransformationInterpolationDelay(0);
            glimmer.setTransformationInterpolationDuration(0);
            float scale = 0.25F;
            glimmer.setTransformation(new Transformation(
                    new Vector3f(-scale * 0.5F, -scale * 0.5F, -scale * 0.5F),
                    new Quaternionf(), new Vector3f(scale), new Quaternionf()));
            level.addFreshEntity(glimmer);
            DisplayBrightnessFx.set(glimmer, 12, 8, 2.0F);
            state.rememberStaticDisplay(glimmer.getUUID());
        }
    }

    /** The 5 lost orbs (plan §7.1 table) + 5 tree orbs circling the crown. */
    private static void spawnOrbs(ServerLevel level, BlockPos center) {
        EchoGroveState state = EchoGroveState.get(level.getServer());
        state.clearOrbUuids();
        // kind → {dx, dyAboveFloor, dz} (dy measured from the LOCAL bowl floor).
        double[][] lost = {
                {-14.0D, 8.0D, 6.0D},    // 0 children's laughter — up in the old tree
                {18.5D, 1.5D, -10.5D},   // 1 silver dust — the rock crevice
                {10.0D, 0.4D, 16.5D},    // 2 sunset — under the bench
                {-6.0D, -0.6D, -18.0D},  // 3 the stick — just under the puddle surface
                {22.0D, 4.8D, 4.0D}};    // 4 lantern light — atop post 3
        for (int kind = 0; kind < 5; kind++) {
            if (state.orbCollected(kind)) {
                continue; // collected orbs never respawn (plan §3.6)
            }
            double[] o = lost[kind];
            spawnOrb(level, state, kind,
                    center.getX() + o[0] + 0.5D,
                    floorY(center, (int) Math.round(o[0]), (int) Math.round(o[2])) + 1.0D + o[1],
                    center.getZ() + o[2] + 0.5D);
        }
        BlockPos treeBase = center.below(BOWL_DEPTH);
        for (int i = 0; i < 5; i++) {
            double angle = (i / 5.0D) * Math.PI * 2.0D;
            spawnOrb(level, state, 10 + i,
                    treeBase.getX() + 0.5D + Math.cos(angle) * 2.6D,
                    treeBase.getY() + 8.5D + (i % 2 == 0 ? 0.6D : -0.2D),
                    treeBase.getZ() + 0.5D + Math.sin(angle) * 2.6D);
        }
    }

    /**
     * Dev reset support ({@code /dev woah echo reset}): discards every persisted orb
     * (found via the uuid list) and respawns the full set for the CURRENT quest
     * state. Returns the number of live orbs removed.
     */
    public static int respawnOrbs(ServerLevel level) {
        EchoGroveState state = EchoGroveState.get(level.getServer());
        if (state.treeCenter() == null) {
            return 0;
        }
        int removed = 0;
        for (java.util.UUID uuid : List.copyOf(state.orbUuids())) {
            net.minecraft.world.entity.Entity entity = level.getEntity(uuid);
            if (entity != null) {
                entity.discard();
                removed++;
            }
        }
        spawnOrbs(level, state.treeCenter().above(BOWL_DEPTH));
        return removed;
    }

    private static void spawnOrb(ServerLevel level, EchoGroveState state, int kind,
            double x, double y, double z) {
        if (!EchoGroveEntities.MEMORY_ORB.isBound()) {
            return;
        }
        MemoryOrbEntity orb = new MemoryOrbEntity(EchoGroveEntities.MEMORY_ORB.get(), level);
        orb.setKind(kind);
        orb.setPos(x, y, z);
        level.addFreshEntity(orb);
        state.rememberOrb(orb.getUUID());
    }

    private static boolean nearKeepClear(int dx, int dz, double clearance) {
        for (int[] anchor : KEEP_CLEAR) {
            if (Math.hypot(dx - anchor[0], dz - anchor[1]) < clearance + 2.0D) {
                return true;
            }
        }
        return false;
    }

    /** Deterministic mix (the skin-generator hash family). */
    static int hash(long seed, int a, int b, int salt) {
        long h = seed ^ (a * 0x9E3779B97F4A7C15L) ^ ((long) b << 32) ^ ((long) salt * 0x27D4EB2DL);
        h ^= h >>> 27;
        h *= 0x3C79AC492BA7B653L;
        h ^= h >>> 33;
        return (int) (h & 0x7FFFFFFF);
    }
}
