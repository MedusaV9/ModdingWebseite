package dev.projecteclipse.eclipse.ritual;

import java.util.ArrayList;
import java.util.List;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscGeometry;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.PointedDripstoneBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.DripstoneThickness;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.Vec3;

/**
 * F-090/F-093 "Map-Zerreißen V3" — the black-hole finale's MAP EFFIGY stage manager
 * (owned and clocked by {@link CreditsSequence}; the accretion field stays in
 * {@link CreditsBlackHoleAct}). The core move: the anchor-frame trick extended from a
 * maw-only stage to the WHOLE map — at prepare time the REAL overworld disc is sampled
 * as a coarse LOD heightmap grid (top state + strata + relief per cell) and rebuilt as
 * a 1:~3.9 scale replica along the TRUE line of sight
 * ({@code replicaPos = vantage + (realPos − vantage) × (anchorDist / vantageDist)}).
 * Every replica cell sits ON the view ray of its real counterpart, so through the
 * crushed finale FOV the effigy is pixel-aligned with where the real map would be:
 * when the black releases, players see THEIR map lying under the hole — and then it
 * gets torn apart. The world itself is never modified (Kulisse law).
 *
 * <p><b>The rip choreography</b> (all offsets on the act clock {@code ripTick} =
 * run tick − {@code T_FINALE_REVEAL}; every pose is a pure function of
 * {@code (index, ripTick)} — the stateless-push law):</p>
 * <ul>
 *   <li><b>Sampling/spawn behind the black</b> (ripTick −320…0): budgeted column reads
 *       (≤ {@value #SAMPLE_PER_TICK}/t) + budgeted identity-pose spawn
 *       (≤ {@value #SPAWN_PER_TICK}/t) — the reveal opens on the finished intact map.
 *       LOD: near half of the camera-facing ~200° sector samples every
 *       {@value #STEP_NEAR} map blocks, the far half every {@value #STEP_FAR}
 *       ("far plates = fewer, bigger displays"); steps widen budget-first until the
 *       cell count fits {@value #CELL_CAP}.</li>
 *   <li><b>Crack fronts</b> ({@link #CRACK_FRONT_AT}): three fronts race along plate
 *       borders (hashed waypoints snapped onto Voronoi edges) in {@value #CRACK_STEPS}
 *       × {@value #CRACK_STEP_TICKS}t propagation steps; a pool of
 *       {@value #SEAM_POOL} glowing violet seam slats lights up along the polylines
 *       ({@link #crackStep} hands each step's midpoint to {@code CreditsSequence} for
 *       the {@code credits4_crackfront} cue + shake + crack SFX).</li>
 *   <li><b>Tectonic plates</b>: the sector is carved into {@value #PLATE_COUNT}
 *       plates ({@value #MEGA_PLATES} mega / {@value #LARGE_PLATES} large / the rest
 *       medium) by a weighted hashed Voronoi (deterministic from the run nonce).
 *       {@link #LIFT_WAVE_AT} lift waves walk hole → camera: rigid lift (rises
 *       4–9 anchor-blocks, tilts 8–25° toward the hole, eased kick-back), mid-air
 *       SUB-FRACTURE at lift+{@value #FRACTURE_TICK}t into 2–4 sub-plates (a
 *       {@value #FRACTURE_SNAP_TICKS}t snap window, {@link #plateBreaks} feeds the
 *       {@code credits4_platebreak} dressing), then a 240–380t spiral INFALL whose
 *       angular velocity rises ∝ q² with PLATE-LEVEL spaghettization (the sub-plate
 *       frame stretches radially toward {@value #PLATE_STRETCH_MAX}×, thins crosswise
 *       inverse-sqrt, members widen into arc filaments — the F-072 trail law) and the
 *       heat-ignite edge-swap from q ≥ {@value #HEAT_Q}.</li>
 *   <li><b>Deep layer</b>: swallowed members RECYCLE into a dark bedrock/deepslate
 *       slab layer {@value #DEEP_DROP} anchor-blocks under where the crust was —
 *       lifting a plate reveals that the map has a body. At offset
 *       {@value #DEEP_RIP_AT} the deep layer itself rips in one accelerating
 *       hole-outward cascade, flowing into the act wind-down.</li>
 *   <li><b>Underside reveal</b>: a recycled pool of {@value #UNDERSIDE_POOL} bedrock
 *       slabs + hanging stalactites rides each lifted plate's transform (pure offset
 *       in the plate frame) and drains with it; the pool re-arms wave over wave.</li>
 *   <li><b>Gravity waves</b> ({@link #GRAVITY_WAVE_AT}): ring shockwaves cross the
 *       effigy at {@value #WAVE_SPEED} anchor-blocks/t — un-lifted cells bob in a
 *       traveling eased sine (±{@value #WAVE_BOB_AMP}) and ~8% of touched cells strip
 *       a shard from the {@value #SHARD_POOL} pool (hop up, fast flat spiral in).</li>
 *   <li><b>Jet shreds</b>: {@link #plateCrossing} publishes the deterministic
 *       horizon-crossing schedule ({@code devourPulse} takes the max with the gulp
 *       floor); from offset ~{@value #JET_FROM} a hashed ~30% of crossings SHRED
 *       instead of draining — the sub-plate's members spray along the ±jet axis (the
 *       disc minor axis in the anchor frame) over {@value #JET_SPRAY_TICKS}t, ignited
 *       and stretched 3× ({@link #jetBurst} hands the beat to {@code CreditsSequence}
 *       for the {@code credits4_jetburst} cue + {@code S2CCreditsJetPayload}
 *       strobe).</li>
 * </ul>
 *
 * <p><b>Budget</b>: crust ≤ {@value #CELL_CAP} (expected ≈ 1250) + underside
 * {@value #UNDERSIDE_POOL} + seams {@value #SEAM_POOL} + shards {@value #SHARD_POOL}
 * = ≈ 2190 displays, + the (reduced) 700-display accretion field ≈ 2890 finale peak —
 * under the audited &lt;3000 target and the 3600 hard cap (every spawn checks
 * {@link CreditsSequence#actCapReached}). Pushes ride {@value #PUSH_STRIDE}t windows
 * (≈ 219 transform updates/t); block-state/brightness NBT writes are edge-triggered
 * through per-display look caches only. Discard is guaranteed on the hold beat, on
 * {@code /dev end_event} and at run teardown; every display carries {@link #TAG} for
 * the crash-stray join sweep.</p>
 */
final class CreditsMapRipAct {
    static final String TAG = "eclipse_credits_maprip";

    // --- budgets / pools ---
    /** Hard crust-cell cap; the LOD steps widen until the grid fits it. */
    static final int CELL_CAP = 1300;
    static final int SEAM_POOL = 160;
    static final int SHARD_POOL = 280;
    static final int UNDERSIDE_POOL = 500;
    static final int SAMPLE_PER_TICK = 60;
    static final int SPAWN_PER_TICK = 30;
    static final int UNDERSIDE_SPAWN_PER_TICK = 40;
    /** Transform-push cadence == interpolation window length. */
    static final int PUSH_STRIDE = 10;

    // --- act timeline (offsets from T_FINALE_REVEAL; the devour window is 0..1300) ---
    /** Crack fronts 1–3 start racing along the plate borders (before any liftoff). */
    static final int[] CRACK_FRONT_AT = {100, 170, 240};
    static final int CRACK_STEPS = 6;
    static final int CRACK_STEP_TICKS = 15;
    /** Lift waves 1–5 walk from the hole toward the camera (wave 5 = nearest megas). */
    static final int[] LIFT_WAVE_AT = {260, 400, 560, 720, 880};
    private static final int[] LIFT_WAVE_SIZE = {8, 8, 9, 8, 7};
    /** Traveling ring shockwaves across the effigy (cell bob + shard stripping). */
    static final int[] GRAVITY_WAVE_AT = {300, 460, 620, 780, 940, 1100};
    /** The underside pool spawns (at the scale floor) just before lift wave 1. */
    static final int UNDERSIDE_SPAWN_AT = LIFT_WAVE_AT[0] - 24;
    /** The deep layer's own rip: one accelerating cascade of everything remaining. */
    static final int DEEP_RIP_AT = 1000;

    // --- plate life cycle ---
    private static final int LIFT_TICKS = 60;
    /** Sub-fracture beat inside the lift (the {@code credits4_platebreak} tick). */
    private static final int FRACTURE_TICK = 40;
    private static final float FRACTURE_SNAP_TICKS = 4.0F;
    private static final int LIFT_JITTER = 14;
    private static final float LIFT_HEIGHT_MIN = 4.0F;
    private static final float LIFT_HEIGHT_VAR = 5.0F;
    private static final float TILT_MIN_DEG = 8.0F;
    private static final float TILT_VAR_DEG = 17.0F;
    private static final int INFALL_MIN = 240;
    private static final int INFALL_VAR = 140;
    /** Fall progress where a sub-plate starts draining over the horizon (the crossing). */
    private static final float DRAIN_Q = 0.9F;
    /** Plate-level spaghettification: peak radial stretch of the sub-plate frame. */
    private static final float PLATE_STRETCH_MAX = 2.2F;
    private static final float STRETCH_START_Q = 0.55F;
    /** Heat-ignite threshold (the F-072 magma edge-swap law, plate edition). */
    private static final float HEAT_Q = 0.75F;
    /** Arc-trail widening across the stretch window (the F-072 filament law). */
    private static final float FILAMENT_TRAIL = 0.55F;
    private static final float SWALLOW_RADIUS = 1.2F;

    // --- jet shreds ---
    /** Earliest crossing offset that may shred (plan: "every 3rd–4th gulp from ~520"). */
    private static final int JET_FROM = 520;
    private static final int JET_SPRAY_TICKS = 50;
    private static final double JET_SHRED_CHANCE = 0.30D;
    /**
     * FXWAVE-9 #4 — SECOND jet cycle: inside this window the shred chance ramps
     * {@value #JET_SHRED_CHANCE} → {@value #JET2_SHRED_CHANCE} and the two LARGEST
     * crossing sub-plates are force-shredded at full strength with OPPOSED jet sides
     * (a bipolar pair) — the show's peak beat repeats bigger instead of tailing off.
     */
    private static final int JET2_FROM = 900;
    private static final int JET2_UNTIL = 1150;
    private static final double JET2_SHRED_CHANCE = 0.55D;

    // --- deep layer ---
    /** Anchor-blocks the recycled slab layer sits under the crust replica. */
    private static final int DEEP_DROP = 3;
    private static final int DEEP_GROW_TICKS = 16;
    private static final int DEEP_RIP_DUR = 150;
    /** The rip cascade staggers hole-outward across this many ticks. */
    private static final int DEEP_RIP_STAGGER = 110;

    // --- gravity waves ---
    /** Ring crest speed (anchor-blocks per tick). */
    private static final float WAVE_SPEED = 1.4F;
    private static final int WAVE_BOB_TICKS = 40;
    private static final float WAVE_BOB_AMP = 1.4F;
    private static final double SHARD_STRIP_CHANCE = 0.08D;
    private static final int SHARD_FLIGHT_TICKS = 90;
    private static final int SHARD_HOP_TICKS = 14;

    /** The act's exit (mirrors the accretion act): everything drains to the floor. */
    private static final int WIND_DOWN_TICKS = 140;
    private static final int WIND_DOWN_START = CreditsBlackHoleAct.SPIRAL_TICKS - WIND_DOWN_TICKS;

    // --- sampling / LOD ---
    /** Sample radius = current stage radius, clamped (the far rim hides behind the maw). */
    private static final int RADIUS_CLAMP = 220;
    private static final int STEP_NEAR = 6;
    private static final int STEP_FAR = 10;
    /** Near/far LOD split: map distance from the vantage-side rim, as a 0..1 fraction. */
    private static final float NEAR_ZONE_FRAC = 0.55F;
    /** Camera-facing sector half-angle (~200° total). */
    private static final double SECTOR_COS = Math.cos(Math.toRadians(100.0D));
    /** How deep a fluid column is probed for its seabed block. */
    private static final int SEABED_SCAN = 8;

    // --- plates ---
    private static final int PLATE_COUNT = 40;
    private static final int MEGA_PLATES = 5;
    private static final int LARGE_PLATES = 15;
    /** Voronoi weights: mega seeds claim ~2× the reach of medium ones. */
    private static final float MEGA_WEIGHT = 1.9F;
    private static final float LARGE_WEIGHT = 1.35F;
    /** A cell this close (weighted map-blocks) to its second seed is a border cell. */
    private static final float BORDER_EPS = 3.0F;

    private static final float VIEW_RANGE = 4.0F;
    private static final float SCALE_FLOOR = 0.02F;

    // --- looks (edge-triggered NBT writes only) ---
    private static final byte LOOK_COLD = 0;
    private static final byte LOOK_STRATA = 1;
    private static final byte LOOK_HOT = 2;
    private static final byte LOOK_DEEP = 3;

    /** V3 heat-glow states (the F-072 law: magma core + rare shroomlight accent). */
    private static final BlockState HEAT_PRIMARY = Blocks.MAGMA_BLOCK.defaultBlockState();
    private static final BlockState HEAT_ACCENT = Blocks.SHROOMLIGHT.defaultBlockState();
    /** The deep layer's dark body. */
    private static final BlockState[] DEEP_PALETTE = {
            Blocks.BEDROCK.defaultBlockState(),
            Blocks.DEEPSLATE.defaultBlockState(),
            Blocks.TUFF.defaultBlockState()};
    /** Glowing crack-seam slats. */
    private static final BlockState[] SEAM_PALETTE = {
            Blocks.PURPLE_STAINED_GLASS.defaultBlockState(),
            Blocks.AMETHYST_BLOCK.defaultBlockState()};
    private static final BlockState[] UNDERSIDE_PALETTE = {
            Blocks.BEDROCK.defaultBlockState(),
            Blocks.DEEPSLATE.defaultBlockState()};
    private static final BlockState STALACTITE_STATE =
            Blocks.POINTED_DRIPSTONE.defaultBlockState()
                    .setValue(PointedDripstoneBlock.TIP_DIRECTION, Direction.DOWN)
                    .setValue(PointedDripstoneBlock.THICKNESS, DripstoneThickness.TIP);
    private static final BlockState STALACTITE_COLUMN = Blocks.DEEPSLATE.defaultBlockState();
    private static final BlockState SAMPLE_FALLBACK = Blocks.STONE.defaultBlockState();

    // ------------------------------------------------------------------ data

    /** One LOD heightmap cell of the effigy grid (list index == display index). */
    private static final class Cell {
        final int x;
        final int z;
        /** 0 = near LOD (fine grid), 1 = far LOD (coarse grid, bigger display). */
        final byte lod;
        int topY;
        BlockState top = SAMPLE_FALLBACK;
        BlockState strata = SAMPLE_FALLBACK;
        /** Replica base offset from the fx anchor (anchor frame). */
        float bx;
        float by;
        float bz;
        /** Display edge length (grid step × replica scale). */
        float scale;
        int plate;
        int sub;
        /** Normalized member rank inside the sub-plate (−1..1; filament trailing). */
        float rank;
        /** Horizontal anchor-frame distance from the hole axis (waves/deep rip). */
        float distHoriz;
        /** Weighted distance gap to the 2nd-nearest seed (Voronoi borderness). */
        float borderGap;

        Cell(int x, int z, byte lod) {
            this.x = x;
            this.z = z;
            this.lod = lod;
        }
    }

    /** One tectonic plate (rigid-body fake: shared origin + rotation per push). */
    private static final class Plate {
        final float seedX;
        final float seedZ;
        final float weight;
        int members;
        /** Map-plan centroid (relative to the hole column, real map blocks). */
        float mapCx;
        float mapCz;
        /** Anchor-frame member centroid. */
        float cx;
        float cy;
        float cz;
        /** Tilt axis (horizontal unit, anchor frame) — tips the hole-side edge UP. */
        float axX;
        float axZ;
        int liftStart = Integer.MAX_VALUE;
        float liftHeight;
        float tiltRad;
        int firstSub;
        int subCount;

        Plate(float seedX, float seedZ, float weight) {
            this.seedX = seedX;
            this.seedZ = seedZ;
            this.weight = weight;
        }
    }

    /** One mid-air fracture piece of a plate (the infall/shred/crossing unit). */
    private static final class SubPlate {
        final int plate;
        int members;
        /** Anchor-frame member centroid. */
        float cx;
        float cy;
        float cz;
        /** Fracture separation direction (horizontal unit) + eased kick distance. */
        float kickX;
        float kickZ;
        float kickDist;
        /** Divergent extra tilt (radians, signed) gained across the snap window. */
        float extraTilt;
        int infallDur;
        float turns;
        /** liftEnd + {@value #DRAIN_Q}·dur — the deterministic horizon-crossing tick. */
        int crossTick;
        float crossStrength;
        boolean shredded;
        float jetSide;

        SubPlate(int plate) {
            this.plate = plate;
        }
    }

    /** One recycled underside piece job (slab or stalactite riding a lifted plate). */
    private record UndersideJob(int cell, boolean stalactite, int start, int end) {}

    /** One recycled gravity-wave shard job (strip → hop → fast flat spiral in). */
    private record ShardJob(int cell, int start) {}

    /** One crack-front propagation step ({@code CreditsSequence} beat dressing). */
    record CrackStep(int front, int step, float progress, Vec3 mid) {}

    private final List<Cell> cells = new ArrayList<>();
    private final Plate[] plates = new Plate[PLATE_COUNT];
    private final List<SubPlate> subs = new ArrayList<>(PLATE_COUNT * 3);

    private final List<Display.BlockDisplay> crustDisplays = new ArrayList<>();
    private final List<Display.BlockDisplay> seamDisplays = new ArrayList<>();
    private final List<Display.BlockDisplay> shardDisplays = new ArrayList<>();
    private final List<Display.BlockDisplay> undersideDisplays = new ArrayList<>();

    /** Edge-triggered look caches (skip no-op NBT round trips). */
    private byte[] crustLookCache;
    private int[] shardJobCache;
    private int[] undersideJobCache;

    // Crack-front geometry (anchor frame) + the seam-slat pool schedule.
    private final Vector3f[][] crackWaypoints = new Vector3f[CRACK_FRONT_AT.length][CRACK_STEPS + 1];
    private final Vector3f[] seamPos = new Vector3f[SEAM_POOL];
    private final float[] seamYaw = new float[SEAM_POOL];
    private final float[] seamLen = new float[SEAM_POOL];
    private final int[] seamAppear = new int[SEAM_POOL];
    private final int[] seamFade = new int[SEAM_POOL];

    private final List<UndersideJob> undersideJobs = new ArrayList<>();
    private int[][] undersideSlotJobs;
    private final List<ShardJob> shardJobs = new ArrayList<>();
    private int[][] shardSlotJobs;

    /** Deterministic horizon-crossing / jet-burst strengths by act tick. */
    private float[] crossingByTick;
    private float[] jetByTick;

    // Stage geometry.
    private Vec3 vantage = Vec3.ZERO;
    private Vec3 fxAnchor = Vec3.ZERO;
    private Vec3 holeCenter = Vec3.ZERO;
    /** Replica scale: anchorDist / vantageDist (≈ 0.256 — the 1:3.9 effigy). */
    private float replicaScale = 0.256F;
    /** Camera basis at the anchor (right / up / view normal) — the jet axis is up. */
    private Vector3f right = new Vector3f(1.0F, 0.0F, 0.0F);
    private Vector3f jetAxis = new Vector3f(0.0F, 1.0F, 0.0F);
    /** Map-plan unit direction hole column → vantage (the camera side). */
    private float vsX;
    private float vsZ;
    private int centerBlockX;
    private int centerBlockZ;
    private int sampleRadius;
    private int stepNear = STEP_NEAR;
    private int stepFar = STEP_FAR;
    private float maxDistHoriz = 1.0F;
    private int nonce;

    private int sampleCursor;
    private int spawnCursor;
    private int undersideCursor;
    private boolean prepared;
    /** Sampling finished + all derived geometry finalized (poses are queryable). */
    private boolean staged;

    // ------------------------------------------------------------------ prepare

    /**
     * Stages the effigy GEOMETRY (no world reads): the anchor-frame replica transform
     * from the black-hole act's vantage/anchor ray, the budget-first LOD grid over the
     * camera-facing sector, the weighted Voronoi plates and the lift-wave schedule.
     * The budgeted world sampling itself runs later behind the post-card black
     * ({@link #sampleBatch}). Never fails: the finale act must always have staged
     * SOMETHING (an empty grid only logs and skips the whole rip).
     */
    void prepare(ServerLevel overworld, CreditsBlackHoleAct blackHole, int nonce) {
        if (!blackHole.prepared()) {
            EclipseMod.LOGGER.warn("CreditsMapRipAct: black-hole act not staged — map rip skipped");
            return;
        }
        this.nonce = nonce;
        this.vantage = blackHole.vantage();
        this.fxAnchor = blackHole.fxAnchor();
        this.holeCenter = blackHole.holeCenter();
        Vec3 toHole = this.holeCenter.subtract(this.vantage);
        this.replicaScale = (float) (this.fxAnchor.subtract(this.vantage).length() / toHole.length());
        Vec3 dir = toHole.normalize();
        Vector3f normal = new Vector3f((float) dir.x, (float) dir.y, (float) dir.z);
        this.right = new Vector3f(normal).cross(0.0F, 1.0F, 0.0F).normalize();
        this.jetAxis = new Vector3f(this.right).cross(normal).normalize();
        double vx = this.vantage.x - this.holeCenter.x;
        double vz = this.vantage.z - this.holeCenter.z;
        double vlen = Math.max(1.0E-4D, Math.sqrt(vx * vx + vz * vz));
        this.vsX = (float) (vx / vlen);
        this.vsZ = (float) (vz / vlen);
        this.centerBlockX = Mth.floor(this.holeCenter.x);
        this.centerBlockZ = Mth.floor(this.holeCenter.z);
        int stage = WorldStageService.stage(overworld.getServer(), DiscProfile.OVERWORLD);
        this.sampleRadius = Math.min(RADIUS_CLAMP, DiscGeometry.mainDiscRadius(stage));

        // Budget-first LOD: widen the steps until the sector grid fits the cell cap.
        for (int widen = 0; widen <= 12; widen++) {
            this.stepNear = STEP_NEAR + widen;
            this.stepFar = STEP_FAR + 2 * widen;
            if (collectCells(null) <= CELL_CAP || widen == 12) {
                collectCells(this.cells);
                break;
            }
        }
        if (this.cells.isEmpty()) {
            EclipseMod.LOGGER.warn("CreditsMapRipAct: empty effigy grid (radius {}) — map rip skipped",
                    this.sampleRadius);
            return;
        }
        placePlates();
        assignWaves();
        this.crustLookCache = new byte[this.cells.size()];
        this.prepared = true;
        int near = 0;
        for (Cell cell : this.cells) {
            if (cell.lod == 0) {
                near++;
            }
        }
        EclipseMod.LOGGER.info("CreditsMapRipAct: staged — {} cell(s) ({} near / {} far, steps {}/{}), "
                + "radius {} (stage {}), replica scale {}", this.cells.size(), near,
                this.cells.size() - near, this.stepNear, this.stepFar, this.sampleRadius, stage,
                this.replicaScale);
    }

    /**
     * Enumerates (or counts, {@code out == null}) the LOD grid over the camera-facing
     * ~200° sector: the near zone (map distance from the vantage-side rim &lt;
     * {@value #NEAR_ZONE_FRAC} of the sector depth) on the fine grid, the far zone on
     * the coarse one — two aligned passes, no overlap.
     */
    private int collectCells(@javax.annotation.Nullable List<Cell> out) {
        int count = 0;
        float rimX = this.vsX * this.sampleRadius;
        float rimZ = this.vsZ * this.sampleRadius;
        float depth = 2.0F * this.sampleRadius;
        for (int pass = 0; pass < 2; pass++) {
            int step = pass == 0 ? this.stepNear : this.stepFar;
            int extent = this.sampleRadius / step;
            for (int gx = -extent; gx <= extent; gx++) {
                for (int gz = -extent; gz <= extent; gz++) {
                    float dx = gx * step;
                    float dz = gz * step;
                    float r2 = dx * dx + dz * dz;
                    if (r2 > (float) this.sampleRadius * this.sampleRadius) {
                        continue;
                    }
                    float r = (float) Math.sqrt(r2);
                    if (r > 1.0F && (dx * this.vsX + dz * this.vsZ) / r < SECTOR_COS) {
                        continue; // the far sliver hides behind the maw/horizon glow
                    }
                    float rx = dx - rimX;
                    float rz = dz - rimZ;
                    boolean near = Math.sqrt(rx * rx + rz * rz) / depth < NEAR_ZONE_FRAC;
                    if (near != (pass == 0)) {
                        continue;
                    }
                    count++;
                    if (out != null) {
                        out.add(new Cell(this.centerBlockX + (int) dx,
                                this.centerBlockZ + (int) dz, (byte) pass));
                    }
                }
            }
        }
        return count;
    }

    /**
     * Carves the sector into {@value #PLATE_COUNT} plates: hashed seeds fanned across
     * the sector (deterministic from the run nonce; mega seeds biased to the camera
     * side so the biggest silhouettes cross the frame last and highest), then a
     * weighted nearest-seed assignment — ragged plate edges come free from the grid.
     */
    private void placePlates() {
        double vsAngle = Math.atan2(this.vsZ, this.vsX);
        for (int k = 0; k < PLATE_COUNT; k++) {
            boolean mega = k < MEGA_PLATES;
            boolean large = !mega && k < MEGA_PLATES + LARGE_PLATES;
            float weight = mega ? MEGA_WEIGHT : large ? LARGE_WEIGHT : 1.0F;
            double half = Math.toRadians(100.0D) * (mega ? 0.55D : 0.96D);
            double ang = vsAngle
                    + (CreditsSequence.hash01(this.nonce + k * 8191, 200) * 2.0D - 1.0D) * half;
            double rr = mega
                    ? this.sampleRadius * (0.45D + 0.5D * CreditsSequence.hash01(this.nonce + k * 8191, 201))
                    : this.sampleRadius * Math.sqrt(CreditsSequence.hash01(this.nonce + k * 8191, 201)) * 0.97D;
            this.plates[k] = new Plate((float) (Math.cos(ang) * rr), (float) (Math.sin(ang) * rr), weight);
        }
        for (Cell cell : this.cells) {
            float dx = cell.x - this.centerBlockX;
            float dz = cell.z - this.centerBlockZ;
            float best = Float.MAX_VALUE;
            float second = Float.MAX_VALUE;
            int bestK = 0;
            for (int k = 0; k < PLATE_COUNT; k++) {
                Plate plate = this.plates[k];
                float ddx = dx - plate.seedX;
                float ddz = dz - plate.seedZ;
                float d = (float) Math.sqrt(ddx * ddx + ddz * ddz) / plate.weight;
                if (d < best) {
                    second = best;
                    best = d;
                    bestK = k;
                } else if (d < second) {
                    second = d;
                }
            }
            cell.plate = bestK;
            cell.borderGap = second - best;
            Plate plate = this.plates[bestK];
            plate.members++;
            plate.mapCx += dx;
            plate.mapCz += dz;
        }
        for (Plate plate : this.plates) {
            if (plate.members > 0) {
                plate.mapCx /= plate.members;
                plate.mapCz /= plate.members;
            }
        }
    }

    /**
     * Lift-wave assignment: wave 1 = the {@code LIFT_WAVE_SIZE[0]} plates nearest the
     * hole (the hole tears out what it touches first); waves 2–5 walk the remaining
     * plates toward the camera by their map-plan projection onto the vantage
     * direction. Per-plate lift schedule + tilt geometry land here too.
     */
    private void assignWaves() {
        List<Plate> live = new ArrayList<>();
        for (Plate plate : this.plates) {
            if (plate.members > 0) {
                live.add(plate);
            }
        }
        live.sort((a, b) -> Float.compare(
                a.mapCx * a.mapCx + a.mapCz * a.mapCz, b.mapCx * b.mapCx + b.mapCz * b.mapCz));
        List<Plate> wave1 = new ArrayList<>(live.subList(0, Math.min(LIFT_WAVE_SIZE[0], live.size())));
        List<Plate> rest = new ArrayList<>(live.subList(wave1.size(), live.size()));
        rest.sort((a, b) -> Float.compare(
                a.mapCx * this.vsX + a.mapCz * this.vsZ, b.mapCx * this.vsX + b.mapCz * this.vsZ));
        int cursor = 0;
        for (int wave = 0; wave < LIFT_WAVE_AT.length; wave++) {
            List<Plate> group;
            if (wave == 0) {
                group = wave1;
            } else {
                int take = Math.min(LIFT_WAVE_SIZE[wave], rest.size() - cursor);
                group = rest.subList(cursor, cursor + Math.max(0, take));
                cursor += Math.max(0, take);
            }
            for (Plate plate : group) {
                int p = plateIndex(plate);
                plate.liftStart = LIFT_WAVE_AT[wave]
                        + (int) (CreditsSequence.hash01(this.nonce + p * 8191, 202)
                                * (2 * LIFT_JITTER)) - LIFT_JITTER;
                plate.liftHeight = LIFT_HEIGHT_MIN
                        + (float) CreditsSequence.hash01(this.nonce + p * 8191, 210) * LIFT_HEIGHT_VAR;
                plate.tiltRad = (float) Math.toRadians(TILT_MIN_DEG
                        + CreditsSequence.hash01(this.nonce + p * 8191, 211) * TILT_VAR_DEG);
                // Tilt axis: perpendicular of the plate→hole direction, signed so the
                // hole-side edge tips UP (the hole peels the crust toward itself).
                float hx = -plate.mapCx;
                float hz = -plate.mapCz;
                float hl = Math.max(1.0E-4F, (float) Math.sqrt(hx * hx + hz * hz));
                plate.axX = -hz / hl;
                plate.axZ = hx / hl;
            }
        }
        // Any overflow plates (short waves) ride the last wave.
        for (; cursor < rest.size(); cursor++) {
            Plate plate = rest.get(cursor);
            int p = plateIndex(plate);
            plate.liftStart = LIFT_WAVE_AT[LIFT_WAVE_AT.length - 1]
                    + (int) (CreditsSequence.hash01(this.nonce + p * 8191, 202) * (2 * LIFT_JITTER))
                    - LIFT_JITTER;
            plate.liftHeight = LIFT_HEIGHT_MIN
                    + (float) CreditsSequence.hash01(this.nonce + p * 8191, 210) * LIFT_HEIGHT_VAR;
            plate.tiltRad = (float) Math.toRadians(TILT_MIN_DEG
                    + CreditsSequence.hash01(this.nonce + p * 8191, 211) * TILT_VAR_DEG);
            float hx = -plate.mapCx;
            float hz = -plate.mapCz;
            float hl = Math.max(1.0E-4F, (float) Math.sqrt(hx * hx + hz * hz));
            plate.axX = -hz / hl;
            plate.axZ = hx / hl;
        }
    }

    private int plateIndex(Plate plate) {
        for (int k = 0; k < PLATE_COUNT; k++) {
            if (this.plates[k] == plate) {
                return k;
            }
        }
        return 0;
    }

    boolean prepared() {
        return this.prepared;
    }

    boolean staged() {
        return this.staged;
    }

    // ------------------------------------------------------------------ sampling

    boolean sampleRemaining() {
        return this.prepared && !this.staged;
    }

    /**
     * Budgeted heightmap sampling (≤ {@value #SAMPLE_PER_TICK} forced column reads/t,
     * spread across the post-card black — ~1300 chunk touches never land in one tick):
     * top block via {@code MOTION_BLOCKING_NO_LEAVES} (fluid columns probe down to
     * their seabed), plus one hashed strata pick for the flank of lifted plates. The
     * final batch finalizes all derived geometry ({@link #finalizeStage}).
     */
    void sampleBatch(ServerLevel overworld) {
        int budget = SAMPLE_PER_TICK;
        while (budget-- > 0 && this.sampleCursor < this.cells.size()) {
            Cell cell = this.cells.get(this.sampleCursor);
            overworld.getChunk(cell.x >> 4, cell.z >> 4); // force-load (GhostShipBuilder pattern)
            int top = overworld.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, cell.x, cell.z);
            BlockPos surface = new BlockPos(cell.x, top - 1, cell.z);
            BlockState state = overworld.getBlockState(surface);
            int drop = 0;
            while (!state.getFluidState().isEmpty() && drop++ < SEABED_SCAN) {
                surface = surface.below();
                state = overworld.getBlockState(surface);
            }
            cell.topY = surface.getY();
            cell.top = isRenderable(state) ? state : SAMPLE_FALLBACK;
            BlockState below = overworld.getBlockState(surface.below(
                    1 + (int) (CreditsSequence.hash01(this.sampleCursor, 238) * 3.0D)));
            cell.strata = isRenderable(below) ? below : SAMPLE_FALLBACK;
            this.sampleCursor++;
        }
        if (this.sampleCursor >= this.cells.size() && !this.staged) {
            finalizeStage();
        }
    }

    /** A state a block display can meaningfully render (no fluids, no invisibles). */
    private static boolean isRenderable(BlockState state) {
        return !state.isAir()
                && state.getFluidState().isEmpty()
                && state.getRenderShape() != net.minecraft.world.level.block.RenderShape.INVISIBLE;
    }

    /**
     * One tick of pure math once the sampling completes: replica base offsets (real
     * relief through the view-ray transform), plate/sub-plate centroids and fracture
     * partitions, the crossing/jet schedules, crack-front polylines + the seam-slat
     * pool, underside jobs and gravity-wave shard jobs.
     */
    private void finalizeStage() {
        // Replica base offsets + per-cell scale.
        for (Cell cell : this.cells) {
            double px = cell.x + 0.5D;
            double py = cell.topY + 0.5D;
            double pz = cell.z + 0.5D;
            cell.bx = (float) (this.vantage.x + (px - this.vantage.x) * this.replicaScale - this.fxAnchor.x);
            cell.by = (float) (this.vantage.y + (py - this.vantage.y) * this.replicaScale - this.fxAnchor.y);
            cell.bz = (float) (this.vantage.z + (pz - this.vantage.z) * this.replicaScale - this.fxAnchor.z);
            cell.scale = (cell.lod == 0 ? this.stepNear : this.stepFar) * this.replicaScale;
            cell.distHoriz = (float) Math.sqrt(cell.bx * cell.bx + cell.bz * cell.bz);
            this.maxDistHoriz = Math.max(this.maxDistHoriz, cell.distHoriz);
        }
        // Plate anchor-frame centroids.
        float[] px = new float[PLATE_COUNT];
        float[] py = new float[PLATE_COUNT];
        float[] pz = new float[PLATE_COUNT];
        for (Cell cell : this.cells) {
            px[cell.plate] += cell.bx;
            py[cell.plate] += cell.by;
            pz[cell.plate] += cell.bz;
        }
        for (int k = 0; k < PLATE_COUNT; k++) {
            if (this.plates[k].members > 0) {
                this.plates[k].cx = px[k] / this.plates[k].members;
                this.plates[k].cy = py[k] / this.plates[k].members;
                this.plates[k].cz = pz[k] / this.plates[k].members;
            }
        }
        buildSubPlates();
        buildSchedules();
        buildCrackFronts();
        buildUndersideJobs();
        buildShardJobs();
        this.staged = true;
        EclipseMod.LOGGER.info("CreditsMapRipAct: sampled — {} cell(s) / {} plate(s) / {} sub-plate(s), "
                + "{} seam slat(s), {} underside job(s) (pool {}), {} shard job(s) (pool {}), "
                + "peak ≈ {} display(s)", this.cells.size(), livePlateCount(), this.subs.size(),
                SEAM_POOL, this.undersideJobs.size(), Math.min(UNDERSIDE_POOL, this.undersideJobs.size()),
                this.shardJobs.size(), Math.min(SHARD_POOL, this.shardJobs.size()),
                this.cells.size() + SEAM_POOL + Math.min(SHARD_POOL, this.shardJobs.size())
                        + Math.min(UNDERSIDE_POOL, this.undersideJobs.size()));
    }

    private int livePlateCount() {
        int live = 0;
        for (Plate plate : this.plates) {
            if (plate.members > 0) {
                live++;
            }
        }
        return live;
    }

    /**
     * Hashed member partition of every plate into 2–4 sub-plates (angular wedges
     * around the plate's map centroid — coherent chunks, never confetti), plus the
     * per-sub infall/fracture/shred parameters.
     */
    private void buildSubPlates() {
        int[] subBase = new int[PLATE_COUNT];
        for (int k = 0; k < PLATE_COUNT; k++) {
            Plate plate = this.plates[k];
            subBase[k] = this.subs.size();
            plate.firstSub = subBase[k];
            plate.subCount = plate.members == 0 ? 0
                    : 2 + (int) (CreditsSequence.hash01(this.nonce + k * 8191, 203) * 3.0D);
            for (int s = 0; s < plate.subCount; s++) {
                this.subs.add(new SubPlate(k));
            }
        }
        for (Cell cell : this.cells) {
            Plate plate = this.plates[cell.plate];
            double ang = Math.atan2(cell.z - this.centerBlockZ - plate.mapCz,
                    cell.x - this.centerBlockX - plate.mapCx) / (Math.PI * 2.0D) + 0.5D;
            int wedge = Math.min(plate.subCount - 1, (int) ((ang
                    + CreditsSequence.hash01(this.nonce + cell.plate * 8191, 204)) % 1.0D
                    * plate.subCount));
            cell.sub = subBase[cell.plate] + wedge;
            SubPlate sub = this.subs.get(cell.sub);
            sub.members++;
            sub.cx += cell.bx;
            sub.cy += cell.by;
            sub.cz += cell.bz;
        }
        int[] rankCursor = new int[this.subs.size()];
        for (int i = 0; i < this.subs.size(); i++) {
            SubPlate sub = this.subs.get(i);
            if (sub.members > 0) {
                sub.cx /= sub.members;
                sub.cy /= sub.members;
                sub.cz /= sub.members;
            }
        }
        for (Cell cell : this.cells) {
            SubPlate sub = this.subs.get(cell.sub);
            // Normalized member rank −1..1 (spread order = grid order — deterministic).
            cell.rank = sub.members <= 1 ? 0.0F
                    : (rankCursor[cell.sub]++ / (float) (sub.members - 1)) * 2.0F - 1.0F;
        }
        for (int i = 0; i < this.subs.size(); i++) {
            SubPlate sub = this.subs.get(i);
            Plate plate = this.plates[sub.plate];
            float kx = sub.cx - plate.cx;
            float kz = sub.cz - plate.cz;
            float kl = (float) Math.sqrt(kx * kx + kz * kz);
            if (kl < 1.0E-3F) {
                double a = CreditsSequence.hash01(this.nonce + i * 131, 214) * Math.PI * 2.0D;
                sub.kickX = (float) Math.cos(a);
                sub.kickZ = (float) Math.sin(a);
            } else {
                sub.kickX = kx / kl;
                sub.kickZ = kz / kl;
            }
            sub.kickDist = 0.6F + (float) CreditsSequence.hash01(this.nonce + i * 131, 214);
            sub.extraTilt = ((float) CreditsSequence.hash01(this.nonce + i * 131, 215) * 2.0F - 1.0F)
                    * (float) Math.toRadians(6.0D);
            sub.infallDur = INFALL_MIN
                    + (int) (CreditsSequence.hash01(this.nonce + i * 131, 212) * INFALL_VAR);
            sub.turns = 1.5F + (float) CreditsSequence.hash01(this.nonce + i * 131, 213) * 1.7F;
            sub.crossTick = plate.liftStart == Integer.MAX_VALUE ? Integer.MAX_VALUE
                    : plate.liftStart + LIFT_TICKS + Math.round(DRAIN_Q * sub.infallDur);
            // FXWAVE-9 #4 mass scaling: small splinters now gulp at 0.45, only true
            // continents reach 1.0 — the shockwave/blink/lens pulse reads plate MASS
            // (the old 0.75 floor made a 3-cell shard thump like a landmass).
            sub.crossStrength = Mth.clamp(0.45F + 0.55F * sub.members / 24.0F, 0.45F, 1.0F);
            boolean inJet2 = sub.crossTick >= JET2_FROM && sub.crossTick < JET2_UNTIL;
            double shredChance = inJet2
                    ? JET_SHRED_CHANCE + (JET2_SHRED_CHANCE - JET_SHRED_CHANCE)
                            * Mth.clamp((sub.crossTick - JET2_FROM)
                                    / (float) (JET2_UNTIL - JET2_FROM), 0.0F, 1.0F)
                    : JET_SHRED_CHANCE;
            sub.shredded = sub.members > 0 && sub.crossTick >= JET_FROM
                    && sub.crossTick < WIND_DOWN_START
                    && CreditsSequence.hash01(this.nonce + i * 131, 216) < shredChance;
            sub.jetSide = CreditsSequence.hash01(this.nonce + i * 131, 217) < 0.5D ? 1.0F : -1.0F;
        }
        forceBipolarPeak();
    }

    /**
     * FXWAVE-9 #4: the two LARGEST sub-plates crossing inside the second jet window
     * always shred, at full strength, on OPPOSED jet sides — a guaranteed bipolar
     * finale pair regardless of the hash rolls.
     */
    private void forceBipolarPeak() {
        SubPlate biggest = null;
        SubPlate second = null;
        for (SubPlate sub : this.subs) {
            if (sub.members == 0 || sub.crossTick < JET2_FROM || sub.crossTick >= JET2_UNTIL) {
                continue;
            }
            if (biggest == null || sub.members > biggest.members) {
                second = biggest;
                biggest = sub;
            } else if (second == null || sub.members > second.members) {
                second = sub;
            }
        }
        if (biggest != null) {
            biggest.shredded = true;
            biggest.crossStrength = 1.0F;
            biggest.jetSide = 1.0F;
        }
        if (second != null) {
            second.shredded = true;
            second.crossStrength = 1.0F;
            second.jetSide = -1.0F;
        }
    }

    /** Bakes the crossing/jet strengths into by-tick lookup tables (O(1) queries). */
    private void buildSchedules() {
        this.crossingByTick = new float[CreditsBlackHoleAct.SPIRAL_TICKS + 64];
        this.jetByTick = new float[this.crossingByTick.length];
        java.util.Arrays.fill(this.crossingByTick, -1.0F);
        java.util.Arrays.fill(this.jetByTick, -1.0F);
        for (SubPlate sub : this.subs) {
            if (sub.members == 0 || sub.crossTick < 0
                    || sub.crossTick >= this.crossingByTick.length) {
                continue;
            }
            this.crossingByTick[sub.crossTick] =
                    Math.max(this.crossingByTick[sub.crossTick], sub.crossStrength);
            if (sub.shredded) {
                this.jetByTick[sub.crossTick] =
                        Math.max(this.jetByTick[sub.crossTick], sub.crossStrength);
            }
        }
    }

    /**
     * Crack-front polylines: hashed start (hole-side) → end (camera-side rim) rays
     * fanned ±50° around the vantage direction, waypoints wobbled laterally and then
     * SNAPPED onto the nearest Voronoi-border cell — the glowing seams follow the
     * plate borders the later tear opens along (cause and effect read as one system).
     * The {@value #SEAM_POOL} slat pool is laid along the polylines, each slat timed
     * to its propagation step and fading when its border's plate lifts.
     */
    private void buildCrackFronts() {
        List<Cell> border = new ArrayList<>();
        for (Cell cell : this.cells) {
            if (cell.borderGap < BORDER_EPS) {
                border.add(cell);
            }
        }
        for (int f = 0; f < CRACK_FRONT_AT.length; f++) {
            double a0 = Math.atan2(-this.vsZ, -this.vsX)
                    + (CreditsSequence.hash01(this.nonce + f * 977, 220) * 2.0D - 1.0D)
                            * Math.toRadians(50.0D);
            double a1 = Math.atan2(this.vsZ, this.vsX)
                    + (CreditsSequence.hash01(this.nonce + f * 977, 221) * 2.0D - 1.0D)
                            * Math.toRadians(50.0D);
            float sx = (float) (Math.cos(a0) * this.sampleRadius * 0.55D);
            float sz = (float) (Math.sin(a0) * this.sampleRadius * 0.55D);
            float ex = (float) (Math.cos(a1) * this.sampleRadius * 0.92D);
            float ez = (float) (Math.sin(a1) * this.sampleRadius * 0.92D);
            for (int k = 0; k <= CRACK_STEPS; k++) {
                float u = k / (float) CRACK_STEPS;
                float wob = (float) (CreditsSequence.hash01(this.nonce + f * 977 + k, 222) * 2.0D - 1.0D)
                        * 0.12F * this.sampleRadius * (k == 0 || k == CRACK_STEPS ? 0.0F : 1.0F);
                float mx = Mth.lerp(u, sx, ex) - (ez - sz) * wob / this.sampleRadius;
                float mz = Mth.lerp(u, sz, ez) + (ex - sx) * wob / this.sampleRadius;
                Cell snap = nearestCell(border, mx, mz, 30.0F);
                if (snap == null) {
                    snap = nearestCell(this.cells, mx, mz, Float.MAX_VALUE);
                }
                this.crackWaypoints[f][k] = snap == null
                        ? new Vector3f(mx * this.replicaScale, 0.0F, mz * this.replicaScale)
                        : new Vector3f(snap.bx, snap.by, snap.bz);
            }
        }
        // The slat pool along the polylines (per front ≈ SEAM_POOL / 3, ≈ 9 per segment).
        int perFront = SEAM_POOL / CRACK_FRONT_AT.length;
        for (int slat = 0; slat < SEAM_POOL; slat++) {
            int f = Math.min(CRACK_FRONT_AT.length - 1, slat / perFront);
            int within = slat - f * perFront;
            int perSeg = Math.max(1, perFront / CRACK_STEPS);
            int seg = Math.min(CRACK_STEPS - 1, within / perSeg);
            float u = (within - seg * perSeg + 0.5F) / perSeg;
            Vector3f a = this.crackWaypoints[f][seg];
            Vector3f b = this.crackWaypoints[f][seg + 1];
            Vector3f pos = new Vector3f(a).lerp(b, u);
            float lat = ((float) CreditsSequence.hash01(slat, 223) - 0.5F) * 0.8F;
            Vector3f dir = new Vector3f(b).sub(a);
            float len = Math.max(0.6F, dir.length());
            dir.div(len);
            pos.add(-dir.z * lat, 0.35F, dir.x * lat);
            this.seamPos[slat] = pos;
            this.seamYaw[slat] = (float) Math.atan2(dir.x, dir.z);
            this.seamLen[slat] = len / perSeg * 1.15F;
            this.seamAppear[slat] = CRACK_FRONT_AT[f] + seg * CRACK_STEP_TICKS
                    + (int) (u * CRACK_STEP_TICKS * 0.8F);
            Cell nearest = nearestCell(this.cells, pos.x / this.replicaScale,
                    pos.z / this.replicaScale, Float.MAX_VALUE);
            int lift = nearest == null ? LIFT_WAVE_AT[0]
                    : this.plates[nearest.plate].liftStart;
            this.seamFade[slat] = (lift == Integer.MAX_VALUE ? WIND_DOWN_START : lift)
                    + (int) (CreditsSequence.hash01(slat, 219) * 10.0D);
        }
    }

    /** Nearest cell to a map-plan offset (relative to the hole column), or null. */
    @javax.annotation.Nullable
    private Cell nearestCell(List<Cell> pool, float mapDx, float mapDz, float maxDist) {
        Cell best = null;
        float bestD = maxDist * maxDist;
        for (Cell cell : pool) {
            float dx = cell.x - this.centerBlockX - mapDx;
            float dz = cell.z - this.centerBlockZ - mapDz;
            float d = dx * dx + dz * dz;
            if (d < bestD) {
                bestD = d;
                best = cell;
            }
        }
        return best;
    }

    /**
     * Underside jobs: ~1 dark slab per 2.5 members + ~1 hanging stalactite per 6,
     * per plate, active from just before the plate's lift until its sub-plate drains.
     * Jobs sort by start and round-robin over the {@value #UNDERSIDE_POOL} pool —
     * earlier waves' pieces re-arm for later waves (never despawned mid-act).
     */
    private void buildUndersideJobs() {
        int[] plateCursor = new int[PLATE_COUNT];
        for (int i = 0; i < this.cells.size(); i++) {
            Cell cell = this.cells.get(i);
            Plate plate = this.plates[cell.plate];
            if (plate.liftStart == Integer.MAX_VALUE) {
                continue;
            }
            int n = plateCursor[cell.plate]++;
            boolean slab = n % 5 < 2; // ≈ 1 per 2.5 members
            boolean stalactite = n % 6 == 3; // ≈ 1 per 6 members
            if (!slab && !stalactite) {
                continue;
            }
            SubPlate sub = this.subs.get(cell.sub);
            int end = plate.liftStart + LIFT_TICKS + sub.infallDur;
            this.undersideJobs.add(new UndersideJob(i, stalactite && !slab,
                    plate.liftStart + 2, end));
        }
        this.undersideJobs.sort((a, b) -> Integer.compare(a.start(), b.start()));
        int slots = Math.min(UNDERSIDE_POOL, this.undersideJobs.size());
        this.undersideSlotJobs = new int[slots][];
        if (slots == 0) {
            this.undersideJobCache = new int[0];
            return;
        }
        List<List<Integer>> bySlot = new ArrayList<>(slots);
        for (int s = 0; s < slots; s++) {
            bySlot.add(new ArrayList<>(2));
        }
        for (int j = 0; j < this.undersideJobs.size(); j++) {
            bySlot.get(j % slots).add(j);
        }
        for (int s = 0; s < slots; s++) {
            this.undersideSlotJobs[s] = bySlot.get(s).stream().mapToInt(Integer::intValue).toArray();
        }
        this.undersideJobCache = new int[slots];
        java.util.Arrays.fill(this.undersideJobCache, Integer.MIN_VALUE);
    }

    /**
     * Gravity-wave shard jobs: as each ring crest passes a still-resting cell, a
     * hashed ~8% strip a small shard off the surface (hop up, then a fast flat spiral
     * into the hole). Jobs round-robin over the {@value #SHARD_POOL} pool.
     */
    private void buildShardJobs() {
        for (int w = 0; w < GRAVITY_WAVE_AT.length; w++) {
            for (int i = 0; i < this.cells.size(); i++) {
                Cell cell = this.cells.get(i);
                Plate plate = this.plates[cell.plate];
                int crest = GRAVITY_WAVE_AT[w] + (int) (cell.distHoriz / WAVE_SPEED);
                if (crest + 6 >= plate.liftStart || crest >= WIND_DOWN_START) {
                    continue; // only un-lifted crust strips
                }
                if (CreditsSequence.hash01(i, 230 + w) < SHARD_STRIP_CHANCE) {
                    this.shardJobs.add(new ShardJob(i, crest));
                }
            }
        }
        this.shardJobs.sort((a, b) -> Integer.compare(a.start(), b.start()));
        int slots = Math.min(SHARD_POOL, this.shardJobs.size());
        this.shardSlotJobs = new int[slots][];
        if (slots == 0) {
            this.shardJobCache = new int[0];
            return;
        }
        List<List<Integer>> bySlot = new ArrayList<>(slots);
        for (int s = 0; s < slots; s++) {
            bySlot.add(new ArrayList<>(4));
        }
        for (int j = 0; j < this.shardJobs.size(); j++) {
            bySlot.get(j % slots).add(j);
        }
        for (int s = 0; s < slots; s++) {
            this.shardSlotJobs[s] = bySlot.get(s).stream().mapToInt(Integer::intValue).toArray();
        }
        this.shardJobCache = new int[slots];
        java.util.Arrays.fill(this.shardJobCache, Integer.MIN_VALUE);
    }

    // ------------------------------------------------------------------ spawning

    private int mainSpawnTotal() {
        return this.cells.size() + SEAM_POOL
                + (this.shardSlotJobs == null ? 0 : this.shardSlotJobs.length);
    }

    boolean spawnRemaining() {
        return this.staged && this.spawnCursor < mainSpawnTotal();
    }

    /**
     * Budgeted spawn behind the post-card black (crust → seam pool → shard pool, all
     * parked at the shared anchor, tracking-safe): the crust spawns at its identity
     * REST pose — the reveal at offset 0 opens on the finished intact map replica;
     * the pools spawn at the scale floor and wait for their schedules.
     */
    void spawnBatch(ServerLevel overworld, int ripTick) {
        int budget = SPAWN_PER_TICK;
        while (budget-- > 0 && this.spawnCursor < mainSpawnTotal()) {
            if (CreditsSequence.actCapReached()) {
                this.spawnCursor = mainSpawnTotal();
                this.undersideCursor = Integer.MAX_VALUE;
                break;
            }
            Display.BlockDisplay piece = EntityType.BLOCK_DISPLAY.create(overworld);
            if (piece == null) {
                return; // retry the same index next tick (list/index alignment invariant)
            }
            int i = this.spawnCursor;
            piece.moveTo(this.fxAnchor.x, this.fxAnchor.y, this.fxAnchor.z, 0.0F, 0.0F);
            piece.setTransformationInterpolationDelay(0);
            piece.setTransformationInterpolationDuration(0);
            if (i < this.cells.size()) {
                Cell cell = this.cells.get(i);
                piece.setBlockState(cell.top);
                piece.setTransformation(crustPose(i, ripTick));
                // Dim space brightness — the intact map lies under a starlit sky.
                CreditsSequence.applyBrightnessOverride(piece, 5, 2);
                this.crustDisplays.add(piece);
            } else if (i < this.cells.size() + SEAM_POOL) {
                int slat = i - this.cells.size();
                piece.setBlockState(SEAM_PALETTE[
                        CreditsSequence.hash01(slat, 218) < 0.72D ? 0 : 1]);
                piece.setTransformation(seamPose(slat, ripTick));
                CreditsSequence.applyBrightnessOverride(piece, 15, 15);
                this.seamDisplays.add(piece);
            } else {
                int slot = i - this.cells.size() - SEAM_POOL;
                this.shardJobCache[slot] = this.shardSlotJobs[slot].length == 0
                        ? Integer.MIN_VALUE : this.shardSlotJobs[slot][0];
                piece.setBlockState(this.shardJobCache[slot] == Integer.MIN_VALUE
                        ? SAMPLE_FALLBACK
                        : this.cells.get(this.shardJobs.get(this.shardJobCache[slot]).cell()).top);
                piece.setTransformation(shardPose(slot, ripTick));
                CreditsSequence.applyBrightnessOverride(piece, 5, 2);
                this.shardDisplays.add(piece);
            }
            piece.addTag(TAG);
            CreditsSequence.applyViewRange(piece, VIEW_RANGE);
            CreditsSequence.trackDisplay(piece);
            overworld.addFreshEntity(piece);
            this.spawnCursor++;
        }
        if (this.spawnCursor >= mainSpawnTotal()) {
            EclipseMod.LOGGER.info("CreditsMapRipAct: effigy live — {} crust + {} seam + {} shard "
                    + "display(s) (underside pool of {} arms at offset {})", this.crustDisplays.size(),
                    this.seamDisplays.size(), this.shardDisplays.size(),
                    this.undersideSlotJobs == null ? 0 : this.undersideSlotJobs.length,
                    UNDERSIDE_SPAWN_AT);
        }
    }

    boolean undersideSpawnRemaining(int ripTick) {
        return this.staged && ripTick >= UNDERSIDE_SPAWN_AT
                && this.undersideSlotJobs != null
                && this.undersideCursor < this.undersideSlotJobs.length;
    }

    /** The underside pool arms just before lift wave 1 (spawned at the scale floor). */
    void spawnUndersideBatch(ServerLevel overworld, int ripTick) {
        int budget = UNDERSIDE_SPAWN_PER_TICK;
        while (budget-- > 0 && this.undersideCursor < this.undersideSlotJobs.length) {
            if (CreditsSequence.actCapReached()) {
                this.undersideCursor = Integer.MAX_VALUE;
                break;
            }
            Display.BlockDisplay piece = EntityType.BLOCK_DISPLAY.create(overworld);
            if (piece == null) {
                return;
            }
            int slot = this.undersideCursor;
            UndersideJob first = this.undersideJobs.get(this.undersideSlotJobs[slot][0]);
            piece.moveTo(this.fxAnchor.x, this.fxAnchor.y, this.fxAnchor.z, 0.0F, 0.0F);
            piece.setBlockState(undersideState(slot, first));
            piece.addTag(TAG);
            piece.setTransformationInterpolationDelay(0);
            piece.setTransformationInterpolationDuration(0);
            piece.setTransformation(undersidePose(slot, ripTick));
            CreditsSequence.applyBrightnessOverride(piece, 4, 1);
            CreditsSequence.applyViewRange(piece, VIEW_RANGE);
            CreditsSequence.trackDisplay(piece);
            overworld.addFreshEntity(piece);
            this.undersideDisplays.add(piece);
            this.undersideJobCache[slot] = this.undersideSlotJobs[slot][0];
            this.undersideCursor++;
        }
        if (this.undersideCursor >= this.undersideSlotJobs.length) {
            EclipseMod.LOGGER.info("CreditsMapRipAct: underside pool armed — {} display(s)",
                    this.undersideDisplays.size());
        }
    }

    private BlockState undersideState(int slot, UndersideJob job) {
        if (!job.stalactite()) {
            return UNDERSIDE_PALETTE[CreditsSequence.hash01(slot, 225) < 0.55D ? 0 : 1];
        }
        return CreditsSequence.hash01(slot, 225) < 0.5D ? STALACTITE_STATE : STALACTITE_COLUMN;
    }

    // ------------------------------------------------------------------ animate

    /**
     * One lookahead interpolation window per {@value #PUSH_STRIDE}t for every pool,
     * plus the edge-triggered look swaps (terrain → strata flank → heat → deep layer;
     * pool pieces re-skin only when their active job changes — never per-push).
     */
    void animate(int ripTick) {
        for (int i = 0; i < this.crustDisplays.size(); i++) {
            Display.BlockDisplay piece = this.crustDisplays.get(i);
            if (piece.isRemoved()) {
                continue;
            }
            piece.setTransformationInterpolationDelay(0);
            piece.setTransformationInterpolationDuration(PUSH_STRIDE);
            piece.setTransformation(crustPose(i, ripTick + PUSH_STRIDE));
            byte want = crustLook(i, ripTick);
            if (want != this.crustLookCache[i]) {
                this.crustLookCache[i] = want;
                Cell cell = this.cells.get(i);
                switch (want) {
                    case LOOK_HOT -> {
                        piece.setBlockState(heatState(i));
                        CreditsSequence.applyBrightnessOverride(piece, 15, 15);
                    }
                    case LOOK_DEEP -> {
                        piece.setBlockState(deepState(i));
                        CreditsSequence.applyBrightnessOverride(piece, 2, 0);
                    }
                    case LOOK_STRATA -> {
                        piece.setBlockState(cell.strata);
                        CreditsSequence.applyBrightnessOverride(piece, 5, 2);
                    }
                    default -> {
                        piece.setBlockState(cell.top);
                        CreditsSequence.applyBrightnessOverride(piece, 5, 2);
                    }
                }
            }
        }
        for (int slat = 0; slat < this.seamDisplays.size(); slat++) {
            Display.BlockDisplay piece = this.seamDisplays.get(slat);
            if (piece.isRemoved()) {
                continue;
            }
            piece.setTransformationInterpolationDelay(0);
            piece.setTransformationInterpolationDuration(PUSH_STRIDE);
            piece.setTransformation(seamPose(slat, ripTick + PUSH_STRIDE));
        }
        for (int slot = 0; slot < this.shardDisplays.size(); slot++) {
            Display.BlockDisplay piece = this.shardDisplays.get(slot);
            if (piece.isRemoved()) {
                continue;
            }
            piece.setTransformationInterpolationDelay(0);
            piece.setTransformationInterpolationDuration(PUSH_STRIDE);
            piece.setTransformation(shardPose(slot, ripTick + PUSH_STRIDE));
            int job = activeShardJob(slot, ripTick);
            if (job != this.shardJobCache[slot] && job != Integer.MIN_VALUE) {
                this.shardJobCache[slot] = job;
                piece.setBlockState(this.cells.get(this.shardJobs.get(job).cell()).top);
            }
        }
        for (int slot = 0; slot < this.undersideDisplays.size(); slot++) {
            Display.BlockDisplay piece = this.undersideDisplays.get(slot);
            if (piece.isRemoved()) {
                continue;
            }
            piece.setTransformationInterpolationDelay(0);
            piece.setTransformationInterpolationDuration(PUSH_STRIDE);
            piece.setTransformation(undersidePose(slot, ripTick + PUSH_STRIDE));
            int job = activeUndersideJob(slot, ripTick);
            if (job != this.undersideJobCache[slot] && job != Integer.MIN_VALUE) {
                this.undersideJobCache[slot] = job;
                piece.setBlockState(undersideState(slot, this.undersideJobs.get(job)));
            }
        }
    }

    /** V3 heat pick: magma core with a hashed shroomlight accent (the F-072 law). */
    private static BlockState heatState(int index) {
        return CreditsSequence.hash01(index, 104) < 0.25D ? HEAT_ACCENT : HEAT_PRIMARY;
    }

    private static BlockState deepState(int index) {
        return DEEP_PALETTE[(int) (CreditsSequence.hash01(index, 206) * DEEP_PALETTE.length)
                % DEEP_PALETTE.length];
    }

    // ------------------------------------------------------------------ schedules

    /**
     * The deterministic horizon-crossing schedule: strength 0.75..1 when a sub-plate
     * pours over the horizon exactly at {@code ripTick}, else −1. {@code
     * CreditsSequence.devourPulse} takes {@code max(swallowPulse, plateCrossing)} —
     * the shockwave/blink/thump land exactly when a continent visibly goes over.
     */
    float plateCrossing(int ripTick) {
        return this.staged && ripTick >= 0 && ripTick < this.crossingByTick.length
                ? this.crossingByTick[ripTick] : -1.0F;
    }

    /**
     * The jet-shred schedule (the shredded subset of {@link #plateCrossing}): strength
     * when a shredded sub-plate starts its ±jet-axis spray at {@code ripTick}, else
     * −1. {@code CreditsSequence} answers with {@code credits4_jetburst} + the
     * {@code S2CCreditsJetPayload} strobe.
     */
    float jetBurst(int ripTick) {
        return this.staged && ripTick >= 0 && ripTick < this.jetByTick.length
                ? this.jetByTick[ripTick] : -1.0F;
    }

    /**
     * The crack-front propagation schedule: the step landing exactly at
     * {@code ripTick} (front offsets {@link #CRACK_FRONT_AT}, {@value #CRACK_STEPS} ×
     * {@value #CRACK_STEP_TICKS}t each — the offsets are staggered so no two fronts
     * ever share a tick), with the step's segment midpoint in WORLD space for the
     * {@code credits4_crackfront} cue. Null on every other tick.
     */
    @javax.annotation.Nullable
    CrackStep crackStep(int ripTick) {
        if (!this.staged) {
            return null;
        }
        for (int f = 0; f < CRACK_FRONT_AT.length; f++) {
            int local = ripTick - CRACK_FRONT_AT[f];
            if (local < 0 || local >= CRACK_STEPS * CRACK_STEP_TICKS
                    || local % CRACK_STEP_TICKS != 0) {
                continue;
            }
            int step = local / CRACK_STEP_TICKS;
            Vector3f mid = new Vector3f(this.crackWaypoints[f][step])
                    .lerp(this.crackWaypoints[f][step + 1], 0.5F);
            return new CrackStep(f, step, step / (float) (CRACK_STEPS - 1),
                    new Vec3(this.fxAnchor.x + mid.x, this.fxAnchor.y + mid.y,
                            this.fxAnchor.z + mid.z));
        }
        return null;
    }

    /**
     * The sub-fracture beats: world positions of every plate splitting exactly at
     * {@code ripTick} (lift+{@value #FRACTURE_TICK}t), for the
     * {@code credits4_platebreak} cue + crack SFX. Usually empty; never more than a
     * couple of entries on one tick (the per-plate lift jitter de-phases them).
     */
    List<Vec3> plateBreaks(int ripTick) {
        if (!this.staged) {
            return List.of();
        }
        List<Vec3> breaks = null;
        for (Plate plate : this.plates) {
            if (plate.members == 0 || plate.liftStart == Integer.MAX_VALUE
                    || ripTick != plate.liftStart + FRACTURE_TICK) {
                continue;
            }
            float lift = easeInOut(FRACTURE_TICK / (float) LIFT_TICKS) * plate.liftHeight;
            if (breaks == null) {
                breaks = new ArrayList<>(2);
            }
            breaks.add(new Vec3(this.fxAnchor.x + plate.cx,
                    this.fxAnchor.y + plate.cy + lift, this.fxAnchor.z + plate.cz));
        }
        return breaks == null ? List.of() : breaks;
    }

    void discard() {
        discardList(this.crustDisplays);
        discardList(this.seamDisplays);
        discardList(this.shardDisplays);
        discardList(this.undersideDisplays);
    }

    private static void discardList(List<Display.BlockDisplay> displays) {
        for (Display.BlockDisplay piece : displays) {
            CreditsSequence.untrackDisplay(piece);
            piece.discard();
        }
        displays.clear();
    }

    // ------------------------------------------------------------------ look law

    /**
     * The crust member's current skin (pure function of {@code (index, ripTick)},
     * mirroring the pose branches): terrain → hashed strata flank once its plate is
     * airborne → magma heat across the infall's last quarter / the jet shred / the
     * deep rip → the dark deep-layer state between swallow and rip.
     */
    private byte crustLook(int i, int ripTick) {
        Cell cell = this.cells.get(i);
        Plate plate = this.plates[cell.plate];
        SubPlate sub = this.subs.get(cell.sub);
        if (plate.liftStart == Integer.MAX_VALUE || ripTick < plate.liftStart) {
            return LOOK_COLD;
        }
        int liftEnd = plate.liftStart + LIFT_TICKS;
        int deepStart = sub.shredded ? sub.crossTick + JET_SPRAY_TICKS : liftEnd + sub.infallDur;
        if (ripTick >= deepStart) {
            int ripStart = deepRipStart(cell, deepStart);
            return ripTick >= ripStart + (int) (0.3F * DEEP_RIP_DUR) ? LOOK_HOT : LOOK_DEEP;
        }
        if (sub.shredded && ripTick >= sub.crossTick) {
            return LOOK_HOT;
        }
        if (ripTick >= liftEnd
                && (ripTick - liftEnd) / (float) sub.infallDur >= HEAT_Q) {
            return LOOK_HOT;
        }
        return CreditsSequence.hash01(i, 205) < 0.28D ? LOOK_STRATA : LOOK_COLD;
    }

    // ------------------------------------------------------------------ poses

    /** Smoothstep (the house easing). */
    private static float easeInOut(float p) {
        p = Mth.clamp(p, 0.0F, 1.0F);
        return p * p * (3.0F - 2.0F * p);
    }

    /** Act wind-down envelope (1160–1300: every pool drains to the floor). */
    private static float windDown(int ripTick) {
        return 1.0F - Mth.clamp((ripTick - WIND_DOWN_START) / (float) WIND_DOWN_TICKS, 0.0F, 1.0F);
    }

    /** Traveling gravity-wave bob of a still-resting cell (pure pose-side). */
    private float waveBob(Cell cell, int ripTick) {
        float bob = 0.0F;
        for (int w = 0; w < GRAVITY_WAVE_AT.length; w++) {
            float u = (ripTick - GRAVITY_WAVE_AT[w] - cell.distHoriz / WAVE_SPEED) / WAVE_BOB_TICKS;
            if (u > 0.0F && u < 1.0F) {
                bob += WAVE_BOB_AMP * Mth.sin(Mth.TWO_PI * u) * Mth.sin((float) Math.PI * u);
            }
        }
        return bob;
    }

    /** Deep-rip start of a cell: the cascade walks hole-outward from the rip beat. */
    private int deepRipStart(Cell cell, int deepStart) {
        return Math.max(DEEP_RIP_AT
                + (int) (cell.distHoriz / this.maxDistHoriz * DEEP_RIP_STAGGER),
                deepStart + DEEP_GROW_TICKS);
    }

    /** Shared (sub-)plate frame result: member position, frame rotation, envelopes. */
    private static final class FramePose {
        final Vector3f pos = new Vector3f();
        final Quaternionf rot = new Quaternionf();
        float drain = 1.0F;
        float stretchRamp;
    }

    /**
     * The rigid-body fake, resolved for one member: {@code plateOrigin(t) +
     * R_plate(t) · (cellOffset − centroid)} through rest → lift/tilt → the fracture
     * snap (kick + divergent tilt ease in over {@value #FRACTURE_SNAP_TICKS}t — the
     * sub frame equals the plate frame at the snap start, so the split never pops) →
     * the spiral infall with plate-level spaghettization. {@code extraDown} shifts
     * the member's local offset down the plate frame (the underside pieces ride the
     * SAME transform for free).
     */
    private FramePose framePoseAt(int i, int ripTick, float extraDown) {
        Cell cell = this.cells.get(i);
        Plate plate = this.plates[cell.plate];
        SubPlate sub = this.subs.get(cell.sub);
        FramePose frame = new FramePose();
        if (plate.liftStart == Integer.MAX_VALUE || ripTick <= plate.liftStart) {
            frame.pos.set(cell.bx, cell.by - extraDown + waveBob(cell, ripTick), cell.bz);
            return frame;
        }
        int snapT = plate.liftStart + FRACTURE_TICK;
        int liftEnd = plate.liftStart + LIFT_TICKS;
        Vector3f local = new Vector3f(cell.bx - sub.cx, cell.by - sub.cy - extraDown,
                cell.bz - sub.cz);
        if (ripTick <= liftEnd) {
            float u = Mth.clamp((ripTick - plate.liftStart) / (float) LIFT_TICKS, 0.0F, 1.0F);
            float lift = easeInOut(u) * plate.liftHeight;
            // Eased kick-back: the tilt overshoots slightly and settles while rising.
            float tilt = plate.tiltRad * easeInOut(Math.min(1.0F, u * 1.25F))
                    * (1.0F + 0.10F * Mth.sin(u * 14.0F) * (1.0F - u));
            Quaternionf plateRot = new Quaternionf().rotationAxis(tilt, plate.axX, 0.0F, plate.axZ);
            float w = ripTick < snapT ? 0.0F
                    : Mth.clamp((ripTick - snapT) / FRACTURE_SNAP_TICKS, 0.0F, 1.0F);
            frame.rot.set(plateRot);
            if (w > 0.0F) {
                frame.rot.mul(new Quaternionf().rotationAxis(sub.extraTilt * easeInOut(w),
                        plate.axX, 0.0F, plate.axZ));
            }
            Vector3f subOff = plateRot.transform(new Vector3f(
                    sub.cx - plate.cx, sub.cy - plate.cy, sub.cz - plate.cz));
            float kick = easeInOut(w) * sub.kickDist;
            frame.pos.set(plate.cx, plate.cy + lift, plate.cz).add(subOff)
                    .add(sub.kickX * kick, 0.0F, sub.kickZ * kick);
            frame.pos.add(frame.rot.transform(local));
            return frame;
        }
        // Infall: the sub-plate spirals in from its deterministic lift-end pose.
        float q = Mth.clamp((ripTick - liftEnd) / (float) sub.infallDur, 0.0F, 1.0F);
        Quaternionf endPlateRot = new Quaternionf().rotationAxis(plate.tiltRad,
                plate.axX, 0.0F, plate.axZ);
        Quaternionf endRot = new Quaternionf(endPlateRot).mul(new Quaternionf()
                .rotationAxis(sub.extraTilt, plate.axX, 0.0F, plate.axZ));
        Vector3f start = new Vector3f(plate.cx, plate.cy + plate.liftHeight, plate.cz)
                .add(endPlateRot.transform(new Vector3f(
                        sub.cx - plate.cx, sub.cy - plate.cy, sub.cz - plate.cz)))
                .add(sub.kickX * sub.kickDist, 0.0F, sub.kickZ * sub.kickDist);
        float hr = Math.max(1.0E-3F, (float) Math.sqrt(start.x * start.x + start.z * start.z));
        float ang0 = (float) Math.atan2(start.z, start.x);
        // Rising angular velocity ∝ q² → the swept angle grows ∝ q³.
        float theta = sub.turns * Mth.TWO_PI * q * q * q;
        float hNow = Math.max(SWALLOW_RADIUS, hr * (float) Math.pow(1.0F - q, 1.4D));
        float ang = ang0 + theta;
        Vector3f origin = new Vector3f(hNow * Mth.cos(ang),
                start.y * (float) Math.pow(1.0F - q, 1.15D), hNow * Mth.sin(ang));
        // rotationY(−θ) advances positions by +θ in the atan2 frame (JOML handedness).
        frame.rot.rotationY(-theta).mul(endRot);
        Vector3f lw = frame.rot.transform(local, new Vector3f());
        float ramp = Mth.clamp((q - STRETCH_START_Q) / (1.0F - STRETCH_START_Q), 0.0F, 1.0F);
        frame.stretchRamp = ramp;
        if (ramp > 0.0F) {
            // Plate-level spaghettification: the sub frame stretches radially, thins
            // crosswise (inverse-sqrt keeps the visual mass roughly constant).
            float stretch = 1.0F + (PLATE_STRETCH_MAX - 1.0F) * ramp * ramp;
            Vector3f radial = new Vector3f(-origin.x, 0.0F, -origin.z);
            float rl = radial.length();
            if (rl > 1.0E-3F) {
                radial.div(rl);
                float par = lw.dot(radial);
                Vector3f parV = new Vector3f(radial).mul(par);
                Vector3f perpV = new Vector3f(lw).sub(parV);
                lw = parV.mul(stretch).add(perpV.mul((float) (1.0D / Math.sqrt(stretch))));
            }
        }
        frame.pos.set(origin).add(lw);
        // Filament arc-trailing (the F-072 law, plate edition): members widen along
        // the orbit as the tidal field takes over — a chunk strings into a filament.
        float trail = cell.rank * (0.10F + FILAMENT_TRAIL * ramp);
        if (trail != 0.0F) {
            frame.pos.rotateY(-trail);
        }
        frame.drain = 1.0F - Mth.clamp((q - DRAIN_Q) / (1.0F - DRAIN_Q), 0.0F, 1.0F);
        return frame;
    }

    /**
     * Absolute pose of crust member {@code i} at {@code ripTick} — the full life
     * cycle: rest (wave bobbing) → rigid lift/fracture/infall via {@link #framePoseAt}
     * (member tumble stays zero outside the filament window — the plate reads RIGID)
     * → the jet shred spray → the deep layer → the deep rip. Pure function of
     * {@code (index, ripTick)} — the stateless-push law.
     */
    private Transformation crustPose(int i, int ripTick) {
        Cell cell = this.cells.get(i);
        Plate plate = this.plates[cell.plate];
        SubPlate sub = this.subs.get(cell.sub);
        float wind = windDown(ripTick);
        if (plate.liftStart != Integer.MAX_VALUE && ripTick > plate.liftStart) {
            int liftEnd = plate.liftStart + LIFT_TICKS;
            int deepStart = sub.shredded ? sub.crossTick + JET_SPRAY_TICKS
                    : liftEnd + sub.infallDur;
            if (ripTick >= deepStart) {
                return deepPose(i, ripTick, deepStart, wind);
            }
            if (sub.shredded && ripTick >= sub.crossTick) {
                return shredPose(i, ripTick, wind);
            }
        }
        FramePose frame = framePoseAt(i, ripTick, 0.0F);
        Quaternionf rotation = frame.rot;
        float stretch = 1.0F;
        float thin = 1.0F;
        if (frame.stretchRamp > 0.0F) {
            // Member-level echo of the frame stretch: slerp toward radial alignment
            // and elongate mildly (the frame carries the big deformation).
            Vector3f inward = new Vector3f(-frame.pos.x, 0.0F, -frame.pos.z);
            if (inward.lengthSquared() > 1.0E-4F) {
                inward.normalize();
                Quaternionf aligned = new Quaternionf().rotationTo(
                        new Vector3f(1.0F, 0.0F, 0.0F), inward);
                rotation = new Quaternionf(rotation).slerp(aligned,
                        Math.min(1.0F, frame.stretchRamp * 1.2F));
            }
            stretch = 1.0F + 0.8F * frame.stretchRamp * frame.stretchRamp;
            thin = (float) (1.0D / Math.sqrt(stretch));
        }
        float body = Math.max(SCALE_FLOOR, cell.scale * frame.drain * wind);
        Vector3f scale = new Vector3f(body * stretch, body * 1.25F * thin, body * thin);
        Vector3f half = new Vector3f(scale).mul(0.5F);
        Vector3f translation = new Vector3f(frame.pos)
                .sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, scale, new Quaternionf());
    }

    /**
     * Deep-layer pose: the swallowed member re-poses as a dark flattened slab
     * {@value #DEEP_DROP} anchor-blocks under where its crust cell was (grow-in over
     * {@value #DEEP_GROW_TICKS}t — the map has a body, not a skin), until the deep
     * rip cascade yanks it into the hole on a fast flat accelerating spiral.
     */
    private Transformation deepPose(int i, int ripTick, int deepStart, float wind) {
        Cell cell = this.cells.get(i);
        float grow = Mth.clamp((ripTick - deepStart) / (float) DEEP_GROW_TICKS, 0.0F, 1.0F);
        float dx = cell.bx;
        float dy = cell.by - DEEP_DROP - (float) CreditsSequence.hash01(i, 206) * 0.8F;
        float dz = cell.bz;
        Quaternionf rotation = new Quaternionf().rotationY(
                (float) (CreditsSequence.hash01(i, 237) * 0.3D - 0.15D));
        float body = cell.scale * grow * wind;
        int ripStart = deepRipStart(cell, deepStart);
        Vector3f pos;
        if (ripTick >= ripStart) {
            float rq = Mth.clamp((ripTick - ripStart) / (float) DEEP_RIP_DUR, 0.0F, 1.0F);
            float hr = Math.max(1.0E-3F, (float) Math.sqrt(dx * dx + dz * dz));
            float ang0 = (float) Math.atan2(dz, dx);
            float theta = 1.6F * Mth.TWO_PI * rq * rq;
            float hNow = Math.max(SWALLOW_RADIUS, hr * (float) Math.pow(1.0F - rq, 1.3D));
            float ang = ang0 + theta;
            pos = new Vector3f(hNow * Mth.cos(ang), dy * (float) Math.pow(1.0F - rq, 1.1D),
                    hNow * Mth.sin(ang));
            rotation = new Quaternionf().rotationY(-theta).mul(rotation)
                    .mul(new Quaternionf().rotationX(rq * 2.2F
                            * ((float) CreditsSequence.hash01(i, 236) - 0.5F)));
            body *= 1.0F - Mth.clamp((rq - 0.85F) / 0.15F, 0.0F, 1.0F);
        } else {
            pos = new Vector3f(dx, dy, dz);
        }
        body = Math.max(SCALE_FLOOR, body);
        Vector3f scale = new Vector3f(body * 1.06F, body * 0.4F, body * 1.06F);
        Vector3f half = new Vector3f(scale).mul(0.5F);
        Vector3f translation = pos.sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, scale, new Quaternionf());
    }

    /**
     * Jet-shred pose: from its deterministic crossing-moment position the member
     * sprays out along the ±jet axis (the disc minor axis in the anchor frame — the
     * same columns the shader strobes) over {@value #JET_SPRAY_TICKS}t, ignited,
     * stretched 3× along the axis and draining toward the tip.
     */
    private Transformation shredPose(int i, int ripTick, float wind) {
        Cell cell = this.cells.get(i);
        SubPlate sub = this.subs.get(cell.sub);
        FramePose launch = framePoseAt(i, sub.crossTick, 0.0F);
        float sq = Mth.clamp((ripTick - sub.crossTick) / (float) JET_SPRAY_TICKS, 0.0F, 1.0F);
        float drive = 1.0F - (1.0F - sq) * (1.0F - sq);
        float reach = 9.0F + (float) CreditsSequence.hash01(i, 207) * 17.0F;
        Vector3f dir = new Vector3f(this.jetAxis).mul(sub.jetSide);
        Vector3f lateral = new Vector3f(this.right)
                .mul(((float) CreditsSequence.hash01(i, 208) - 0.5F) * 0.5F)
                .add(new Vector3f(this.jetAxis).cross(this.right)
                        .mul(((float) CreditsSequence.hash01(i, 209) - 0.5F) * 0.5F));
        Vector3f pos = new Vector3f(launch.pos)
                .add(new Vector3f(dir).add(lateral).mul(reach * drive));
        Quaternionf rotation = new Quaternionf().rotationTo(new Vector3f(1.0F, 0.0F, 0.0F), dir);
        float body = Math.max(SCALE_FLOOR, cell.scale * wind
                * (1.0F - Mth.clamp((sq - 0.72F) / 0.28F, 0.0F, 1.0F)));
        Vector3f scale = new Vector3f(body * 3.0F * (0.4F + 0.6F * drive),
                body * 0.45F, body * 0.45F);
        Vector3f half = new Vector3f(scale).mul(0.5F);
        Vector3f translation = pos.sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, scale, new Quaternionf());
    }

    /**
     * Seam-slat pose: a thin full-bright violet slat parked along its crack-front
     * segment — grows in when its propagation step fires (racing along the segment),
     * glows until the bordering plate lifts, then fades under the tear.
     */
    private Transformation seamPose(int slat, int ripTick) {
        float env = Mth.clamp((ripTick - this.seamAppear[slat]) / 3.0F, 0.0F, 1.0F)
                * (1.0F - Mth.clamp((ripTick - this.seamFade[slat]) / 20.0F, 0.0F, 1.0F))
                * windDown(ripTick);
        env = Math.max(SCALE_FLOOR, env);
        Quaternionf rotation = new Quaternionf().rotationY(this.seamYaw[slat]);
        Vector3f scale = new Vector3f(0.26F * env, 0.16F * env,
                Math.max(SCALE_FLOOR, this.seamLen[slat] * env));
        Vector3f half = new Vector3f(scale).mul(0.5F);
        Vector3f translation = new Vector3f(this.seamPos[slat])
                .sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, scale, new Quaternionf());
    }

    /** Latest shard job of {@code slot} active at {@code ripTick} (else MIN_VALUE). */
    private int activeShardJob(int slot, int ripTick) {
        int[] jobs = this.shardSlotJobs[slot];
        for (int k = jobs.length - 1; k >= 0; k--) {
            int start = this.shardJobs.get(jobs[k]).start();
            if (ripTick >= start) {
                return ripTick < start + SHARD_FLIGHT_TICKS ? jobs[k] : Integer.MIN_VALUE;
            }
        }
        return Integer.MIN_VALUE;
    }

    /**
     * Gravity-wave shard pose: pops off its cell's surface as the crest passes, hops
     * 2–4 anchor-blocks up with a hot tumble, then gets dragged into the hole on a
     * fast flat spiral — recycled per job across the six waves.
     */
    private Transformation shardPose(int slot, int ripTick) {
        int job = activeShardJob(slot, ripTick);
        if (job == Integer.MIN_VALUE) {
            Cell home = this.cells.get(this.shardJobs.get(this.shardSlotJobs[slot][0]).cell());
            return floorPose(home.bx, home.by, home.bz);
        }
        ShardJob shard = this.shardJobs.get(job);
        Cell cell = this.cells.get(shard.cell());
        int local = ripTick - shard.start();
        float grow = Mth.clamp(local / 4.0F, 0.0F, 1.0F);
        float rise = 2.0F + (float) CreditsSequence.hash01(job, 227) * 2.0F;
        Vector3f pos;
        if (local <= SHARD_HOP_TICKS) {
            float h = local / (float) SHARD_HOP_TICKS;
            float ease = 1.0F - (1.0F - h) * (1.0F - h);
            pos = new Vector3f(cell.bx + h * ((float) CreditsSequence.hash01(job, 239) - 0.5F),
                    cell.by + cell.scale * 0.6F + rise * ease, cell.bz);
        } else {
            float v = (local - SHARD_HOP_TICKS) / (float) (SHARD_FLIGHT_TICKS - SHARD_HOP_TICKS);
            float hr = Math.max(1.0E-3F, cell.distHoriz);
            float ang0 = (float) Math.atan2(cell.bz, cell.bx);
            float theta = (1.1F + (float) CreditsSequence.hash01(job, 228) * 0.8F)
                    * Mth.TWO_PI * v * v;
            float hNow = Math.max(SWALLOW_RADIUS, hr * (float) Math.pow(1.0F - v, 1.5D));
            float ang = ang0 + theta;
            float y0 = cell.by + cell.scale * 0.6F + rise;
            pos = new Vector3f(hNow * Mth.cos(ang), y0 * (float) Math.pow(1.0F - v, 1.2D),
                    hNow * Mth.sin(ang));
        }
        float u = local / (float) SHARD_FLIGHT_TICKS;
        Vector3f axis = new Vector3f(
                (float) (CreditsSequence.hash01(job, 229) * 2.0D - 1.0D),
                (float) (0.3D + CreditsSequence.hash01(job, 236)),
                (float) (CreditsSequence.hash01(job, 226) * 2.0D - 1.0D)).normalize();
        Quaternionf rotation = new Quaternionf().rotationAxis(
                slot * CreditsSequence.GOLDEN_ANGLE + u * (4.0F
                        + (float) CreditsSequence.hash01(job, 236) * 4.0F), axis);
        float body = Math.max(SCALE_FLOOR, cell.scale
                * (0.3F + (float) CreditsSequence.hash01(job, 226) * 0.2F)
                * grow * (1.0F - Mth.clamp((u - 0.85F) / 0.15F, 0.0F, 1.0F)) * windDown(ripTick));
        Vector3f scale = new Vector3f(body);
        Vector3f half = new Vector3f(scale).mul(0.5F);
        Vector3f translation = pos.sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, scale, new Quaternionf());
    }

    /** Latest underside job of {@code slot} active at {@code ripTick} (else MIN_VALUE). */
    private int activeUndersideJob(int slot, int ripTick) {
        int[] jobs = this.undersideSlotJobs[slot];
        for (int k = jobs.length - 1; k >= 0; k--) {
            UndersideJob job = this.undersideJobs.get(jobs[k]);
            if (ripTick >= job.start()) {
                return ripTick < job.end() ? jobs[k] : Integer.MIN_VALUE;
            }
        }
        return Integer.MIN_VALUE;
    }

    /**
     * Underside pose: the piece rides its cell's (sub-)plate transform with a plain
     * downward local offset (zero extra math — {@link #framePoseAt} does the work):
     * dark slabs pave the lifted plate's belly, stalactites hang further down and
     * swing ±4° on the plate motion; everything drains with the plate and re-arms
     * for the next wave.
     */
    private Transformation undersidePose(int slot, int ripTick) {
        int jobIdx = activeUndersideJob(slot, ripTick);
        if (jobIdx == Integer.MIN_VALUE) {
            UndersideJob first = this.undersideJobs.get(this.undersideSlotJobs[slot][0]);
            Cell home = this.cells.get(first.cell());
            return floorPose(home.bx, home.by - 1.0F, home.bz);
        }
        UndersideJob job = this.undersideJobs.get(jobIdx);
        Cell cell = this.cells.get(job.cell());
        float grow = Mth.clamp((ripTick - job.start()) / 8.0F, 0.0F, 1.0F);
        float down = job.stalactite()
                ? cell.scale * 0.75F + 1.3F
                : cell.scale * 0.5F + (float) CreditsSequence.hash01(slot, 224) * 0.35F;
        FramePose frame = framePoseAt(job.cell(), ripTick, down);
        Quaternionf rotation = new Quaternionf(frame.rot);
        float env = Math.max(SCALE_FLOOR, grow * frame.drain * windDown(ripTick));
        Vector3f scale;
        if (job.stalactite()) {
            // ±4° swing off the plate's belly (a slow pendulum on the act clock).
            rotation.mul(new Quaternionf().rotationZ(
                    0.07F * Mth.sin(ripTick * 0.13F + slot * 1.7F)));
            scale = new Vector3f(0.4F * env, 2.2F * env, 0.4F * env);
        } else {
            scale = new Vector3f(cell.scale * 1.02F * env, cell.scale * 0.32F * env,
                    cell.scale * 1.02F * env);
        }
        Vector3f half = new Vector3f(scale).mul(0.5F);
        Vector3f translation = new Vector3f(frame.pos)
                .sub(rotation.transform(half, new Vector3f()));
        return new Transformation(translation, rotation, scale, new Quaternionf());
    }

    /** Scale-floor parking pose (a pool piece between jobs — never popped). */
    private static Transformation floorPose(float x, float y, float z) {
        Vector3f scale = new Vector3f(SCALE_FLOOR);
        return new Transformation(new Vector3f(x, y, z), new Quaternionf(), scale,
                new Quaternionf());
    }
}
