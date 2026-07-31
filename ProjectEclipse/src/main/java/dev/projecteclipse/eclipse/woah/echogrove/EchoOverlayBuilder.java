package dev.projecteclipse.eclipse.woah.echogrove;

import java.util.ArrayList;
import java.util.List;

import com.mojang.math.Transformation;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import dev.projecteclipse.eclipse.worldgen.stage.DisplayBrightnessFx;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.LeavesBlock;
import net.minecraft.world.level.block.state.BlockState;
import org.joml.Quaternionf;
import org.joml.Vector3f;

/**
 * WOAH-05 past-overlay pool (plan §5) — the pre-parked Scale-0.02 BlockDisplay set
 * that the memory flood grows and shrinks. Never terrain: ~620 displays, spawned
 * ONCE per window in 50/tick batches (the CreditsFormationAct law), parked at
 * {@value #PARK_SCALE} (never exactly 0 — interpolation health), pushed to target
 * scale per flood and back. Idle cost: zero pushes.
 *
 * <p><b>W13-C3 flood beat:</b> the grow/shrink is ONE continuous radial wave — each
 * display's single push carries an interpolation DELAY derived from its exact XZ
 * distance to the memory tree ({@code dist/distMax ×} {@value #FLOOD_TRAVEL_TICKS} t
 * growing inside-out, mirrored shrinking outside-in, so the flood visibly pulls back
 * INTO the tree). The front travels ~0.83 blocks/t as a smooth wavefront instead of
 * 4 discrete bands, and it costs ZERO extra packets — the delay rides the same
 * transform push the 4-band version already sent.</p>
 *
 * <p>Specs are deterministic from the site seed (same hash family as
 * {@link EchoGroveTerraformer}), so a discarded pool rebuilds bit-identically.
 * Restart duplicates are prevented by tag sweeps ({@value #OVERLAY_TAG}) before
 * every pool build plus the startup sweep in {@code EchoGroveSites}.</p>
 *
 * <p>Post-finale afterglow (plan §5.2): 15% of the crown displays park at 0.8 and
 * the warm-light group at 0.2 — the grove reads "half awake" forever.</p>
 */
public final class EchoOverlayBuilder {
    public static final String OVERLAY_TAG = "eclipse_echo_overlay";
    static final float PARK_SCALE = 0.02F;
    private static final int SPAWN_PER_TICK = 50;
    private static final double WINDOW_OPEN_DIST = 128.0D;
    private static final double WINDOW_CLOSE_DIST = 160.0D;
    private static final int WINDOW_CLOSE_TICKS = 2400; // > 2 minutes far → discard
    private static final float VIEW_RANGE = 2.0F;
    public static final int WAVES = 4;
    /** W13-C3 flood beat: radial travel time of the grow/shrink front (~0.83 B/t). */
    public static final int FLOOD_TRAVEL_TICKS = 36;

    /** One parked overlay display blueprint ({@code dist} = exact XZ tree distance). */
    record OverlaySpec(double x, double y, double z, BlockState state, float targetScale,
            int wave, boolean warmLight, boolean afterglowCrown, float yawDeg, double dist) {}

    private static List<OverlaySpec> specs = List.of();
    /** Largest {@code OverlaySpec.dist} of the set (the flood front's outer edge). */
    private static double distMax = 1.0D;
    private static final List<Display.BlockDisplay> POOL = new ArrayList<>();
    private static int spawnCursor;
    private static boolean windowOpen;
    private static int farTicks;
    private static final List<Display.BlockDisplay> FINALE_BLOOM = new ArrayList<>();

    private EchoOverlayBuilder() {}

    // ------------------------------------------------------------------ window driver

    /**
     * Per-tick window driver (called from {@code MemoryFloodService}): opens within
     * {@value #WINDOW_OPEN_DIST} of the tree (batch-spawn), discards after
     * {@value #WINDOW_CLOSE_TICKS} beyond {@value #WINDOW_CLOSE_DIST}.
     */
    public static void tickWindow(ServerLevel level, BlockPos tree, boolean finaleDone) {
        double near = Double.MAX_VALUE;
        for (ServerPlayer player : level.players()) {
            near = Math.min(near, player.position().distanceToSqr(
                    tree.getX() + 0.5D, tree.getY(), tree.getZ() + 0.5D));
        }
        if (!windowOpen) {
            if (near <= WINDOW_OPEN_DIST * WINDOW_OPEN_DIST) {
                openWindow(level, tree);
            }
            return;
        }
        if (near > WINDOW_CLOSE_DIST * WINDOW_CLOSE_DIST) {
            if (++farTicks > WINDOW_CLOSE_TICKS) {
                discardPool();
            }
            return;
        }
        farTicks = 0;
        spawnBatch(level, tree, finaleDone);
    }

    private static void openWindow(ServerLevel level, BlockPos tree) {
        windowOpen = true;
        farTicks = 0;
        spawnCursor = 0;
        // Despawn-guarantee sweep: any tagged display from a previous session dies
        // before the deterministic rebuild (no duplicates after restart).
        int swept = 0;
        for (var stray : level.getEntities(EntityType.BLOCK_DISPLAY,
                e -> e.getTags().contains(OVERLAY_TAG))) {
            stray.discard();
            swept++;
        }
        if (swept > 0) {
            EclipseMod.LOGGER.debug("EchoOverlayBuilder: swept {} stale overlay display(s)", swept);
        }
        if (specs.isEmpty()) {
            specs = buildSpecs(tree);
            EclipseMod.LOGGER.info("EchoOverlayBuilder: {} overlay spec(s) derived", specs.size());
        }
    }

    private static void spawnBatch(ServerLevel level, BlockPos tree, boolean finaleDone) {
        int budget = SPAWN_PER_TICK;
        while (budget-- > 0 && spawnCursor < specs.size()) {
            OverlaySpec spec = specs.get(spawnCursor);
            Display.BlockDisplay display = EntityType.BLOCK_DISPLAY.create(level);
            if (display == null) {
                return; // retry same index next tick
            }
            display.moveTo(spec.x(), spec.y(), spec.z(), 0.0F, 0.0F);
            display.setBlockState(spec.state());
            display.addTag(OVERLAY_TAG);
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(0);
            display.setTransformation(pose(spec, parkScale(spec, finaleDone)));
            level.addFreshEntity(display);
            DisplayBrightnessFx.setViewRange(display, VIEW_RANGE);
            if (finaleDone && spec.warmLight()) {
                DisplayBrightnessFx.set(display, 14, 10, VIEW_RANGE);
            }
            POOL.add(display);
            spawnCursor++;
        }
    }

    /** Idle scale of a spec (park floor, or the afterglow floors after the finale). */
    private static float parkScale(OverlaySpec spec, boolean finaleDone) {
        if (finaleDone) {
            if (spec.afterglowCrown()) {
                return 0.8F;
            }
            if (spec.warmLight()) {
                return 0.2F;
            }
        }
        return PARK_SCALE;
    }

    public static void discardPool() {
        for (Display.BlockDisplay display : POOL) {
            display.discard();
        }
        POOL.clear();
        for (Display.BlockDisplay display : FINALE_BLOOM) {
            display.discard();
        }
        FINALE_BLOOM.clear();
        spawnCursor = 0;
        windowOpen = false;
        farTicks = 0;
    }

    /** Pool fully parked again (dev reset / afterglow floor re-park). */
    public static void reparkAll(boolean finaleDone) {
        for (int i = 0; i < POOL.size() && i < specs.size(); i++) {
            Display.BlockDisplay display = POOL.get(i);
            if (display.isRemoved()) {
                continue;
            }
            OverlaySpec spec = specs.get(i);
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(10);
            display.setTransformation(pose(spec, parkScale(spec, finaleDone)));
        }
    }

    public static boolean poolReady() {
        return windowOpen && spawnCursor >= specs.size() && !specs.isEmpty();
    }

    public static int poolSize() {
        return POOL.size();
    }

    public static int poolTarget() {
        return specs.size();
    }

    // ------------------------------------------------------------------ flood pushes

    /**
     * One flood wave push (plan §5.2): every display of {@code wave} gets ONE
     * interpolated transform to target ({@code grow=true}) or back to its park
     * scale over {@code windowTicks}.
     *
     * <p>W13-C3 flood beat: the push carries a per-display interpolation DELAY —
     * {@code dist/distMax ×} {@value #FLOOD_TRAVEL_TICKS} t growing (inside-out),
     * mirrored shrinking (outside-in, the flood retreats INTO the tree) — minus the
     * wave's own dispatch tick, so the four band pushes fuse into one seam-free
     * continuous front. Zero extra packets: the delay rides the same push.</p>
     */
    public static void pushWave(int wave, boolean grow, int windowTicks, boolean finaleDone) {
        double outerEdge = Math.max(1.0D, distMax);
        for (int i = 0; i < POOL.size() && i < specs.size(); i++) {
            OverlaySpec spec = specs.get(i);
            if (spec.wave() != wave) {
                continue;
            }
            Display.BlockDisplay display = POOL.get(i);
            if (display.isRemoved()) {
                continue;
            }
            double fraction = grow ? spec.dist() / outerEdge : 1.0D - spec.dist() / outerEdge;
            int delay = Mth.clamp(
                    (int) Math.round(fraction * FLOOD_TRAVEL_TICKS) - wave,
                    0, FLOOD_TRAVEL_TICKS);
            display.setTransformationInterpolationDelay(delay);
            display.setTransformationInterpolationDuration(windowTicks);
            display.setTransformation(pose(spec,
                    grow ? spec.targetScale() : parkScale(spec, finaleDone)));
        }
    }

    /**
     * Brightness step on the warm-light group (≤ 3 steps per flood — the
     * DisplayBrightnessFx craft law: steps hide in the growth motion).
     */
    public static void brightnessStep(boolean set) {
        for (int i = 0; i < POOL.size() && i < specs.size(); i++) {
            OverlaySpec spec = specs.get(i);
            if (!spec.warmLight()) {
                continue;
            }
            Display.BlockDisplay display = POOL.get(i);
            if (display.isRemoved()) {
                continue;
            }
            if (set) {
                DisplayBrightnessFx.set(display, 14, 10, VIEW_RANGE);
            } else {
                DisplayBrightnessFx.clear(display);
            }
        }
    }

    // ------------------------------------------------------------------ finale bloom

    /**
     * The finale blossom set (plan §5.3): ~120 displays only at the memory tree,
     * spawned in one batch (finale is a one-time event), scale-in over 60t. After
     * the hold, {@link #settleFinaleBloom} keeps the 30-display afterglow subset.
     */
    public static void spawnFinaleBloom(ServerLevel level, BlockPos tree) {
        if (!FINALE_BLOOM.isEmpty()) {
            return;
        }
        long seed = FrozenParams.mapSeed() ^ 0x0EC0B100L;
        BlockState cherry = Blocks.CHERRY_LEAVES.defaultBlockState()
                .setValue(LeavesBlock.PERSISTENT, true);
        BlockState petals = Blocks.PINK_PETALS.defaultBlockState();
        BlockState light = Blocks.OCHRE_FROGLIGHT.defaultBlockState();
        for (int i = 0; i < 120; i++) {
            int h = EchoGroveTerraformer.hash(seed, i, 53, 12);
            double angle = (h & 1023) / 1024.0D * Math.PI * 2.0D;
            double radius = 1.2D + ((h >> 10) & 255) / 255.0D * 3.6D;
            double y = tree.getY() + 8.0D + ((h >> 18) & 63) / 63.0D * 4.0D;
            BlockState state = i < 12 ? light : ((h & 2) == 0 ? cherry : petals);
            Display.BlockDisplay display = EntityType.BLOCK_DISPLAY.create(level);
            if (display == null) {
                continue;
            }
            display.moveTo(tree.getX() + 0.5D + Math.cos(angle) * radius, y,
                    tree.getZ() + 0.5D + Math.sin(angle) * radius, 0.0F, 0.0F);
            display.setBlockState(state);
            display.addTag(OVERLAY_TAG);
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(0);
            float target = i < 12 ? 0.35F : 0.7F + ((h >> 24) & 31) / 62.0F;
            display.setTransformation(poseAt(target * 0.0F + PARK_SCALE, (h & 255) * 1.4F));
            level.addFreshEntity(display);
            DisplayBrightnessFx.set(display, 13, 9, VIEW_RANGE);
            FINALE_BLOOM.add(display);
            // The grow-in: one interpolated push right after the park spawn.
            display.setTransformationInterpolationDelay(1);
            display.setTransformationInterpolationDuration(60);
            display.setTransformation(poseAt(target, (h & 255) * 1.4F));
        }
    }

    /** Finale hold over: 30 displays stay (the forever-bloomed tree), the rest shrink out. */
    public static void settleFinaleBloom() {
        for (int i = 0; i < FINALE_BLOOM.size(); i++) {
            Display.BlockDisplay display = FINALE_BLOOM.get(i);
            if (display.isRemoved()) {
                continue;
            }
            if (i % 4 == 0) {
                continue; // the afterglow subset stays as pushed
            }
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(40);
            display.setTransformation(poseAt(PARK_SCALE, 0.0F));
        }
    }

    // ------------------------------------------------------------------ specs

    private static Transformation pose(OverlaySpec spec, float scale) {
        return poseAt(scale, spec.yawDeg());
    }

    private static Transformation poseAt(float scale, float yawDeg) {
        Quaternionf rotation = new Quaternionf().rotationY(yawDeg * ((float) Math.PI / 180.0F));
        Vector3f half = new Vector3f(scale * 0.5F);
        Vector3f translation = rotation.transform(half, new Vector3f()).negate();
        return new Transformation(translation, rotation, new Vector3f(scale), new Quaternionf());
    }

    /** Radius wave of a grove offset (the past blooms outward from the tree). */
    private static int waveOf(double dx, double dz) {
        double dist = Math.hypot(dx, dz);
        if (dist < 8.0D) {
            return 0;
        }
        if (dist < 15.0D) {
            return 1;
        }
        if (dist < 22.0D) {
            return 2;
        }
        return 3;
    }

    /** Spec factory: derives the exact XZ tree distance (the flood-front delay read). */
    private static OverlaySpec spec(BlockPos tree, double x, double y, double z,
            BlockState state, float targetScale, int wave, boolean warmLight,
            boolean afterglowCrown, float yawDeg) {
        double dist = Math.hypot(x - (tree.getX() + 0.5D), z - (tree.getZ() + 0.5D));
        return new OverlaySpec(x, y, z, state, targetScale, wave, warmLight,
                afterglowCrown, yawDeg, dist);
    }

    /**
     * Deterministic overlay set (plan §5.2 table): bleached-tree crowns (~330),
     * memory-tree crown (60 + 8 light fruit), flower carpet (~160), warm lights
     * (~30) and scene garnish (~40) — ~620 total. Same seed + hash family as the
     * terraformer, so overlays sit exactly on the real trees.
     */
    private static List<OverlaySpec> buildSpecs(BlockPos tree) {
        long seed = FrozenParams.mapSeed() ^ 0x0EC0_6807EL;
        BlockPos groveCenter = tree.above(EchoGroveLayout.BOWL_DEPTH);
        List<OverlaySpec> list = new ArrayList<>(640);
        BlockState paleLeaves = dev.projecteclipse.eclipse.registry.PaleGardenBlocks
                .PALE_OAK_LEAVES.get().defaultBlockState();
        BlockState birch = Blocks.BIRCH_LEAVES.defaultBlockState()
                .setValue(LeavesBlock.PERSISTENT, true);
        BlockState azalea = Blocks.FLOWERING_AZALEA_LEAVES.defaultBlockState()
                .setValue(LeavesBlock.PERSISTENT, true);
        BlockState froglight = Blocks.OCHRE_FROGLIGHT.defaultBlockState();

        // 1. Crowns of the bleached trees (10–14 each; golden-phase rotated —
        //    neighbors never grow in sync, the BD-SHIP law).
        List<int[]> trees = EchoGroveTerraformer.treeOffsets(seed);
        int crownIndex = 0;
        for (int t = 0; t < trees.size(); t++) {
            int[] offset = trees.get(t);
            boolean old = (t == 0) || ((t + 1) % 5 == 0);
            int height = EchoGroveTerraformer.treeHeight(seed, offset[0], offset[1], old);
            int floorY = groveCenter.getY() - EchoGroveTerraformer.bowlDepth(
                    Math.hypot(offset[0], offset[1]));
            int crowns = 10 + Math.floorMod(
                    EchoGroveTerraformer.hash(seed, offset[0], offset[1], 20), 5);
            for (int c = 0; c < crowns; c++) {
                int h = EchoGroveTerraformer.hash(seed, crownIndex, c, 21);
                double angle = (h & 1023) / 1024.0D * Math.PI * 2.0D;
                double radius = 0.6D + ((h >> 10) & 255) / 255.0D * 2.2D;
                double y = floorY + height + 0.5D + (((h >> 18) & 63) / 63.0D - 0.35D) * 3.0D;
                int roll = Math.floorMod(h >> 6, 100);
                BlockState state = roll < 60 ? paleLeaves : (roll < 85 ? birch : azalea);
                float target = 1.6F + ((h >> 24) & 31) / 31.0F * 0.8F;
                list.add(spec(tree,
                        groveCenter.getX() + offset[0] + 0.5D + Math.cos(angle) * radius,
                        y,
                        groveCenter.getZ() + offset[1] + 0.5D + Math.sin(angle) * radius,
                        state, target, waveOf(offset[0], offset[1]), false,
                        (crownIndex + c) % 7 == 0, (h & 255) * 1.4F));
                crownIndex++;
            }
        }

        // 2. Memory-tree crown: 60 leaves + 8 ochre "light fruit".
        for (int i = 0; i < 68; i++) {
            int h = EchoGroveTerraformer.hash(seed, i, 22, 22);
            double angle = (h & 1023) / 1024.0D * Math.PI * 2.0D;
            double radius = 1.0D + ((h >> 10) & 255) / 255.0D * 4.0D;
            double y = tree.getY() + EchoGroveLayout.TREE_HEIGHT - 3.0D
                    + ((h >> 18) & 63) / 63.0D * 5.0D;
            boolean fruit = i >= 60;
            float target = fruit ? 0.5F : 1.8F + ((h >> 24) & 31) / 31.0F * 0.8F;
            list.add(spec(tree,
                    tree.getX() + 0.5D + Math.cos(angle) * radius, y,
                    tree.getZ() + 0.5D + Math.sin(angle) * radius,
                    fruit ? froglight : (((h & 4) == 0) ? azalea : paleLeaves),
                    target, 0, false, i % 5 == 0, (h & 255) * 1.4F));
        }

        // 3. Flower/grass carpet on the core floor (~160).
        BlockState[] carpet = {
                Blocks.PEONY.defaultBlockState(), Blocks.LILAC.defaultBlockState(),
                Blocks.OXEYE_DAISY.defaultBlockState(), Blocks.SHORT_GRASS.defaultBlockState(),
                Blocks.MOSS_CARPET.defaultBlockState()};
        for (int i = 0; i < 160; i++) {
            int h = EchoGroveTerraformer.hash(seed, i, 23, 23);
            double angle = (h & 1023) / 1024.0D * Math.PI * 2.0D;
            double radius = 2.5D + ((h >> 10) & 511) / 511.0D * 15.0D;
            double dx = Math.cos(angle) * radius;
            double dz = Math.sin(angle) * radius;
            int floorY = groveCenter.getY() - EchoGroveTerraformer.bowlDepth(radius);
            list.add(spec(tree,
                    groveCenter.getX() + 0.5D + dx, floorY + 1.02D, groveCenter.getZ() + 0.5D + dz,
                    carpet[Math.floorMod(h >> 20, carpet.length)],
                    0.9F + ((h >> 24) & 31) / 31.0F * 0.3F,
                    waveOf(dx, dz), false, false, 0.0F));
        }

        // 4. Warm light (~30 froglights, scale 0.3) at lantern posts / bench / cart.
        int[][] lightSpots = {
                EchoScenes.LANTERN_POSTS[0], EchoScenes.LANTERN_POSTS[1],
                EchoScenes.LANTERN_POSTS[2], {10, 16}, {20, -6}, {-6, -18}};
        int lightIndex = 0;
        for (int[] spot : lightSpots) {
            for (int i = 0; i < 5; i++) {
                int h = EchoGroveTerraformer.hash(seed, lightIndex, 24, 24);
                double ox = ((h & 63) / 63.0D - 0.5D) * 2.4D;
                double oz = (((h >> 6) & 63) / 63.0D - 0.5D) * 2.4D;
                int floorY = groveCenter.getY() - EchoGroveTerraformer.bowlDepth(
                        Math.hypot(spot[0], spot[1]));
                double y = floorY + 1.6D + ((h >> 12) & 63) / 63.0D * 2.2D;
                list.add(spec(tree,
                        groveCenter.getX() + spot[0] + 0.5D + ox, y,
                        groveCenter.getZ() + spot[1] + 0.5D + oz,
                        froglight, 0.3F, waveOf(spot[0], spot[1]), true, false, 0.0F));
                lightIndex++;
            }
        }

        // 5. Scene garnish (~40): flower box on the cart, ivy leaves at the rock,
        //    wool cushions on the bench.
        for (int i = 0; i < 12; i++) {
            int h = EchoGroveTerraformer.hash(seed, i, 25, 25);
            int floorY = groveCenter.getY() - EchoGroveTerraformer.bowlDepth(Math.hypot(20, -6));
            list.add(spec(tree,
                    groveCenter.getX() + 20 + 0.2D + (i % 4) * 0.35D, floorY + 2.1D,
                    groveCenter.getZ() - 6 + 0.2D + (i / 4) * 0.35D,
                    (h & 1) == 0 ? Blocks.PEONY.defaultBlockState()
                            : Blocks.OXEYE_DAISY.defaultBlockState(),
                    0.4F, waveOf(20, -6), false, false, 0.0F));
        }
        for (int i = 0; i < 20; i++) {
            int h = EchoGroveTerraformer.hash(seed, i, 26, 26);
            int floorY = groveCenter.getY() - EchoGroveTerraformer.bowlDepth(Math.hypot(18, -10));
            list.add(spec(tree,
                    groveCenter.getX() + 17.0D + ((h & 63) / 63.0D) * 4.0D,
                    floorY + 1.2D + (((h >> 6) & 63) / 63.0D) * 2.6D,
                    groveCenter.getZ() - 11.0D + (((h >> 12) & 63) / 63.0D) * 3.0D,
                    azalea, 0.5F + ((h >> 18) & 31) / 31.0F * 0.5F,
                    waveOf(18, -10), false, false, (h & 255) * 1.4F));
        }
        for (int i = 0; i < 2; i++) {
            int floorY = groveCenter.getY() - EchoGroveTerraformer.bowlDepth(Math.hypot(10, 16));
            list.add(spec(tree,
                    groveCenter.getX() + 9.3D + i * 1.2D, floorY + 1.55D,
                    groveCenter.getZ() + 16.5D,
                    Blocks.WHITE_WOOL.defaultBlockState(), 0.4F,
                    waveOf(10, 16), false, false, 0.0F));
        }
        // W13-C3: the flood front's outer edge — every delay normalizes against it.
        double max = 1.0D;
        for (OverlaySpec overlaySpec : list) {
            max = Math.max(max, overlaySpec.dist());
        }
        distMax = max;
        return List.copyOf(list);
    }
}
