package dev.projecteclipse.eclipse.sequence;

import java.util.ArrayDeque;
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
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.worldgen.stage.DisplayBrightnessFx;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityJoinLevelEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * The block-display choreography of {@link NetherOpeningSequence} — the ground of the
 * future crater first JUMPS, then is thrown into the sky.
 *
 * <p><b>Two beats</b>, both driven from the sequence (nothing here ever runs on its own):</p>
 * <ol>
 *   <li>{@link #beginTremor} — phase 2: waves of {@value #HOP_WAVE} real ground blocks are
 *       kicked loose all over the crater footprint, ride a short parabola
 *       ({@value #HOP_TICKS} ticks) with a drunken tilt and slam back down. The wave cadence
 *       breathes with {@link #hopWavePressure}, so the quake reads as swells rather than
 *       popcorn. F-102 <b>slam beats</b>: the tick a wave lands back in the ground (spawn +
 *       {@value #HOP_TICKS}, rate-limited to one beat per {@value #SLAM_BEAT_MIN_INTERVAL}
 *       ticks) the swarm plays a muffled ground thud and fires the
 *       {@code eclipse:fx/cue/nether_tremor_slam} cue over the SHIPPED position cue lane
 *       ({@code S2CFxEventPayload} — nothing new on the wire, the B7 ember-tear precedent);
 *       the client row ({@code veilfx.NetherOpenPhotonFxRows}) answers with a dust-ring
 *       stamp + camera kick, so the visible block slam, the thud and the shake are ONE
 *       fühlbarer Einschlag-Beat. {@code a} carries the pressure at the landing tick.</li>
 *   <li>{@link #erupt} — phase 3: the whole footprint is blown out at once as up to
 *       {@value #FOUNTAIN_PIECES} pieces on ballistic fountain arcs (up + outward, faster
 *       and steeper towards the middle), tumbling hard and scaling to zero as they fall,
 *       so nothing ever lands as visible litter. {@value #JET_SHARE} of them are JET
 *       slugs fired out of the throat on a lighter gravity — the central column that
 *       gives the eruption an axis.</li>
 * </ol>
 *
 * <p><b>Transport</b> (the {@code StormDebrisFx} law): every piece is mounted at ONE fixed
 * entity position — the crater axis at {@value #MOUNT_ABOVE_LIP} above the lip — and all
 * motion lives in the transformation's translation, pushed every
 * {@value #UPDATE_INTERVAL_TICKS} ticks with a matching interpolation duration and a
 * one-window keyframe LEAD. The shared mount keeps the entire swarm inside the crater's own
 * (builder-ticketed) chunk, so no piece can vanish because its chunk unloaded mid-shot, and
 * the {@value #VIEW_RANGE}× view-range override (~{@value #VIEW_RANGE_BLOCKS} blocks) makes
 * the throw readable from the whole desert ring.</p>
 *
 * <p><b>Budget</b>: pushes are phase-sliced across the update interval (~{@value #HARD_CAP}/
 * {@value #UPDATE_INTERVAL_TICKS} entity-data packets per tick worst case) and the entire
 * pass early-outs while no player is within {@value #PLAYER_GATE_RANGE} blocks. The swarm is
 * hard-capped at {@value #HARD_CAP} live pieces across BOTH beats.</p>
 *
 * <p><b>Despawn guarantee</b> (the {@code StormDebrisFx} doctrine): every piece carries the
 * command tag {@value #ENTITY_TAG} and is tracked in a live-UUID set. A tagged display that
 * joins a level WITHOUT being tracked was persisted by a crash mid-sequence and is discarded
 * on load; the swarm force-clears itself after {@value #WATCHDOG_TICKS} ticks even if the
 * sequence never releases it; and {@code /kill @e[tag=eclipse_nether_upheaval]} always
 * works.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class NetherUpheavalFx {
    /** Frozen command tag on every piece — strays from a crash are swept on load. */
    public static final String ENTITY_TAG = "eclipse_nether_upheaval";

    // ------------------------------------------------------------------ tuning constants

    /** Absolute ceiling of live pieces across both beats — never exceeded. */
    private static final int HARD_CAP = 480;
    /** Pieces kicked loose per quake wave. */
    private static final int HOP_WAVE = 9;
    /** Ticks between two quake waves at full pressure (scaled up while pressure is low). */
    private static final int HOP_WAVE_INTERVAL = 14;
    /** One hop: up and back down over this many ticks. */
    private static final int HOP_TICKS = 26;
    /** Hop apex band (blocks). */
    private static final double HOP_HEIGHT_MIN = 0.5D;
    private static final double HOP_HEIGHT_MAX = 1.9D;
    /** Fountain size (FX-Wave-12 eruption gigantism). */
    private static final int FOUNTAIN_PIECES = 380;
    /** Fountain pieces spawned per tick — spreads the spawn cost over ~1.5 s. */
    private static final int FOUNTAIN_SPAWN_BATCH = 12;
    /** Fountain launch speed band at the rim … (blocks/tick). */
    private static final double FOUNTAIN_SPEED_MIN = 0.55D;
    /** … and in the middle of the mouth, where the eruption is strongest. */
    private static final double FOUNTAIN_SPEED_MAX = 1.75D;
    /** Outward lean of a fountain arc as a fraction of its launch speed. */
    private static final double FOUNTAIN_SPREAD = 0.55D;
    /** Gravity pulling the arcs back down (blocks/tick²). */
    private static final double FOUNTAIN_GRAVITY = 0.045D;
    /** A fountain piece is discarded (and its slot freed) after this long. */
    private static final int FOUNTAIN_FLIGHT_TICKS = 110;
    /** Last fraction of the flight the piece scales to zero over. */
    private static final double FOUNTAIN_FADE_FRACTION = 0.3D;

    /**
     * FX-Wave-12 JET class: this share of the eruption launches from the very throat of
     * the crater — inside {@value #JET_RADIUS_FRACTION}× the mouth radius — nearly
     * straight up at {@value #JET_SPEED_MIN}–{@value #JET_SPEED_MAX} blocks/tick. That is
     * the central COLUMN that turns a wide fountain into an eruption with an axis.
     */
    private static final double JET_SHARE = 0.15D;
    private static final double JET_RADIUS_FRACTION = 0.25D;
    private static final double JET_SPEED_MIN = 2.6D;
    private static final double JET_SPEED_MAX = 3.4D;
    /** Tight outward lean — the jet must read as a column, not a second fountain. */
    private static final double JET_SPREAD = 0.03D;
    /**
     * Jet gravity as a multiple of {@value #FOUNTAIN_GRAVITY}.
     *
     * <p>The FX-Wave-12 recipe asked for 0.6 to make the jet hang, but the piece life is
     * the harder constraint and it wins. A jet apexes at {@code t = v / g} and fades from
     * {@code (1 - }{@value #FOUNTAIN_FADE_FRACTION}{@code ) × }{@value
     * #FOUNTAIN_FLIGHT_TICKS}{@code  = 77t}. At 0.6 the top of the launch band apexes at
     * 126t — the slug is DISCARDED still climbing, so the column never tops out at all.
     * Even 0.8 apexes at 94t, i.e. at 47 % scale, so the crown of the column is drawn by
     * a piece that has half melted away. Full gravity is the largest reduction the 110t
     * life can actually pay for: the whole {@value #JET_SPEED_MIN}–{@value
     * #JET_SPEED_MAX} band then apexes by 76t, a beat BEFORE the fade opens, and the
     * column reads at full scale all the way to its crown.
     *
     * <p>Apex is {@code v² / (2·g)}, so that band tops out at ~75–128 blocks and, since
     * the speed roll is biased low, sits around ~95 for the bulk of the jets — the
     * ~90–120 block column the recipe was actually describing.
     */
    private static final double JET_GRAVITY_FACTOR = 1.0D;

    // --- F-102 slam beats (the fühlbare Einschlag-Beats of phase 2) ---
    /**
     * Cue id of the hop-wave slam beat. Both sides derive the same
     * {@code FxCues.cue("nether_tremor_slam")} id (the CreditsSequence naming-contract
     * precedent, so {@code FxCues.java} stays untouched); the client row lives in
     * {@code veilfx.NetherOpenPhotonFxRows}.
     */
    private static final ResourceLocation CUE_TREMOR_SLAM = FxCues.cue("nether_tremor_slam");
    /**
     * Minimum ticks between two slam beats. Waves land every 14–56 ticks (the pressure
     * cadence); un-limited that is a machine gun, limited to one per ~2.4 s the tremor
     * gets 6–7 clean, growing beats over its 18 s — beats, not texture.
     */
    private static final int SLAM_BEAT_MIN_INTERVAL = 48;
    /**
     * Cue broadcast range (blocks). The camera kick fades to zero at 120 anyway
     * ({@code NetherOpenClientFx.SHAKE_RANGE}) and a ring stamp nobody can see would
     * only burn a Photon executor slot — no reason to ship the beat dimension-wide the
     * way the phase entries are.
     */
    private static final double SLAM_CUE_RANGE = 160.0D;
    /** Slam thud volume/pitch bands, scaled by the pressure at the landing tick. */
    private static final float SLAM_THUD_VOLUME_MIN = 0.9F;
    private static final float SLAM_THUD_VOLUME_SPAN = 0.7F;
    private static final float SLAM_THUD_PITCH_MIN = 0.3F;
    private static final float SLAM_THUD_PITCH_SPAN = 0.08F;

    /** Transform push cadence == interpolation duration (DisplayAnimator law). */
    private static final int UPDATE_INTERVAL_TICKS = 3;
    /** Mount height above the lip plane — the one entity anchor of the whole swarm. */
    private static final int MOUNT_ABOVE_LIP = 6;
    /** Whole pass sleeps (zero packets) with no player this close to the crater axis. */
    private static final double PLAYER_GATE_RANGE = 224.0D;
    /** Force-clear after this long without a release (wedged run / lost hand-off). */
    private static final int WATCHDOG_TICKS = 2400;
    /** Display view-range override in vanilla units (× 64 blocks). */
    private static final float VIEW_RANGE = 6.0F;
    private static final int VIEW_RANGE_BLOCKS = 384;
    /** Ember-lit rubble: a little block light so pieces read against the night desert. */
    private static final int PIECE_BLOCK_LIGHT = 6;
    private static final int MAX_SKY_LIGHT = 15;
    /** Piece size spread (FX-Wave-12: widened so slabs read as slabs). */
    private static final float MIN_SCALE = 0.35F;
    private static final float MAX_SCALE = 1.9F;
    /** Scatter around the launch-speed-derived size so the coupling is not a staircase. */
    private static final double SCALE_JITTER = 0.22D;
    /** Tumble rate band (degrees per tick) — hops barely tilt, the fountain spins hard. */
    private static final double HOP_SPIN_MAX_DEG_PER_TICK = 1.1D;
    private static final double FOUNTAIN_SPIN_MIN_DEG_PER_TICK = 2.0D;
    private static final double FOUNTAIN_SPIN_MAX_DEG_PER_TICK = 9.0D;
    /** Jet shrapnel spins hardest of all — it is the smallest, fastest debris there is. */
    private static final double JET_SPIN_MAX_DEG_PER_TICK = 14.0D;

    /**
     * Fallback palette for columns whose real block state cannot be read (chunk not loaded
     * yet, or the column is already air because the builder got there first): the desert
     * ring over the breach plus its crimson-creep repaint.
     */
    private static final BlockState[] FALLBACK_PALETTE = {
            Blocks.SAND.defaultBlockState(),
            Blocks.SANDSTONE.defaultBlockState(),
            Blocks.SMOOTH_SANDSTONE.defaultBlockState(),
            Blocks.STONE.defaultBlockState(),
            Blocks.TUFF.defaultBlockState(),
            Blocks.NETHERRACK.defaultBlockState(),
            Blocks.BLACKSTONE.defaultBlockState(),
            Blocks.MAGMA_BLOCK.defaultBlockState()};

    /** The single live swarm (one opening at a time), or {@code null}. Server thread only. */
    @Nullable
    private static Swarm swarm;
    /** UUIDs of pieces spawned THIS session; tagged joiners outside it are crash strays. */
    private static final Set<UUID> LIVE_DISPLAYS = Collections.synchronizedSet(new HashSet<>());

    private NetherUpheavalFx() {}

    // ------------------------------------------------------------------ public beats

    /**
     * Arms the quake swarm over the crater footprint. Idempotent — a repeat call while a
     * swarm already runs is ignored, so a replay never doubles it.
     *
     * @param center crater centre at the surface lip plane
     * @param radius crater mouth radius (pieces are kicked loose inside it)
     */
    public static void beginTremor(ServerLevel level, BlockPos center, double radius) {
        if (swarm != null) {
            return;
        }
        swarm = new Swarm(level, center, radius);
        EclipseMod.LOGGER.info("NetherUpheavalFx: quake swarm armed at {} (r {})",
                center.toShortString(), radius);
    }

    /**
     * The rupture: blows the whole footprint out as ballistic fountain arcs. Arms the swarm
     * first when the quake beat was skipped (FX replay straight into phase 3).
     */
    public static void erupt(ServerLevel level, BlockPos center, double radius) {
        if (swarm == null) {
            beginTremor(level, center, radius);
        }
        Swarm current = swarm;
        if (current == null || current.level != level || current.erupting) {
            return;
        }
        current.erupting = true;
        EclipseMod.LOGGER.info("NetherUpheavalFx: erupting — up to {} fountain piece(s) over {} ticks",
                FOUNTAIN_PIECES, FOUNTAIN_FLIGHT_TICKS);
    }

    /**
     * Releases the swarm: no new pieces are spawned, live ones fly out their arc and the
     * swarm discards itself once the last one lands. The phase-4 hand-off.
     */
    public static void release() {
        Swarm current = swarm;
        if (current != null) {
            current.released = true;
        }
    }

    /** Discards every piece immediately (abort paths, dev stop, restart recovery). */
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

    /** Live piece count (dev status). */
    public static int livePieces() {
        Swarm current = swarm;
        return current == null ? 0 : current.pieces.size();
    }

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        // In-memory only: pieces that made it to disk are swept by the join check on the
        // next boot (they can never be adopted, since LIVE_DISPLAYS is cleared here).
        swarm = null;
        LIVE_DISPLAYS.clear();
    }

    /** StormDebrisFx sweep doctrine: a tagged display we did not spawn is a crash stray. */
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

    /** How hard the quake is pushing right now (0..1) — set by the sequence each tick. */
    private static float hopWavePressure = 1.0F;

    /** Quake pressure for the next waves: 0 = no hops, 1 = full {@value #HOP_WAVE_INTERVAL}. */
    public static void setHopWavePressure(float pressure) {
        hopWavePressure = Mth.clamp(pressure, 0.0F, 1.0F);
    }

    /** One sampled ground column: where a piece launches from, and what it is made of. */
    private record Column(Vec3 pos, BlockState state) {}

    /** One kicked/thrown chunk of ground. All motion is a pure function of the swarm age. */
    private static final class Piece {
        @Nullable
        Display.BlockDisplay display;
        final BlockState state;
        final float scale;
        /** Launch point in world space (surface of its column). */
        final Vec3 from;
        /** Ballistic launch velocity (blocks/tick); {@code null} for a hop. */
        @Nullable
        final Vec3 velocity;
        /** Gravity on this arc (blocks/tick²) — the JET class flies on a lighter one. */
        final double gravity;
        /** Hop apex height (blocks); ignored for fountain pieces. */
        final double hopHeight;
        /** Total lifetime in ticks — the piece is discarded when it runs out. */
        final int lifeTicks;
        final Vector3f spinAxis;
        final float spinRate;
        final float spinPhase;
        /** Push slice: only pushed on swarm ticks where {@code age % interval == phase}. */
        final int pushPhase;
        /** Swarm age the piece was spawned at. */
        final int bornAge;

        Piece(BlockState state, float scale, Vec3 from, @Nullable Vec3 velocity, double gravity,
                double hopHeight, int lifeTicks, Vector3f spinAxis, float spinRate,
                float spinPhase, int pushPhase, int bornAge) {
            this.state = state;
            this.scale = scale;
            this.from = from;
            this.velocity = velocity;
            this.gravity = gravity;
            this.hopHeight = hopHeight;
            this.lifeTicks = lifeTicks;
            this.spinAxis = spinAxis;
            this.spinRate = spinRate;
            this.spinPhase = spinPhase;
            this.pushPhase = pushPhase;
            this.bornAge = bornAge;
        }
    }

    private static final class Swarm {
        final ServerLevel level;
        final BlockPos center;
        final double radius;
        /** The one fixed entity position every piece mounts at (crater axis above the lip). */
        final Vec3 mount;
        final RandomSource random;
        final List<Piece> pieces = new ArrayList<>(HARD_CAP);

        int age;
        int lastWaveAge = -HOP_WAVE_INTERVAL;
        boolean erupting;
        int fountainSpawned;
        boolean released;
        boolean done;
        /** Swarm ages at which a spawned hop wave slams back down (spawn + HOP_TICKS). */
        final ArrayDeque<Integer> pendingSlamAges = new ArrayDeque<>();
        /** Age of the last fired slam beat (rate limiter). */
        int lastSlamAge = -SLAM_BEAT_MIN_INTERVAL;

        Swarm(ServerLevel level, BlockPos center, double radius) {
            this.level = level;
            this.center = center;
            this.radius = radius;
            this.mount = new Vec3(center.getX() + 0.5D, center.getY() + MOUNT_ABOVE_LIP,
                    center.getZ() + 0.5D);
            this.random = RandomSource.create(level.getGameTime() * 31L + center.hashCode());
        }

        void tick() {
            this.age++;
            if (this.age > WATCHDOG_TICKS) {
                EclipseMod.LOGGER.warn(
                        "NetherUpheavalFx: swarm outlived its watchdog ({} ticks) — force-clearing",
                        WATCHDOG_TICKS);
                discardAll();
                this.done = true;
                return;
            }
            boolean visible = playerNear();
            if (visible && !this.released) {
                if (this.erupting) {
                    spawnFountainBatch();
                } else if (this.age - this.lastWaveAge >= waveInterval()) {
                    this.lastWaveAge = this.age;
                    spawnHopWave();
                }
            }
            tickSlamBeats();
            reap();
            if (this.released && this.pieces.isEmpty()) {
                this.done = true; // last arc landed: the swarm retires itself
                return;
            }
            if (visible) {
                animate();
            }
        }

        /** Wave cadence stretches as the quake pressure drops (1× … 4× the base interval). */
        private int waveInterval() {
            return (int) (HOP_WAVE_INTERVAL * (1.0F + 3.0F * (1.0F - hopWavePressure)));
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

        private void spawnHopWave() {
            if (hopWavePressure <= 0.0F) {
                return;
            }
            int before = this.pieces.size();
            int batch = Math.max(1, Math.round(HOP_WAVE * hopWavePressure));
            for (int i = 0; i < batch; i++) {
                Column column = surfacePoint(Math.sqrt(this.random.nextDouble()) * this.radius);
                if (column == null) {
                    continue;
                }
                double height = HOP_HEIGHT_MIN
                        + this.random.nextDouble() * (HOP_HEIGHT_MAX - HOP_HEIGHT_MIN)
                                * (0.4D + 0.6D * hopWavePressure);
                // Hops are not thrown, so they keep a free size roll (speedFraction random).
                spawn(build(column, null, FOUNTAIN_GRAVITY, height, HOP_TICKS,
                        HOP_SPIN_MAX_DEG_PER_TICK * 0.15D, HOP_SPIN_MAX_DEG_PER_TICK,
                        this.random.nextDouble()));
            }
            if (this.pieces.size() > before) {
                // F-102: the wave WILL slam back down at spawn + HOP_TICKS — that landing
                // tick (not the launch) is the beat. Only waves that really put pieces in
                // the air queue one; skipped/unloaded columns never fake a beat.
                this.pendingSlamAges.addLast(this.age + HOP_TICKS);
            }
        }

        /**
         * F-102 slam beats: fires the thud + {@link #CUE_TREMOR_SLAM} cue when a queued
         * hop wave lands, rate-limited to one beat per {@value #SLAM_BEAT_MIN_INTERVAL}
         * ticks (over-cadenced landings merge into the running beat). The eruption drops
         * every pending beat — the RUPTURE punch owns the frame from that tick on.
         */
        private void tickSlamBeats() {
            if (this.erupting || this.released) {
                this.pendingSlamAges.clear();
                return;
            }
            boolean due = false;
            while (!this.pendingSlamAges.isEmpty() && this.pendingSlamAges.peekFirst() <= this.age) {
                this.pendingSlamAges.removeFirst();
                due = true;
            }
            if (!due || this.age - this.lastSlamAge < SLAM_BEAT_MIN_INTERVAL) {
                return;
            }
            this.lastSlamAge = this.age;
            float pressure = hopWavePressure;
            // Muffled body thump, growing with the quake (the rupture keeps its 4.0/0.5
            // GENERIC_EXPLODE headroom — these stay well under it).
            this.level.playSound(null, this.center, SoundEvents.GENERIC_EXPLODE.value(),
                    SoundSource.BLOCKS,
                    SLAM_THUD_VOLUME_MIN + SLAM_THUD_VOLUME_SPAN * pressure,
                    SLAM_THUD_PITCH_MIN + SLAM_THUD_PITCH_SPAN * pressure);
            // Existing position cue lane (S2CFxEventPayload) — the client row stamps the
            // dust ring and kicks the camera, proximity-scaled on its own side. Anchor =
            // lip-plane block center, the same (x+0.5, y+0.5, z+0.5) the phase one-shots
            // use (SURFACE_LIFT), so ring and fissure star share one ground plane.
            FxPayloads.sendFxEvent(this.level, CUE_TREMOR_SLAM,
                    Vec3.atCenterOf(this.center), pressure, 0.0F, SLAM_CUE_RANGE);
        }

        private void spawnFountainBatch() {
            int budget = Math.min(FOUNTAIN_SPAWN_BATCH, FOUNTAIN_PIECES - this.fountainSpawned);
            for (int i = 0; i < budget; i++) {
                if (this.random.nextDouble() < JET_SHARE) {
                    spawnJet();
                    continue;
                }
                // Bias towards the middle: the throat throws hardest, the rim only crumbles.
                double t = this.random.nextDouble();
                double dist = t * t * this.radius;
                Column column = surfacePoint(dist);
                if (column == null) {
                    continue;
                }
                double centrality = 1.0D - dist / Math.max(1.0D, this.radius);
                double speed = FOUNTAIN_SPEED_MIN
                        + (FOUNTAIN_SPEED_MAX - FOUNTAIN_SPEED_MIN) * centrality
                                * (0.65D + this.random.nextDouble() * 0.35D);
                double angle = Math.atan2(column.pos().z - this.mount.z,
                        column.pos().x - this.mount.x)
                        + (this.random.nextDouble() - 0.5D) * 0.8D;
                double outward = speed * FOUNTAIN_SPREAD * (0.3D + this.random.nextDouble());
                Vec3 velocity = new Vec3(Math.cos(angle) * outward, speed,
                        Math.sin(angle) * outward);
                this.fountainSpawned++;
                spawn(build(column, velocity, FOUNTAIN_GRAVITY, 0.0D, FOUNTAIN_FLIGHT_TICKS,
                        FOUNTAIN_SPIN_MIN_DEG_PER_TICK, FOUNTAIN_SPIN_MAX_DEG_PER_TICK,
                        (speed - FOUNTAIN_SPEED_MIN)
                                / (FOUNTAIN_SPEED_MAX - FOUNTAIN_SPEED_MIN)));
            }
        }

        /**
         * One JET slug: torn out of the throat (inside {@value #JET_RADIUS_FRACTION}× the
         * mouth radius) and fired nearly straight up. The speed roll is biased low, so the
         * band's 75–128 block apex range lands around ~95 for the bulk of the column and
         * only the occasional hero slug goes the full distance.
         */
        private void spawnJet() {
            Column column = surfacePoint(Math.sqrt(this.random.nextDouble())
                    * this.radius * JET_RADIUS_FRACTION);
            if (column == null) {
                return;
            }
            double jetRoll = Math.pow(this.random.nextDouble(), 1.6D);
            double speed = JET_SPEED_MIN + (JET_SPEED_MAX - JET_SPEED_MIN) * jetRoll;
            double angle = this.random.nextDouble() * Math.PI * 2.0D;
            double outward = speed * JET_SPREAD * this.random.nextDouble();
            Vec3 velocity = new Vec3(Math.cos(angle) * outward, speed,
                    Math.sin(angle) * outward);
            this.fountainSpawned++;
            spawn(build(column, velocity, FOUNTAIN_GRAVITY * JET_GRAVITY_FACTOR, 0.0D,
                    FOUNTAIN_FLIGHT_TICKS, FOUNTAIN_SPIN_MAX_DEG_PER_TICK,
                    JET_SPIN_MAX_DEG_PER_TICK, 0.8D + 0.2D * jetRoll));
        }

        /**
         * A random surface point at {@code dist} from the axis, carrying its column's REAL
         * block state. {@code null} when the column is not loaded — the caller skips it and
         * the next wave tries again.
         */
        @Nullable
        private Column surfacePoint(double dist) {
            double angle = this.random.nextDouble() * Math.PI * 2.0D;
            int x = (int) Math.round(this.center.getX() + Math.cos(angle) * dist);
            int z = (int) Math.round(this.center.getZ() + Math.sin(angle) * dist);
            if (!this.level.isLoaded(new BlockPos(x, this.center.getY(), z))) {
                return null;
            }
            int surfaceY = this.level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z);
            BlockState state = this.level.getBlockState(new BlockPos(x, surfaceY - 1, z));
            if (state.isAir()) {
                state = FALLBACK_PALETTE[this.random.nextInt(FALLBACK_PALETTE.length)];
            }
            return new Column(new Vec3(x + 0.5D, surfaceY, z + 0.5D), state);
        }

        /**
         * FX-Wave-12 mass law: size and tumble are DERIVED from how hard the piece was
         * thrown ({@code speedFraction} 0 = barely nudged, 1 = shotgunned). Fast pieces
         * come out small and spinning hard, slow ones come out as big lazy slabs, so the
         * eruption reads as a real spray of graded debris instead of uniform confetti.
         */
        private Piece build(Column column, @Nullable Vec3 velocity, double gravity,
                double hopHeight, int lifeTicks, double spinMinDeg, double spinMaxDeg,
                double speedFraction) {
            double thrown = Mth.clamp(speedFraction, 0.0D, 1.0D);
            float scale = (float) Mth.clamp(
                    MAX_SCALE - thrown * (MAX_SCALE - MIN_SCALE)
                            + (this.random.nextDouble() * 2.0D - 1.0D) * SCALE_JITTER,
                    MIN_SCALE, MAX_SCALE);
            double spinDeg = spinMinDeg + (spinMaxDeg - spinMinDeg) * Mth.clamp(
                    thrown + (this.random.nextDouble() - 0.5D) * 0.3D, 0.0D, 1.0D);
            Vector3f spinAxis = new Vector3f(
                    this.random.nextFloat() - 0.5F,
                    this.random.nextFloat() - 0.5F,
                    this.random.nextFloat() - 0.5F);
            if (spinAxis.lengthSquared() < 1.0E-4F) {
                spinAxis.set(0.0F, 1.0F, 0.0F);
            }
            spinAxis.normalize();
            return new Piece(
                    column.state(),
                    scale,
                    column.pos(), velocity, gravity, hopHeight, lifeTicks, spinAxis,
                    (float) Math.toRadians(spinDeg)
                            * (this.random.nextBoolean() ? 1.0F : -1.0F),
                    (float) (this.random.nextDouble() * Math.PI * 2.0D),
                    this.pieces.size() % UPDATE_INTERVAL_TICKS,
                    this.age);
        }

        private void spawn(Piece piece) {
            if (this.pieces.size() >= HARD_CAP) {
                return;
            }
            BlockPos mountPos = BlockPos.containing(this.mount);
            if (!this.level.isLoaded(mountPos)) {
                return; // crater column not loaded (yet): the next wave retries
            }
            Display.BlockDisplay display = EntityType.BLOCK_DISPLAY.create(this.level);
            if (display == null) {
                return;
            }
            display.setBlockState(piece.state);
            display.moveTo(this.mount.x, this.mount.y, this.mount.z, 0.0F, 0.0F);
            display.addTag(ENTITY_TAG);
            // Displays are dropped past view_range * 64 blocks from their ENTITY anchor and
            // the whole swarm anchors on the crater axis, so the override is what makes the
            // throw visible from the ring; the block-light floor keeps the rubble readable.
            // One NBT round-trip, before the first pose is pushed.
            DisplayBrightnessFx.set(display, PIECE_BLOCK_LIGHT, MAX_SKY_LIGHT, VIEW_RANGE);
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
         * window ENDS on (keyframe lead) so the client tween covers the gap instead of
         * trailing a full interval behind the server.
         */
        private void animate() {
            int slice = this.age % UPDATE_INTERVAL_TICKS;
            for (Piece piece : this.pieces) {
                if (piece.pushPhase != slice) {
                    continue;
                }
                Display.BlockDisplay display = piece.display;
                if (display == null || display.isRemoved()) {
                    continue;
                }
                display.setTransformationInterpolationDelay(0);
                display.setTransformationInterpolationDuration(UPDATE_INTERVAL_TICKS);
                display.setTransformation(poseAt(piece, this.age + UPDATE_INTERVAL_TICKS));
            }
        }

        /** Discards pieces whose arc/hop has run out (and any the world removed under us). */
        private void reap() {
            this.pieces.removeIf(piece -> {
                Display.BlockDisplay display = piece.display;
                if (display == null || display.isRemoved()) {
                    if (display != null) {
                        LIVE_DISPLAYS.remove(display.getUUID());
                    }
                    return true;
                }
                if (this.age - piece.bornAge < piece.lifeTicks) {
                    return false;
                }
                LIVE_DISPLAYS.remove(display.getUUID());
                display.discard();
                piece.display = null;
                return true;
            });
        }

        /**
         * Absolute pose of one piece at swarm age {@code t}: a sine hop or a ballistic arc,
         * folded into one translation relative to the shared mount, plus the piece's own
         * tumble. Pure function of {@code t}, so pushes are stateless.
         */
        private Transformation poseAt(Piece piece, int t) {
            double life = Math.max(0.0D, t - piece.bornAge);
            double px = piece.from.x;
            double py = piece.from.y;
            double pz = piece.from.z;
            float scale = piece.scale;

            Vec3 velocity = piece.velocity;
            if (velocity == null) {
                // Hop: one clean sine arc, clamped at the ends so the slam reads as a slam.
                double u = Mth.clamp(life / (double) piece.lifeTicks, 0.0D, 1.0D);
                py += Math.sin(Math.PI * u) * piece.hopHeight;
            } else {
                px += velocity.x * life;
                py += velocity.y * life - 0.5D * piece.gravity * life * life;
                pz += velocity.z * life;
                double fadeStart = piece.lifeTicks * (1.0D - FOUNTAIN_FADE_FRACTION);
                if (life > fadeStart) {
                    float fade = (float) Mth.clamp(
                            (life - fadeStart) / (piece.lifeTicks - fadeStart), 0.0D, 1.0D);
                    scale = piece.scale * (1.0F - fade);
                }
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
