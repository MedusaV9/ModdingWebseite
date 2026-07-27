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

    /** F-031c whirl debris count band (rolled once per siege). */
    private static final int DEBRIS_MIN = 80;
    private static final int DEBRIS_MAX = 150;
    /** Staggered debris spawn: batch size / cadence (spawn-cost smoothing). */
    private static final int SPAWN_BATCH = 6;
    private static final int SPAWN_STAGGER_TICKS = 2;
    /** Transform push cadence == interpolation duration (DisplayAnimator law). */
    private static final int UPDATE_INTERVAL_TICKS = 3;
    /** Whirl orbit band around the combat center (blocks) and height band. */
    private static final double ORBIT_MIN_R = 6.0D;
    private static final double ORBIT_MAX_R = 22.0D;
    private static final double ORBIT_MIN_Y = 0.8D;
    private static final double ORBIT_MAX_Y = 14.0D;
    /** Shared tangential speed the per-piece angular rate derives from (blocks/tick). */
    private static final double TANGENTIAL_BLOCKS_PER_TICK = 0.42D;
    /** Piece size spread + tumble band (degrees/tick). */
    private static final float MIN_SCALE = 0.35F;
    private static final float MAX_SCALE = 1.15F;
    private static final double SPIN_MIN_DEG = 1.0D;
    private static final double SPIN_MAX_DEG = 4.5D;
    /** Display range/light overrides (readable against the dark interior). */
    private static final float VIEW_RANGE = 4.0F;
    private static final int DEBRIS_BLOCK_LIGHT = 6;
    private static final int MAX_SKY_LIGHT = 15;

    // F-031d block lifts.
    /** Volley cadence band ("alle 8–15 s"). */
    private static final int LIFT_MIN_INTERVAL = 160;
    private static final int LIFT_MAX_INTERVAL = 300;
    /** Blocks torn out per volley ("3–6 ECHTE Blöcke"). */
    private static final int LIFT_MIN = 3;
    private static final int LIFT_MAX = 6;
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
                            storm.radius(), tyrant.position());
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

        Siege(ServerLevel level, int stormId, Vec3 stormCenter, float stormRadius, Vec3 tyrantPos) {
            this.level = level;
            this.stormId = stormId;
            this.stormCenter = stormCenter;
            this.stormRadius = stormRadius;
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
                    + "(radius ×{} over {}t, {} whirl displays, lift volleys every {}–{}t)",
                    this.stormId, RADIUS_SCALE, GROW_TICKS, this.debrisTarget,
                    LIFT_MIN_INTERVAL, LIFT_MAX_INTERVAL);
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
            if (this.spawned < this.debrisTarget && this.age % SPAWN_STAGGER_TICKS == 0) {
                spawnBatch();
            }
            animateWhirl();
            if (this.age >= this.nextLiftAge && this.lifts.isEmpty()) {
                this.nextLiftAge = this.age + rollLiftInterval();
                liftVolley();
            }
            tickLifts();
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
                pushPose(this.whirl.get(i), this.age + UPDATE_INTERVAL_TICKS);
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

        private WhirlPiece buildWhirl() {
            double orbitR = ORBIT_MIN_R + this.random.nextDouble() * (ORBIT_MAX_R - ORBIT_MIN_R);
            Vector3f spinAxis = new Vector3f(this.random.nextFloat() - 0.5F,
                    this.random.nextFloat() - 0.5F, this.random.nextFloat() - 0.5F);
            if (spinAxis.lengthSquared() < 1.0E-4F) {
                spinAxis.set(0.0F, 1.0F, 0.0F);
            }
            spinAxis.normalize();
            return new WhirlPiece(
                    PALETTE[this.random.nextInt(PALETTE.length)],
                    MIN_SCALE + (MAX_SCALE - MIN_SCALE)
                            * (float) Math.pow(this.random.nextDouble(), 1.5D),
                    this.random.nextDouble() * Math.PI * 2.0D,
                    (TANGENTIAL_BLOCKS_PER_TICK
                            * (0.7D + this.random.nextDouble() * 0.6D)) / Math.max(1.0D, orbitR),
                    orbitR,
                    ORBIT_MIN_Y + this.random.nextDouble() * (ORBIT_MAX_Y - ORBIT_MIN_Y),
                    2.0D + this.random.nextDouble() * 3.0D,
                    60.0D + this.random.nextDouble() * 160.0D,
                    this.random.nextDouble() * Math.PI * 2.0D,
                    spinAxis,
                    (float) Math.toRadians(SPIN_MIN_DEG
                            + this.random.nextDouble() * (SPIN_MAX_DEG - SPIN_MIN_DEG))
                            * (this.random.nextBoolean() ? 1.0F : -1.0F),
                    this.whirl.size() % UPDATE_INTERVAL_TICKS,
                    this.age);
        }

        /** One interpolated push per piece in this tick's slice (keyframe LEAD, phase-sliced). */
        private void animateWhirl() {
            int slice = this.age % UPDATE_INTERVAL_TICKS;
            boolean missing = false;
            for (int i = 0; i < this.whirl.size(); i++) {
                WhirlPiece piece = this.whirl.get(i);
                if (piece.pushPhase != slice) {
                    continue;
                }
                if (piece.display == null || piece.display.isRemoved()) {
                    missing = true;
                    continue;
                }
                pushPose(piece, this.age + UPDATE_INTERVAL_TICKS);
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
            display.setTransformationInterpolationDuration(UPDATE_INTERVAL_TICKS);
            display.setTransformation(poseFor(piece, t));
        }

        /** Absolute pose of one whirl piece at siege age {@code t} (pure function of t). */
        private Transformation poseFor(WhirlPiece piece, int t) {
            double life = t - piece.bornAge;
            double angle = piece.angle0 + piece.angularSpeed * life;
            double orbitR = piece.radius;
            double py = this.combatCenter.y + piece.bandY
                    + Math.sin((Math.PI * 2.0D / piece.bobPeriod) * life + piece.bobPhase)
                            * piece.bobAmplitude;
            double px = this.combatCenter.x + Math.cos(angle) * orbitR;
            double pz = this.combatCenter.z + Math.sin(angle) * orbitR;
            float scale = piece.scale;

            if (this.ending == 1) {
                // F-033 stage 3 — victory: radially OUTWARD from the storm center, rising
                // slightly, scaling to zero as the shockwave carries the arena apart.
                float raw = Mth.clamp((t - this.endingStart) / (float) FLING_OUT_TICKS, 0.0F, 1.0F);
                float eased = 1.0F - (1.0F - raw) * (1.0F - raw); // ease-out throw
                double out = piece.radius + eased * (this.stormRadius * 1.6D + 20.0D);
                px = this.combatCenter.x + Math.cos(angle) * out;
                pz = this.combatCenter.z + Math.sin(angle) * out;
                py += eased * 6.0D * (1.0D - raw);
                scale = piece.scale * (1.0F - eased);
            } else if (this.ending == 2) {
                // Abandon: the wind lets go — pieces sink to the ground and shrink out.
                float raw = Mth.clamp((t - this.endingStart) / (float) SINK_TICKS, 0.0F, 1.0F);
                float eased = raw * raw;
                py = Mth.lerp(eased, py, this.combatCenter.y + 0.3D);
                scale = piece.scale * (1.0F - raw);
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

        /** Tears {@value #LIFT_MIN}–{@value #LIFT_MAX} real surface blocks out of the ring. */
        private void liftVolley() {
            int want = LIFT_MIN + this.random.nextInt(LIFT_MAX - LIFT_MIN + 1);
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
        final Vector3f spinAxis;
        final float spinRate;
        final int pushPhase;
        final int bornAge;

        WhirlPiece(BlockState state, float scale, double angle0, double angularSpeed,
                double radius, double bandY, double bobAmplitude, double bobPeriod,
                double bobPhase, Vector3f spinAxis, float spinRate, int pushPhase, int bornAge) {
            this.state = state;
            this.scale = scale;
            this.angle0 = angle0;
            this.angularSpeed = angularSpeed;
            this.radius = radius;
            this.bandY = bandY;
            this.bobAmplitude = bobAmplitude;
            this.bobPeriod = bobPeriod;
            this.bobPhase = bobPhase;
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
