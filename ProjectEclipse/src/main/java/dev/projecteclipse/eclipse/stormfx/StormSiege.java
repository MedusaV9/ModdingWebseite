package dev.projecteclipse.eclipse.stormfx;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import javax.annotation.Nullable;

import com.mojang.math.Transformation;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.boss.fog.FogTyrantEntity;
import dev.projecteclipse.eclipse.entity.boss.fog.TyrantStatue;
import dev.projecteclipse.eclipse.lives.GraveProtection;
import dev.projecteclipse.eclipse.network.fx.S2CStormSiegePayload;
import dev.projecteclipse.eclipse.network.fx.S2CStormStatePayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.worldgen.stage.DisplayBrightnessFx;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.BlockParticleOption;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.damagesource.DamageTypes;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityJoinLevelEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * F-031 — the server-side SIEGE orchestrator: the Fog-Tyrant boss fight raging INSIDE a
 * standing C8 site storm turns the storm itself hostile. Detection is a poll (every
 * {@value #POLL_TICKS} ticks): a living {@link FogTyrantEntity} inside an ACTIVE sphere
 * storm's footprint starts the siege; the tyrant vanishing ends it — via
 * {@code StormRegistry} state {@code EXPLODE} (victory: the death thunderclap burst) or
 * without one (abandon: the Herald wipe/reset despawned him). The boss class itself is
 * NEVER touched — the whole feature reads the world.
 *
 * <p><b>While the siege runs:</b></p>
 * <ul>
 *   <li><b>Client overlay</b> ({@link S2CStormSiegePayload}, re-sent as a keepalive every
 *       {@value #KEEPALIVE_TICKS} ticks — idempotent): storm grows to
 *       {@value #RADIUS_SCALE}× over {@value #GROW_TICKS} ticks (F-031a), the occluder
 *       core dissolves for combat sight (F-032), the volumetric pass drops one quality
 *       tier + caps steps (F-031b).</li>
 *   <li><b>Whirl debris</b> (F-031c): {@value #DEBRIS_MIN}–{@value #DEBRIS_MAX}
 *       {@link Display.BlockDisplay} chunks orbit the combat ring. Transport is the
 *       {@code StormDebrisFx} law: every display mounts at ONE fixed position (combat
 *       center, mid-height) and all motion lives in interpolated transformation pushes,
 *       phase-sliced across {@value #UPDATE_INTERVAL_TICKS}-tick windows.</li>
 *   <li><b>Block lifts</b> (F-031d): every {@value #LIFT_MIN_INTERVAL}–{@value
 *       #LIFT_MAX_INTERVAL} ticks the storm tears {@value #LIFT_MIN}–{@value #LIFT_MAX}
 *       REAL surface blocks out of the combat ring (block removed from the world, a
 *       display rises), hovers them, then flings each at a random arena player — impact
 *       deals {@value #DAMAGE_MIN}–{@value #DAMAGE_MAX} falling-block damage in a small
 *       radius, bursts block particles, and the block either re-places itself where it
 *       lands (if free) or drops as an item. Simple full-cube blocks only (no block
 *       entities, no bedrock-class blocks, no fluids).</li>
 * </ul>
 *
 * <p><b>Endings are clean by construction:</b> victory converts the whirl debris into the
 * F-033 stage-3 radial fling (outward over {@value #FLING_OUT_TICKS} ticks, scale → 0)
 * and resolves every airborne lift as a drop; abandon sinks the debris out over
 * {@value #SINK_TICKS} ticks, restores lifted blocks (re-place if still free, drop
 * otherwise) and eases the client overlay back. Despawn guarantee (the
 * {@code StormDebrisFx} doctrine, hardened by F-084): every display carries
 * {@value #ENTITY_TAG} + the {@value #STORM_FX_TAG} umbrella + this siege's per-fight
 * scope tag ({@value #FIGHT_SCOPE_TAG_PREFIX}{@code storm_<id>}); tagged joiners not in
 * a live-UUID set (ours or {@code TyrantStatue}'s) are strays and are discarded on load
 * — that ONE check covers crash strays after a restart AND frozen displays whose chunk
 * unloaded mid-session (their UUIDs are pruned from {@code LIVE_DISPLAYS} the moment
 * the animation loses them, so the reload sweeps them). Ending completion additionally
 * sweeps every loaded entity still carrying the siege's scope tag, a
 * {@value #WATCHDOG_TICKS}-tick watchdog force-clears a wedged siege,
 * {@link #forceClearNow} clears everything on demand (shutdown sweeps), and both
 * {@code /kill @e[tag=eclipse_storm_siege_debris]} and
 * {@code /kill @e[tag=eclipse_storm_fx]} always work.</p>
 *
 * <p><b>Graves are sacrosanct (F-086):</b> the lift sampler never tears out a grave or
 * any block within one block of a grave (no floating graves), and every re-place path
 * guards against writing over a grave cell ({@link GraveProtection}).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class StormSiege {
    /** Frozen command tag on every siege display — strays from a crash are swept on load. */
    public static final String ENTITY_TAG = "eclipse_storm_siege_debris";
    /**
     * F-084 umbrella tag on EVERY fight-spawned entity (siege debris, statue pieces,
     * statue hitboxes) — the one-tag admin escape hatch and the shared join-sweep key.
     */
    public static final String STORM_FX_TAG = "eclipse_storm_fx";
    /**
     * F-084 per-fight scope tag prefix; a siege stamps
     * {@code eclipse_fight_storm_<stormId>} (storm ids are stable per site), the statue
     * stamps {@code eclipse_fight_lair_<x>_<y>_<z>} — targeted sweeps key off these.
     */
    public static final String FIGHT_SCOPE_TAG_PREFIX = "eclipse_fight_";

    // ------------------------------------------------------------------ tuning constants
    /** Fight detection poll cadence (entity scan — cheap, but no need for per-tick). */
    private static final int POLL_TICKS = 20;
    /** Siege payload keepalive cadence (late joiners + lost packets; handler idempotent). */
    private static final int KEEPALIVE_TICKS = 100;
    /** F-031a: the storm grows to this multiple of its wire radius during the fight. */
    private static final float RADIUS_SCALE = 1.3F;
    /** F-031a: growth ramp length (~5 s; the client eases both ways on this clock). */
    private static final int GROW_TICKS = 100;

    /** F-031c whirl debris count band (rolled once per siege) — FX-Wave-12 gigantism. */
    private static final int DEBRIS_MIN = 350;
    private static final int DEBRIS_MAX = 500;
    /** Staggered debris spawn: batch size / cadence (spawn-cost smoothing). */
    private static final int SPAWN_BATCH = 10;
    private static final int SPAWN_STAGGER_TICKS = 2;
    /** Transform push cadence == interpolation duration (DisplayAnimator law). */
    private static final int UPDATE_INTERVAL_TICKS = 3;
    /**
     * FX-Wave-12: THREE discrete orbit radius bands (near / mid / far) instead of one
     * continuous 6–22 spread. Discrete bands are what buys parallax — a continuous
     * spread averages out into one soft cloud, three shells read as a near wall, a mid
     * body and a far silhouette sliding past each other at visibly different rates.
     */
    private static final double[] ORBIT_BAND_MIN = {6.0D, 12.0D, 24.0D};
    private static final double[] ORBIT_BAND_MAX = {12.0D, 24.0D, 38.0D};
    /** Cumulative share of the swarm per band (near-heavy: the fight is in the middle). */
    private static final double[] ORBIT_BAND_SHARE = {0.34D, 0.72D, 1.0D};
    private static final double ORBIT_MIN_Y = 0.8D;
    /**
     * FX-Wave-12: the funnel ceiling is no longer a flat 14 — it is derived from the
     * storm's own wire height (a sphere dome carries height == radius), so the debris
     * towers all the way up the INTERIOR WALL of whatever dome the fight stands in.
     */
    private static final double ORBIT_MAX_Y_FACTOR = 0.85D;
    /** Floor under the derived ceiling — a tiny storm still gets the old funnel height. */
    private static final double ORBIT_MAX_Y_FLOOR = 14.0D;
    /** Shared tangential speed the per-piece angular rate derives from (blocks/tick). */
    private static final double TANGENTIAL_BLOCKS_PER_TICK = 0.42D;
    /**
     * Sediment law (the {@code DayRiftOrbits.paramsFor} pattern): band height and angular
     * speed are DERIVED from the piece scale instead of rolled next to it — heavy slabs
     * grind low and slow along the floor of the funnel, light shards ride high and whip.
     * Reading the funnel bottom-up therefore reads it heaviest-first, which is what makes
     * the whirl look SORTED instead of sprinkled; the jitters keep it off the stairs.
     */
    private static final double SPEED_LIGHT_FACTOR = 1.4D;
    private static final double SPEED_HEAVY_FACTOR = 0.6D;
    private static final double SPEED_JITTER = 0.08D;
    private static final double BAND_Y_JITTER = 2.0D;
    /** Piece size spread + tumble band (degrees/tick). */
    private static final float MIN_SCALE = 0.35F;
    private static final float MAX_SCALE = 1.15F;
    /** Roughly one piece in this many is a KEYSTONE slab, pinned lowest and slowest. */
    private static final int KEYSTONE_EVERY = 12;
    /** Keystone size as a multiple of {@value #MAX_SCALE} (≈2.76 blocks of raw slab). */
    private static final float KEYSTONE_SCALE_FACTOR = 2.4F;
    private static final double SPIN_MIN_DEG = 1.0D;
    private static final double SPIN_MAX_DEG = 4.5D;
    /** Slow radial in/out breathing of an orbit (the StormDebrisFx wobble idiom). */
    private static final double RADIUS_WOBBLE = 2.6D;
    private static final double RADIUS_WOBBLE_MIN_PERIOD = 90.0D;
    private static final double RADIUS_WOBBLE_MAX_PERIOD = 240.0D;
    /**
     * Slow inward-spiral GUST: a raised cosine (never negative) that sucks a piece toward
     * the eye and lets it back out, so the funnel breathes in as well as around.
     */
    private static final double GUST_INWARD_BLOCKS = 4.5D;
    private static final double GUST_MIN_PERIOD = 200.0D;
    private static final double GUST_MAX_PERIOD = 420.0D;
    /**
     * Wobble + gust may never push a piece inside this radius: the near band starts at
     * 6 and the gust pulls up to {@value #GUST_INWARD_BLOCKS} blocks in, so without this
     * floor the funnel would breathe straight through the tyrant's melee space.
     */
    private static final double ORBIT_HARD_MIN_R = 5.0D;
    /** Spawn ease-in: a piece fades up and drifts in over this window instead of popping. */
    private static final int SPAWN_EASE_TICKS = 24;
    /** Extra radius a piece eases IN from while it fades up. */
    private static final double SPAWN_EASE_RADIUS_OUT = 6.0D;
    /**
     * PERF (the {@code EndArrivalDebrisFx.tickMsptGuard} port): this whirl runs DURING a
     * boss fight, so it must be the first thing to yield. Over {@value
     * #MSPT_DEGRADE_NANOS} ns average tick time the siege stops spawning debris and
     * halves its push cadence; it recovers below {@value #MSPT_RECOVER_NANOS} ns
     * (hysteresis). Degraded means slower interpolation windows, never a cut show.
     */
    private static final long MSPT_DEGRADE_NANOS = 45_000_000L;
    private static final long MSPT_RECOVER_NANOS = 38_000_000L;
    private static final int MSPT_CHECK_INTERVAL_TICKS = 20;
    /** Display range/light overrides (readable against the dark interior). */
    private static final float VIEW_RANGE = 4.0F;
    private static final int DEBRIS_BLOCK_LIGHT = 6;
    private static final int MAX_SKY_LIGHT = 15;

    // F-031d block lifts.
    /** Volley cadence band ("alle 8–15 s"). */
    private static final int LIFT_MIN_INTERVAL = 160;
    private static final int LIFT_MAX_INTERVAL = 300;
    /** Blocks torn out per volley (FX-Wave-12: the storm takes real bites out of the arena). */
    private static final int LIFT_MIN = 8;
    private static final int LIFT_MAX = 14;
    /**
     * One volley lands as this many staggered SUB-volleys: a wave of eight-plus blocks
     * ripping out on a single tick reads as a glitch, two waves read as the storm
     * inhaling twice. Also keeps the setBlock/particle cost off one tick.
     */
    private static final int LIFT_SUBVOLLEYS = 2;
    private static final int LIFT_SUBVOLLEY_STAGGER_TICKS = 18;
    /** Ground ring the volley samples (blocks from the combat center). */
    private static final double LIFT_RING_MIN = 5.0D;
    private static final double LIFT_RING_MAX = 15.0D;
    /** Lift phases: rise off the ground → menacing hover → fling at a player. */
    private static final int RISE_TICKS = 25;
    private static final int HOVER_TICKS = 14;
    private static final int FLING_TICKS = 13;
    /** Hover height above the torn-out socket. */
    private static final double RISE_HEIGHT_MIN = 5.0D;
    private static final double RISE_HEIGHT_MAX = 8.0D;
    /** Impact: players inside this radius of the landing point take the hit. */
    private static final double IMPACT_RADIUS = 2.5D;
    private static final float DAMAGE_MIN = 2.0F;
    private static final float DAMAGE_MAX = 4.0F;
    /** Players this close to the combat center are lift targets / message recipients. */
    private static final double ARENA_PLAYER_RANGE = 28.0D;

    // Endings.
    /** F-033 stage 3: victory flings the whirl debris radially outward over this window. */
    private static final int FLING_OUT_TICKS = 40;
    /** Abandon: debris sinks to the ground and scales out over this window. */
    private static final int SINK_TICKS = 20;
    /** Tyrant dead but the storm has not exploded yet (death cinematic): wait this long. */
    private static final int VICTORY_GRACE_TICKS = 200;
    /** Wedged-siege watchdog (30 min) — the StormDebrisFx doctrine. */
    private static final int WATCHDOG_TICKS = 36000;

    /** Torn-arena palette (deliberately ground-flavored — this IS the arena floor). */
    private static final BlockState[] PALETTE = {
            Blocks.STONE.defaultBlockState(),
            Blocks.COBBLESTONE.defaultBlockState(),
            Blocks.ANDESITE.defaultBlockState(),
            Blocks.TUFF.defaultBlockState(),
            Blocks.DEEPSLATE.defaultBlockState(),
            Blocks.COBBLED_DEEPSLATE.defaultBlockState(),
            Blocks.DIRT.defaultBlockState(),
            Blocks.COARSE_DIRT.defaultBlockState(),
            Blocks.GRAVEL.defaultBlockState(),
            Blocks.MOSSY_COBBLESTONE.defaultBlockState()};

    /** Live sieges by storm id (tiny map; one fight per site in practice). */
    private static final Map<Integer, Siege> SIEGES = new ConcurrentHashMap<>();
    /** UUIDs of displays spawned THIS session; tagged joiners outside it are crash strays. */
    private static final Set<UUID> LIVE_DISPLAYS = Collections.synchronizedSet(new HashSet<>());
    private static int pollCountdown = POLL_TICKS;

    private StormSiege() {}

    // ------------------------------------------------------------------ lifecycle events

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (--pollCountdown <= 0) {
            pollCountdown = POLL_TICKS;
            detectFights(event);
        }
        if (SIEGES.isEmpty()) {
            return;
        }
        for (Siege siege : SIEGES.values()) {
            siege.tick();
            if (siege.done) {
                SIEGES.remove(siege.stormId);
            }
        }
    }

    /**
     * StormDebrisFx sweep doctrine, extended for F-084: ANY entity carrying a storm-fx
     * tag (siege debris, statue displays, statue {@code Interaction} hitboxes) that
     * joins without being tracked by a live owner is a stray — a crash leftover after a
     * restart (the live sets are empty then) or a mid-session chunk-reload orphan (the
     * animation pruned its UUID from {@code LIVE_DISPLAYS} when the chunk unloaded).
     */
    @SubscribeEvent
    static void onEntityJoin(EntityJoinLevelEvent event) {
        Entity entity = event.getEntity();
        if (event.getLevel().isClientSide()
                || (!entity.getTags().contains(ENTITY_TAG)
                        && !entity.getTags().contains(STORM_FX_TAG))) {
            return;
        }
        if (!LIVE_DISPLAYS.contains(entity.getUUID())
                && !TyrantStatue.isLivePiece(entity.getUUID())) {
            entity.discard();
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        // In-memory only: pieces that made it to disk are swept by the join check next
        // boot (they can never be adopted, since LIVE_DISPLAYS clears here). Lifted-block
        // originals are already out of the world at this point — acceptable loss on a
        // hard stop, identical to any mid-explosion crash.
        SIEGES.clear();
        LIVE_DISPLAYS.clear();
        pollCountdown = POLL_TICKS;
    }

    /**
     * F-080 shutdown sweep hook + the F-084 on-demand clear (one public "clear all
     * siege displays NOW" entry point — {@code EclipseShutdownSweep} calls it on
     * {@code ServerStoppingEvent}, before the final save and level close): every live
     * siege eases its client overlay off, restores its airborne lifts into their
     * still-free sockets (drop as items otherwise; grave cells are never overwritten)
     * and discards every display through the existing fight-end cleanup path,
     * including the scope-tag sweep for loaded pieces that fell out of the tracking
     * lists. Idempotent; safe with no siege running. Returns the display count
     * dropped; the {@code ServerStoppedEvent} handler stays as the idempotent
     * bookkeeping reset.
     */
    public static int forceClearNow() {
        int discarded = 0;
        for (Siege siege : SIEGES.values()) {
            for (int i = 0; i < siege.whirl.size(); i++) {
                if (siege.whirl.get(i).display != null) {
                    discarded++;
                }
            }
            discarded += siege.lifts.size();
            siege.broadcastSiege(false);
            siege.resolveLifts(true);
            siege.discardAll();
            siege.done = true;
        }
        SIEGES.clear();
        return discarded;
    }

    // ------------------------------------------------------------------ detection

    /**
     * A living tyrant inside an ACTIVE sphere storm's footprint = fight running. The scan
     * is bounded: per sphere storm one entity query over its footprint, every
     * {@value #POLL_TICKS} ticks, only in dimensions that HAVE storms.
     */
    private static void detectFights(ServerTickEvent.Post event) {
        for (ServerLevel level : event.getServer().getAllLevels()) {
            List<StormRegistry.StormData> storms = StormRegistry.storms(level);
            for (int i = 0; i < storms.size(); i++) {
                StormRegistry.StormData storm = storms.get(i);
                if (storm.stormType() != S2CStormStatePayload.TYPE_SPHERE
                        || storm.state() != S2CStormStatePayload.STATE_ACTIVE
                        || SIEGES.containsKey(storm.stormId())) {
                    continue;
                }
                FogTyrantEntity tyrant = findTyrant(level, storm.center(), storm.radius());
                if (tyrant != null) {
                    Siege siege = new Siege(level, storm.stormId(), storm.center(),
                            storm.radius(), storm.height(), tyrant.position());
                    SIEGES.put(storm.stormId(), siege);
                    siege.begin();
                }
            }
        }
    }

    @Nullable
    private static FogTyrantEntity findTyrant(ServerLevel level, Vec3 center, float radius) {
        AABB box = AABB.ofSize(center.add(0.0D, radius * 0.5D, 0.0D),
                radius * 2.0D, radius * 2.0D, radius * 2.0D);
        List<FogTyrantEntity> found =
                level.getEntitiesOfClass(FogTyrantEntity.class, box, Entity::isAlive);
        return found.isEmpty() ? null : found.get(0);
    }

    // ------------------------------------------------------------------ the siege

    private static final class Siege {
        final ServerLevel level;
        final int stormId;
        final Vec3 stormCenter;
        final float stormRadius;
        /**
         * Funnel ceiling for this fight: {@value #ORBIT_MAX_Y_FACTOR} × the storm's wire
         * height (floored at {@value #ORBIT_MAX_Y_FLOOR}) — the debris tower height.
         */
        final double orbitMaxY;
        /** Combat ring center — the tyrant's position at detection (he self-pins there). */
        final Vec3 combatCenter;
        /** The one fixed entity position every display mounts at (StormDebrisFx law). */
        final Vec3 mount;
        /** F-084 per-fight scope tag on every display this siege spawns. */
        final String scopeTag;
        final RandomSource random;
        final int debrisTarget;
        final List<WhirlPiece> whirl = new ArrayList<>(DEBRIS_MAX);
        final List<LiftedBlock> lifts = new ArrayList<>(LIFT_MAX * 2);

        int age;
        int spawned;
        int keepaliveCountdown = KEEPALIVE_TICKS;
        int nextLiftAge;
        /** Age the tyrant was last seen ALIVE (grace clock for the death cinematic). */
        int tyrantSeenAge;
        /** Ending mode: 0 = running, 1 = victory fling, 2 = abandon sink. */
        int ending;
        int endingStart;
        boolean done;
        /** True while the MSPT guard has the siege degraded (no spawns, half cadence). */
        boolean degraded;
        /** Age the pending lift sub-volley fires at, or −1 when none is queued. */
        int subVolleyAge = -1;
        int subVolleyCount;

        Siege(ServerLevel level, int stormId, Vec3 stormCenter, float stormRadius,
                float stormHeight, Vec3 tyrantPos) {
            this.level = level;
            this.stormId = stormId;
            this.stormCenter = stormCenter;
            this.stormRadius = stormRadius;
            this.orbitMaxY = Math.max(ORBIT_MAX_Y_FLOOR, stormHeight * ORBIT_MAX_Y_FACTOR);
            this.combatCenter = tyrantPos;
            this.mount = new Vec3(tyrantPos.x, tyrantPos.y + 8.0D, tyrantPos.z);
            this.scopeTag = FIGHT_SCOPE_TAG_PREFIX + "storm_" + stormId;
            this.random = RandomSource.create(level.getGameTime() * 17L + stormId);
            this.debrisTarget = DEBRIS_MIN + this.random.nextInt(DEBRIS_MAX - DEBRIS_MIN + 1);
            this.nextLiftAge = rollLiftInterval() / 2; // first volley lands early-ish
        }

        void begin() {
            broadcastSiege(true);
            messageArena("eclipse.storm.siege.begin");
            this.level.playSound(null, BlockPos.containing(this.combatCenter),
                    EclipseSounds.EVENT_STORM_SPHERE_ROAR.get(), SoundSource.HOSTILE, 1.2F, 0.8F);
            EclipseMod.LOGGER.info("StormSiege: fight detected inside storm {} — siege up "
                    + "(radius ×{} over {}t, {} whirl displays up to y+{}, lift volleys "
                    + "every {}–{}t in {} sub-volleys)",
                    this.stormId, RADIUS_SCALE, GROW_TICKS, this.debrisTarget,
                    String.format(java.util.Locale.ROOT, "%.1f", this.orbitMaxY),
                    LIFT_MIN_INTERVAL, LIFT_MAX_INTERVAL, LIFT_SUBVOLLEYS);
        }

        void tick() {
            this.age++;
            if (this.ending != 0) {
                tickEnding();
                return;
            }
            if (this.age > WATCHDOG_TICKS) {
                EclipseMod.LOGGER.warn("StormSiege: siege on storm {} outlived its watchdog "
                        + "({} ticks) — force-abandoning", this.stormId, WATCHDOG_TICKS);
                beginEnding(2);
                return;
            }
            if (--this.keepaliveCountdown <= 0) {
                this.keepaliveCountdown = KEEPALIVE_TICKS;
                broadcastSiege(true);
            }
            checkFightState();
            if (this.ending != 0) {
                return;
            }
            tickMsptGuard();
            if (this.spawned < this.debrisTarget && !this.degraded
                    && this.age % SPAWN_STAGGER_TICKS == 0) {
                spawnBatch();
            }
            animateWhirl();
            if (this.subVolleyAge >= 0 && this.age >= this.subVolleyAge) {
                int pending = this.subVolleyCount;
                this.subVolleyAge = -1;
                this.subVolleyCount = 0;
                tearBlocks(pending);
            }
            if (this.age >= this.nextLiftAge && this.lifts.isEmpty() && this.subVolleyAge < 0) {
                this.nextLiftAge = this.age + rollLiftInterval();
                liftVolley();
            }
            tickLifts();
        }

        /**
         * The {@code EndArrivalDebrisFx.tickMsptGuard} lever, ported verbatim: over
         * {@value #MSPT_DEGRADE_NANOS} ns average tick time the siege pauses debris
         * spawns and halves its push cadence; it recovers below {@value
         * #MSPT_RECOVER_NANOS} ns (hysteresis). Lifts and endings are untouched — the
         * fight never loses its readable hazards, only the whirl's packet rate.
         */
        private void tickMsptGuard() {
            if (this.age % MSPT_CHECK_INTERVAL_TICKS != 0) {
                return;
            }
            long avgNanos = this.level.getServer().getAverageTickTimeNanos();
            if (this.degraded) {
                if (avgNanos < MSPT_RECOVER_NANOS) {
                    this.degraded = false;
                    EclipseMod.LOGGER.info("StormSiege: MSPT recovered ({} ms) — full cadence",
                            avgNanos / 1_000_000L);
                }
            } else if (avgNanos > MSPT_DEGRADE_NANOS) {
                this.degraded = true;
                EclipseMod.LOGGER.info("StormSiege: MSPT guard tripped ({} ms > 45 ms) — "
                        + "whirl spawns paused, pushes halved", avgNanos / 1_000_000L);
            }
        }

        /** Live push cadence: doubled (halved rate) while the MSPT guard is degraded. */
        private int pushInterval() {
            return this.degraded ? UPDATE_INTERVAL_TICKS * 2 : UPDATE_INTERVAL_TICKS;
        }

        /** Victory / abandon detection (every {@value #POLL_TICKS} ticks, off the age clock). */
        private void checkFightState() {
            StormRegistry.StormData storm = StormRegistry.get(this.stormId);
            if (storm != null && storm.state() == S2CStormStatePayload.STATE_EXPLODE) {
                // The tyrant death thunderclap burst the storm — victory.
                beginEnding(1);
                return;
            }
            if (storm == null || storm.state() == S2CStormStatePayload.STATE_DISSIPATE) {
                beginEnding(2); // storm retired under the fight (external dissipate)
                return;
            }
            if (this.age % POLL_TICKS != 0) {
                return;
            }
            FogTyrantEntity tyrant = findTyrant(this.level, this.stormCenter, this.stormRadius);
            if (tyrant != null) {
                this.tyrantSeenAge = this.age;
                return;
            }
            // No LIVING tyrant. Either he is mid-death-cinematic (the EXPLODE lands within
            // the grace window) or he reset/despawned (abandon).
            boolean corpsePresent = !this.level.getEntitiesOfClass(FogTyrantEntity.class,
                    AABB.ofSize(this.stormCenter.add(0.0D, this.stormRadius * 0.5D, 0.0D),
                            this.stormRadius * 2.0D, this.stormRadius * 2.0D,
                            this.stormRadius * 2.0D)).isEmpty();
            if (!corpsePresent && this.age - this.tyrantSeenAge > POLL_TICKS) {
                beginEnding(2); // gone without a corpse — the Herald wipe/reset
            } else if (this.age - this.tyrantSeenAge > VICTORY_GRACE_TICKS) {
                beginEnding(2); // death cinematic never produced the burst — fail safe
            }
        }

        // --- endings ---

        private void beginEnding(int mode) {
            this.ending = mode;
            this.endingStart = this.age;
            broadcastSiege(false);
            resolveLifts(mode == 2);
            if (mode == 2) {
                messageArena("eclipse.storm.siege.calm");
            }
            // First keyframe of the ending pose for EVERY piece at once (turn = one gesture).
            for (int i = 0; i < this.whirl.size(); i++) {
                pushPose(this.whirl.get(i), this.age + pushInterval());
            }
            EclipseMod.LOGGER.info("StormSiege: siege on storm {} ending ({}) — {} whirl "
                    + "display(s) {}, {} lift(s) resolved", this.stormId,
                    mode == 1 ? "victory" : "abandon", this.whirl.size(),
                    mode == 1 ? "flinging radially outward" : "sinking out", this.lifts.size());
        }

        private void tickEnding() {
            int window = this.ending == 1 ? FLING_OUT_TICKS : SINK_TICKS;
            if (this.age - this.endingStart > window) {
                discardAll();
                this.done = true;
                return;
            }
            animateWhirl();
        }

        // --- client overlay + messaging ---

        private void broadcastSiege(boolean active) {
            PacketDistributor.sendToPlayersInDimension(this.level,
                    new S2CStormSiegePayload(this.stormId, active, GROW_TICKS, RADIUS_SCALE));
        }

        private void messageArena(String langKey) {
            List<ServerPlayer> players = arenaPlayers();
            for (int i = 0; i < players.size(); i++) {
                players.get(i).displayClientMessage(Component.translatable(langKey), true);
            }
        }

        private List<ServerPlayer> arenaPlayers() {
            List<ServerPlayer> players = new ArrayList<>(4);
            for (ServerPlayer player : this.level.players()) {
                if (!player.isSpectator() && player.isAlive()
                        && player.position().distanceTo(this.combatCenter) <= ARENA_PLAYER_RANGE) {
                    players.add(player);
                }
            }
            return players;
        }

        // --- whirl debris (F-031c) ---

        private void spawnBatch() {
            int batch = Math.min(SPAWN_BATCH, this.debrisTarget - this.spawned);
            for (int i = 0; i < batch; i++) {
                WhirlPiece piece = buildWhirl();
                Display.BlockDisplay display = spawnDisplay(piece.state, poseFor(piece, this.age));
                if (display == null) {
                    return; // chunk not ready — retry next batch
                }
                piece.display = display;
                this.whirl.add(piece);
                this.spawned++;
            }
        }

        /**
         * FX-Wave-12 whirl piece: one of three discrete radius bands, then the
         * {@code DayRiftOrbits.paramsFor} sediment law — the SIZE is rolled first and the
         * band height plus the angular rate are derived from it (heavy = low + slow,
         * light = high + fast), with ~1 piece in {@value #KEYSTONE_EVERY} promoted to a
         * {@value #KEYSTONE_SCALE_FACTOR}× keystone slab pinned lowest and slowest.
         */
        private WhirlPiece buildWhirl() {
            int band = bandFor(this.random.nextDouble());
            double orbitR = ORBIT_BAND_MIN[band]
                    + this.random.nextDouble() * (ORBIT_BAND_MAX[band] - ORBIT_BAND_MIN[band]);
            boolean keystone = this.random.nextInt(KEYSTONE_EVERY) == 0;
            float scale = keystone ? MAX_SCALE * KEYSTONE_SCALE_FACTOR
                    : MIN_SCALE + (MAX_SCALE - MIN_SCALE)
                            * (float) Math.pow(this.random.nextDouble(), 1.5D);
            // 0 = the lightest shard, 1 = the heaviest slab (a keystone clamps in at 1).
            double mass = Mth.clamp((scale - MIN_SCALE) / (double) (MAX_SCALE - MIN_SCALE),
                    0.0D, 1.0D);
            double bandJitter = keystone ? 0.0D
                    : (this.random.nextDouble() * 2.0D - 1.0D) * BAND_Y_JITTER;
            double bandY = Mth.clamp(
                    ORBIT_MIN_Y + (1.0D - mass) * (this.orbitMaxY - ORBIT_MIN_Y) + bandJitter,
                    ORBIT_MIN_Y, this.orbitMaxY);
            double speedFactor = Mth.clamp(
                    SPEED_LIGHT_FACTOR - mass * (SPEED_LIGHT_FACTOR - SPEED_HEAVY_FACTOR)
                            + (keystone ? 0.0D
                                    : (this.random.nextDouble() * 2.0D - 1.0D) * SPEED_JITTER),
                    SPEED_HEAVY_FACTOR, SPEED_LIGHT_FACTOR);
            Vector3f spinAxis = new Vector3f(this.random.nextFloat() - 0.5F,
                    this.random.nextFloat() - 0.5F, this.random.nextFloat() - 0.5F);
            if (spinAxis.lengthSquared() < 1.0E-4F) {
                spinAxis.set(0.0F, 1.0F, 0.0F);
            }
            spinAxis.normalize();
            return new WhirlPiece(
                    PALETTE[this.random.nextInt(PALETTE.length)],
                    scale,
                    this.random.nextDouble() * Math.PI * 2.0D,
                    (TANGENTIAL_BLOCKS_PER_TICK * speedFactor) / Math.max(1.0D, orbitR),
                    orbitR,
                    bandY,
                    2.0D + this.random.nextDouble() * 3.0D,
                    60.0D + this.random.nextDouble() * 160.0D,
                    this.random.nextDouble() * Math.PI * 2.0D,
                    RADIUS_WOBBLE_MIN_PERIOD + this.random.nextDouble()
                            * (RADIUS_WOBBLE_MAX_PERIOD - RADIUS_WOBBLE_MIN_PERIOD),
                    this.random.nextDouble() * Math.PI * 2.0D,
                    GUST_MIN_PERIOD
                            + this.random.nextDouble() * (GUST_MAX_PERIOD - GUST_MIN_PERIOD),
                    this.random.nextDouble() * Math.PI * 2.0D,
                    spinAxis,
                    (float) Math.toRadians(SPIN_MIN_DEG
                            + this.random.nextDouble() * (SPIN_MAX_DEG - SPIN_MIN_DEG))
                            * (this.random.nextBoolean() ? 1.0F : -1.0F),
                    // Slices are assigned over the DOUBLED window so the degraded 6 t
                    // cadence still spreads evenly; full cadence folds it back mod 3.
                    this.whirl.size() % (UPDATE_INTERVAL_TICKS * 2),
                    this.age);
        }

        /** Picks a discrete radius band from a 0..1 roll against the cumulative shares. */
        private static int bandFor(double roll) {
            for (int band = 0; band < ORBIT_BAND_SHARE.length - 1; band++) {
                if (roll < ORBIT_BAND_SHARE[band]) {
                    return band;
                }
            }
            return ORBIT_BAND_SHARE.length - 1;
        }

        /**
         * One interpolated push per piece in this tick's slice (keyframe LEAD,
         * phase-sliced). Under the MSPT guard the window doubles to 6 t — half the
         * packets, same choreography, because the poses are pure functions of {@code t}.
         */
        private void animateWhirl() {
            int interval = pushInterval();
            int slice = this.age % interval;
            boolean missing = false;
            for (int i = 0; i < this.whirl.size(); i++) {
                WhirlPiece piece = this.whirl.get(i);
                boolean pushNow = this.degraded
                        ? piece.pushPhase == slice
                        : piece.pushPhase % UPDATE_INTERVAL_TICKS == slice;
                if (!pushNow) {
                    continue;
                }
                if (piece.display == null || piece.display.isRemoved()) {
                    missing = true;
                    continue;
                }
                pushPose(piece, this.age + interval);
            }
            if (missing) {
                this.whirl.removeIf(piece -> {
                    if (piece.display == null) {
                        return true;
                    }
                    if (piece.display.isRemoved()) {
                        // F-084 (gap G-2): an isRemoved() display here was UNLOADED to
                        // its chunk (or externally killed), not discarded by us — forget
                        // its UUID so the join sweep reclaims the persisted entity the
                        // moment its chunk reloads, instead of adopting a frozen ghost.
                        LIVE_DISPLAYS.remove(piece.display.getUUID());
                        return true;
                    }
                    return false;
                });
            }
        }

        private void pushPose(WhirlPiece piece, int t) {
            Display.BlockDisplay display = piece.display;
            if (display == null || display.isRemoved()) {
                return;
            }
            display.setTransformationInterpolationDelay(0);
            // Push-cadence law: the interpolation duration IS the push interval.
            display.setTransformationInterpolationDuration(pushInterval());
            display.setTransformation(poseFor(piece, t));
        }

        /**
         * Absolute pose of one whirl piece at siege age {@code t} (pure function of t).
         *
         * <p>FX-Wave-12 adds three terms on top of the base orbit: a slow radial WOBBLE
         * (the StormDebrisFx idiom), a slow inward-spiral GUST (a raised cosine, so it
         * only ever pulls toward the eye and releases) and a spawn EASE — the piece fades
         * up from zero scale while it drifts in from {@value #SPAWN_EASE_RADIUS_OUT}
         * blocks further out, so nothing ever pops into the funnel.</p>
         */
        private Transformation poseFor(WhirlPiece piece, int t) {
            double life = t - piece.bornAge;
            double ease = Mth.clamp(life / (double) SPAWN_EASE_TICKS, 0.0D, 1.0D);
            ease = ease * ease * (3.0D - 2.0D * ease); // smoothstep
            double angle = piece.angle0 + piece.angularSpeed * life;
            double gust = GUST_INWARD_BLOCKS * 0.5D * (1.0D
                    - Math.cos((Math.PI * 2.0D / piece.gustPeriod) * life + piece.gustPhase));
            double orbitR = Math.max(ORBIT_HARD_MIN_R, piece.radius
                    + Math.sin((Math.PI * 2.0D / piece.radiusWobblePeriod) * life
                            + piece.radiusWobblePhase) * RADIUS_WOBBLE
                    - gust
                    + (1.0D - ease) * SPAWN_EASE_RADIUS_OUT);
            double py = this.combatCenter.y + piece.bandY
                    + Math.sin((Math.PI * 2.0D / piece.bobPeriod) * life + piece.bobPhase)
                            * piece.bobAmplitude;
            double px = this.combatCenter.x + Math.cos(angle) * orbitR;
            double pz = this.combatCenter.z + Math.sin(angle) * orbitR;
            float scale = (float) (piece.scale * ease);

            if (this.ending == 1) {
                // F-033 stage 3 — victory: radially OUTWARD from the storm center, rising
                // slightly, scaling to zero as the shockwave carries the arena apart.
                float raw = Mth.clamp((t - this.endingStart) / (float) FLING_OUT_TICKS, 0.0F, 1.0F);
                float eased = 1.0F - (1.0F - raw) * (1.0F - raw); // ease-out throw
                double out = orbitR + eased * (this.stormRadius * 1.6D + 20.0D);
                px = this.combatCenter.x + Math.cos(angle) * out;
                pz = this.combatCenter.z + Math.sin(angle) * out;
                py += eased * 6.0D * (1.0D - raw);
                scale *= 1.0F - eased;
            } else if (this.ending == 2) {
                // Abandon: the wind lets go — pieces sink to the ground and shrink out.
                float raw = Mth.clamp((t - this.endingStart) / (float) SINK_TICKS, 0.0F, 1.0F);
                float eased = raw * raw;
                py = Mth.lerp(eased, py, this.combatCenter.y + 0.3D);
                scale *= 1.0F - raw;
            }

            float spinAngle = piece.spinRate * (float) life;
            Quaternionf rotation = new Quaternionf().rotationAxis(spinAngle, piece.spinAxis);
            Vector3f translation = new Vector3f(
                    (float) (px - this.mount.x),
                    (float) (py - this.mount.y),
                    (float) (pz - this.mount.z));
            Vector3f half = new Vector3f(scale * 0.5F, scale * 0.5F, scale * 0.5F);
            translation.sub(rotation.transform(half, new Vector3f()));
            return new Transformation(translation, rotation,
                    new Vector3f(scale, scale, scale), new Quaternionf());
        }

        // --- block lifts (F-031d) ---

        private int rollLiftInterval() {
            return LIFT_MIN_INTERVAL
                    + this.random.nextInt(LIFT_MAX_INTERVAL - LIFT_MIN_INTERVAL + 1);
        }

        /**
         * Rolls one volley of {@value #LIFT_MIN}–{@value #LIFT_MAX} real surface blocks
         * and splits it into {@value #LIFT_SUBVOLLEYS} waves: the first tears out now,
         * the rest is queued {@value #LIFT_SUBVOLLEY_STAGGER_TICKS} ticks later (the
         * "never dump everything in one tick" law, applied to world edits too).
         */
        private void liftVolley() {
            int want = LIFT_MIN + this.random.nextInt(LIFT_MAX - LIFT_MIN + 1);
            int first = Math.max(1, want / LIFT_SUBVOLLEYS);
            this.subVolleyCount = want - first;
            this.subVolleyAge = this.subVolleyCount > 0
                    ? this.age + LIFT_SUBVOLLEY_STAGGER_TICKS : -1;
            tearBlocks(first);
        }

        /** Tears {@code want} real surface blocks out of the ring (one sub-volley). */
        private void tearBlocks(int want) {
            if (want <= 0) {
                return;
            }
            int lifted = 0;
            for (int attempt = 0; attempt < want * 6 && lifted < want; attempt++) {
                BlockPos pos = sampleRingGround();
                if (pos == null || !liftable(pos)) {
                    continue;
                }
                BlockState state = this.level.getBlockState(pos);
                Display.BlockDisplay display = spawnDisplay(state,
                        liftPoseAt(Vec3.atLowerCornerOf(pos), 1.0F, 0.0F));
                if (display == null) {
                    continue;
                }
                this.level.setBlock(pos, Blocks.AIR.defaultBlockState(), 3);
                this.level.playSound(null, pos, state.getSoundType().getBreakSound(),
                        SoundSource.HOSTILE, 0.9F, 0.7F + this.random.nextFloat() * 0.2F);
                this.level.sendParticles(new BlockParticleOption(ParticleTypes.BLOCK, state),
                        pos.getX() + 0.5D, pos.getY() + 0.8D, pos.getZ() + 0.5D,
                        12, 0.35D, 0.3D, 0.35D, 0.1D);
                LiftedBlock lift = new LiftedBlock(state, pos.immutable(), display, this.age,
                        RISE_HEIGHT_MIN
                                + this.random.nextDouble() * (RISE_HEIGHT_MAX - RISE_HEIGHT_MIN),
                        this.random.nextDouble() * Math.PI * 2.0D);
                this.lifts.add(lift);
                lifted++;
            }
            if (lifted > 0) {
                messageArena("eclipse.storm.siege.lift");
                this.level.playSound(null, BlockPos.containing(this.combatCenter),
                        EclipseSounds.EVENT_RIFT_WHOOSH.get(), SoundSource.HOSTILE,
                        0.9F, 0.55F + this.random.nextFloat() * 0.2F);
            }
        }

        @Nullable
        private BlockPos sampleRingGround() {
            double angle = this.random.nextDouble() * Math.PI * 2.0D;
            double reach = LIFT_RING_MIN
                    + this.random.nextDouble() * (LIFT_RING_MAX - LIFT_RING_MIN);
            int x = Mth.floor(this.combatCenter.x + Math.cos(angle) * reach);
            int z = Mth.floor(this.combatCenter.z + Math.sin(angle) * reach);
            if (!this.level.isLoaded(new BlockPos(x, (int) this.combatCenter.y, z))) {
                return null;
            }
            int y = this.level.getHeight(Heightmap.Types.WORLD_SURFACE, x, z) - 1;
            // Stay near the arena floor: a lift from a treetop or a cave lip reads wrong.
            if (Math.abs(y - this.combatCenter.y) > 6.0D) {
                return null;
            }
            return new BlockPos(x, y, z);
        }

        /**
         * Simple full-cube world blocks only — no BEs, no unbreakables, no fluids, and
         * (F-086) never a grave nor any block within one block of a grave: the BE check
         * already excludes the grave itself, the {@code nearGrave} ring keeps the storm
         * from sucking the ground out from under one (no floating graves).
         */
        private boolean liftable(BlockPos pos) {
            BlockState state = this.level.getBlockState(pos);
            return !state.isAir()
                    && state.getDestroySpeed(this.level, pos) >= 0.0F
                    && this.level.getBlockEntity(pos) == null
                    && state.getFluidState().isEmpty()
                    && state.isCollisionShapeFullBlock(this.level, pos)
                    && !GraveProtection.isGraveAt(this.level, pos)
                    && !GraveProtection.nearGrave(this.level, pos, 1);
        }

        private void tickLifts() {
            for (int i = this.lifts.size() - 1; i >= 0; i--) {
                LiftedBlock lift = this.lifts.get(i);
                if (lift.display.isRemoved()) {
                    // F-084 (gap G-2): unloaded/killed mid-flight — forget the UUID (the
                    // join sweep reclaims the persisted display on chunk reload) and
                    // drop the torn-out REAL block at its socket so it is never lost.
                    LIVE_DISPLAYS.remove(lift.display.getUUID());
                    dropAsItem(lift.state, Vec3.atCenterOf(lift.origin).add(0.0D, 1.0D, 0.0D));
                    this.lifts.remove(i);
                    continue;
                }
                if (!tickLift(lift)) {
                    this.lifts.remove(i);
                }
            }
        }

        /** @return {@code false} once the lift resolved (impact / no target) and was removed. */
        private boolean tickLift(LiftedBlock lift) {
            int life = this.age - lift.bornAge;
            if (life <= RISE_TICKS + HOVER_TICKS) {
                // RISE + HOVER: eased climb out of the socket, then a menacing wobble.
                float rise = Mth.clamp(life / (float) RISE_TICKS, 0.0F, 1.0F);
                float eased = 1.0F - (1.0F - rise) * (1.0F - rise) * (1.0F - rise);
                float wobble = life > RISE_TICKS ? (life - RISE_TICKS) / (float) HOVER_TICKS : 0.0F;
                pushLiftPose(lift, liftPoseAt(hoverPos(lift, eased, wobble), 1.0F,
                        life * 0.06F));
                return true;
            }
            if (lift.target == null) {
                // FLING start: lock a random arena player. Lead the aim by half the
                // flight so a moving player still has to actually dodge.
                List<ServerPlayer> players = arenaPlayers();
                if (players.isEmpty()) {
                    resolveLift(lift, true); // nobody to throw at — just drop the block
                    return false;
                }
                ServerPlayer target = players.get(this.random.nextInt(players.size()));
                lift.target = target.position()
                        .add(target.getDeltaMovement().scale(FLING_TICKS * 0.5D))
                        .add(0.0D, 1.0D, 0.0D);
                lift.flingFrom = hoverPos(lift, 1.0F, 1.0F);
                this.level.playSound(null, BlockPos.containing(lift.flingFrom),
                        EclipseSounds.EVENT_RIFT_WHOOSH.get(), SoundSource.HOSTILE, 0.8F, 1.3F);
            }
            int flingLife = life - RISE_TICKS - HOVER_TICKS;
            if (flingLife < FLING_TICKS) {
                // Quadratic arc from hover to the locked aim point (mid raised 2 blocks).
                float t = flingLife / (float) FLING_TICKS;
                Vec3 mid = lift.flingFrom.add(lift.target).scale(0.5D).add(0.0D, 2.0D, 0.0D);
                double omt = 1.0D - t;
                Vec3 pos = lift.flingFrom.scale(omt * omt)
                        .add(mid.scale(2.0D * omt * t))
                        .add(lift.target.scale(t * t));
                pushLiftPose(lift, liftPoseAt(pos, 1.0F, life * 0.25F));
                return true;
            }
            impact(lift);
            return false;
        }

        private Vec3 hoverPos(LiftedBlock lift, float riseEased, float wobble) {
            double bobX = Math.sin(wobble * Math.PI * 3.0D + lift.wobblePhase) * 0.35D * wobble;
            double bobZ = Math.cos(wobble * Math.PI * 2.0D + lift.wobblePhase) * 0.35D * wobble;
            return new Vec3(lift.origin.getX() + 0.5D + bobX,
                    lift.origin.getY() + 0.5D + lift.riseHeight * riseEased,
                    lift.origin.getZ() + 0.5D + bobZ);
        }

        /** F-031d impact: damage + particles + re-place-or-drop, then the display dies. */
        private void impact(LiftedBlock lift) {
            Vec3 at = lift.target != null ? lift.target
                    : lift.display.position();
            float damage = DAMAGE_MIN + this.random.nextFloat() * (DAMAGE_MAX - DAMAGE_MIN);
            for (ServerPlayer player : this.level.players()) {
                if (!player.isSpectator() && player.isAlive()
                        && player.position().distanceTo(at) <= IMPACT_RADIUS + 1.0D) {
                    player.hurt(this.level.damageSources().source(DamageTypes.FALLING_BLOCK),
                            damage);
                }
            }
            this.level.sendParticles(new BlockParticleOption(ParticleTypes.BLOCK, lift.state),
                    at.x, at.y, at.z, 24, 0.5D, 0.5D, 0.5D, 0.15D);
            this.level.playSound(null, BlockPos.containing(at),
                    lift.state.getSoundType().getBreakSound(), SoundSource.HOSTILE, 1.0F, 0.9F);
            // The block either plants itself where it landed (free spot) or drops. The
            // grave guard is unreachable today (a grave never canBeReplaced()) but keeps
            // F-086 true through future refactors.
            BlockPos landing = BlockPos.containing(at);
            if (this.level.isLoaded(landing)
                    && this.level.getBlockState(landing).canBeReplaced()
                    && !GraveProtection.isGraveAt(this.level, landing)) {
                this.level.setBlockAndUpdate(landing, lift.state);
            } else {
                dropAsItem(lift.state, at);
            }
            discardDisplay(lift.display);
        }

        /**
         * Fight-end resolution of every airborne lift: victory drops the block items where
         * they fly ({@code restore=false}); abandon puts blocks BACK into their sockets
         * when still free ({@code restore=true} — the ground heals), dropping otherwise.
         */
        private void resolveLifts(boolean restore) {
            for (int i = 0; i < this.lifts.size(); i++) {
                resolveLift(this.lifts.get(i), restore);
            }
            this.lifts.clear();
        }

        /** Resolution of ONE airborne lift (same restore-or-drop law; display dies). */
        private void resolveLift(LiftedBlock lift, boolean restore) {
            if (lift.display.isRemoved()) {
                return;
            }
            if (restore && this.level.isLoaded(lift.origin)
                    && this.level.getBlockState(lift.origin).canBeReplaced()
                    && !GraveProtection.isGraveAt(this.level, lift.origin)) {
                this.level.setBlockAndUpdate(lift.origin, lift.state);
            } else {
                dropAsItem(lift.state, lift.display.position()
                        .add(0.0D, lift.riseHeight * 0.5D, 0.0D));
            }
            discardDisplay(lift.display);
        }

        private void dropAsItem(BlockState state, Vec3 at) {
            ItemStack stack = new ItemStack(state.getBlock().asItem());
            if (!stack.isEmpty()) {
                ItemEntity item = new ItemEntity(this.level, at.x, at.y, at.z, stack);
                item.setDefaultPickUpDelay();
                this.level.addFreshEntity(item);
            }
        }

        private Transformation liftPoseAt(Vec3 pos, float scale, float spin) {
            Quaternionf rotation = new Quaternionf().rotationY(spin);
            Vector3f translation = new Vector3f(
                    (float) (pos.x - this.mount.x - 0.5D),
                    (float) (pos.y - this.mount.y - 0.5D),
                    (float) (pos.z - this.mount.z - 0.5D));
            return new Transformation(translation, rotation,
                    new Vector3f(scale, scale, scale), new Quaternionf());
        }

        private void pushLiftPose(LiftedBlock lift, Transformation pose) {
            lift.display.setTransformationInterpolationDelay(0);
            lift.display.setTransformationInterpolationDuration(1);
            lift.display.setTransformation(pose);
        }

        // --- display plumbing ---

        @Nullable
        private Display.BlockDisplay spawnDisplay(BlockState state, Transformation pose) {
            BlockPos mountPos = BlockPos.containing(this.mount);
            if (!this.level.isLoaded(mountPos)) {
                return null;
            }
            Display.BlockDisplay display = EntityType.BLOCK_DISPLAY.create(this.level);
            if (display == null) {
                return null;
            }
            display.setBlockState(state);
            display.moveTo(this.mount.x, this.mount.y, this.mount.z, 0.0F, 0.0F);
            display.addTag(ENTITY_TAG);
            display.addTag(STORM_FX_TAG);
            display.addTag(this.scopeTag);
            DisplayBrightnessFx.set(display, DEBRIS_BLOCK_LIGHT, MAX_SKY_LIGHT, VIEW_RANGE);
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(0);
            display.setTransformation(pose);
            LIVE_DISPLAYS.add(display.getUUID());
            this.level.addFreshEntity(display);
            return display;
        }

        private void discardDisplay(Display.BlockDisplay display) {
            LIVE_DISPLAYS.remove(display.getUUID());
            if (!display.isRemoved()) {
                display.discard();
            }
        }

        void discardAll() {
            for (int i = 0; i < this.whirl.size(); i++) {
                Display.BlockDisplay display = this.whirl.get(i).display;
                if (display != null) {
                    discardDisplay(display);
                }
            }
            this.whirl.clear();
            resolveLifts(false);
            sweepScopedStrays();
        }

        /**
         * F-084 ending-completion sweep: discard every LOADED entity still carrying this
         * siege's scope tag (pieces that fell out of the tracking lists while loaded).
         * Bounded scan — every display mounts at the combat center, so the box around
         * the storm covers the whole fight; unloaded stragglers are reclaimed by the
         * join sweep instead (their UUIDs left {@code LIVE_DISPLAYS} at prune time).
         */
        private void sweepScopedStrays() {
            AABB box = AABB.ofSize(this.stormCenter,
                    this.stormRadius * 4.0D + 64.0D, this.stormRadius * 4.0D + 64.0D,
                    this.stormRadius * 4.0D + 64.0D);
            List<Entity> strays = this.level.getEntities((Entity) null, box,
                    entity -> entity.getTags().contains(this.scopeTag));
            for (int i = 0; i < strays.size(); i++) {
                LIVE_DISPLAYS.remove(strays.get(i).getUUID());
                strays.get(i).discard();
            }
            if (!strays.isEmpty()) {
                EclipseMod.LOGGER.info("StormSiege: ending sweep discarded {} stray scoped "
                        + "display(s) for storm {}", strays.size(), this.stormId);
            }
        }
    }

    /** One whirling debris chunk. All motion is a pure function of the siege age. */
    private static final class WhirlPiece {
        @Nullable
        Display.BlockDisplay display;
        final BlockState state;
        final float scale;
        final double angle0;
        final double angularSpeed;
        final double radius;
        final double bandY;
        final double bobAmplitude;
        final double bobPeriod;
        final double bobPhase;
        /** Slow radial breathing of the orbit (FX-Wave-12). */
        final double radiusWobblePeriod;
        final double radiusWobblePhase;
        /** Slow inward-spiral gust that sucks the piece toward the eye and releases it. */
        final double gustPeriod;
        final double gustPhase;
        final Vector3f spinAxis;
        final float spinRate;
        final int pushPhase;
        final int bornAge;

        WhirlPiece(BlockState state, float scale, double angle0, double angularSpeed,
                double radius, double bandY, double bobAmplitude, double bobPeriod,
                double bobPhase, double radiusWobblePeriod, double radiusWobblePhase,
                double gustPeriod, double gustPhase, Vector3f spinAxis, float spinRate,
                int pushPhase, int bornAge) {
            this.state = state;
            this.scale = scale;
            this.angle0 = angle0;
            this.angularSpeed = angularSpeed;
            this.radius = radius;
            this.bandY = bandY;
            this.bobAmplitude = bobAmplitude;
            this.bobPeriod = bobPeriod;
            this.bobPhase = bobPhase;
            this.radiusWobblePeriod = radiusWobblePeriod;
            this.radiusWobblePhase = radiusWobblePhase;
            this.gustPeriod = gustPeriod;
            this.gustPhase = gustPhase;
            this.spinAxis = spinAxis;
            this.spinRate = spinRate;
            this.pushPhase = pushPhase;
            this.bornAge = bornAge;
        }
    }

    /** One REAL block torn out of the arena floor, mid-flight. */
    private static final class LiftedBlock {
        final BlockState state;
        final BlockPos origin;
        final Display.BlockDisplay display;
        final int bornAge;
        final double riseHeight;
        final double wobblePhase;
        /** Locked aim point (player-led), set the tick the fling starts. */
        @Nullable
        Vec3 target;
        Vec3 flingFrom = Vec3.ZERO;

        LiftedBlock(BlockState state, BlockPos origin, Display.BlockDisplay display,
                int bornAge, double riseHeight, double wobblePhase) {
            this.state = state;
            this.origin = origin;
            this.display = display;
            this.bornAge = bornAge;
            this.riseHeight = riseHeight;
            this.wobblePhase = wobblePhase;
        }
    }
}
