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
import dev.projecteclipse.eclipse.worldgen.stage.DisplayBrightnessFx;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
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

    /** Stream size the staggered spawn fills up to ("HUNDERTE Endstein-Brocken"). */
    private static final int STREAM_TARGET = 220;
    /** Absolute ceiling — never exceeded, whatever happens. */
    private static final int HARD_CAP = 260;
    /** Pieces per spawn batch and the stagger between batches (spawn-cost smoothing). */
    private static final int SPAWN_BATCH = 10;
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
    /** Helix angular rate during the climb (radians per tick). */
    private static final double CLIMB_SPIN_MIN = 0.18D;
    private static final double CLIMB_SPIN_MAX = 0.34D;
    /** Outward-spiral angular sweep over one whole transit (radians). */
    private static final double TRANSIT_SWEEP_MIN = 0.9D;
    private static final double TRANSIT_SWEEP_MAX = 2.4D;
    /** Island-target ring around the DISC center, as fractions of the disc radius. */
    private static final double TARGET_RADIUS_MIN_FACTOR = 0.30D;
    private static final double TARGET_RADIUS_MAX_FACTOR = 0.96D;
    /** Island-target height band above the disc surface. */
    private static final double TARGET_Y_MIN = 1.0D;
    private static final double TARGET_Y_MAX = 14.0D;
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
        /** Climb-leg helix parameters. */
        double climbAngle0;
        double climbSpin;
        double climbRadius;
        /** Transit-leg spiral: angular sweep + target ring slot around the disc center. */
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

        int age;
        int arrivals;
        int puffsThisTick;
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
            boolean visible = playerNear();
            if (!collapsing() && visible && this.pieces.size() < STREAM_TARGET
                    && this.age % SPAWN_STAGGER_TICKS == 0) {
                spawnBatch();
            }
            if (!visible) {
                return; // presence gate: pieces hold their last pose, zero packets
            }
            animate();
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

        /** (Re)rolls one piece's whole flight: palette, size, helix, spiral, island slot. */
        private void rearm(Piece piece, int bornAge) {
            piece.state = PALETTE[this.random.nextInt(PALETTE.length)];
            piece.scale = MIN_SCALE + (MAX_SCALE - MIN_SCALE)
                    * (float) Math.pow(this.random.nextDouble(), 1.5D);
            piece.climbAngle0 = this.random.nextDouble() * Math.PI * 2.0D;
            piece.climbSpin = (CLIMB_SPIN_MIN
                    + this.random.nextDouble() * (CLIMB_SPIN_MAX - CLIMB_SPIN_MIN))
                    * (this.random.nextBoolean() ? 1.0D : -1.0D);
            piece.climbRadius = CLIMB_HELIX_MIN
                    + this.random.nextDouble() * (CLIMB_HELIX_MAX - CLIMB_HELIX_MIN);
            piece.transitSweep = (TRANSIT_SWEEP_MIN
                    + this.random.nextDouble() * (TRANSIT_SWEEP_MAX - TRANSIT_SWEEP_MIN))
                    * (this.random.nextBoolean() ? 1.0D : -1.0D);
            piece.targetRadius = this.discRadius * (TARGET_RADIUS_MIN_FACTOR
                    + this.random.nextDouble() * (TARGET_RADIUS_MAX_FACTOR - TARGET_RADIUS_MIN_FACTOR));
            piece.targetY = this.discCenter.y + TARGET_Y_MIN
                    + this.random.nextDouble() * (TARGET_Y_MAX - TARGET_Y_MIN);
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
            piece.pushPhase = this.pieces.size() % UPDATE_INTERVAL_TICKS;
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
         * re-armed in place (recycle) — unless the collapse has started.
         */
        private void animate() {
            int slice = this.age % UPDATE_INTERVAL_TICKS;
            boolean missing = false;
            for (Piece piece : this.pieces) {
                if (piece.pushPhase != slice) {
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
                display.setTransformationInterpolationDuration(UPDATE_INTERVAL_TICKS);
                display.setTransformation(poseAt(piece, this.age + UPDATE_INTERVAL_TICKS));
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
            // Photon-less baseline: a small END_ROD/PORTAL sparkle at the snap-in point.
            this.level.sendParticles(ParticleTypes.END_ROD, at.x, at.y, at.z,
                    6, 0.6D, 0.6D, 0.6D, 0.03D);
            this.level.sendParticles(ParticleTypes.PORTAL, at.x, at.y, at.z,
                    10, 0.8D, 0.8D, 0.8D, 0.2D);
        }

        /**
         * Flight position for eased climb progress {@code c} (0..1) and eased transit
         * progress {@code s} (0..1). Climb: altar top → rift in a tight helix around the
         * pillar axis. Transit: rift → island slot in a wide outward spiral around the
         * DISC center (radius opens, height sinks onto the band).
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
            double startAngle = Math.atan2(this.rift.z - this.discCenter.z,
                    this.rift.x - this.discCenter.x);
            double startRadius = Math.hypot(this.rift.x - this.discCenter.x,
                    this.rift.z - this.discCenter.z) + piece.climbRadius;
            double angle = startAngle + piece.transitSweep * s;
            double radius = Mth.lerp(s, startRadius, piece.targetRadius);
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
