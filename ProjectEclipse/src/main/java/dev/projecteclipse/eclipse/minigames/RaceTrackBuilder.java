package dev.projecteclipse.eclipse.minigames;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.ChatFormatting;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.network.chat.Component;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.item.DyeColor;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.StairBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;

/**
 * F-061: the Legacy-style speedway of the {@code race} minigame — a hand-authored,
 * closed ~385-block circuit generated block by block into the void dimension
 * {@code eclipse:minigame_sky}. The minigames carry no baked region payloads like the
 * xbox worlds do; every course is a pure {@code seed → List<Placement>} function written
 * by {@link CourseBlocks}, so THIS CLASS IS THE MAP FILE.
 *
 * <p><b>Layout</b> — "Eclipse Speedway", a teardrop circuit driven anticlockwise on the
 * map, 7 blocks of racing surface plus kerbs and a wall/fence boundary, over three height
 * levels (y 64 → 76 → 64):</p>
 * <ol>
 *   <li><b>Start/finish straight</b> (y 64): the gantry with two beacon pillars, banner
 *       masts, a checkered line, the five-lamp redstone start rig
 *       ({@link Track#lightSwitches()} is toggled by {@link LegacyRace}) and the
 *       signboards, with a four-tier grandstand along the outside.</li>
 *   <li><b>Blue-ice boost straight</b> (flat, y 64) feeding the fast right-hander.</li>
 *   <li><b>The climb</b> around the wide east end, y 64 → 76 (max grade 1:6).</li>
 *   <li><b>The bridge</b> (flat, y 76) over a water course built 14 blocks below, with
 *       stone-brick railings and pylons down to the river bed — and the second blue-ice
 *       boost, so the crossing is taken at full speed.</li>
 *   <li><b>The chicane</b> on the descent, honey blocks on both apexes.</li>
 *   <li><b>The hairpin</b> at the western point (radius ≈ 13, back at y 64), honey on the
 *       inside line, its own grandstand.</li>
 * </ol>
 *
 * <p>Seven colored wool checkpoint arches mark the lap (index 0 IS the start/finish
 * gate); their centers ({@link Checkpoint}) are what {@link LegacyRace} tests the path
 * actually run against. The geometry is fully deterministic — the seed only drives
 * cosmetic accents (banner colors), never the racing line — so the clear-then-rebuild in
 * {@link MinigameService} always rewrites exactly the same blocks.</p>
 *
 * <p><b>Write order matters.</b> The sweep runs in three passes ({@link Pass}) so a
 * half-step ramp or a foundation can never claim a position the racing surface needs one
 * sample later: SURFACE first, RAMP second, TRIM (foundations, boundary, decor) last.
 * Inside a pass the {@link Canvas} is first-writer-wins.</p>
 */
public final class RaceTrackBuilder {

    /** One checkpoint gate; index 0 is the start/finish line and closes the lap. */
    public record Checkpoint(int index, Vec3 center, float yaw, DyeColor color) {}

    /** Everything the race logic needs about the built circuit. */
    public record Track(List<CourseBlocks.Placement> blocks, List<Checkpoint> checkpoints,
            List<Vec3> gridSpots, float startYaw, List<BlockPos> lightSwitches,
            List<MinigameSigns.SignSpec> signs, Vec3 paddock, float paddockYaw,
            double lapLength) {}

    /** Sweep passes — see the class comment for why the order is load-bearing. */
    private enum Pass { SURFACE, RAMP, TRIM }

    // ------------------------------------------------------------------ geometry constants

    /** Circuit centerline waypoints {@code {x, y, z}} — a CLOSED Catmull-Rom spline. */
    private static final double[][] WAYPOINTS = {
            {-70, 64, -14},   //  0 hairpin exit, run-up to the start/finish line
            {-52, 64, -28},   //  1 grid
            {-28, 64, -38},   //  2 START/FINISH
            {  0, 64, -42},   //  3 ice boost straight
            { 26, 65, -42},   //  4
            { 48, 67, -36},   //  5 turn 1
            { 64, 69, -22},   //  6 the climb
            { 72, 72,  -2},   //  7
            { 68, 75,  18},   //  8 crest
            { 54, 76,  34},   //  9 bridge run-in
            { 32, 76,  42},   // 10 bridge over the water course
            { 10, 75,  44},   // 11
            { -8, 73,  42},   // 12 chicane entry
            {-22, 71,  34},   // 13 chicane kink
            {-36, 69,  38},   // 14 chicane exit
            {-54, 66,  32},   // 15 hairpin approach
            {-70, 64,  18},   // 16 hairpin
            {-78, 64,   2},   // 17 hairpin apex
    };

    /** Sample step in spline parameter (≈ 0.2 blocks of arc) — the surface stays gapless. */
    private static final double T_STEP = 0.01D;
    /** Lateral sample step; finer than a block so diagonals stay watertight. */
    private static final double O_STEP = 0.4D;
    /** Half width of the racing surface (7 blocks wide). */
    private static final double ROAD_HALF = 3.4D;
    /** Half width including the kerbs. */
    private static final double KERB_HALF = 4.4D;
    /** Half width including the boundary strip the fence/wall stands on. */
    private static final double EDGE_HALF = 5.2D;

    /**
     * Blue-ice boost stretches {@code {fromT, toT}} — the two "throttle pinned" zones.
     * Both MUST stay inside a flat waypoint span (equal heights at both ends): a full ice
     * block cannot follow the half-step ramp the rest of the surface climbs on, so ice on
     * a slope would leave steps in the racing line.
     */
    private static final double[][] ICE_ZONES = {
            {2.45D, 3.30D},  // the long start/finish straight (y 64, waypoints 2 → 3)
            {9.30D, 9.98D},  // the bridge deck (y 76, waypoints 9 → 10) into the descent
    };
    private static final double BRIDGE_FROM = 9.25D;
    private static final double BRIDGE_TO = 10.85D;

    /** Honey hazards {@code {t, halfWindow, offsetMin, offsetMax}} (offset = lateral). */
    private static final double[][] HONEY_PATCHES = {
            {12.95D, 0.20D, 0.6D, 3.4D},   // chicane apex 1
            {13.95D, 0.20D, -3.4D, -0.6D}, // chicane apex 2
            {17.05D, 0.28D, 1.2D, 3.4D},   // hairpin inside line
    };

    /** Checkpoint spline parameters; index 0 is the start/finish line. */
    private static final double[] CHECKPOINT_T = {2.0D, 4.6D, 7.2D, 9.0D, 11.8D, 14.2D, 16.6D};
    private static final DyeColor[] CHECKPOINT_COLORS = {
            DyeColor.WHITE, DyeColor.LIME, DyeColor.YELLOW, DyeColor.LIGHT_BLUE,
            DyeColor.MAGENTA, DyeColor.ORANGE, DyeColor.PINK};

    /** Grid rows behind the start line (blocks of arc) and their lateral lane offsets. */
    private static final double[] GRID_ROW_DISTANCE = {5.0D, 10.0D, 15.0D, 20.0D};
    private static final double[] GRID_LANES = {-2.2D, 0.0D, 2.2D};

    /** The water course under the bridge — in a void dimension it is a BUILT basin. */
    private static final int WATER_MIN_X = 22;
    private static final int WATER_MAX_X = 38;
    private static final int WATER_MIN_Z = 24;
    private static final int WATER_MAX_Z = 56;
    private static final int WATER_BED_Y = 60;
    private static final int WATER_TOP_Y = 62;

    /** Start-light rig: five lamps hanging under the gantry beam. */
    private static final int START_LIGHT_COUNT = 5;
    private static final int GANTRY_HEIGHT = 6;
    /** Height of the paddock platform inside the circuit (finishers + late joiners). */
    private static final int PADDOCK_Y = 78;

    /**
     * Below this a racer is rescued back to their last checkpoint. The lowest racing
     * surface stands at y 65 and the water course tops out at {@value #WATER_TOP_Y}, so
     * this one line catches both a fall off the bridge and a swim in the river.
     */
    public static final int FALL_RESCUE_Y = 63;

    private static int cachedSeed = Integer.MIN_VALUE;
    private static Track cachedTrack;

    private RaceTrackBuilder() {}

    // ------------------------------------------------------------------ public API

    /** Deterministic circuit for {@code seed} (single-entry cache, server thread only). */
    public static Track build(int seed) {
        if (cachedTrack == null || cachedSeed != seed) {
            cachedTrack = generate(seed);
            cachedSeed = seed;
        }
        return cachedTrack;
    }

    /** Drops the cached track (server stop / event close). */
    static void invalidateCache() {
        cachedTrack = null;
        cachedSeed = Integer.MIN_VALUE;
    }

    /** Course bounds for the close-time entity sweep — track, stands, water and paddock. */
    public static AABB bounds() {
        return new AABB(-110, 40, -85, 105, 130, 85);
    }

    // ------------------------------------------------------------------ spline

    /**
     * Closed Catmull-Rom point at parameter {@code t} (wraps at the waypoint count).
     *
     * <p>The racing line is splined in XZ, but the ELEVATION is interpolated linearly: a
     * spline overshoots between two waypoints of equal height, and a stretch that dips to
     * y 63.99 is a stretch that half-steps. That is invisible on asphalt (the ramp pass
     * levels it out with slabs) but it cannot be levelled under a full block of blue ice,
     * which is how the boost straights ended up with 1-block steps in them. Linear height
     * keeps every flat waypoint span EXACTLY flat.</p>
     */
    private static Vec3 pointAt(double t) {
        int n = WAYPOINTS.length;
        int i = Mth.floor(t);
        double f = t - i;
        double[] p0 = WAYPOINTS[Math.floorMod(i - 1, n)];
        double[] p1 = WAYPOINTS[Math.floorMod(i, n)];
        double[] p2 = WAYPOINTS[Math.floorMod(i + 1, n)];
        double[] p3 = WAYPOINTS[Math.floorMod(i + 2, n)];
        return new Vec3(spline(p0[0], p1[0], p2[0], p3[0], f),
                Mth.lerp(f, p1[1], p2[1]),
                spline(p0[2], p1[2], p2[2], p3[2], f));
    }

    private static double spline(double a0, double a1, double a2, double a3, double f) {
        double f2 = f * f;
        double f3 = f2 * f;
        return 0.5D * (2.0D * a1 + (-a0 + a2) * f
                + (2.0D * a0 - 5.0D * a1 + 4.0D * a2 - a3) * f2
                + (-a0 + 3.0D * a1 - 3.0D * a2 + a3) * f3);
    }

    /** Unit racing direction in XZ at {@code t}. */
    private static Vec3 tangentAt(double t) {
        Vec3 ahead = pointAt(t + 0.01D);
        Vec3 behind = pointAt(t - 0.01D);
        Vec3 delta = new Vec3(ahead.x - behind.x, 0.0D, ahead.z - behind.z);
        return delta.lengthSqr() < 1.0E-9D ? new Vec3(1.0D, 0.0D, 0.0D) : delta.normalize();
    }

    /** Lateral unit vector; POSITIVE offsets point to the INSIDE of the circuit. */
    private static Vec3 sideAt(double t) {
        Vec3 tangent = tangentAt(t);
        return new Vec3(-tangent.z, 0.0D, tangent.x);
    }

    /** Minecraft yaw of the racing direction at {@code t}. */
    private static float yawAt(double t) {
        Vec3 tangent = tangentAt(t);
        return (float) Math.toDegrees(Math.atan2(-tangent.x, tangent.z));
    }

    /** Walking surface (feet height) of the racing line at {@code t}. */
    private static double surfaceAt(double t) {
        double y = pointAt(t).y;
        int base = Mth.floor(y);
        return base + (isHalfStep(y) ? 1.5D : 1.0D);
    }

    /** Whether the centerline sits high enough in its block to carry a slab ramp. */
    private static boolean isHalfStep(double y) {
        return y - Mth.floor(y) >= 0.5D;
    }

    // ------------------------------------------------------------------ generation

    private static Track generate(int seed) {
        RandomSource rand = RandomSource.create(seed * 31L + 7L);
        Canvas canvas = new Canvas();

        double lapLength = sweep(canvas, rand, Pass.SURFACE, T_STEP);
        // The ramp pass runs at quadruple resolution: right on a half-step transition the
        // coarse sweep can skip a single cell, and a missing slab there is a pothole.
        sweep(canvas, rand, Pass.RAMP, T_STEP / 4.0D);
        sweep(canvas, rand, Pass.TRIM, T_STEP);

        List<Checkpoint> checkpoints = new ArrayList<>();
        for (int i = 0; i < CHECKPOINT_T.length; i++) {
            double t = CHECKPOINT_T[i];
            Vec3 center = pointAt(t);
            checkpoints.add(new Checkpoint(i, new Vec3(center.x, surfaceAt(t) + 1.0D, center.z),
                    yawAt(t), CHECKPOINT_COLORS[i]));
            if (i > 0) {
                layCheckpointArch(canvas, t, CHECKPOINT_COLORS[i]);
            }
        }

        List<BlockPos> lightSwitches = new ArrayList<>();
        List<MinigameSigns.SignSpec> signs = new ArrayList<>();
        layStartGantry(canvas, rand, lightSwitches, signs);
        layGrandstand(canvas, rand, 2.15D, 3.85D);
        layGrandstand(canvas, rand, 16.25D, 17.65D);
        layWaterCourse(canvas);
        Vec3 paddock = layPaddock(canvas);

        List<CourseBlocks.Placement> placements = new ArrayList<>(canvas.map.size());
        canvas.map.forEach((pos, state) -> placements.add(new CourseBlocks.Placement(pos, state)));
        EclipseMod.LOGGER.info(
                "Legacy race circuit generated for seed {}: {} blocks, lap {} blocks, {} checkpoints",
                seed, placements.size(), (int) lapLength, checkpoints.size());
        return new Track(List.copyOf(placements), List.copyOf(checkpoints), gridSpots(),
                yawAt(CHECKPOINT_T[0]), List.copyOf(lightSwitches), List.copyOf(signs),
                paddock, yawAt(CHECKPOINT_T[0]) + 180.0F, lapLength);
    }

    /**
     * Sweeps the whole circuit once for {@code pass} and returns the lap length in blocks
     * (only the SURFACE pass measures — the others retrace the identical parametrization).
     */
    private static double sweep(Canvas canvas, RandomSource rand, Pass pass, double step) {
        BlockState asphalt = Blocks.SMOOTH_STONE.defaultBlockState();
        BlockState bridgeDeck = Blocks.STONE_BRICKS.defaultBlockState();
        BlockState ice = Blocks.BLUE_ICE.defaultBlockState();
        BlockState honey = Blocks.HONEY_BLOCK.defaultBlockState();
        BlockState dash = Blocks.WHITE_CONCRETE.defaultBlockState();
        BlockState kerbA = Blocks.RED_CONCRETE.defaultBlockState();
        BlockState kerbB = Blocks.WHITE_CONCRETE.defaultBlockState();
        BlockState edge = Blocks.POLISHED_BLACKSTONE.defaultBlockState();
        BlockState edgeLight = Blocks.SEA_LANTERN.defaultBlockState();
        BlockState slab = Blocks.SMOOTH_STONE_SLAB.defaultBlockState();
        BlockState fence = Blocks.OAK_FENCE.defaultBlockState();
        BlockState wall = Blocks.STONE_BRICK_WALL.defaultBlockState();
        BlockState foundation = Blocks.STONE.defaultBlockState();

        double lapLength = 0.0D;
        Vec3 previous = pointAt(0.0D);
        for (double t = 0.0D; t < WAYPOINTS.length; t += step) {
            Vec3 center = pointAt(t);
            lapLength += Math.sqrt(Mth.square(center.x - previous.x)
                    + Mth.square(center.z - previous.z));
            previous = center;

            Vec3 side = sideAt(t);
            boolean onBridge = t >= BRIDGE_FROM && t <= BRIDGE_TO;
            boolean onIce = isIce(t);
            int baseY = Mth.floor(center.y);
            boolean halfStep = isHalfStep(center.y);
            boolean dashPhase = ((int) (lapLength / 2.0D)) % 2 == 0;
            boolean marker = ((int) lapLength) % 24 == 0;

            for (double offset = -EDGE_HALF; offset <= EDGE_HALF + 1.0E-6D; offset += O_STEP) {
                BlockPos pos = BlockPos.containing(center.x + side.x * offset, baseY,
                        center.z + side.z * offset);
                double absolute = Math.abs(offset);
                boolean isRoad = absolute <= ROAD_HALF;
                boolean isHoney = isRoad && isHoney(t, offset);
                switch (pass) {
                    case SURFACE -> {
                        BlockState surface;
                        if (isHoney) {
                            surface = honey;
                        } else if (isRoad && onIce) {
                            surface = ice;
                        } else if (isRoad && onBridge) {
                            surface = bridgeDeck;
                        } else if (isRoad) {
                            surface = absolute < 0.5D && dashPhase ? dash : asphalt;
                        } else if (absolute <= KERB_HALF) {
                            surface = dashPhase ? kerbA : kerbB;
                        } else {
                            surface = marker ? edgeLight : edge;
                        }
                        canvas.fill(pos, surface);
                    }
                    // A half-step ramp keeps every climb walkable at sprint speed: without
                    // it the elevation change lands as full-block steps nobody can run up.
                    case RAMP -> {
                        // The honey test has to look at the CANVAS, not just at this
                        // sample: the sweep visits every block position from several
                        // parameters, and one non-honey visit used to bury a honey block
                        // under a slab — an invisible hazard that no longer slows anybody.
                        if (halfStep && absolute <= KERB_HALF && !onIce
                                && !canvas.holds(pos, honey)) {
                            canvas.fill(pos.above(), slab);
                        }
                    }
                    case TRIM -> {
                        canvas.fill(pos.below(), foundation);
                        if (onBridge) {
                            canvas.fill(pos.below(2), foundation); // visible deck underside
                        }
                    }
                }
            }

            if (pass != Pass.TRIM) {
                continue;
            }

            // Boundary: stone-brick walls on the outside, oak fences on the inside.
            for (int signum = -1; signum <= 1; signum += 2) {
                double offset = signum * (EDGE_HALF + 0.3D);
                BlockPos base = BlockPos.containing(center.x + side.x * offset, baseY,
                        center.z + side.z * offset);
                canvas.fill(base, edge);
                canvas.fill(base.below(), foundation);
                canvas.fill(base.above(), signum < 0 ? wall : fence);
                if (onBridge) {
                    canvas.fill(base.above(2), signum < 0 ? wall : fence);
                }
            }

            // Bridge pylons down to the river bed (the water pass yields to them).
            if (onBridge && marker) {
                for (int signum = -1; signum <= 1; signum += 2) {
                    BlockPos foot = BlockPos.containing(center.x + side.x * signum * 3.0D,
                            baseY - 2, center.z + side.z * signum * 3.0D);
                    for (int y = foot.getY(); y >= WATER_BED_Y; y--) {
                        canvas.fill(new BlockPos(foot.getX(), y, foot.getZ()),
                                Blocks.STONE_BRICKS.defaultBlockState());
                    }
                }
            }

            // Lantern (or pennant) posts along the outside boundary, roughly every 24 blocks.
            if (marker && !onBridge) {
                BlockPos post = BlockPos.containing(center.x - side.x * (EDGE_HALF + 1.4D), baseY,
                        center.z - side.z * (EDGE_HALF + 1.4D));
                canvas.fill(post.below(), foundation);
                canvas.fill(post, edge);
                canvas.fill(post.above(), fence);
                canvas.fill(post.above(2), fence);
                canvas.fill(post.above(3), rand.nextInt(3) == 0
                        ? bannerFor(DyeColor.byId(rand.nextInt(16)))
                        : Blocks.LANTERN.defaultBlockState());
            }
        }
        return lapLength;
    }

    private static boolean isIce(double t) {
        for (double[] zone : ICE_ZONES) {
            if (t >= zone[0] && t <= zone[1]) {
                return true;
            }
        }
        return false;
    }

    private static boolean isHoney(double t, double offset) {
        for (double[] patch : HONEY_PATCHES) {
            if (Math.abs(t - patch[0]) <= patch[1] && offset >= patch[2] && offset <= patch[3]) {
                return true;
            }
        }
        return false;
    }

    /** Colored wool arch spanning the track — the visible checkpoint gate. */
    private static void layCheckpointArch(Canvas canvas, double t, DyeColor color) {
        Vec3 center = pointAt(t);
        Vec3 side = sideAt(t);
        int baseY = Mth.floor(center.y);
        BlockState wool = woolFor(color);
        BlockState pillar = Blocks.POLISHED_BLACKSTONE_BRICKS.defaultBlockState();
        BlockState glow = Blocks.SHROOMLIGHT.defaultBlockState();
        for (int signum = -1; signum <= 1; signum += 2) {
            double offset = signum * (EDGE_HALF + 0.9D);
            BlockPos foot = BlockPos.containing(center.x + side.x * offset, baseY + 1,
                    center.z + side.z * offset);
            for (int y = 0; y < 5; y++) {
                canvas.set(foot.above(y), y == 4 ? glow : pillar);
            }
            canvas.fill(foot.below(), Blocks.STONE.defaultBlockState());
        }
        for (double offset = -(EDGE_HALF + 0.9D); offset <= EDGE_HALF + 0.9D; offset += O_STEP) {
            BlockPos span = BlockPos.containing(center.x + side.x * offset, baseY + 6,
                    center.z + side.z * offset);
            canvas.set(span, wool);
            canvas.set(span.above(), Math.abs(offset) < 1.0D ? glow : wool);
        }
    }

    /**
     * Start/finish furniture: the checkered line, two beacon pillars, the gantry with the
     * five redstone start lamps (their switch blocks are collected for the countdown), the
     * pennant line and the circuit's signboards.
     */
    private static void layStartGantry(Canvas canvas, RandomSource rand,
            List<BlockPos> lightSwitches, List<MinigameSigns.SignSpec> signs) {
        double t = CHECKPOINT_T[0];
        Vec3 center = pointAt(t);
        Vec3 side = sideAt(t);
        Vec3 tangent = tangentAt(t);
        int baseY = Mth.floor(center.y);
        BlockState black = Blocks.BLACK_CONCRETE.defaultBlockState();
        BlockState white = Blocks.WHITE_CONCRETE.defaultBlockState();
        BlockState pillar = Blocks.POLISHED_BLACKSTONE_BRICKS.defaultBlockState();
        BlockState beam = Blocks.POLISHED_BLACKSTONE.defaultBlockState();

        // Checkered start/finish line, two blocks deep across the full road.
        for (int depth = 0; depth <= 1; depth++) {
            for (double offset = -KERB_HALF; offset <= KERB_HALF; offset += O_STEP) {
                Vec3 spot = center.add(tangent.scale(depth)).add(side.scale(offset));
                boolean dark = (Mth.floor(offset + 8.0D) + depth) % 2 == 0;
                canvas.set(BlockPos.containing(spot.x, baseY, spot.z), dark ? black : white);
            }
        }

        // The signboards face the grid, so racers read them while they wait for lights out.
        Direction towardGrid = Direction.getNearest(-tangent.x, 0.0D, -tangent.z);
        for (int signum = -1; signum <= 1; signum += 2) {
            // Beacon pillar: a 3x3 iron base is exactly a level-1 beacon → visible beam.
            Vec3 beaconSpot = center.add(side.scale(signum * (EDGE_HALF + 4.0D)));
            BlockPos beaconBase = BlockPos.containing(beaconSpot.x, baseY, beaconSpot.z);
            for (int dx = -1; dx <= 1; dx++) {
                for (int dz = -1; dz <= 1; dz++) {
                    canvas.set(beaconBase.offset(dx, 0, dz), Blocks.IRON_BLOCK.defaultBlockState());
                    canvas.fill(beaconBase.offset(dx, -1, dz), Blocks.STONE.defaultBlockState());
                }
            }
            canvas.set(beaconBase.above(), Blocks.BEACON.defaultBlockState());

            // Gantry pillar with its banner mast.
            Vec3 pillarSpot = center.add(side.scale(signum * (EDGE_HALF + 1.6D)));
            BlockPos pillarBase = BlockPos.containing(pillarSpot.x, baseY + 1, pillarSpot.z);
            for (int y = 0; y < GANTRY_HEIGHT; y++) {
                canvas.set(pillarBase.above(y), pillar);
            }
            canvas.fill(pillarBase.below(), Blocks.STONE.defaultBlockState());
            canvas.set(pillarBase.above(GANTRY_HEIGHT),
                    bannerFor(signum < 0 ? DyeColor.RED : DyeColor.LIGHT_BLUE));

            // A WALL sign: it hangs on the pillar, which a standing sign here could not.
            // The BLOCK joins the layout so a rebuild can clear it again; the TEXT is
            // written by MinigameSigns once the budgeted build has landed.
            BlockPos boardPos = pillarBase.above(2).relative(towardGrid);
            canvas.set(boardPos, MinigameSigns.wallSign(towardGrid));
            signs.add(new MinigameSigns.SignSpec(boardPos,
                    MinigameSigns.wallSign(towardGrid),
                    List.of(Component.translatable("eclipse.minigame.race.sign.title")
                                    .withStyle(ChatFormatting.DARK_RED),
                            Component.translatable("eclipse.minigame.race.sign.laps",
                                    MinigameConfig.get().raceLaps()),
                            Component.translatable("eclipse.minigame.race.sign.hint"),
                            Component.translatable("eclipse.minigame.sign.leave")),
                    DyeColor.WHITE));
        }

        // The gantry beam and the start lights. A redstone lamp placed lit without a power
        // source is switched off again by the first neighbour update, so every lamp hangs
        // under a switch block that the countdown flips to a redstone block.
        for (double offset = -(EDGE_HALF + 1.6D); offset <= EDGE_HALF + 1.6D; offset += O_STEP) {
            Vec3 spot = center.add(side.scale(offset));
            canvas.fill(BlockPos.containing(spot.x, baseY + GANTRY_HEIGHT, spot.z), beam);
        }
        for (int light = 0; light < START_LIGHT_COUNT; light++) {
            double offset = -KERB_HALF + (2.0D * KERB_HALF * light) / (START_LIGHT_COUNT - 1);
            Vec3 spot = center.add(side.scale(offset));
            BlockPos switchPos = BlockPos.containing(spot.x, baseY + GANTRY_HEIGHT, spot.z);
            canvas.set(switchPos, beam);
            canvas.set(switchPos.below(), Blocks.REDSTONE_LAMP.defaultBlockState());
            lightSwitches.add(switchPos);
        }
        // Pennants over the beam so the start reads from across the circuit.
        for (int i = 0; i < 4; i++) {
            Vec3 spot = center.add(side.scale(-KERB_HALF + i * (2.0D * KERB_HALF / 3.0D)));
            canvas.set(BlockPos.containing(spot.x, baseY + GANTRY_HEIGHT + 1, spot.z),
                    bannerFor(rand.nextBoolean() ? DyeColor.YELLOW : DyeColor.WHITE));
        }
    }

    /**
     * Four-tier grandstand outside the boundary over a stretch of the circuit, with flag
     * masts at the back. Only ever placed with {@code fill}, so it yields to the track.
     */
    private static void layGrandstand(Canvas canvas, RandomSource rand, double fromT, double toT) {
        BlockState bench = Blocks.SMOOTH_STONE.defaultBlockState();
        BlockState support = Blocks.STONE_BRICKS.defaultBlockState();
        int sample = 0;
        for (double t = fromT; t <= toT; t += 0.01D, sample++) {
            Vec3 center = pointAt(t);
            Vec3 side = sideAt(t);
            int baseY = Mth.floor(center.y);
            for (int tier = 0; tier < 4; tier++) {
                for (int cell = 0; cell < 2; cell++) {
                    // Negative offsets are OUTSIDE the circuit — that is where stands go.
                    double lateral = -(7.0D + tier * 2.0D + cell);
                    BlockPos seat = BlockPos.containing(center.x + side.x * lateral, baseY + tier,
                            center.z + side.z * lateral);
                    canvas.fill(seat, cell == 0 ? stairsToward(side) : bench);
                    for (int below = 1; below <= tier + 1; below++) {
                        canvas.fill(seat.below(below), support);
                    }
                }
            }
            if (sample % 60 == 0) {
                BlockPos mast = BlockPos.containing(center.x - side.x * 15.0D, baseY + 4,
                        center.z - side.z * 15.0D);
                for (int below = 0; below < 5; below++) {
                    canvas.fill(mast.below(below + 1), support);
                }
                for (int y = 0; y < 3; y++) {
                    canvas.fill(mast.above(y), Blocks.OAK_FENCE.defaultBlockState());
                }
                canvas.fill(mast.above(3), bannerFor(DyeColor.byId(rand.nextInt(16))));
            }
        }
    }

    /** The water course the bridge crosses — a basin built into the void with sand banks. */
    private static void layWaterCourse(Canvas canvas) {
        BlockState bed = Blocks.GRAVEL.defaultBlockState();
        BlockState bank = Blocks.SAND.defaultBlockState();
        BlockState rim = Blocks.STONE_BRICKS.defaultBlockState();
        BlockState water = Blocks.WATER.defaultBlockState();
        for (int x = WATER_MIN_X - 2; x <= WATER_MAX_X + 2; x++) {
            for (int z = WATER_MIN_Z - 2; z <= WATER_MAX_Z + 2; z++) {
                boolean outerRing = x < WATER_MIN_X || x > WATER_MAX_X
                        || z < WATER_MIN_Z || z > WATER_MAX_Z;
                for (int y = WATER_BED_Y - 1; y <= WATER_TOP_Y + 1; y++) {
                    if (outerRing) {
                        canvas.fill(new BlockPos(x, y, z), y >= WATER_TOP_Y ? bank : rim);
                    } else if (y < WATER_BED_Y) {
                        canvas.fill(new BlockPos(x, y, z), rim);
                    } else if (y == WATER_BED_Y) {
                        canvas.fill(new BlockPos(x, y, z), bed);
                    }
                }
            }
        }
        // Water fills last so the basin walls AND the bridge pylons keep their positions.
        for (int x = WATER_MIN_X; x <= WATER_MAX_X; x++) {
            for (int z = WATER_MIN_Z; z <= WATER_MAX_Z; z++) {
                for (int y = WATER_BED_Y + 1; y <= WATER_TOP_Y; y++) {
                    canvas.fill(new BlockPos(x, y, z), water);
                }
            }
        }
    }

    /**
     * Spectator paddock inside the circuit: where late joiners wait out a running heat and
     * finishers are parked. Barrier-fenced, so nobody drops back into the void.
     */
    private static Vec3 layPaddock(Canvas canvas) {
        double t = CHECKPOINT_T[0];
        Vec3 anchor = pointAt(t).add(sideAt(t).scale(26.0D));
        BlockPos middle = BlockPos.containing(anchor.x, PADDOCK_Y, anchor.z);
        BlockState floor = Blocks.POLISHED_BLACKSTONE_BRICKS.defaultBlockState();
        BlockState trim = Blocks.CHISELED_POLISHED_BLACKSTONE.defaultBlockState();
        for (int dx = -6; dx <= 6; dx++) {
            for (int dz = -6; dz <= 6; dz++) {
                boolean rim = Math.abs(dx) == 6 || Math.abs(dz) == 6;
                canvas.set(middle.offset(dx, 0, dz), rim ? trim : floor);
                if (rim) {
                    canvas.set(middle.offset(dx, 1, dz), Blocks.BARRIER.defaultBlockState());
                    canvas.set(middle.offset(dx, 2, dz), Blocks.BARRIER.defaultBlockState());
                }
            }
        }
        for (int dx = -6; dx <= 6; dx += 12) {
            for (int dz = -6; dz <= 6; dz += 12) {
                canvas.set(middle.offset(dx, 1, dz), Blocks.SEA_LANTERN.defaultBlockState());
            }
        }
        return new Vec3(middle.getX() + 0.5D, PADDOCK_Y + 1.0D, middle.getZ() + 0.5D);
    }

    /** Starting grid positions behind the start/finish line (3 lanes x 4 rows). */
    private static List<Vec3> gridSpots() {
        List<Vec3> spots = new ArrayList<>();
        for (double back : GRID_ROW_DISTANCE) {
            double t = parameterBefore(CHECKPOINT_T[0], back);
            Vec3 center = pointAt(t);
            Vec3 side = sideAt(t);
            double surface = surfaceAt(t);
            for (double lane : GRID_LANES) {
                spots.add(new Vec3(center.x + side.x * lane, surface, center.z + side.z * lane));
            }
        }
        return List.copyOf(spots);
    }

    /** Walks the spline backwards from {@code t0} by {@code distance} blocks of arc. */
    private static double parameterBefore(double t0, double distance) {
        double walked = 0.0D;
        double t = t0;
        Vec3 previous = pointAt(t);
        while (walked < distance) {
            t -= T_STEP;
            Vec3 current = pointAt(t);
            walked += Math.sqrt(Mth.square(current.x - previous.x)
                    + Mth.square(current.z - previous.z));
            previous = current;
        }
        return t;
    }

    // ------------------------------------------------------------------ block helpers

    private static BlockState stairsToward(Vec3 direction) {
        return Blocks.STONE_BRICK_STAIRS.defaultBlockState()
                .setValue(StairBlock.FACING, Direction.getNearest(direction.x, 0.0D, direction.z));
    }

    private static BlockState woolFor(DyeColor color) {
        return switch (color) {
            case WHITE -> Blocks.WHITE_WOOL.defaultBlockState();
            case ORANGE -> Blocks.ORANGE_WOOL.defaultBlockState();
            case MAGENTA -> Blocks.MAGENTA_WOOL.defaultBlockState();
            case LIGHT_BLUE -> Blocks.LIGHT_BLUE_WOOL.defaultBlockState();
            case YELLOW -> Blocks.YELLOW_WOOL.defaultBlockState();
            case LIME -> Blocks.LIME_WOOL.defaultBlockState();
            case PINK -> Blocks.PINK_WOOL.defaultBlockState();
            case GRAY -> Blocks.GRAY_WOOL.defaultBlockState();
            case LIGHT_GRAY -> Blocks.LIGHT_GRAY_WOOL.defaultBlockState();
            case CYAN -> Blocks.CYAN_WOOL.defaultBlockState();
            case PURPLE -> Blocks.PURPLE_WOOL.defaultBlockState();
            case BLUE -> Blocks.BLUE_WOOL.defaultBlockState();
            case BROWN -> Blocks.BROWN_WOOL.defaultBlockState();
            case GREEN -> Blocks.GREEN_WOOL.defaultBlockState();
            case RED -> Blocks.RED_WOOL.defaultBlockState();
            case BLACK -> Blocks.BLACK_WOOL.defaultBlockState();
        };
    }

    private static BlockState bannerFor(DyeColor color) {
        return switch (color) {
            case WHITE -> Blocks.WHITE_BANNER.defaultBlockState();
            case ORANGE -> Blocks.ORANGE_BANNER.defaultBlockState();
            case MAGENTA -> Blocks.MAGENTA_BANNER.defaultBlockState();
            case LIGHT_BLUE -> Blocks.LIGHT_BLUE_BANNER.defaultBlockState();
            case YELLOW -> Blocks.YELLOW_BANNER.defaultBlockState();
            case LIME -> Blocks.LIME_BANNER.defaultBlockState();
            case PINK -> Blocks.PINK_BANNER.defaultBlockState();
            case GRAY -> Blocks.GRAY_BANNER.defaultBlockState();
            case LIGHT_GRAY -> Blocks.LIGHT_GRAY_BANNER.defaultBlockState();
            case CYAN -> Blocks.CYAN_BANNER.defaultBlockState();
            case PURPLE -> Blocks.PURPLE_BANNER.defaultBlockState();
            case BLUE -> Blocks.BLUE_BANNER.defaultBlockState();
            case BROWN -> Blocks.BROWN_BANNER.defaultBlockState();
            case GREEN -> Blocks.GREEN_BANNER.defaultBlockState();
            case RED -> Blocks.RED_BANNER.defaultBlockState();
            case BLACK -> Blocks.BLACK_BANNER.defaultBlockState();
        };
    }

    /** Deterministic insertion-ordered block canvas: {@code set} wins, {@code fill} yields. */
    private static final class Canvas {
        private final Map<BlockPos, BlockState> map = new LinkedHashMap<>();

        void set(BlockPos pos, BlockState state) {
            map.put(pos.immutable(), state);
        }

        void fill(BlockPos pos, BlockState state) {
            map.putIfAbsent(pos.immutable(), state);
        }

        /** Whether a previous pass already claimed {@code pos} with exactly {@code state}. */
        boolean holds(BlockPos pos, BlockState state) {
            return map.get(pos) == state;
        }
    }
}
