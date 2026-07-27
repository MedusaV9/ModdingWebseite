package dev.projecteclipse.eclipse.woah.chronostasis;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import javax.annotation.Nullable;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.stage.DisplayBrightnessFx;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;

/**
 * WOAH-03 frozen-scene constructor (plan §3.1/§5): ~460 persistent
 * {@link Display.BlockDisplay} props in five groups — the frozen lightning bolt, the
 * mid-detonation explosion, the collapsing watchtower, the Chronosphere + hourglass,
 * and ambient birds/leaves. Deterministic from {@code sceneSeed}
 * ({@link RandomSource#create(long)}) so reconcile/rebuild always reproduces the same
 * scene.
 *
 * <p><b>Display laws applied</b> (ExpansionBorderFx / SanctumOrbitals / StormDebrisFx /
 * CreditsShatterAct):</p>
 * <ul>
 *   <li>Persistence model = {@code SanctumOrbitals}: props are PERSISTENT, tagged
 *       {@value #TAG} + one identity tag per prop; reconcile adopts one display per
 *       identity, discards duplicates/strays, respawns missing —
 *       {@code /kill @e[tag=eclipse_chrono_prop]} self-heals. NO boot discard sweep
 *       (that is the law for the TEMPORARY fx classes only).</li>
 *   <li>Entity position = the GROUP anchor (bolt foot, blast center, tower center,
 *       sphere center, clearing center); all placement lives in the transformation
 *       (StormDebrisFx transport: free-air light sample, a couple of chunks own
 *       everything).</li>
 *   <li>Every pose is a pure function {@link #poseOf} of {@link PoseParams} —
 *       stateless-push law: one push heals any restart/pause drift.</li>
 *   <li>{@link DisplayBrightnessFx} sets brightness + {@value #VIEW_RANGE} view range
 *       in one NBT round-trip (bolt/sphere 15/15 self-lit, debris 7/15).</li>
 *   <li>Spawn budget {@value #SPAWN_BUDGET_PER_TICK}/t (CreditsShatterAct value),
 *       hard display cap {@value #MAX_DISPLAYS}.</li>
 * </ul>
 */
public final class ChronoSceneBuilder {
    /** Collective command tag on every scene prop (scans, dev cleanup, self-heal). */
    public static final String TAG = "eclipse_chrono_prop";
    /** {@code Display.shouldRenderAtSqrDistance} multiplier: 4 × 64 = 256 blocks. */
    public static final float VIEW_RANGE = 4.0F;
    /** Hard cap (plan §3.1); the deterministic build stays well below (~460). */
    public static final int MAX_DISPLAYS = 600;
    /** Displays spawned per tick during first build / reconcile top-up. */
    public static final int SPAWN_BUDGET_PER_TICK = 60;

    /** Chronosphere ring spin: deliberately tiny — 0.8°/s = 0.04°/t ("almost stopped"). */
    public static final double RING_DEG_PER_TICK = 0.04D;

    // Site-local group anchor offsets (plan §5; single source set — client reads them
    // through ChronoStasisSite's re-exports).
    public static final int BOLT_DX = -6;
    public static final int BOLT_DZ = 2;
    public static final int BLAST_DX = -2;
    public static final int BLAST_DZ = -10;
    public static final int TOWER_DX = 14;
    public static final int TOWER_DZ = -6;
    /** Chronosphere hover height above the bowl floor at the center. */
    public static final double SPHERE_HOVER = 6.0D;

    /** The five scene groups; each prop belongs to exactly one. */
    public enum Group { BOLT, BLAST, TOWER, SPHERE, AMBIENT }

    // Per-group kind discriminators for poseOf.
    static final int KIND_DEFAULT = 0;
    static final int KIND_BOLT_ACCENT = 1;   // end-rod hot core
    static final int KIND_BLAST_SMOKE = 1;   // frozen smoke ball (rises on discharge)
    static final int KIND_SPHERE_RING = 0;   // rotating ring segment
    static final int KIND_SPHERE_CORE = 1;
    static final int KIND_SPHERE_GLASS = 2;  // hourglass cone box
    static final int KIND_SPHERE_SAND = 3;   // frozen sand stream segment
    static final int KIND_SPHERE_STATIC = 4; // sand pile / slumped top sand
    static final int KIND_BIRD_BODY = 0;
    static final int KIND_BIRD_WING = 1;
    static final int KIND_LEAF = 2;
    static final int KIND_LOG = 3;

    /**
     * One immutable scene prop. {@code offset}/{@code size}/{@code baseRot} are the
     * frozen base pose ingredients (never mutated — poseOf copies); {@code params}
     * carries the group-specific pose-function inputs documented at each build site.
     */
    public record Prop(Group group, int index, int kind, BlockState state,
            Vector3f offset, Vector3f size, Quaternionf baseRot,
            int brightnessBlock, float[] params) {

        public String identityTag() {
            return TAG + "_" + this.group.name().toLowerCase(Locale.ROOT) + "_" + this.index;
        }
    }

    /**
     * Pose-function inputs (all absolute — stateless-push law). {@code sceneTick} is the
     * frozen scene clock (0 = base pose; JOLT pushes 2 then back). The {@code *T} values
     * are the per-group DISCHARGE progress envelopes 0..1; {@code sphereT} additionally
     * accelerates the ring spin. {@code gameTime} drives the only continuous animation
     * (ring rotation).
     */
    public record PoseParams(double sceneTick, double boltT, double blastT, double towerT,
            double sphereT, long gameTime) {

        public static PoseParams frozen(long gameTime) {
            return new PoseParams(0.0D, 0.0D, 0.0D, 0.0D, 0.0D, gameTime);
        }

        public static PoseParams jolt(double sceneTick, long gameTime) {
            return new PoseParams(sceneTick, 0.0D, 0.0D, 0.0D, 0.0D, gameTime);
        }
    }

    /** Live scene bookkeeping (in-memory; the props rebuild deterministically). */
    public static final class SceneState {
        final List<Prop> props;
        final Map<String, Integer> byTag;
        final Display.BlockDisplay[] displays;
        final ArrayDeque<Integer> spawnQueue = new ArrayDeque<>();
        boolean reconciled;

        SceneState(List<Prop> props) {
            this.props = props;
            this.byTag = new HashMap<>(props.size() * 2);
            for (int i = 0; i < props.size(); i++) {
                this.byTag.put(props.get(i).identityTag(), i);
            }
            this.displays = new Display.BlockDisplay[props.size()];
        }

        public List<Prop> props() {
            return this.props;
        }

        public boolean reconciled() {
            return this.reconciled;
        }

        public int pendingSpawns() {
            return this.spawnQueue.size();
        }

        @Nullable
        public Display.BlockDisplay display(int index) {
            return this.displays[index];
        }

        public int liveCount() {
            int live = 0;
            for (Display.BlockDisplay display : this.displays) {
                if (display != null && !display.isRemoved()) {
                    live++;
                }
            }
            return live;
        }
    }

    private ChronoSceneBuilder() {}

    // ------------------------------------------------------------------ anchors

    /** World anchor of a group; {@code center} = site center at PLATEAU surface Y. */
    public static Vec3 groupAnchor(Group group, BlockPos center) {
        double cx = center.getX() + 0.5D;
        double cy = center.getY();
        double cz = center.getZ() + 0.5D;
        return switch (group) {
            case BOLT -> new Vec3(cx + BOLT_DX, floorY(cy, BOLT_DX, BOLT_DZ) + 0.1D, cz + BOLT_DZ);
            case BLAST -> new Vec3(cx + BLAST_DX, floorY(cy, BLAST_DX, BLAST_DZ) + 4.0D, cz + BLAST_DZ);
            case TOWER -> new Vec3(cx + TOWER_DX, floorY(cy, TOWER_DX, TOWER_DZ) + 8.0D, cz + TOWER_DZ);
            case SPHERE -> new Vec3(cx, floorY(cy, 0, 0) + SPHERE_HOVER, cz);
            case AMBIENT -> new Vec3(cx, cy + 0.5D, cz);
        };
    }

    /** The Chronosphere center — interaction pad + FX anchor offset target. */
    public static Vec3 sphereCenter(BlockPos center) {
        return groupAnchor(Group.SPHERE, center);
    }

    /**
     * Bowl floor Y of the carved sink at local (dx, dz) — MUST stay the mirror of
     * {@code ChronoStasisSite.bowlDepth} (the carve and the scene share one law).
     */
    public static double floorY(double plateauY, double dx, double dz) {
        return plateauY - ChronoStasisSite.bowlDepth(dx, dz);
    }

    // ------------------------------------------------------------------ deterministic build

    /** Fresh scene bookkeeping for the given seed (props are pure functions of it). */
    public static SceneState createState(long seed) {
        List<Prop> props = buildProps(seed);
        if (props.size() > MAX_DISPLAYS) {
            // Hard cap law: never exceed 600 — trim ambient garnish first (risk §11.1).
            EclipseMod.LOGGER.warn("ChronoSceneBuilder: {} props exceed the {} cap — trimming",
                    props.size(), MAX_DISPLAYS);
            props = props.subList(0, MAX_DISPLAYS);
        }
        return new SceneState(props);
    }

    /** All scene props in deterministic order (index unique per group). */
    static List<Prop> buildProps(long seed) {
        RandomSource random = RandomSource.create(seed);
        List<Prop> props = new ArrayList<>(480);
        buildBolt(random, props);
        buildBlast(random, props);
        buildTower(random, props);
        buildSphere(random, props);
        buildAmbient(random, props);
        return List.copyOf(props);
    }

    /**
     * §5.1 frozen lightning (~56 displays): a 16-segment zigzag polyline to y+55 with 3
     * branches + 4 twig tips. Each stem segment = white glass core + light-blue glass
     * shell (aura-by-transparency); every 4th stem segment adds an end-rod hot core.
     * params = [heightFrac, jitterSeed].
     */
    private static void buildBolt(RandomSource random, List<Prop> props) {
        int index = 0;
        Vector3f cursor = new Vector3f(0.0F, 0.0F, 0.0F);
        List<Vector3f> branchOrigins = new ArrayList<>();
        List<Vector3f> branchDirs = new ArrayList<>();
        for (int segment = 0; segment < 16; segment++) {
            float length = 3.2F + random.nextFloat() * 1.0F;
            float girth = 0.35F + random.nextFloat() * 0.35F;
            // Zigzag: ±8–22° around Y, ±5–12° off vertical, deterministic per segment.
            float yaw = (random.nextFloat() * 2.0F - 1.0F) * Mth.DEG_TO_RAD * (8.0F + random.nextFloat() * 14.0F) * 8.0F;
            float lean = Mth.DEG_TO_RAD * (5.0F + random.nextFloat() * 7.0F);
            Vector3f dir = new Vector3f(
                    Mth.sin(yaw) * Mth.sin(lean), Mth.cos(lean), Mth.cos(yaw) * Mth.sin(lean)).normalize();
            Vector3f mid = new Vector3f(cursor).add(new Vector3f(dir).mul(length * 0.5F));
            Quaternionf orient = new Quaternionf().rotationTo(new Vector3f(0.0F, 1.0F, 0.0F), dir);
            float heightFrac = mid.y / 55.0F;
            float jitterSeed = random.nextFloat() * Mth.TWO_PI;
            // Core + shell layering (plan §5.1 palette).
            props.add(new Prop(Group.BOLT, index++, KIND_DEFAULT,
                    Blocks.WHITE_STAINED_GLASS.defaultBlockState(), new Vector3f(mid),
                    new Vector3f(Math.max(0.15F, girth - 0.1F), length - 0.1F, Math.max(0.15F, girth - 0.1F)),
                    new Quaternionf(orient), 15, new float[] {heightFrac, jitterSeed}));
            props.add(new Prop(Group.BOLT, index++, KIND_DEFAULT,
                    Blocks.LIGHT_BLUE_STAINED_GLASS.defaultBlockState(), new Vector3f(mid),
                    new Vector3f(girth * 1.25F, length, girth * 1.25F),
                    new Quaternionf(orient), 15, new float[] {heightFrac, jitterSeed + 1.3F}));
            if (segment % 4 == 2) {
                props.add(new Prop(Group.BOLT, index++, KIND_BOLT_ACCENT,
                        Blocks.END_ROD.defaultBlockState(), new Vector3f(mid),
                        new Vector3f(0.5F, length * 0.8F, 0.5F),
                        new Quaternionf(orient), 15, new float[] {heightFrac, jitterSeed + 2.6F}));
            }
            cursor.add(new Vector3f(dir).mul(length));
            if (segment == 5 || segment == 9 || segment == 12) {
                branchOrigins.add(new Vector3f(cursor));
                float branchYaw = random.nextFloat() * Mth.TWO_PI;
                float branchLean = Mth.DEG_TO_RAD * (40.0F + random.nextFloat() * 30.0F);
                branchDirs.add(new Vector3f(
                        Mth.sin(branchYaw) * Mth.sin(branchLean), Mth.cos(branchLean),
                        Mth.cos(branchYaw) * Mth.sin(branchLean)).normalize());
            }
        }
        // 3 main branches (4 segments each) + a 2-segment twig off every branch end + 1 spare.
        List<Vector3f> twigOrigins = new ArrayList<>();
        List<Vector3f> twigDirs = new ArrayList<>();
        for (int branch = 0; branch < branchOrigins.size(); branch++) {
            Vector3f branchCursor = new Vector3f(branchOrigins.get(branch));
            Vector3f dir = new Vector3f(branchDirs.get(branch));
            for (int segment = 0; segment < 4; segment++) {
                float length = 2.0F + random.nextFloat() * 1.2F;
                dir.rotateY((random.nextFloat() - 0.5F) * 0.6F).normalize();
                Vector3f mid = new Vector3f(branchCursor).add(new Vector3f(dir).mul(length * 0.5F));
                Quaternionf orient = new Quaternionf().rotationTo(new Vector3f(0.0F, 1.0F, 0.0F), dir);
                props.add(new Prop(Group.BOLT, index++, KIND_DEFAULT,
                        Blocks.LIGHT_BLUE_STAINED_GLASS.defaultBlockState(), new Vector3f(mid),
                        new Vector3f(0.35F, length, 0.35F), new Quaternionf(orient), 15,
                        new float[] {mid.y / 55.0F, random.nextFloat() * Mth.TWO_PI}));
                branchCursor.add(new Vector3f(dir).mul(length));
            }
            twigOrigins.add(new Vector3f(branchCursor));
            twigDirs.add(new Vector3f(dir).rotateY(0.9F).normalize());
        }
        twigOrigins.add(new Vector3f(cursor));
        twigDirs.add(new Vector3f(0.4F, 0.9F, -0.2F).normalize());
        for (int twig = 0; twig < 4 && twig < twigOrigins.size(); twig++) {
            Vector3f twigCursor = new Vector3f(twigOrigins.get(twig));
            Vector3f dir = new Vector3f(twigDirs.get(twig));
            for (int segment = 0; segment < 2; segment++) {
                float length = 1.4F + random.nextFloat() * 0.8F;
                Vector3f mid = new Vector3f(twigCursor).add(new Vector3f(dir).mul(length * 0.5F));
                Quaternionf orient = new Quaternionf().rotationTo(new Vector3f(0.0F, 1.0F, 0.0F), dir);
                props.add(new Prop(Group.BOLT, index++, KIND_DEFAULT,
                        Blocks.WHITE_STAINED_GLASS.defaultBlockState(), new Vector3f(mid),
                        new Vector3f(0.2F, length, 0.2F), new Quaternionf(orient), 15,
                        new float[] {mid.y / 55.0F, random.nextFloat() * Mth.TWO_PI}));
                twigCursor.add(new Vector3f(dir).mul(length));
                dir.rotateY((random.nextFloat() - 0.5F) * 0.8F).normalize();
            }
        }
    }

    /**
     * §5.2 frozen explosion (~130 displays): three radial fragment shells around an
     * empty core (r 1.5/3/5) + a frozen smoke mushroom (40 gray glass cubes).
     * Fragment params = [dirX, dirY, dirZ, baseRadius]; smoke params = [riseSeed].
     */
    private static void buildBlast(RandomSource random, List<Prop> props) {
        int index = 0;
        int[] shellCounts = {18, 34, 38};
        float[] shellRadii = {1.5F, 3.0F, 5.0F};
        BlockState[][] shellPalettes = {
                {Blocks.MAGMA_BLOCK.defaultBlockState(), Blocks.SHROOMLIGHT.defaultBlockState()},
                {Blocks.ORANGE_STAINED_GLASS.defaultBlockState(), Blocks.RED_STAINED_GLASS.defaultBlockState(),
                        Blocks.BLACKSTONE.defaultBlockState()},
                {Blocks.COBBLESTONE.defaultBlockState(), Blocks.COAL_BLOCK.defaultBlockState(),
                        Blocks.POLISHED_BASALT.defaultBlockState()}};
        float[][] shellScales = {{0.5F, 0.9F}, {0.3F, 0.7F}, {0.2F, 0.6F}};
        for (int shell = 0; shell < 3; shell++) {
            for (int i = 0; i < shellCounts[shell]; i++) {
                // Uniform-ish random unit direction.
                float theta = random.nextFloat() * Mth.TWO_PI;
                float y = random.nextFloat() * 2.0F - 1.0F;
                float horizontal = Mth.sqrt(Math.max(0.0F, 1.0F - y * y));
                Vector3f dir = new Vector3f(Mth.cos(theta) * horizontal, y, Mth.sin(theta) * horizontal);
                float radius = shellRadii[shell] + (random.nextFloat() * 2.0F - 1.0F) * 0.8F;
                float scale = shellScales[shell][0]
                        + random.nextFloat() * (shellScales[shell][1] - shellScales[shell][0]);
                Quaternionf tumble = new Quaternionf()
                        .rotateY(random.nextFloat() * Mth.TWO_PI)
                        .rotateX((random.nextFloat() - 0.5F) * 2.0F)
                        .rotateZ((random.nextFloat() - 0.5F) * 2.0F);
                BlockState state = shellPalettes[shell][random.nextInt(shellPalettes[shell].length)];
                int brightness = shell == 0 ? 15 : 7;
                props.add(new Prop(Group.BLAST, index++, KIND_DEFAULT, state,
                        new Vector3f(dir).mul(radius), new Vector3f(scale, scale, scale),
                        tumble, brightness, new float[] {dir.x, dir.y, dir.z, radius}));
            }
        }
        // Frozen smoke mushroom: a cone drifting upward, y+5..+12 above the blast anchor.
        for (int i = 0; i < 40; i++) {
            float height = 1.0F + random.nextFloat() * 7.0F; // above blast center (y+4)
            float coneRadius = 1.0F + height * 0.55F + random.nextFloat() * 1.2F;
            float angle = random.nextFloat() * Mth.TWO_PI;
            float scale = 0.6F + random.nextFloat() * 1.0F;
            BlockState state = random.nextBoolean()
                    ? Blocks.GRAY_STAINED_GLASS.defaultBlockState()
                    : Blocks.LIGHT_GRAY_STAINED_GLASS.defaultBlockState();
            Quaternionf tumble = new Quaternionf().rotateY(random.nextFloat() * Mth.TWO_PI)
                    .rotateX((random.nextFloat() - 0.5F) * 0.6F);
            props.add(new Prop(Group.BLAST, index++, KIND_BLAST_SMOKE, state,
                    new Vector3f(Mth.cos(angle) * coneRadius, height + 1.0F, Mth.sin(angle) * coneRadius),
                    new Vector3f(scale, scale, scale), tumble, 7,
                    new float[] {random.nextFloat() * Mth.TWO_PI}));
        }
    }

    /**
     * §5.3 collapsing watchtower (~140 displays): masonry chunks + timber beams frozen
     * on ballistic arcs toward a north-west fan. params = [startX, startY, startZ,
     * dirX, dirZ, flightT0, throwDist]; walkability: y(t) = 2.2 + (startY − 2.2)(1 − t²)
     * keeps every underside ≥ 2.2 blocks over the floor. Anchor sits at stump top
     * (floor + 8), so offsets are (pos − (0, 8, 0)).
     */
    private static void buildTower(RandomSource random, List<Prop> props) {
        int index = 0;
        BlockState[] masonry = {
                Blocks.STONE_BRICKS.defaultBlockState(), Blocks.STONE_BRICKS.defaultBlockState(),
                Blocks.STONE_BRICKS.defaultBlockState(),
                Blocks.CRACKED_STONE_BRICKS.defaultBlockState(), Blocks.CRACKED_STONE_BRICKS.defaultBlockState(),
                Blocks.MOSSY_STONE_BRICKS.defaultBlockState(),
                Blocks.COBBLESTONE.defaultBlockState()};
        for (int i = 0; i < 140; i++) {
            boolean beam = i >= 110 && i < 130;
            boolean accent = i >= 130;
            // Start point on the (imagined) intact tower: height 7–18, radius ≤ 3.
            float startAngle = random.nextFloat() * Mth.TWO_PI;
            float startRadius = 0.5F + random.nextFloat() * 2.5F;
            float startX = Mth.cos(startAngle) * startRadius;
            float startZ = Mth.sin(startAngle) * startRadius;
            float startY = 7.0F + random.nextFloat() * 11.0F;
            // North-west fan ±35°.
            float fan = Mth.DEG_TO_RAD * ((225.0F - 90.0F) + (random.nextFloat() * 2.0F - 1.0F) * 35.0F);
            float dirX = Mth.cos(fan);
            float dirZ = Mth.sin(fan);
            float flightT0 = 0.15F + random.nextFloat() * 0.6F;
            float throwDist = 3.0F + random.nextFloat() * 7.0F;
            Vector3f size;
            BlockState state;
            if (beam) {
                state = random.nextBoolean() ? Blocks.OAK_PLANKS.defaultBlockState()
                        : Blocks.OAK_LOG.defaultBlockState();
                size = new Vector3f(0.3F, 0.3F, 1.6F);
            } else if (accent) {
                state = random.nextBoolean() ? Blocks.CHISELED_STONE_BRICKS.defaultBlockState()
                        : Blocks.STONE_BRICK_STAIRS.defaultBlockState();
                float scale = 0.5F + random.nextFloat() * 0.5F;
                size = new Vector3f(scale, scale, scale);
            } else {
                state = masonry[random.nextInt(masonry.length)];
                if (random.nextFloat() < 0.08F) {
                    size = new Vector3f(1.8F, 0.9F, 0.4F); // wall plate — strongly anisotropic
                } else {
                    float scale = 0.4F + random.nextFloat() * 0.9F;
                    size = new Vector3f(scale, scale, scale);
                }
            }
            Quaternionf baseRot = new Quaternionf().rotateY(random.nextFloat() * Mth.TWO_PI);
            props.add(new Prop(Group.TOWER, index++, KIND_DEFAULT, state,
                    new Vector3f(0.0F, 0.0F, 0.0F), size, baseRot, 7,
                    new float[] {startX, startY, startZ, dirX, dirZ, flightT0, throwDist}));
        }
    }

    /**
     * §5.4 Chronosphere + hourglass (~73 displays). Ring segment params =
     * [ring, segAngle, ringRadius, tilt]; sand stream params = [slot]. The rings are the
     * scene's ONLY continuous animation (0.8°/s, SanctumOrbitals transport).
     */
    private static void buildSphere(RandomSource random, List<Prop> props) {
        int index = 0;
        float[] ringRadii = {1.6F, 2.3F, 3.0F};
        float[] ringTilts = {0.0F, Mth.DEG_TO_RAD * 55.0F, -Mth.DEG_TO_RAD * 55.0F};
        BlockState[] ringPalette = {
                Blocks.WAXED_COPPER_BLOCK.defaultBlockState(),
                Blocks.GOLD_BLOCK.defaultBlockState(),
                Blocks.CHISELED_QUARTZ_BLOCK.defaultBlockState()};
        for (int ring = 0; ring < 3; ring++) {
            for (int segment = 0; segment < 12; segment++) {
                float segAngle = segment * Mth.TWO_PI / 12.0F + ring * 0.35F;
                props.add(new Prop(Group.SPHERE, index++, KIND_SPHERE_RING,
                        ringPalette[segment % 3], new Vector3f(0.0F, 0.0F, 0.0F),
                        new Vector3f(0.55F, 0.18F, 0.18F), new Quaternionf(), 15,
                        new float[] {ring, segAngle, ringRadii[ring], ringTilts[ring]}));
            }
        }
        // Core: 3 interlocked amethyst displays, 45° cants.
        for (int i = 0; i < 3; i++) {
            BlockState state = i == 1 ? Blocks.BUDDING_AMETHYST.defaultBlockState()
                    : Blocks.AMETHYST_BLOCK.defaultBlockState();
            Quaternionf cant = new Quaternionf()
                    .rotateY(Mth.DEG_TO_RAD * 45.0F * i)
                    .rotateX(Mth.DEG_TO_RAD * (i == 0 ? 0.0F : 45.0F));
            props.add(new Prop(Group.SPHERE, index++, KIND_SPHERE_CORE, state,
                    new Vector3f(0.0F, 0.0F, 0.0F), new Vector3f(0.7F, 0.7F, 0.7F),
                    cant, 15, new float[] {i}));
        }
        // Hourglass: two 12-box cones tapering to the waist at local y −2.0 (the
        // hourglass hangs at y+2.5..+5.5 over the floor; sphere anchor = floor + 6).
        for (int cone = 0; cone < 2; cone++) {
            float sign = cone == 0 ? 1.0F : -1.0F; // upper vs lower cone
            for (int i = 0; i < 12; i++) {
                float t = i / 11.0F;
                float radius = 1.1F - t * 0.8F;
                float angle = i * 2.4F + cone * 1.2F;
                float y = -2.0F + sign * (1.35F - t * 1.05F);
                BlockState state = i % 3 == 0 ? Blocks.WHITE_STAINED_GLASS.defaultBlockState()
                        : Blocks.GLASS.defaultBlockState();
                Quaternionf tilt = new Quaternionf().rotateY(angle)
                        .rotateX(sign * (0.5F + t * 0.4F));
                props.add(new Prop(Group.SPHERE, index++, KIND_SPHERE_GLASS, state,
                        new Vector3f(Mth.cos(angle) * radius, y, Mth.sin(angle) * radius),
                        new Vector3f(0.5F, 0.14F, 0.24F), tilt, 15, new float[] {}));
            }
        }
        // Frozen sand stream: 5 slim sandstone segments through the waist.
        for (int slot = 0; slot < 5; slot++) {
            props.add(new Prop(Group.SPHERE, index++, KIND_SPHERE_SAND,
                    Blocks.SANDSTONE.defaultBlockState(),
                    new Vector3f(0.0F, -2.0F - slot * 0.5F + 1.0F, 0.0F),
                    new Vector3f(0.12F, 0.5F, 0.12F), new Quaternionf(), 15,
                    new float[] {slot}));
        }
        // Sand pile cone (3 flat discs) at the lower bulb + 2 slumped grains up top.
        for (int i = 0; i < 3; i++) {
            float scale = 0.9F - i * 0.28F;
            props.add(new Prop(Group.SPHERE, index++, KIND_SPHERE_STATIC,
                    Blocks.SAND.defaultBlockState(),
                    new Vector3f(0.0F, -3.35F + i * 0.13F, 0.0F),
                    new Vector3f(scale, 0.12F, scale), new Quaternionf(), 15, new float[] {}));
        }
        for (int i = 0; i < 2; i++) {
            props.add(new Prop(Group.SPHERE, index++, KIND_SPHERE_STATIC,
                    Blocks.SAND.defaultBlockState(),
                    new Vector3f(i == 0 ? 0.25F : -0.2F, -0.9F - i * 0.25F, i == 0 ? -0.15F : 0.2F),
                    new Vector3f(0.4F, 0.14F, 0.4F),
                    new Quaternionf().rotateX(0.4F * (i == 0 ? 1 : -1)).rotateZ(0.3F),
                    15, new float[] {}));
        }
    }

    /**
     * §5.5 ambient garnish (~55 displays): 4 frozen birds (body + 2 wings + beak),
     * 32 falling birch leaves, 7 hovering log chunks. Bird-wing params =
     * [side, hingeAngle]; leaf params = [spinSeed].
     */
    private static void buildAmbient(RandomSource random, List<Prop> props) {
        int index = 0;
        for (int bird = 0; bird < 4; bird++) {
            float angle = random.nextFloat() * Mth.TWO_PI;
            float radius = 8.0F + random.nextFloat() * 12.0F;
            float height = 8.0F + random.nextFloat() * 6.0F;
            Vector3f base = new Vector3f(Mth.cos(angle) * radius, height, Mth.sin(angle) * radius);
            float heading = angle + Mth.HALF_PI * (random.nextBoolean() ? 1.0F : -1.0F) * 0.3F;
            Quaternionf yaw = new Quaternionf().rotateY(-heading);
            props.add(new Prop(Group.AMBIENT, index++, KIND_BIRD_BODY,
                    Blocks.BLACK_CONCRETE.defaultBlockState(), new Vector3f(base),
                    new Vector3f(0.28F, 0.2F, 0.42F), new Quaternionf(yaw), 7, new float[] {}));
            for (int wing = 0; wing < 2; wing++) {
                float side = wing == 0 ? 1.0F : -1.0F;
                float hinge = Mth.DEG_TO_RAD * (15.0F + random.nextFloat() * 25.0F);
                Quaternionf wingRot = new Quaternionf(yaw).rotateZ(side * hinge);
                props.add(new Prop(Group.AMBIENT, index++, KIND_BIRD_WING,
                        Blocks.SPRUCE_PLANKS.defaultBlockState(),
                        new Vector3f(base).add(new Vector3f(side * 0.32F, 0.08F, 0.0F).rotateY(-heading)),
                        new Vector3f(0.5F, 0.04F, 0.24F), wingRot, 7,
                        new float[] {side, hinge}));
            }
            props.add(new Prop(Group.AMBIENT, index++, KIND_BIRD_BODY,
                    Blocks.ORANGE_TERRACOTTA.defaultBlockState(),
                    new Vector3f(base).add(new Vector3f(0.0F, 0.05F, 0.26F).rotateY(-heading)),
                    new Vector3f(0.06F, 0.06F, 0.06F), new Quaternionf(yaw), 7, new float[] {}));
        }
        for (int leaf = 0; leaf < 32; leaf++) {
            float angle = random.nextFloat() * Mth.TWO_PI;
            float radius = random.nextFloat() * 23.0F;
            float scale = 0.12F + random.nextFloat() * 0.08F;
            Quaternionf tip = new Quaternionf()
                    .rotateY(random.nextFloat() * Mth.TWO_PI)
                    .rotateX((random.nextFloat() - 0.5F) * 1.6F)
                    .rotateZ((random.nextFloat() - 0.5F) * 1.6F);
            props.add(new Prop(Group.AMBIENT, index++, KIND_LEAF,
                    Blocks.BIRCH_LEAVES.defaultBlockState(),
                    new Vector3f(Mth.cos(angle) * radius, 1.0F + random.nextFloat() * 6.0F,
                            Mth.sin(angle) * radius),
                    new Vector3f(scale, scale, scale), tip, 7,
                    new float[] {random.nextFloat() * Mth.TWO_PI}));
        }
        for (int log = 0; log < 7; log++) {
            float angle = random.nextFloat() * Mth.TWO_PI;
            float radius = 18.0F + random.nextFloat() * 5.0F;
            float scale = 0.25F + random.nextFloat() * 0.25F;
            props.add(new Prop(Group.AMBIENT, index++, KIND_LOG,
                    Blocks.BIRCH_LOG.defaultBlockState(),
                    new Vector3f(Mth.cos(angle) * radius, 0.5F + random.nextFloat() * 1.5F,
                            Mth.sin(angle) * radius),
                    new Vector3f(scale, scale, scale),
                    new Quaternionf().rotateY(random.nextFloat() * Mth.TWO_PI)
                            .rotateX((random.nextFloat() - 0.5F) * 0.8F),
                    7, new float[] {}));
        }
    }

    // ------------------------------------------------------------------ pose functions

    /**
     * Absolute pose of one prop under {@code params} — the stateless-push law: every
     * component derives from the prop's frozen ingredients + the shared clock values,
     * so ONE push heals any drift. Rotation pivots the per-axis-scaled box around its
     * own center (T = point − Q·(size/2), the ExpansionBorderFx half-vector recipe).
     */
    public static Transformation poseOf(Prop prop, PoseParams params) {
        Vector3f offset = new Vector3f(prop.offset());
        Quaternionf rotation = new Quaternionf(prop.baseRot());
        Vector3f size = new Vector3f(prop.size());
        float[] p = prop.params();
        switch (prop.group()) {
            case BOLT -> {
                // Jolt: joints twitch by tiny hash-phased deltas; discharge: top-down scale-out.
                float jitter = (float) (0.03D * params.sceneTick() * Math.sin(p[1] * 3.1D));
                if (jitter != 0.0F) {
                    rotation.rotateY(jitter).rotateX(jitter * 0.6F);
                    offset.add(0.0F, (float) (0.05D * params.sceneTick()), 0.0F);
                }
                float shrink = (float) Mth.clamp(
                        1.0D - (params.boltT() * 1.5D - (1.0D - p[0]) * 0.5D), 0.0D, 1.0D);
                size.mul(shrink);
                offset.y *= 1.0F - (float) params.boltT() * (1.0F - shrink) * 0.5F;
            }
            case BLAST -> {
                if (prop.kind() == KIND_BLAST_SMOKE) {
                    // Smoke: frozen; discharge lifts it 6 blocks and fades (scale→0).
                    offset.add(0.0F, (float) (params.blastT() * 6.0D), 0.0F);
                    size.mul((float) Math.max(0.0D, 1.0D - params.blastT()));
                    rotation.rotateY((float) (params.blastT() * 0.8D + params.sceneTick() * 0.01D));
                } else {
                    // Fragments hang on radial spokes; radius breathes with sceneTick
                    // (×1.02 per jolt tick) and blows out ×4 while shrinking on discharge.
                    double radius = p[3] * (1.0D + 0.02D * params.sceneTick())
                            * (1.0D + 3.0D * params.blastT());
                    offset.set(p[0] * (float) radius, p[1] * (float) radius, p[2] * (float) radius);
                    size.mul((float) Math.max(0.0D, 1.0D - params.blastT()));
                    rotation.rotateY((float) (params.blastT() * 2.4D));
                }
            }
            case TOWER -> {
                // Ballistic collapse arc parameterized by flightT ∈ [0,1].
                double flightT = Mth.clamp(p[5] + 0.01D * params.sceneTick()
                        + (1.0D - p[5]) * params.towerT(), 0.0D, 1.0D);
                float x = p[0] + p[3] * (float) (flightT * p[6]);
                float z = p[2] + p[4] * (float) (flightT * p[6]);
                float y = 2.2F + (p[1] - 2.2F) * (float) (1.0D - flightT * flightT);
                offset.set(x, y - 8.0F, z); // anchor sits at stump top = floor + 8
                float tumble = (float) (flightT * Mth.TWO_PI * (0.5D + (prop.index() % 5) * 0.2D));
                rotation.rotateX(tumble * 0.7F).rotateZ(tumble * 0.4F);
            }
            case SPHERE -> {
                switch (prop.kind()) {
                    case KIND_SPHERE_RING -> {
                        double direction = ((int) p[0] % 2 == 0) ? 1.0D : -1.0D;
                        double angle = p[1]
                                + direction * Math.toRadians(RING_DEG_PER_TICK) * params.gameTime()
                                + Math.toRadians(2.0D) * params.sceneTick()
                                + direction * params.sphereT() * Math.PI * 4.0D * (p[0] + 1.0D);
                        float tilt = p[3];
                        Vector3f local = new Vector3f(
                                (float) (Math.cos(angle) * p[2]), 0.0F, (float) (Math.sin(angle) * p[2]));
                        Quaternionf plane = new Quaternionf().rotationX(tilt);
                        plane.transform(local);
                        offset.set(local);
                        rotation.set(new Quaternionf(plane).rotateY((float) (-angle + Mth.HALF_PI)));
                    }
                    case KIND_SPHERE_CORE -> rotation.rotateY(
                            (float) (Math.toRadians(2.0D) * params.sceneTick()
                                    + params.sphereT() * Math.PI * 2.0D));
                    case KIND_SPHERE_SAND -> offset.add(0.0F, (float) (-0.05D * params.sceneTick()), 0.0F);
                    default -> {}
                }
            }
            case AMBIENT -> {
                switch (prop.kind()) {
                    case KIND_BIRD_WING -> {
                        // One wing-beat frame per jolt: ±6° around the hinge.
                        float flap = (float) (Mth.DEG_TO_RAD * 6.0D * params.sceneTick() * 0.5D) * p[0];
                        rotation.rotateZ(flap);
                    }
                    case KIND_LEAF -> {
                        offset.add(0.0F, (float) (-0.04D * params.sceneTick()), 0.0F);
                        rotation.rotateY((float) (Mth.DEG_TO_RAD * 3.0D * params.sceneTick()
                                + Math.sin(p[0]) * 0.0D));
                    }
                    default -> {}
                }
            }
        }
        // Re-center the [0,size]³ box on its offset through the rotation.
        Vector3f half = new Vector3f(size).mul(0.5F);
        rotation.transform(half);
        Vector3f translation = new Vector3f(offset).sub(half);
        return new Transformation(translation, rotation, size, new Quaternionf());
    }

    // ------------------------------------------------------------------ spawn / reconcile

    /**
     * Adopt/dedupe/respawn pass (SanctumOrbitals doctrine, plan §3.1). The first pass of
     * a boot defers until every anchor chunk's entity section is loaded (the load-race
     * lesson: adopting beats duplicating). {@code force} discards adopted displays too
     * (dev rebuild). Missing props are queued; {@link #drainSpawns} tops up at
     * {@value #SPAWN_BUDGET_PER_TICK}/tick.
     */
    public static void reconcile(ServerLevel level, SceneState state, BlockPos center,
            PoseParams bornPose, boolean force) {
        if (!anchorsEntityLoaded(level, center)) {
            if (!state.reconciled) {
                EclipseMod.LOGGER.debug(
                        "ChronoSceneBuilder: anchor entity sections not loaded — reconcile deferred");
            }
            return;
        }
        int adopted = 0;
        int discarded = 0;
        boolean[] seen = new boolean[state.props.size()];
        for (Display.BlockDisplay display : scanTagged(level, center)) {
            Integer index = identityIndexOf(display, state);
            if (force || index == null || seen[index]) {
                display.discard();
                discarded++;
            } else {
                seen[index] = true;
                state.displays[index] = display;
                adopted++;
            }
        }
        state.spawnQueue.clear();
        int queued = 0;
        for (int i = 0; i < state.props.size(); i++) {
            Display.BlockDisplay cached = seen[i] ? state.displays[i] : null;
            if (cached == null || cached.isRemoved()) {
                state.displays[i] = null;
                state.spawnQueue.add(i);
                queued++;
            }
        }
        state.reconciled = true;
        if (queued > 0 || discarded > 0 || force) {
            EclipseMod.LOGGER.info(
                    "ChronoSceneBuilder: adopted {}, discarded {}, queued {} spawn(s) of {} props",
                    adopted, discarded, queued, state.props.size());
        }
        // Drain the first slice immediately so a dev rebuild shows progress this tick.
        drainSpawns(level, state, center, bornPose, SPAWN_BUDGET_PER_TICK);
    }

    /** Spawns up to {@code budget} queued props; returns how many were spawned. */
    public static int drainSpawns(ServerLevel level, SceneState state, BlockPos center,
            PoseParams bornPose, int budget) {
        int spawned = 0;
        while (spawned < budget && !state.spawnQueue.isEmpty()) {
            int index = state.spawnQueue.poll();
            Prop prop = state.props.get(index);
            Display.BlockDisplay display = spawnProp(level, prop, center, bornPose);
            if (display != null) {
                state.displays[index] = display;
                spawned++;
            }
        }
        return spawned;
    }

    @Nullable
    private static Display.BlockDisplay spawnProp(ServerLevel level, Prop prop, BlockPos center,
            PoseParams bornPose) {
        Display.BlockDisplay display = new Display.BlockDisplay(EntityType.BLOCK_DISPLAY, level);
        Vec3 anchor = groupAnchor(prop.group(), center);
        display.moveTo(anchor.x, anchor.y, anchor.z, 0.0F, 0.0F);
        display.setBlockState(prop.state());
        display.addTag(TAG);
        display.addTag(prop.identityTag());
        display.setTransformationInterpolationDelay(0);
        display.setTransformationInterpolationDuration(0);
        display.setTransformation(poseOf(prop, bornPose));
        DisplayBrightnessFx.set(display, prop.brightnessBlock(), 15, VIEW_RANGE);
        if (!level.addFreshEntity(display)) {
            EclipseMod.LOGGER.error("ChronoSceneBuilder: failed to add display {}", prop.identityTag());
            return null;
        }
        return display;
    }

    /** One interpolated pose push (delay 0 restarts from the currently rendered pose). */
    public static void pushPose(Display.BlockDisplay display, Prop prop, PoseParams params,
            int durationTicks) {
        display.setTransformationInterpolationDelay(0);
        display.setTransformationInterpolationDuration(durationTicks);
        display.setTransformation(poseOf(prop, params));
    }

    /** Discards EVERY tagged scene prop in the site volume (rollback / dev reset). */
    public static int discardAllTagged(ServerLevel level, BlockPos center) {
        List<Display.BlockDisplay> tagged = scanTagged(level, center);
        tagged.forEach(Display.BlockDisplay::discard);
        return tagged.size();
    }

    private static List<Display.BlockDisplay> scanTagged(ServerLevel level, BlockPos center) {
        AABB volume = new AABB(
                center.getX() - 26.0D, center.getY() - 24.0D, center.getZ() - 26.0D,
                center.getX() + 26.0D, center.getY() + 24.0D, center.getZ() + 26.0D);
        return level.getEntities(EntityType.BLOCK_DISPLAY, volume,
                display -> display.getTags().contains(TAG));
    }

    @Nullable
    private static Integer identityIndexOf(Display.BlockDisplay display, SceneState state) {
        for (String tag : display.getTags()) {
            Integer index = state.byTag.get(tag);
            if (index != null) {
                return index;
            }
        }
        return null;
    }

    /** Whether every distinct group-anchor chunk has its entity section loaded. */
    private static boolean anchorsEntityLoaded(ServerLevel level, BlockPos center) {
        for (Group group : Group.values()) {
            Vec3 anchor = groupAnchor(group, center);
            BlockPos pos = BlockPos.containing(anchor);
            if (!level.isLoaded(pos) || !level.areEntitiesLoaded(ChunkPos.asLong(pos))) {
                return false;
            }
        }
        return true;
    }
}
