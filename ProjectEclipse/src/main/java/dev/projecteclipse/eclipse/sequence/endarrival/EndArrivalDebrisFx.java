package dev.projecteclipse.eclipse.sequence.endarrival;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.worldgen.EndDiscGeometry;
import dev.projecteclipse.eclipse.worldgen.stage.DisplayBrightnessFx;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityJoinLevelEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * F-077 phase 3 — "der Altar spuckt das End aus": hundreds of {@link Display.BlockDisplay}
 * end-stone/obsidian/purpur chunks that climb the violet pillar from the altar, pour out of
 * the rift mouth and spiral OUTWARD onto the forming disc band, where each one snaps into
 * the island silhouette with a violet implosion puff ({@code CUE_PUFF}) while the real
 * chunks materialize underneath ({@code EndDiscService}'s budgeted writer runs in parallel
 * — the displays are the "Baustoff-Show", the writer is the truth).
 *
 * <p><b>V2 "GIGANTISMUS"</b> (PLAN-F077 §3, WP-C/D/H): the stream grew to
 * {@value #STREAM_TARGET} pieces (cap {@value #HARD_CAP}) braided into
 * {@value #STRAND_COUNT} co-rotating helix strands; landings are no longer random ring
 * slots but REAL disc-silhouette columns sampled from
 * {@link dev.projecteclipse.eclipse.worldgen.EndDiscGeometry} (grid stride
 * {@value #TARGET_SAMPLE_STRIDE}, pillars last), opened wave by wave
 * ({@value #WAVE_COUNT} annulus waves, one every {@value #WAVE_OPEN_INTERVAL_TICKS} t,
 * inward → outward); landings stamp the {@code end_arrival_snap} tick; and a
 * 45 ms-MSPT guard (hysteresis {@value #MSPT_RECOVER_NANOS} ns) pauses spawning and
 * halves the push rate (6 t windows) instead of ever dropping the show.</p>
 *
 * <p><b>Doctrine</b> is {@link dev.projecteclipse.eclipse.sequence.StormDebrisFx} 1:1:</p>
 * <ul>
 *   <li><b>Transport</b>: every piece is mounted at ONE fixed entity position (the pillar
 *       axis at mid-height between altar and rift) and all motion lives in the
 *       transformation's translation, pushed every {@value #UPDATE_INTERVAL_TICKS} ticks
 *       with a matching interpolation duration and a one-window keyframe lead. The mount
 *       keeps the whole stream inside the always-loaded altar column and carries a
 *       {@value #VIEW_RANGE}× view-range override (~512 blocks) so the far disc-edge
 *       arrivals stay visible from the ground.</li>
 *   <li><b>Budget</b>: batch spawn ({@value #SPAWN_BATCH} per {@value #SPAWN_STAGGER_TICKS}
 *       ticks up to {@value #STREAM_TARGET}, hard cap {@value #HARD_CAP}); pushes are
 *       phase-sliced across the update interval; the whole pass early-outs (pieces hold
 *       their pose) with no player within {@value #PLAYER_GATE_RANGE} blocks.</li>
 *   <li><b>Recycling</b>: a piece that ARRIVES on the band is not discarded — it is re-armed
 *       as a fresh piece at the altar, so the stream runs the whole phase at a constant
 *       entity count with zero spawn churn.</li>
 *   <li><b>Despawn guarantee</b>: command tag {@value #ENTITY_TAG} + live-UUID sweep on
 *       join (crash strays are discarded on load), a {@value #WATCHDOG_TICKS}-tick
 *       force-clear watchdog, and {@code /kill @e[tag=eclipse_end_arrival_debris]} always
 *       works.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EndArrivalDebrisFx {
    /** Frozen command tag on every debris piece — strays from a crash are swept on load. */
    public static final String ENTITY_TAG = "eclipse_end_arrival_debris";

    // ------------------------------------------------------------------ tuning constants

    /** Stream size the staggered spawn fills up to (V2 "GIGANTISMUS": 600, was 220). */
    private static final int STREAM_TARGET = 600;
    /** Absolute ceiling — never exceeded, whatever happens (V2: 700, was 260). */
    private static final int HARD_CAP = 700;
    /** Pieces per spawn batch and the stagger between batches (spawn-cost smoothing). */
    private static final int SPAWN_BATCH = 14;
    private static final int SPAWN_STAGGER_TICKS = 2;
    /** Transform push cadence == interpolation duration (DisplayAnimator law). */
    private static final int UPDATE_INTERVAL_TICKS = 3;
    /** Whole pass sleeps (zero packets) with no player this close to the pillar axis. */
    private static final double PLAYER_GATE_RANGE = 384.0D;
    /** Force-clear after this long without a collapse (wedged run / lost hand-off). */
    private static final int WATCHDOG_TICKS = 2400;

    /** Climb leg: altar top → rift mouth, riding the pillar in a tight helix. */
    private static final int CLIMB_TICKS = 50;
    /** Transit leg: rift mouth → island target, the wide outward spiral. */
    private static final int TRANSIT_TICKS = 76;
    /** Arrival fade: the piece scales to zero over the transit's last ticks. */
    private static final int ARRIVE_FADE_TICKS = 12;
    /** Helix radius band around the pillar axis during the climb. */
    private static final double CLIMB_HELIX_MIN = 1.6D;
    private static final double CLIMB_HELIX_MAX = 4.2D;
    /**
     * V2 (WP-C) braid: number of intertwined climb strands. Every piece is quantized
     * onto one of these 120°-offset lanes, all co-rotating at {@link #STRAND_SPIN} —
     * three readable comet streams instead of one homogeneous swarm (the
     * {@code end_arrival2_strand_trail} asset sheathes them at orbital 0.22–0.30).
     */
    private static final int STRAND_COUNT = 3;
    /** Shared braid angular rate (rad/t), jittered ±10 % per piece. */
    private static final double STRAND_SPIN = 0.26D;
    /** Per-piece angular jitter inside a strand lane (radians). */
    private static final double STRAND_ANGLE_JITTER = 0.35D;
    /** Minimum transit sweep (radians): closer targets gain a full extra turn instead. */
    private static final double TRANSIT_SWEEP_MIN = 0.9D;
    /** V2 (WP-D) silhouette sampling: grid stride over the disc footprint (blocks). */
    private static final int TARGET_SAMPLE_STRIDE = 9;
    /** Assembly waves (annuli, inward → outward; the last one owns the pillars). */
    private static final int WAVE_COUNT = 5;
    /** One assembly wave opens every this many stream ticks (5 × 80 t = the SPILL span). */
    private static final int WAVE_OPEN_INTERVAL_TICKS = 80;
    /** Piece size spread. */
    private static final float MIN_SCALE = 0.35F;
    private static final float MAX_SCALE = 1.5F;
    /** Tumble rate band (degrees per tick). */
    private static final double SPIN_MIN_DEG_PER_TICK = 0.8D;
    private static final double SPIN_MAX_DEG_PER_TICK = 4.0D;

    /** Finale: every piece rushes its remaining path and scales out over this long. */
    public static final int COLLAPSE_TICKS = 50;

    /** Display view-range override in vanilla units (× 64 blocks) — StormDebrisFx law. */
    private static final float VIEW_RANGE = 8.0F;
    /** Sky-lit end stone against the bright day sky needs a small block-light floor. */
    private static final int DEBRIS_BLOCK_LIGHT = 8;
    private static final int MAX_SKY_LIGHT = 15;

    /** Every Nth arrival stamps a violet CUE_PUFF + END_ROD baseline at the impact. */
    private static final int PUFF_EVERY_N_ARRIVALS = 4;
    /** Hard per-tick ceiling on arrival puffs (a recycle wave must not burst-fire cues). */
    private static final int MAX_PUFFS_PER_TICK = 2;
    /** Puff cue broadcast radius (blocks). */
    private static final double PUFF_RANGE = 320.0D;

    /**
     * V2 (WP-H) MSPT guard: above this average tick time new spawns pause and the push
     * cadence halves (6 t windows); below {@link #MSPT_RECOVER_NANOS} the stream
     * recovers (hysteresis so the guard never flaps). The 45 ms line mirrors the
     * pregen {@code msptGuard} doctrine ({@code ExpansionTiming}/{@code GrowthPacing}).
     */
    private static final long MSPT_DEGRADE_NANOS = 45_000_000L;
    private static final long MSPT_RECOVER_NANOS = 38_000_000L;
    /** Guard evaluation cadence (ticks). */
    private static final int MSPT_CHECK_INTERVAL_TICKS = 20;

    /** The End palette (user ask: end_stone, obsidian, purpur accents, chorus). */
    private static final BlockState[] PALETTE = {
            Blocks.END_STONE.defaultBlockState(),
            Blocks.END_STONE.defaultBlockState(),
            Blocks.END_STONE.defaultBlockState(),
            Blocks.END_STONE.defaultBlockState(),
            Blocks.END_STONE_BRICKS.defaultBlockState(),
            Blocks.OBSIDIAN.defaultBlockState(),
            Blocks.OBSIDIAN.defaultBlockState(),
            Blocks.CRYING_OBSIDIAN.defaultBlockState(),
            Blocks.PURPUR_BLOCK.defaultBlockState(),
            Blocks.PURPUR_PILLAR.defaultBlockState(),
            Blocks.CHORUS_PLANT.defaultBlockState(),
            Blocks.CHORUS_FLOWER.defaultBlockState()};

    /** The single live stream (one arrival per world), or {@code null}. Server thread only. */
    @Nullable
    private static Stream stream;
    /** UUIDs of pieces spawned THIS session; tagged joiners outside it are crash strays. */
    private static final Set<UUID> LIVE_DISPLAYS = Collections.synchronizedSet(new HashSet<>());

    private EndArrivalDebrisFx() {}

    // ------------------------------------------------------------------ public beats

    /**
     * Arms the debris stream. Idempotent — a repeat call while a stream already runs is
     * ignored, so a re-fired phase never doubles it.
     *
     * @param altarTop   pillar base (the altar top center)
     * @param rift       pillar mouth (the rift point high above)
     * @param discCenter island-band center at surface height (the End disc center)
     * @param discRadius island-band radius (the End disc radius)
     */
    public static void begin(ServerLevel level, Vec3 altarTop, Vec3 rift, Vec3 discCenter,
            double discRadius) {
        if (stream != null) {
            return;
        }
        stream = new Stream(level, altarTop, rift, discCenter, discRadius);
        EclipseMod.LOGGER.info(
                "EndArrivalDebrisFx: stream armed (altar {}, rift {}, band r {}, target {} pieces)",
                altarTop, rift, discRadius, STREAM_TARGET);
    }

    /**
     * The finale: recycling stops, every piece rushes its remaining path and scales to
     * zero over {@value #COLLAPSE_TICKS} ticks, then the stream discards itself.
     * A no-op without a stream.
     */
    public static void collapse(ServerLevel level) {
        Stream current = stream;
        if (current == null || current.level != level || current.collapsing()) {
            return;
        }
        current.beginCollapse();
        EclipseMod.LOGGER.info("EndArrivalDebrisFx: collapsing {} piece(s) over {} ticks",
                current.pieces.size(), COLLAPSE_TICKS);
    }

    /** Discards the stream immediately (abort paths, dev stop, restart recovery). */
    public static void clearAll() {
        Stream current = stream;
        if (current != null) {
            current.discardAll();
            stream = null;
        }
    }

    /** Whether a stream is currently live (dev status / guards). */
    public static boolean isActive() {
        return stream != null;
    }

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        // In-memory only: pieces that made it to disk are swept by the join check on the
        // next boot (they can never be adopted, since LIVE_DISPLAYS is cleared here).
        stream = null;
        LIVE_DISPLAYS.clear();
    }

    /** StructureFlightFx sweep doctrine: a tagged display we did not spawn is a crash stray. */
    @SubscribeEvent
    static void onEntityJoin(EntityJoinLevelEvent event) {
        Entity entity = event.getEntity();
        if (!event.getLevel().isClientSide() && entity instanceof Display.BlockDisplay
                && entity.getTags().contains(ENTITY_TAG)
                && !LIVE_DISPLAYS.contains(entity.getUUID())) {
            entity.discard();
        }
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        Stream current = stream;
        if (current == null) {
            return;
        }
        MinecraftServer server = event.getServer();
        if (current.level.getServer() != server) {
            return;
        }
        current.tick();
        if (current.done) {
            stream = null;
        }
    }

    // ------------------------------------------------------------------ the stream

    /**
     * One flying chunk. All motion is a pure function of the stream age; a piece is
     * RE-ARMED in place when its path ends (the recycle law), so its parameters are
     * mutable but only ever rewritten wholesale by {@link Stream#rearm}.
     */
    private static final class Piece {
        @Nullable
        Display.BlockDisplay display;
        BlockState state = Blocks.END_STONE.defaultBlockState();
        float scale;
        /** Climb-leg helix parameters (V2: quantized onto one of the braid strands). */
        double climbAngle0;
        double climbSpin;
        double climbRadius;
        /**
         * Transit-leg spiral (V2 WP-D): total angular sweep landing EXACTLY on the
         * sampled silhouette column ({@code targetAngle}/{@code targetRadius}/{@code
         * targetY} around the disc center).
         */
        double transitSweep;
        double targetRadius;
        double targetY;
        /** Tumble. */
        final Vector3f spinAxis = new Vector3f(0.0F, 1.0F, 0.0F);
        float spinRate;
        float spinPhase;
        /** Push slice: only pushed on stream ticks where {@code age % interval == phase}. */
        int pushPhase;
        /** Stream age the current flight started at. */
        int bornAge;
        /** Small per-piece jitter at the pillar base so the stream has body. */
        double baseJitterX;
        double baseJitterZ;
    }

    private static final class Stream {
        final ServerLevel level;
        final Vec3 altarTop;
        final Vec3 rift;
        final Vec3 discCenter;
        final double discRadius;
        /** The one fixed entity position every piece mounts at (pillar axis, mid-height). */
        final Vec3 mount;
        final RandomSource random;
        final List<Piece> pieces = new ArrayList<>(STREAM_TARGET);
        /**
         * V2 (WP-D): real silhouette landing columns per assembly wave — annulus
         * buckets inward → outward, pillars folded into the last wave. Sampled once
         * at arm time from {@code EndDiscGeometry} (pure functions, no chunk access).
         */
        final List<List<Vec3>> waveTargets;
        /** Transit spiral origin (rift point in disc-polar coordinates). */
        final double startAngle;
        final double startRadius;

        int age;
        int arrivals;
        int puffsThisTick;
        /** V2 (WP-H): true while the MSPT guard has the stream degraded. */
        boolean degraded;
        /** Stream age the collapse started at, or −1 while the spill still runs. */
        int collapseStart = -1;
        boolean done;

        Stream(ServerLevel level, Vec3 altarTop, Vec3 rift, Vec3 discCenter, double discRadius) {
            this.level = level;
            this.altarTop = altarTop;
            this.rift = rift;
            this.discCenter = discCenter;
            this.discRadius = discRadius;
            this.mount = new Vec3(altarTop.x, (altarTop.y + rift.y) * 0.5D, altarTop.z);
            this.random = RandomSource.create(level.getGameTime() * 31L + Double.hashCode(altarTop.x));
            this.startAngle = Math.atan2(rift.z - discCenter.z, rift.x - discCenter.x);
            this.startRadius = Math.hypot(rift.x - discCenter.x, rift.z - discCenter.z);
            this.waveTargets = sampleWaveTargets(discCenter, discRadius);
        }

        /**
         * Samples the disc's REAL silhouette into {@value #WAVE_COUNT} annulus buckets
         * ({@code EndDiscGeometry.footprintContains}/{@code topYAt} on a
         * {@value #TARGET_SAMPLE_STRIDE}-block grid ≈ 400 columns for r = 96); the
         * eight obsidian pillars are folded into the LAST wave so the spires visibly
         * finish the build. Any empty bucket (degenerate geometry) falls back to a
         * ring slot at the bucket's mid radius so the show never starves.
         */
        private static List<List<Vec3>> sampleWaveTargets(Vec3 discCenter, double discRadius) {
            List<List<Vec3>> buckets = new ArrayList<>(WAVE_COUNT);
            for (int i = 0; i < WAVE_COUNT; i++) {
                buckets.add(new ArrayList<>());
            }
            int centerX = (int) Math.floor(discCenter.x);
            int centerZ = (int) Math.floor(discCenter.z);
            int reach = (int) Math.ceil(discRadius);
            for (int x = centerX - reach; x <= centerX + reach; x += TARGET_SAMPLE_STRIDE) {
                for (int z = centerZ - reach; z <= centerZ + reach; z += TARGET_SAMPLE_STRIDE) {
                    if (!EndDiscGeometry.footprintContains(x, z)) {
                        continue;
                    }
                    int topY = EndDiscGeometry.topYAt(x, z);
                    if (topY == Integer.MIN_VALUE) {
                        continue;
                    }
                    double dist = Math.hypot(x + 0.5D - discCenter.x, z + 0.5D - discCenter.z);
                    int wave = Mth.clamp((int) (dist / discRadius * WAVE_COUNT), 0, WAVE_COUNT - 1);
                    buckets.get(wave).add(new Vec3(x + 0.5D, topY + 1.0D, z + 0.5D));
                }
            }
            // The spires land last — the skyline completes as the finale approaches.
            List<Vec3> lastWave = buckets.get(WAVE_COUNT - 1);
            for (int i = 0; i < EndDiscGeometry.PILLAR_COUNT; i++) {
                int px = EndDiscGeometry.pillarX(i);
                int pz = EndDiscGeometry.pillarZ(i);
                int topY = EndDiscGeometry.topYAt(px, pz);
                if (topY != Integer.MIN_VALUE) {
                    lastWave.add(new Vec3(px + 0.5D, topY + 1.0D, pz + 0.5D));
                }
            }
            for (int i = 0; i < WAVE_COUNT; i++) {
                if (buckets.get(i).isEmpty()) {
                    double radius = (i + 0.5D) / WAVE_COUNT * discRadius;
                    buckets.get(i).add(new Vec3(discCenter.x + radius, discCenter.y + 2.0D,
                            discCenter.z));
                }
            }
            return buckets;
        }

        /** The assembly wave currently open (inward → outward, one every 80 t). */
        private int currentWave() {
            return Mth.clamp(this.age / WAVE_OPEN_INTERVAL_TICKS, 0, WAVE_COUNT - 1);
        }

        boolean collapsing() {
            return this.collapseStart >= 0;
        }

        void tick() {
            this.age++;
            this.puffsThisTick = 0;
            if (this.age > WATCHDOG_TICKS && !collapsing()) {
                EclipseMod.LOGGER.warn(
                        "EndArrivalDebrisFx: stream outlived its watchdog ({} ticks) — force-clearing",
                        WATCHDOG_TICKS);
                discardAll();
                this.done = true;
                return;
            }
            if (collapsing() && this.age - this.collapseStart > COLLAPSE_TICKS) {
                discardAll();
                this.done = true;
                return;
            }
            tickMsptGuard();
            boolean visible = playerNear();
            if (!collapsing() && visible && !this.degraded
                    && this.pieces.size() < STREAM_TARGET
                    && this.age % SPAWN_STAGGER_TICKS == 0) {
                spawnBatch();
            }
            if (!visible) {
                return; // presence gate: pieces hold their last pose, zero packets
            }
            animate();
        }

        /**
         * V2 (WP-H) degrade lever: over {@value #MSPT_DEGRADE_NANOS} ns average tick
         * time the stream stops spawning and halves its push cadence; it recovers
         * below {@value #MSPT_RECOVER_NANOS} ns (hysteresis). The show always
         * continues — degraded means slower interpolation windows, never a cut.
         */
        private void tickMsptGuard() {
            if (this.age % MSPT_CHECK_INTERVAL_TICKS != 0) {
                return;
            }
            long avgNanos = this.level.getServer().getAverageTickTimeNanos();
            if (this.degraded) {
                if (avgNanos < MSPT_RECOVER_NANOS) {
                    this.degraded = false;
                    EclipseMod.LOGGER.info("EndArrivalDebrisFx: MSPT recovered ({} ms) — full cadence",
                            avgNanos / 1_000_000L);
                }
            } else if (avgNanos > MSPT_DEGRADE_NANOS) {
                this.degraded = true;
                EclipseMod.LOGGER.info(
                        "EndArrivalDebrisFx: MSPT guard tripped ({} ms > 45 ms) — spawns paused, pushes halved",
                        avgNanos / 1_000_000L);
            }
        }

        private boolean playerNear() {
            double rangeSq = PLAYER_GATE_RANGE * PLAYER_GATE_RANGE;
            for (ServerPlayer player : this.level.players()) {
                if (!player.isSpectator()
                        && player.distanceToSqr(this.mount.x, this.mount.y, this.mount.z) <= rangeSq) {
                    return true;
                }
            }
            return false;
        }

        // --- spawning / recycling ---

        private void spawnBatch() {
            int batch = Math.min(SPAWN_BATCH, STREAM_TARGET - this.pieces.size());
            for (int i = 0; i < batch; i++) {
                spawn();
            }
        }

        /** (Re)rolls one piece's whole flight: palette, size, strand lane, silhouette slot. */
        private void rearm(Piece piece, int bornAge) {
            piece.state = PALETTE[this.random.nextInt(PALETTE.length)];
            piece.scale = MIN_SCALE + (MAX_SCALE - MIN_SCALE)
                    * (float) Math.pow(this.random.nextDouble(), 1.5D);
            // V2 (WP-C): quantize onto one of the co-rotating braid strands.
            int strand = this.random.nextInt(STRAND_COUNT);
            piece.climbAngle0 = strand * (Math.PI * 2.0D / STRAND_COUNT)
                    + (this.random.nextDouble() - 0.5D) * 2.0D * STRAND_ANGLE_JITTER;
            piece.climbSpin = STRAND_SPIN * (0.9D + this.random.nextDouble() * 0.2D);
            piece.climbRadius = CLIMB_HELIX_MIN
                    + this.random.nextDouble() * (CLIMB_HELIX_MAX - CLIMB_HELIX_MIN);
            // V2 (WP-D): land on a REAL silhouette column of the currently open wave.
            List<Vec3> bucket = this.waveTargets.get(currentWave());
            Vec3 target = bucket.get(this.random.nextInt(bucket.size()));
            piece.targetRadius = Math.hypot(target.x - this.discCenter.x,
                    target.z - this.discCenter.z);
            piece.targetY = target.y;
            double targetAngle = Math.atan2(target.z - this.discCenter.z,
                    target.x - this.discCenter.x);
            // Total sweep landing EXACTLY on the target angle; near-radial paths gain
            // a full extra turn so every flight still reads as a spiral.
            double sweep = Math.atan2(Math.sin(targetAngle - this.startAngle),
                    Math.cos(targetAngle - this.startAngle));
            if (Math.abs(sweep) < TRANSIT_SWEEP_MIN) {
                sweep += (this.random.nextBoolean() ? 1.0D : -1.0D) * Math.PI * 2.0D;
            }
            piece.transitSweep = sweep;
            piece.spinAxis.set(
                    this.random.nextFloat() - 0.5F,
                    this.random.nextFloat() - 0.5F,
                    this.random.nextFloat() - 0.5F);
            if (piece.spinAxis.lengthSquared() < 1.0E-4F) {
                piece.spinAxis.set(0.0F, 1.0F, 0.0F);
            }
            piece.spinAxis.normalize();
            piece.spinRate = (float) Math.toRadians(SPIN_MIN_DEG_PER_TICK
                    + this.random.nextDouble() * (SPIN_MAX_DEG_PER_TICK - SPIN_MIN_DEG_PER_TICK))
                    * (this.random.nextBoolean() ? 1.0F : -1.0F);
            piece.spinPhase = (float) (this.random.nextDouble() * Math.PI * 2.0D);
            piece.baseJitterX = (this.random.nextDouble() - 0.5D) * 3.0D;
            piece.baseJitterZ = (this.random.nextDouble() - 0.5D) * 3.0D;
            piece.bornAge = bornAge;
        }

        private void spawn() {
            if (this.pieces.size() >= HARD_CAP) {
                return;
            }
            BlockPos mountPos = BlockPos.containing(this.mount);
            if (!this.level.isLoaded(mountPos)) {
                return; // altar column not loaded (yet): try again on the next batch
            }
            Display.BlockDisplay display = EntityType.BLOCK_DISPLAY.create(this.level);
            if (display == null) {
                return;
            }
            Piece piece = new Piece();
            rearm(piece, this.age);
            // Stagger flight phases so the very first batches don't arrive as one wall.
            piece.bornAge = this.age - this.random.nextInt(CLIMB_TICKS + TRANSIT_TICKS);
            // Slices are assigned over the DOUBLED window so the WP-H degraded cadence
            // (6 t) still spreads pushes evenly; normal cadence folds it mod 3.
            piece.pushPhase = this.pieces.size() % (UPDATE_INTERVAL_TICKS * 2);
            display.setBlockState(piece.state);
            display.moveTo(this.mount.x, this.mount.y, this.mount.z, 0.0F, 0.0F);
            display.addTag(ENTITY_TAG);
            // Range override + light floor, one NBT round-trip before the first pose
            // (StormDebrisFx law — without it nobody sees the disc-edge arrivals).
            DisplayBrightnessFx.set(display, DEBRIS_BLOCK_LIGHT, MAX_SKY_LIGHT, VIEW_RANGE);
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(0);
            display.setTransformation(poseAt(piece, this.age));
            LIVE_DISPLAYS.add(display.getUUID());
            this.level.addFreshEntity(display);
            piece.display = display;
            this.pieces.add(piece);
        }

        // --- motion ---

        /**
         * One interpolated push per piece in this tick's slice, targeting the pose the
         * window ENDS on (keyframe lead). A piece whose flight ended this window is
         * re-armed in place (recycle) — unless the collapse has started. Under the
         * WP-H guard the window doubles to 6 t (half the pushes, same show — the
         * slices were assigned mod 6, so the degraded cadence stays evenly spread).
         */
        private void animate() {
            int interval = this.degraded ? UPDATE_INTERVAL_TICKS * 2 : UPDATE_INTERVAL_TICKS;
            int slice = this.age % interval;
            boolean missing = false;
            for (Piece piece : this.pieces) {
                boolean pushNow = this.degraded
                        ? piece.pushPhase == slice
                        : piece.pushPhase % UPDATE_INTERVAL_TICKS == slice;
                if (!pushNow) {
                    continue;
                }
                Display.BlockDisplay display = piece.display;
                if (display == null || display.isRemoved()) {
                    missing = true;
                    continue;
                }
                int flightTicks = CLIMB_TICKS + TRANSIT_TICKS;
                if (!collapsing() && this.age - piece.bornAge >= flightTicks) {
                    onArrival(piece);
                    rearm(piece, this.age);
                    // The block palette may have changed with the re-arm; sync it.
                    display.setBlockState(piece.state);
                    display.setTransformationInterpolationDelay(0);
                    display.setTransformationInterpolationDuration(0);
                    display.setTransformation(poseAt(piece, this.age));
                    continue;
                }
                display.setTransformationInterpolationDelay(0);
                display.setTransformationInterpolationDuration(interval);
                display.setTransformation(poseAt(piece, this.age + interval));
            }
            if (missing) {
                this.pieces.removeIf(piece -> piece.display == null || piece.display.isRemoved());
            }
        }

        /** Arrival stamp: every Nth landing fires the violet puff cue + END_ROD baseline. */
        private void onArrival(Piece piece) {
            this.arrivals++;
            if (this.arrivals % PUFF_EVERY_N_ARRIVALS != 0
                    || this.puffsThisTick >= MAX_PUFFS_PER_TICK) {
                return;
            }
            this.puffsThisTick++;
            Vec3 at = flightPos(piece, 1.0D, 1.0D);
            FxPayloads.sendFxEvent(this.level, EndArrivalFxCues.CUE_PUFF, at, 0.0F, 0.0F, PUFF_RANGE);
            // V2 (WP-G): the chorus-flower snap tick — rides the same ≤ 2/t rate limit.
            this.level.playSound(null, at.x, at.y, at.z,
                    EclipseSounds.EVENT_END_ARRIVAL_SNAP.get(), SoundSource.AMBIENT,
                    1.6F, 0.9F + this.random.nextFloat() * 0.25F);
            // Photon-less baseline: a small END_ROD/PORTAL sparkle at the snap-in point.
            this.level.sendParticles(ParticleTypes.END_ROD, at.x, at.y, at.z,
                    6, 0.6D, 0.6D, 0.6D, 0.03D);
            this.level.sendParticles(ParticleTypes.PORTAL, at.x, at.y, at.z,
                    10, 0.8D, 0.8D, 0.8D, 0.2D);
        }

        /**
         * Flight position for eased climb progress {@code c} (0..1) and eased transit
         * progress {@code s} (0..1). Climb: altar top → rift riding one of the three
         * braid strands around the pillar axis. Transit: rift → the piece's REAL
         * silhouette column in a wide spiral around the DISC center that lands EXACTLY
         * on the target angle/radius/height (V2 WP-D).
         */
        private Vec3 flightPos(Piece piece, double c, double s) {
            if (s <= 0.0D) {
                double angle = piece.climbAngle0 + piece.climbSpin * (c * CLIMB_TICKS);
                double x = Mth.lerp(c, this.altarTop.x + piece.baseJitterX, this.rift.x)
                        + Math.cos(angle) * piece.climbRadius;
                double y = Mth.lerp(c * c, this.altarTop.y, this.rift.y);
                double z = Mth.lerp(c, this.altarTop.z + piece.baseJitterZ, this.rift.z)
                        + Math.sin(angle) * piece.climbRadius;
                return new Vec3(x, y, z);
            }
            double angle = this.startAngle + piece.transitSweep * s;
            // The helix offset melts away over the transit so s = 1 IS the target.
            double radius = Mth.lerp(s, this.startRadius + piece.climbRadius, piece.targetRadius);
            double y = Mth.lerp(s * s * (3.0D - 2.0D * s), this.rift.y, piece.targetY);
            return new Vec3(
                    this.discCenter.x + Math.cos(angle) * radius,
                    y,
                    this.discCenter.z + Math.sin(angle) * radius);
        }

        /** Absolute pose of one piece at stream age {@code t} — pure function of {@code t}. */
        private Transformation poseAt(Piece piece, int t) {
            double life = t - piece.bornAge;
            double climbRaw = Mth.clamp(life / CLIMB_TICKS, 0.0D, 1.0D);
            double transitRaw = Mth.clamp((life - CLIMB_TICKS) / TRANSIT_TICKS, 0.0D, 1.0D);
            // Collapse: the whole stream fast-forwards its remaining path and scales out.
            float collapseFade = 0.0F;
            if (collapsing()) {
                float cf = (float) Mth.clamp(
                        (t - this.collapseStart) / (double) COLLAPSE_TICKS, 0.0D, 1.0D);
                collapseFade = cf;
                // Rush: progress is pushed toward the end of the current leg.
                if (transitRaw > 0.0D || climbRaw >= 1.0D) {
                    transitRaw = Math.min(1.0D, transitRaw + cf * (1.0D - transitRaw));
                } else {
                    climbRaw = Math.min(1.0D, climbRaw + cf * (1.0D - climbRaw));
                }
            }
            Vec3 pos = flightPos(piece, climbRaw, transitRaw);

            float scale = piece.scale;
            // Departure pop-in (first ticks) and arrival snap-out (last transit ticks).
            if (life < 6.0D) {
                scale *= (float) (life / 6.0D);
            }
            double flightTicks = CLIMB_TICKS + TRANSIT_TICKS;
            double untilArrival = flightTicks - life;
            if (untilArrival < ARRIVE_FADE_TICKS) {
                scale *= (float) Mth.clamp(untilArrival / ARRIVE_FADE_TICKS, 0.0D, 1.0D);
            }
            scale *= 1.0F - collapseFade;

            float spinAngle = piece.spinPhase + piece.spinRate * (float) life;
            Quaternionf rotation = new Quaternionf().rotationAxis(spinAngle, piece.spinAxis);
            Vector3f translation = new Vector3f(
                    (float) (pos.x - this.mount.x),
                    (float) (pos.y - this.mount.y),
                    (float) (pos.z - this.mount.z));
            // Re-centre the [0,scale]^3 block mesh on the flight point through the rotation.
            Vector3f half = new Vector3f(scale * 0.5F, scale * 0.5F, scale * 0.5F);
            translation.sub(rotation.transform(half, new Vector3f()));
            return new Transformation(translation, rotation,
                    new Vector3f(scale, scale, scale), new Quaternionf());
        }

        void beginCollapse() {
            this.collapseStart = this.age;
            // First collapse keyframe for EVERY piece at once (not just this tick's slice)
            // — the dissolve must read as one gesture (StormDebrisFx law).
            for (Piece piece : this.pieces) {
                Display.BlockDisplay display = piece.display;
                if (display != null && !display.isRemoved()) {
                    display.setTransformationInterpolationDelay(0);
                    display.setTransformationInterpolationDuration(UPDATE_INTERVAL_TICKS);
                    display.setTransformation(poseAt(piece, this.age + UPDATE_INTERVAL_TICKS));
                }
            }
        }

        void discardAll() {
            for (Piece piece : this.pieces) {
                Display.BlockDisplay display = piece.display;
                if (display != null) {
                    LIVE_DISPLAYS.remove(display.getUUID());
                    if (!display.isRemoved()) {
                        display.discard();
                    }
                    piece.display = null;
                }
            }
            this.pieces.clear();
        }
    }
}
