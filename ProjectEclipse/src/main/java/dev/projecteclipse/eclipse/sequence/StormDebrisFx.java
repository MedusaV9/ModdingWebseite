package dev.projecteclipse.eclipse.sequence;

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
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.worldgen.stage.DisplayBrightnessFx;
import net.minecraft.core.BlockPos;
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
 * BD-STORM (F-017) — the torn-world debris choreography of the intro storm: hundreds of
 * {@link Display.BlockDisplay} chunks of stone, deepslate, earth and splintered wood
 * ripped out of the disc, wheeling around the vortex while it rages, thrown higher by
 * every lightning strike, and finally dragged in one spiral into the island at the centre
 * where they wink out.
 *
 * <p><b>Three beats</b>, all driven from {@link IntroSequence} (nothing here ever runs
 * outside the cutscene):</p>
 * <ol>
 *   <li>{@link #begin} — the swarm arms with the vortex and staggers
 *       {@value #SPAWN_BATCH} pieces in every {@value #SPAWN_STAGGER_TICKS} ticks until
 *       {@value #AMBIENT_TARGET} of them orbit the shell in a slow, wobbling vortex.</li>
 *   <li>{@link #lightningKick} — each strike flings {@value #LIGHTNING_KICK_PIECES} fresh
 *       pieces up out of the ground at the impact column; they arc up on a loft envelope
 *       and then merge into the swarm.</li>
 *   <li>{@link #collapse} — the burst: every piece spirals inward and downward onto the
 *       revealed island, whipping faster as it closes, scaling to zero as it arrives. The
 *       swarm discards itself when the spiral ends.</li>
 * </ol>
 *
 * <p><b>Transport</b> (the {@code SanctumOrbitals}/{@code StructureFlightFx} law): every
 * piece is mounted at ONE fixed entity position — the vortex axis at mid-height — and all
 * motion lives in the transformation's translation, pushed every
 * {@value #UPDATE_INTERVAL_TICKS} ticks with a matching interpolation duration and a
 * one-window keyframe LEAD, so clients tween between poses instead of trailing them.
 * Mounting everything on the axis (rather than each piece where it flies) keeps the whole
 * swarm inside the always-loaded altar column chunk — no piece can vanish because its own
 * chunk unloaded mid-shot — and samples light in open air instead of inside the terrain.
 * Displays render out to {@code view_range * 64} blocks from their ENTITY position, so the
 * mount also fixes the range: the swarm carries an explicit
 * {@value #VIEW_RANGE}× override (~{@value #VIEW_RANGE_BLOCKS} blocks) or nobody would see
 * it from the disc ring.</p>
 *
 * <p><b>Budget</b>: pushes are phase-sliced across the update interval, so the server sends
 * roughly {@code AMBIENT_TARGET / UPDATE_INTERVAL_TICKS} entity-data packets per tick
 * (~{@value #AMBIENT_TARGET}/{@value #UPDATE_INTERVAL_TICKS}) rather than the whole swarm in
 * one tick, and the entire pass early-outs while no player is within
 * {@value #PLAYER_GATE_RANGE} blocks of the vortex (pieces simply hold their pose). The
 * swarm is hard-capped at {@value #HARD_CAP} pieces including lightning kicks.</p>
 *
 * <p><b>Despawn guarantee</b> (the {@code StructureFlightFx} doctrine): every piece carries
 * the command tag {@value #ENTITY_TAG} and is tracked in a live-UUID set. A tagged display
 * that joins a level WITHOUT being tracked was persisted by a crash mid-cinematic and is
 * discarded on load, so a killed server can never leave rubble hanging over spawn. On top
 * of that the swarm force-clears itself after {@value #WATCHDOG_TICKS} ticks even if no
 * collapse ever arrives, and {@code /kill @e[tag=eclipse_storm_debris]} always works.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class StormDebrisFx {
    /** Frozen command tag on every debris piece — strays from a crash are swept on load. */
    public static final String ENTITY_TAG = "eclipse_storm_debris";

    // ------------------------------------------------------------------ tuning constants

    /** Ambient swarm size the staggered spawn fills up to (user ask: "150–400"). */
    private static final int AMBIENT_TARGET = 200;
    /** Absolute ceiling including lightning kicks — never exceeded, whatever happens. */
    private static final int HARD_CAP = 400;
    /** Pieces per spawn batch and the stagger between batches (spawn-cost smoothing). */
    private static final int SPAWN_BATCH = 8;
    private static final int SPAWN_STAGGER_TICKS = 3;
    /** Transform push cadence == interpolation duration (DisplayAnimator law). */
    private static final int UPDATE_INTERVAL_TICKS = 3;
    /** Fresh pieces thrown up out of the ground by one lightning strike. */
    private static final int LIGHTNING_KICK_PIECES = 12;
    /** Minimum ticks between two lightning kicks (a strike hail must not flood the swarm). */
    private static final int LIGHTNING_KICK_COOLDOWN_TICKS = 25;
    /** Loft envelope of a kicked piece: ground → orbit over this many ticks. */
    private static final int LOFT_TICKS = 44;
    /** Whole pass sleeps (zero packets) with no player this close to the vortex axis. */
    private static final double PLAYER_GATE_RANGE = 224.0D;
    /** Force-clear after this long without a collapse (wedged run / lost hand-off). */
    private static final int WATCHDOG_TICKS = 6000;

    /** Orbit band around the shell, as multiples of the storm radius. */
    private static final double RADIUS_INNER_FACTOR = 1.05D;
    private static final double RADIUS_OUTER_FACTOR = 2.2D;
    /** Vertical band inside the storm column, as fractions of the storm height. */
    private static final double HEIGHT_LOW_FRACTION = 0.06D;
    private static final double HEIGHT_HIGH_FRACTION = 1.08D;
    /**
     * Tangential speed (blocks/tick) the angular rate is derived from, so outer pieces do
     * not whip around faster than inner ones. Varied ±{@value #SPEED_VARIANCE} per piece.
     */
    private static final double TANGENTIAL_BLOCKS_PER_TICK = 0.34D;
    private static final double SPEED_VARIANCE = 0.4D;
    /**
     * Hard floor on the orbit radius as a multiple of the shell radius. The inner band plus
     * a full inward {@link #RADIUS_WOBBLE} swing would otherwise dip pieces INSIDE the smoke
     * (r as low as 0.89× the shell), where they are invisible and read as debris "eaten" by
     * the storm; the clamp keeps every piece just outside the wall it is orbiting.
     */
    private static final double SHELL_CLEARANCE_FACTOR = 1.03D;
    /** Slow radial in/out breathing of a piece's orbit (blocks / ticks). */
    private static final double RADIUS_WOBBLE = 3.5D;
    private static final double RADIUS_WOBBLE_MIN_PERIOD = 120.0D;
    private static final double RADIUS_WOBBLE_MAX_PERIOD = 320.0D;
    /** Vertical bob of a piece around its band height (blocks / ticks). */
    private static final double BOB_AMPLITUDE = 4.5D;
    private static final double BOB_MIN_PERIOD = 90.0D;
    private static final double BOB_MAX_PERIOD = 260.0D;
    /** Piece size spread. */
    private static final float MIN_SCALE = 0.30F;
    private static final float MAX_SCALE = 1.35F;
    /** Tumble rate band (degrees per tick). */
    private static final double SPIN_MIN_DEG_PER_TICK = 0.5D;
    private static final double SPIN_MAX_DEG_PER_TICK = 3.2D;

    /** Collapse spiral length; slightly longer than the vortex DISSIPATE so it outlives it. */
    public static final int COLLAPSE_TICKS = 80;
    /** Angular whip-up factor at the end of the collapse spiral (× the base rate). */
    private static final double COLLAPSE_SPIN_UP = 5.0D;

    /** Display view-range override in vanilla units (× 64 blocks) — see the class doc. */
    private static final float VIEW_RANGE = 8.0F;
    private static final int VIEW_RANGE_BLOCKS = 512;
    /** Storm-lit debris: a little block light so pieces read against the black shell. */
    private static final int DEBRIS_BLOCK_LIGHT = 5;
    private static final int MAX_SKY_LIGHT = 15;

    /** Torn-ground palette: stone, deepslate, earth, splintered wood (user ask). */
    private static final BlockState[] PALETTE = {
            Blocks.STONE.defaultBlockState(),
            Blocks.COBBLESTONE.defaultBlockState(),
            Blocks.ANDESITE.defaultBlockState(),
            Blocks.TUFF.defaultBlockState(),
            Blocks.DEEPSLATE.defaultBlockState(),
            Blocks.COBBLED_DEEPSLATE.defaultBlockState(),
            Blocks.DEEPSLATE_BRICKS.defaultBlockState(),
            Blocks.DIRT.defaultBlockState(),
            Blocks.COARSE_DIRT.defaultBlockState(),
            Blocks.ROOTED_DIRT.defaultBlockState(),
            Blocks.GRASS_BLOCK.defaultBlockState(),
            Blocks.GRAVEL.defaultBlockState(),
            Blocks.MOSSY_COBBLESTONE.defaultBlockState(),
            Blocks.OAK_LOG.defaultBlockState(),
            Blocks.OAK_PLANKS.defaultBlockState(),
            Blocks.STRIPPED_OAK_LOG.defaultBlockState(),
            Blocks.SPRUCE_LOG.defaultBlockState(),
            Blocks.SPRUCE_PLANKS.defaultBlockState()};

    /** The single live swarm (one intro at a time), or {@code null}. Server thread only. */
    @Nullable
    private static Swarm swarm;
    /** UUIDs of pieces spawned THIS session; tagged joiners outside it are crash strays. */
    private static final Set<UUID> LIVE_DISPLAYS = Collections.synchronizedSet(new HashSet<>());

    private StormDebrisFx() {}

    // ------------------------------------------------------------------ public beats

    /**
     * Arms the swarm around a storm. Idempotent for the same centre — a repeat call while a
     * swarm already runs is ignored, so a replay or a re-fired phase never doubles it.
     *
     * @param center vortex ground centre (the same {@code Vec3} the storm was spawned at)
     * @param radius storm shell radius
     * @param height storm shell height
     */
    public static void begin(ServerLevel level, Vec3 center, float radius, float height) {
        if (swarm != null) {
            return;
        }
        swarm = new Swarm(level, center, radius, height);
        EclipseMod.LOGGER.info("StormDebrisFx: swarm armed at {} (r {}, h {}, target {} pieces)",
                center, radius, height, AMBIENT_TARGET);
    }

    /**
     * A lightning strike just hit: throw {@value #LIGHTNING_KICK_PIECES} fresh pieces up out
     * of the ground at the impact column. Rate-limited and capped; a no-op without a swarm
     * (so replays and the FX-only lightning controller stay safe).
     */
    public static void lightningKick(ServerLevel level, Vec3 impact) {
        Swarm current = swarm;
        if (current == null || current.level != level || current.collapsing()) {
            return;
        }
        current.kick(impact);
    }

    /**
     * The burst: every piece spirals inward onto {@code target} (the revealed island) and
     * scales to zero, then the swarm discards itself. A no-op without a swarm.
     */
    public static void collapse(ServerLevel level, Vec3 target) {
        Swarm current = swarm;
        if (current == null || current.level != level || current.collapsing()) {
            return;
        }
        current.beginCollapse(target);
        EclipseMod.LOGGER.info("StormDebrisFx: collapsing {} piece(s) into {} over {} ticks",
                current.pieces.size(), target, COLLAPSE_TICKS);
    }

    /** Discards the swarm immediately (abort paths, dev revert, restart recovery). */
    public static void clearAll() {
        Swarm current = swarm;
        if (current != null) {
            current.discardAll();
            swarm = null;
        }
    }

    /** Whether a swarm is currently live (dev status / guards). */
    public static boolean isActive() {
        return swarm != null;
    }

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        // In-memory only: pieces that made it to disk are swept by the join check on the
        // next boot (they can never be adopted, since LIVE_DISPLAYS is cleared here).
        swarm = null;
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
        Swarm current = swarm;
        if (current == null) {
            return;
        }
        MinecraftServer server = event.getServer();
        if (current.level.getServer() != server) {
            return;
        }
        current.tick();
        if (current.done) {
            swarm = null;
        }
    }

    // ------------------------------------------------------------------ the swarm

    /** One flying chunk of the disc. All motion is a pure function of the swarm age. */
    private static final class Piece {
        @Nullable
        Display.BlockDisplay display;
        final BlockState state;
        final float scale;
        /** Orbit parameters around the vortex axis. */
        final double angle0;
        final double angularSpeed;
        final double radius;
        final double radiusWobblePeriod;
        final double radiusWobblePhase;
        final double bandY;
        final double bobAmplitude;
        final double bobPeriod;
        final double bobPhase;
        /** Tumble. */
        final Vector3f spinAxis;
        final float spinRate;
        final float spinPhase;
        /** Push slice: only pushed on swarm ticks where {@code age % interval == phase}. */
        final int pushPhase;
        /** Lightning kicks arc up from here over {@link #LOFT_TICKS}; null = ambient piece. */
        @Nullable
        final Vec3 loftFrom;
        /** Swarm age the piece was spawned at (drives its loft envelope). */
        final int bornAge;

        Piece(BlockState state, float scale, double angle0, double angularSpeed, double radius,
                double radiusWobblePeriod, double radiusWobblePhase, double bandY,
                double bobAmplitude, double bobPeriod, double bobPhase, Vector3f spinAxis,
                float spinRate, float spinPhase, int pushPhase, @Nullable Vec3 loftFrom, int bornAge) {
            this.state = state;
            this.scale = scale;
            this.angle0 = angle0;
            this.angularSpeed = angularSpeed;
            this.radius = radius;
            this.radiusWobblePeriod = radiusWobblePeriod;
            this.radiusWobblePhase = radiusWobblePhase;
            this.bandY = bandY;
            this.bobAmplitude = bobAmplitude;
            this.bobPeriod = bobPeriod;
            this.bobPhase = bobPhase;
            this.spinAxis = spinAxis;
            this.spinRate = spinRate;
            this.spinPhase = spinPhase;
            this.pushPhase = pushPhase;
            this.loftFrom = loftFrom;
            this.bornAge = bornAge;
        }
    }

    private static final class Swarm {
        final ServerLevel level;
        final Vec3 center;
        final float radius;
        final float height;
        /** The one fixed entity position every piece mounts at (vortex axis, mid-height). */
        final Vec3 mount;
        final RandomSource random;
        final List<Piece> pieces = new ArrayList<>(AMBIENT_TARGET);

        int age;
        int spawned;
        int lastKickAge = -LIGHTNING_KICK_COOLDOWN_TICKS;
        /** Swarm age the collapse spiral started at, or −1 while the storm still rages. */
        int collapseStart = -1;
        Vec3 collapseTarget = Vec3.ZERO;
        boolean done;

        Swarm(ServerLevel level, Vec3 center, float radius, float height) {
            this.level = level;
            this.center = center;
            this.radius = radius;
            this.height = height;
            this.mount = new Vec3(center.x, center.y + height * 0.5D, center.z);
            this.random = RandomSource.create(level.getGameTime() * 31L + Double.hashCode(center.x));
        }

        boolean collapsing() {
            return this.collapseStart >= 0;
        }

        void tick() {
            this.age++;
            if (this.age > WATCHDOG_TICKS && !collapsing()) {
                EclipseMod.LOGGER.warn(
                        "StormDebrisFx: swarm outlived its watchdog ({} ticks) — force-clearing", WATCHDOG_TICKS);
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
            if (!collapsing() && visible && this.spawned < AMBIENT_TARGET
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

        // --- spawning ---

        private void spawnBatch() {
            int batch = Math.min(SPAWN_BATCH, AMBIENT_TARGET - this.spawned);
            for (int i = 0; i < batch; i++) {
                spawn(buildAmbient());
            }
        }

        /** Lightning kick: fresh pieces punched up out of the ground at the impact column. */
        void kick(Vec3 impact) {
            if (this.age - this.lastKickAge < LIGHTNING_KICK_COOLDOWN_TICKS) {
                return;
            }
            this.lastKickAge = this.age;
            int budget = Math.min(LIGHTNING_KICK_PIECES, HARD_CAP - this.pieces.size());
            if (budget <= 0) {
                return;
            }
            for (int i = 0; i < budget; i++) {
                // Kicked pieces leave the ground in a tight ring at the strike column and
                // are aimed at the INNER orbit band, so the throw reads as "up the wall".
                double angle = this.random.nextDouble() * Math.PI * 2.0D;
                double scatter = 1.0D + this.random.nextDouble() * 5.0D;
                Vec3 from = new Vec3(
                        impact.x + Math.cos(angle) * scatter,
                        this.center.y + this.random.nextDouble() * 1.5D,
                        impact.z + Math.sin(angle) * scatter);
                spawn(buildKicked(from));
            }
            this.level.playSound(null, impact.x, this.center.y, impact.z,
                    EclipseSounds.EVENT_RIFT_WHOOSH.get(), SoundSource.WEATHER,
                    0.7F, 0.6F + this.random.nextFloat() * 0.3F);
        }

        private Piece buildAmbient() {
            double orbitRadius = this.radius * RADIUS_INNER_FACTOR
                    + this.random.nextDouble() * this.radius * (RADIUS_OUTER_FACTOR - RADIUS_INNER_FACTOR);
            double bandY = this.center.y + this.height * (HEIGHT_LOW_FRACTION
                    + this.random.nextDouble() * (HEIGHT_HIGH_FRACTION - HEIGHT_LOW_FRACTION));
            return build(orbitRadius, bandY, null);
        }

        private Piece buildKicked(Vec3 from) {
            double orbitRadius = this.radius * RADIUS_INNER_FACTOR
                    + this.random.nextDouble() * this.radius * 0.55D;
            // Kicks end up HIGH — the strike is what throws them over the shell top.
            double bandY = this.center.y + this.height * (0.55D + this.random.nextDouble() * 0.5D);
            return build(orbitRadius, bandY, from);
        }

        private Piece build(double orbitRadius, double bandY, @Nullable Vec3 loftFrom) {
            // Angular rate from a shared tangential speed: outer pieces do not outrun inner
            // ones, and one 3-tick interpolation window covers ~2-3° of arc (the linear
            // tween across such a chord is visually exact — VFXPOLISH-3's window law).
            double speed = TANGENTIAL_BLOCKS_PER_TICK
                    * (1.0D - SPEED_VARIANCE + this.random.nextDouble() * SPEED_VARIANCE * 2.0D);
            Vector3f spinAxis = new Vector3f(
                    this.random.nextFloat() - 0.5F,
                    this.random.nextFloat() - 0.5F,
                    this.random.nextFloat() - 0.5F);
            if (spinAxis.lengthSquared() < 1.0E-4F) {
                spinAxis.set(0.0F, 1.0F, 0.0F);
            }
            spinAxis.normalize();
            return new Piece(
                    PALETTE[this.random.nextInt(PALETTE.length)],
                    MIN_SCALE + (MAX_SCALE - MIN_SCALE)
                            * (float) Math.pow(this.random.nextDouble(), 1.6D),
                    this.random.nextDouble() * Math.PI * 2.0D,
                    speed / Math.max(1.0D, orbitRadius),
                    orbitRadius,
                    RADIUS_WOBBLE_MIN_PERIOD
                            + this.random.nextDouble() * (RADIUS_WOBBLE_MAX_PERIOD - RADIUS_WOBBLE_MIN_PERIOD),
                    this.random.nextDouble() * Math.PI * 2.0D,
                    bandY,
                    this.random.nextDouble() * BOB_AMPLITUDE,
                    BOB_MIN_PERIOD + this.random.nextDouble() * (BOB_MAX_PERIOD - BOB_MIN_PERIOD),
                    this.random.nextDouble() * Math.PI * 2.0D,
                    spinAxis,
                    (float) Math.toRadians(SPIN_MIN_DEG_PER_TICK
                            + this.random.nextDouble() * (SPIN_MAX_DEG_PER_TICK - SPIN_MIN_DEG_PER_TICK))
                            * (this.random.nextBoolean() ? 1.0F : -1.0F),
                    (float) (this.random.nextDouble() * Math.PI * 2.0D),
                    this.pieces.size() % UPDATE_INTERVAL_TICKS,
                    loftFrom,
                    this.age);
        }

        private void spawn(Piece piece) {
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
            display.setBlockState(piece.state);
            display.moveTo(this.mount.x, this.mount.y, this.mount.z, 0.0F, 0.0F);
            display.addTag(ENTITY_TAG);
            // Displays are dropped past view_range * 64 blocks from their ENTITY anchor and
            // the whole swarm anchors on the vortex axis, so the range override is what makes
            // the outer pieces visible at all; the block-light floor keeps them readable
            // against the black shell. One NBT round-trip, before the first pose is pushed.
            DisplayBrightnessFx.set(display, DEBRIS_BLOCK_LIGHT, MAX_SKY_LIGHT, VIEW_RANGE);
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(0);
            display.setTransformation(poseAt(piece, this.age));
            LIVE_DISPLAYS.add(display.getUUID());
            this.level.addFreshEntity(display);
            piece.display = display;
            this.pieces.add(piece);
            if (piece.loftFrom == null) {
                this.spawned++;
            }
        }

        // --- motion ---

        /**
         * One interpolated push per piece in this tick's slice, targeting the pose the
         * window ENDS on (keyframe lead) so the client tween covers the gap instead of
         * trailing a full interval behind the server.
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
                display.setTransformationInterpolationDelay(0);
                display.setTransformationInterpolationDuration(UPDATE_INTERVAL_TICKS);
                display.setTransformation(poseAt(piece, this.age + UPDATE_INTERVAL_TICKS));
            }
            if (missing) {
                this.pieces.removeIf(piece -> piece.display == null || piece.display.isRemoved());
            }
        }

        /**
         * Absolute pose of one piece at swarm age {@code t}: vortex orbit (angle + wobbling
         * radius + bob), optionally blended out of a lightning loft, optionally blended into
         * the collapse spiral — folded into one translation relative to the shared mount,
         * plus the piece's own tumble. Pure function of {@code t}, so pushes are stateless.
         */
        private Transformation poseAt(Piece piece, int t) {
            double life = t - piece.bornAge;
            double angle = piece.angle0 + piece.angularSpeed * life;
            double orbitRadius = Math.max(this.radius * SHELL_CLEARANCE_FACTOR, piece.radius
                    + Math.sin((Math.PI * 2.0D / piece.radiusWobblePeriod) * life + piece.radiusWobblePhase)
                            * RADIUS_WOBBLE);
            double orbitY = piece.bandY
                    + Math.sin((Math.PI * 2.0D / piece.bobPeriod) * life + piece.bobPhase)
                            * piece.bobAmplitude;

            double px = this.center.x + Math.cos(angle) * orbitRadius;
            double py = orbitY;
            double pz = this.center.z + Math.sin(angle) * orbitRadius;
            float scale = piece.scale;

            // Lightning loft: the piece leaves the ground at the strike column and eases
            // into its orbit slot over LOFT_TICKS (ease-out — a real throw decelerating).
            Vec3 loftFrom = piece.loftFrom;
            if (loftFrom != null && life < LOFT_TICKS) {
                float raw = (float) Mth.clamp(life / (double) LOFT_TICKS, 0.0D, 1.0D);
                float eased = 1.0F - (1.0F - raw) * (1.0F - raw) * (1.0F - raw);
                px = Mth.lerp(eased, loftFrom.x, px);
                py = Mth.lerp(eased, loftFrom.y, py);
                pz = Mth.lerp(eased, loftFrom.z, pz);
            }

            // Collapse spiral: radius closes on the target while the angle whips up, so the
            // path reads as a spiral rather than a straight suck-in; scale rides to zero so
            // the pieces "arrive and are gone" instead of popping out over the island.
            if (collapsing()) {
                float raw = (float) Mth.clamp(
                        (t - this.collapseStart) / (double) COLLAPSE_TICKS, 0.0D, 1.0D);
                float eased = raw * raw * (3.0F - 2.0F * raw);
                double whip = piece.angularSpeed * COLLAPSE_SPIN_UP * (t - this.collapseStart) * eased;
                double closing = orbitRadius * (1.0F - eased) * (1.0F - eased);
                px = this.collapseTarget.x + Math.cos(angle + whip) * closing;
                pz = this.collapseTarget.z + Math.sin(angle + whip) * closing;
                py = Mth.lerp(eased, py, this.collapseTarget.y);
                scale = piece.scale * (1.0F - eased);
            }

            float spinAngle = piece.spinPhase + piece.spinRate * (float) life;
            Quaternionf rotation = new Quaternionf().rotationAxis(spinAngle, piece.spinAxis);
            Vector3f translation = new Vector3f(
                    (float) (px - this.mount.x),
                    (float) (py - this.mount.y),
                    (float) (pz - this.mount.z));
            // Re-centre the [0,scale]^3 block mesh on the flight point through the rotation.
            Vector3f half = new Vector3f(scale * 0.5F, scale * 0.5F, scale * 0.5F);
            translation.sub(rotation.transform(half, new Vector3f()));
            return new Transformation(translation, rotation,
                    new Vector3f(scale, scale, scale), new Quaternionf());
        }

        void beginCollapse(Vec3 target) {
            this.collapseStart = this.age;
            this.collapseTarget = target;
            // Push the first collapse keyframe for EVERY piece at once (not just this
            // tick's slice), or up to two thirds of the swarm would keep orbiting for
            // another two ticks before turning inward — the turn must read as one gesture.
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
