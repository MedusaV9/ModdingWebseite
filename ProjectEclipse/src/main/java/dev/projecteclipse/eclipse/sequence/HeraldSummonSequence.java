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
import dev.projecteclipse.eclipse.entity.boss.HeraldEntity;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CScreenFadePayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.sequence.endarrival.EndArrivalFxCues;
import dev.projecteclipse.eclipse.worldgen.stage.DisplayBrightnessFx;
import net.minecraft.commands.arguments.EntityAnchorArgument;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.network.protocol.game.ClientboundSoundPacket;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.Display;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LightningBolt;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityJoinLevelEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * F-053 — the Herald's arrival cutscene: the ~9 s beat sheet that runs BEFORE
 * {@link HeraldEntity#summon} and hands the moment over to it. One shared entry point for
 * both spawn paths (the day-7 {@code HeraldsLureItem} offering and
 * {@code /dev event start herold}), so the boss can never arrive two different ways.
 *
 * <p><b>Beat sheet</b> (ticks from {@link #begin}):</p>
 * <ol>
 *   <li><b>t=0 announcement</b> — the sky goes out: a dark violet veil rises over
 *       {@value #DARKEN_IN_TICKS}t, holds and releases, under one deep horn
 *       ({@code BOSS_HERALD_ROAR_FAR} at pitch {@value #HORN_PITCH}) sent as a private
 *       sound packet to every player within {@value #HORN_RANGE} blocks — a level
 *       {@code playSound} would only carry {@code volume × 16} blocks and the horn has to
 *       cross the disc.</li>
 *   <li><b>t={@value #PILLAR_TICK} column</b> — {@code CUE_HERALD_SUMMON_PILLAR} +
 *       {@code CUE_HERALD_GLYPH_SWIRL}: light/ash shaft and two counter-rotating rune
 *       bands over the dais (Photon; photon-less clients get the shipped Quasar
 *       altar shaft + sanctum glyph legs).</li>
 *   <li><b>t={@value #GROUND_TICK} the floor breaks</b> — {@value #SLAB_COUNT} block
 *       displays of the dais's OWN ground material heave out of the floor, tilt, hang,
 *       and sink back (see {@link Slab}); the {@value #SLAB_STAGGER_TICKS}t stagger walks
 *       the ring around, so the last chunks are still settling as the boss lands.</li>
 *   <li><b>t={@value #FOCUS_TICK} camera</b> — every player within
 *       {@value #FOCUS_RANGE} blocks is pulled to look at the spawn column for
 *       {@value #FOCUS_TICKS}t. The {@code cutscene/} package's look-at is a per-keyframe
 *       property of a full camera PATH (it teleports and freezes the player, which is
 *       wrong for a fight that is about to start), so this is the soft version: one
 *       {@code ClientboundPlayerLookAtPacket} per tick aimed at a point that eases from
 *       the player's own view toward the column. Rotation only — no position packet, no
 *       lost momentum, and a player who fights the pull still wins ground.</li>
 *   <li><b>t={@value #SILHOUETTE_TICK}…{@value #MATERIALIZE_TICK} the shape</b> — a
 *       particle silhouette (spindle profile: narrow feet, broad shoulders, crowned head)
 *       assembles at the hover height, tightening from {@value #SILHOUETTE_SPREAD_START}
 *       to nothing as it goes.</li>
 *   <li><b>t={@value #SPAWN_TICK} arrival</b> — visual-only lightning + shockwave ring +
 *       camera shake, then {@link HeraldEntity#summon} (which owns the beam, the roar cue
 *       and the intro title card).</li>
 * </ol>
 *
 * <p><b>Despawn guarantee</b> ({@code StormDebrisFx} doctrine): every slab carries the
 * command tag {@value #ENTITY_TAG} and is tracked in a live-UUID set; a tagged display
 * that joins a level without being tracked was persisted by a crash mid-cutscene and is
 * discarded on load. {@code /kill @e[tag=eclipse_herald_riftbreak]} always works.</p>
 *
 * <p><b>Spawn guarantee</b>: the lure is consumed the moment the offering is accepted, so
 * the boss MUST arrive. If the run somehow outlives {@value #WATCHDOG_TICKS} ticks without
 * reaching its spawn beat, the watchdog summons the Herald anyway and then clears up.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class HeraldSummonSequence {
    /** Frozen command tag on every heaved slab — strays from a crash are swept on load. */
    public static final String ENTITY_TAG = "eclipse_herald_riftbreak";

    // ------------------------------------------------------------------ beat sheet

    private static final int DARKEN_IN_TICKS = 20;
    private static final int DARKEN_HOLD_TICKS = 45;
    private static final int DARKEN_OUT_TICKS = 35;
    /** Veil colour of the announcement beat: near-black with a violet cast. */
    private static final int DARKEN_ARGB = 0xA6_0B_04_16;
    private static final float HORN_PITCH = 0.45F;
    private static final double HORN_RANGE = 192.0D;

    private static final int PILLAR_TICK = 15;
    private static final int GROUND_TICK = 30;
    private static final int FOCUS_TICK = 30;
    private static final int SILHOUETTE_TICK = 55;
    private static final int MATERIALIZE_TICK = 130;
    private static final int SPAWN_TICK = 150;
    private static final int END_TICK = 190;
    /** Force-spawn + clear if the run ever wedges (see the class doc's spawn guarantee). */
    private static final int WATCHDOG_TICKS = 400;

    /** Camera focus: how far the pull reaches and how long it lasts (~3.5 s). */
    private static final double FOCUS_RANGE = 48.0D;
    private static final int FOCUS_TICKS = 70;
    /**
     * Per-tick share of the remaining angle the gaze closes. 0.11 reaches ~99.97 % over
     * {@value #FOCUS_TICKS}t while the first ticks stay gentle enough to feel like a pull
     * rather than a snap.
     */
    private static final double FOCUS_PULL = 0.11D;

    /** Broadcast radius of the cutscene's FX cues / veil / shake. */
    private static final double FX_RANGE = 128.0D;

    /**
     * FX-12 world-grade lanes ({@code EndArrivalFxCues} — beat-agnostic, any sequence may
     * drive them): the announcement sinks the whole world by {@value #OMEN_DIM} and HOLDS
     * it — the {@code DARKEN_*} screen veil is a one-shot, the grade is the sustain — the
     * materialize beat throws one violet pulse over it, and the arrival releases both.
     */
    private static final float OMEN_DIM = 0.35F;
    private static final float OMEN_DIM_RAMP = 30.0F;
    private static final float MATERIALIZE_TINT = 0.5F;
    private static final float MATERIALIZE_TINT_RAMP = 15.0F;
    private static final float GRADE_RELEASE_RAMP = 60.0F;

    // ------------------------------------------------------------------ ground break

    /** Slabs heaved out of the dais floor (user ask: 12–20). */
    private static final int SLAB_COUNT = 16;
    private static final double SLAB_MIN_RADIUS = 2.6D;
    private static final double SLAB_MAX_RADIUS = 7.5D;
    /** Rise/hang/sink envelope of one slab, in ticks after its own stagger. */
    private static final int SLAB_RISE_TICKS = 26;
    private static final int SLAB_HANG_TICKS = 48;
    private static final int SLAB_SINK_TICKS = 30;
    private static final int SLAB_STAGGER_TICKS = 3;
    private static final double SLAB_LIFT_MIN = 0.9D;
    private static final double SLAB_LIFT_MAX = 2.3D;
    private static final float SLAB_TILT_MAX_DEG = 16.0F;
    private static final float SLAB_SCALE_MIN = 0.9F;
    private static final float SLAB_SCALE_MAX = 1.7F;
    /** Transform push cadence == interpolation duration (the DisplayAnimator law). */
    private static final int UPDATE_INTERVAL_TICKS = 3;
    /** Display view-range override in vanilla units (× 64 blocks) and the slab light floor. */
    private static final float VIEW_RANGE = 4.0F;
    private static final int SLAB_BLOCK_LIGHT = 4;
    private static final int MAX_SKY_LIGHT = 15;

    /** Fallback palette when the dais column reads as air/fluid (should not happen). */
    private static final BlockState[] FALLBACK_PALETTE = {
            Blocks.DEEPSLATE.defaultBlockState(),
            Blocks.COBBLED_DEEPSLATE.defaultBlockState(),
            Blocks.STONE.defaultBlockState()};

    // ------------------------------------------------------------------ silhouette

    private static final int SILHOUETTE_INTERVAL_TICKS = 4;
    private static final int SILHOUETTE_RINGS = 7;
    private static final int SILHOUETTE_POINTS = 10;
    private static final double SILHOUETTE_HEIGHT = 4.6D;
    private static final double SILHOUETTE_SPREAD_START = 0.55D;

    /** The one live run (a second summon reuses it — see {@link #begin}). Server thread only. */
    @Nullable
    private static Run run;
    /** UUIDs of slabs spawned THIS session; tagged joiners outside it are crash strays. */
    private static final Set<UUID> LIVE_DISPLAYS = Collections.synchronizedSet(new HashSet<>());

    private HeraldSummonSequence() {}

    // ------------------------------------------------------------------ public API

    /**
     * Runs the arrival cutscene over {@code altarPos} and summons the Herald at its spawn
     * beat. {@code groundY} is the dais floor the slabs and the boss's hover measure from
     * (the same value {@link HeraldEntity#summon} takes).
     *
     * @return {@code false} when a run is already live — the caller then did NOT consume a
     *         summon (a second lure in the same window must not vanish silently)
     */
    public static boolean begin(ServerLevel level, BlockPos altarPos, int groundY) {
        if (run != null) {
            EclipseMod.LOGGER.info("Herald summon cutscene already running at {} — second start refused",
                    run.altarPos.toShortString());
            return false;
        }
        run = new Run(level, altarPos, groundY);
        EclipseMod.LOGGER.info("Herald summon cutscene armed at {} (ground {}) — spawn at t={}",
                altarPos.toShortString(), groundY, SPAWN_TICK);
        return true;
    }

    /** Whether a run is live (dev status / guards). */
    public static boolean isActive() {
        return run != null;
    }

    /** Discards the run and every slab immediately WITHOUT summoning (dev revert, abort). */
    public static void clearAll() {
        Run current = run;
        if (current != null) {
            current.releaseGrade();
            current.discardSlabs();
            run = null;
        }
    }

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        // In-memory only: slabs that made it to disk are swept by the join check on the
        // next boot (they can never be adopted, since LIVE_DISPLAYS is cleared here).
        run = null;
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
        Run current = run;
        if (current == null) {
            return;
        }
        if (current.level.getServer() != event.getServer()) {
            return;
        }
        current.tick();
        if (current.done) {
            run = null;
        }
    }

    // ------------------------------------------------------------------ the run

    /** One heaved chunk of the dais floor. All motion is a pure function of the run age. */
    private static final class Slab {
        @Nullable
        Display.BlockDisplay display;
        final BlockState state;
        final Vec3 ground;
        final float scale;
        final double lift;
        final int startAge;
        final float tiltX;
        final float tiltZ;
        final float yaw;
        /** Push slice: only pushed on run ticks where {@code age % interval == phase}. */
        final int pushPhase;

        Slab(BlockState state, Vec3 ground, float scale, double lift, int startAge,
                float tiltX, float tiltZ, float yaw, int pushPhase) {
            this.state = state;
            this.ground = ground;
            this.scale = scale;
            this.lift = lift;
            this.startAge = startAge;
            this.tiltX = tiltX;
            this.tiltZ = tiltZ;
            this.yaw = yaw;
            this.pushPhase = pushPhase;
        }

        /** 0 → 1 → 0 heave envelope at run age {@code t} (rise, hang, sink). */
        double envelope(int t) {
            int life = t - this.startAge;
            if (life <= 0) {
                return 0.0D;
            }
            if (life < SLAB_RISE_TICKS) {
                double raw = life / (double) SLAB_RISE_TICKS;
                return 1.0D - (1.0D - raw) * (1.0D - raw) * (1.0D - raw); // ease-out: a heave
            }
            if (life < SLAB_RISE_TICKS + SLAB_HANG_TICKS) {
                return 1.0D;
            }
            double raw = (life - SLAB_RISE_TICKS - SLAB_HANG_TICKS) / (double) SLAB_SINK_TICKS;
            if (raw >= 1.0D) {
                return 0.0D;
            }
            return 1.0D - raw * raw * (3.0D - 2.0D * raw); // smoothstep back into the floor
        }
    }

    private static final class Run {
        final ServerLevel level;
        final BlockPos altarPos;
        final int groundY;
        /** Column the whole cutscene is built around (dais centre at floor height). */
        final Vec3 center;
        /** Where the Herald materialises — the hover slot {@code summon} drops it into. */
        final Vec3 hover;
        /** The one fixed entity position every slab mounts at (StormDebrisFx transport law). */
        final Vec3 mount;
        final RandomSource random;
        final List<Slab> slabs = new ArrayList<>(SLAB_COUNT);

        int age;
        boolean spawned;
        boolean done;

        Run(ServerLevel level, BlockPos altarPos, int groundY) {
            this.level = level;
            this.altarPos = altarPos;
            this.groundY = groundY;
            this.center = new Vec3(altarPos.getX() + 0.5D, groundY, altarPos.getZ() + 0.5D);
            this.hover = new Vec3(this.center.x,
                    altarPos.getY() + HeraldEntity.SUMMON_HEIGHT, this.center.z);
            this.mount = new Vec3(this.center.x, this.center.y + 1.0D, this.center.z);
            this.random = RandomSource.create(level.getGameTime() * 31L + altarPos.asLong());
        }

        void tick() {
            this.age++;
            if (this.age == 1) {
                beatAnnouncement();
            }
            if (this.age == PILLAR_TICK) {
                beatColumn();
            }
            if (this.age == GROUND_TICK) {
                beatGroundBreak();
            }
            if (this.age >= FOCUS_TICK && this.age < FOCUS_TICK + FOCUS_TICKS) {
                pullGaze();
            }
            if (this.age >= SILHOUETTE_TICK && this.age <= MATERIALIZE_TICK
                    && this.age % SILHOUETTE_INTERVAL_TICKS == 0) {
                beatSilhouette();
            }
            if (this.age == MATERIALIZE_TICK) {
                beatMaterialize();
            }
            animateSlabs();
            if (this.age == SPAWN_TICK) {
                beatArrival();
            }
            if (this.age >= END_TICK || this.age > WATCHDOG_TICKS) {
                if (!this.spawned) {
                    // Spawn guarantee: the lure was already eaten, so the boss owes an entrance.
                    EclipseMod.LOGGER.warn("Herald summon cutscene reached t={} without its spawn beat "
                            + "— summoning now", this.age);
                    summonNow();
                }
                releaseGrade(); // safety net: the watchdog tail must not park the dim
                discardSlabs();
                this.done = true;
                EclipseMod.LOGGER.info("Herald summon cutscene finished after {}t", this.age);
            }
        }

        // --- beats ---

        /** t=0: the sky goes out and one deep horn crosses the disc. */
        private void beatAnnouncement() {
            S2CScreenFadePayload veil = new S2CScreenFadePayload(
                    DARKEN_IN_TICKS, DARKEN_HOLD_TICKS, DARKEN_OUT_TICKS, DARKEN_ARGB);
            for (ServerPlayer player : this.level.players()) {
                double distanceSq = player.position().distanceToSqr(this.center);
                if (distanceSq <= FX_RANGE * FX_RANGE) {
                    PacketDistributor.sendToPlayer(player, veil);
                }
                if (distanceSq <= HORN_RANGE * HORN_RANGE) {
                    // The far roar is a variable-range event, but a level playSound still
                    // caps at volume × 16 blocks: send it AT the listener instead.
                    player.connection.send(new ClientboundSoundPacket(
                            net.minecraft.core.registries.BuiltInRegistries.SOUND_EVENT
                                    .wrapAsHolder(EclipseSounds.BOSS_HERALD_ROAR_FAR.get()),
                            SoundSource.HOSTILE, player.getX(), player.getY(), player.getZ(),
                            1.0F, HORN_PITCH, this.random.nextLong()));
                }
            }
            this.level.playSound(null, this.altarPos, SoundEvents.BEACON_DEACTIVATE,
                    SoundSource.HOSTILE, 1.6F, 0.5F);
            // FX-12: the sky veil is a 3-second flash — the world_grade dim is what makes
            // the omen LAST. Held all the way to the arrival beat, which releases it.
            FxPayloads.sendFxEvent(this.level, EndArrivalFxCues.CUE_GRADE,
                    this.center, OMEN_DIM, OMEN_DIM_RAMP, FX_RANGE);
        }

        /** t=15: the light/ash column and the rune bands claim the dais. */
        private void beatColumn() {
            FxPayloads.sendFxEvent(this.level, FxCues.CUE_HERALD_SUMMON_PILLAR,
                    this.center, 0.0F, 0.0F, FX_RANGE);
            FxPayloads.sendFxEvent(this.level, FxCues.CUE_HERALD_GLYPH_SWIRL,
                    this.center, 0.0F, 0.0F, FX_RANGE);
            this.level.playSound(null, this.altarPos, EclipseSounds.EVENT_BEAM_HUM.get(),
                    SoundSource.HOSTILE, 1.4F, 0.7F);
        }

        /** t=30: slabs of the dais floor tear loose in a staggered ring. */
        private void beatGroundBreak() {
            for (int i = 0; i < SLAB_COUNT; i++) {
                double angle = Math.PI * 2.0D * i / SLAB_COUNT
                        + this.random.nextDouble() * 0.25D;
                double radius = SLAB_MIN_RADIUS
                        + this.random.nextDouble() * (SLAB_MAX_RADIUS - SLAB_MIN_RADIUS);
                Vec3 ground = new Vec3(
                        this.center.x + Math.cos(angle) * radius,
                        this.center.y,
                        this.center.z + Math.sin(angle) * radius);
                spawnSlab(ground, i * SLAB_STAGGER_TICKS);
            }
            this.level.playSound(null, this.altarPos, SoundEvents.DEEPSLATE_BREAK,
                    SoundSource.HOSTILE, 2.0F, 0.5F);
            PacketDistributor.sendToPlayersNear(this.level, null, this.center.x, this.center.y,
                    this.center.z, FX_RANGE, S2CShakePayload.shake(0.25F, 40));
        }

        /**
         * The gaze pull (see the class doc): re-aim at a point eased from where the player
         * is ALREADY looking toward the column, so the turn is a smooth arc and a player
         * who keeps moving their mouse can still fight it.
         */
        private void pullGaze() {
            Vec3 focus = this.hover.subtract(0.0D, 2.0D, 0.0D);
            for (ServerPlayer player : this.level.players()) {
                if (player.isSpectator()
                        || player.position().distanceToSqr(this.center) > FOCUS_RANGE * FOCUS_RANGE) {
                    continue;
                }
                Vec3 eye = player.getEyePosition();
                double reach = Math.max(1.0D, focus.distanceTo(eye));
                Vec3 looking = eye.add(player.getLookAngle().scale(reach));
                Vec3 stepped = looking.add(focus.subtract(looking).scale(FOCUS_PULL));
                player.lookAt(EntityAnchorArgument.Anchor.EYES, stepped);
            }
        }

        /**
         * A shape gathers in the hover slot: rings of soul flame on a spindle profile
         * (narrow at the feet, broad at the shoulders, a crowned point on top) whose
         * scatter tightens to nothing as the materialisation completes.
         */
        private void beatSilhouette() {
            double progress = Mth.clamp(
                    (this.age - SILHOUETTE_TICK) / (double) (MATERIALIZE_TICK - SILHOUETTE_TICK),
                    0.0D, 1.0D);
            double spread = SILHOUETTE_SPREAD_START * (1.0D - progress);
            double baseY = this.hover.y - SILHOUETTE_HEIGHT * 0.5D;
            for (int ring = 0; ring < SILHOUETTE_RINGS; ring++) {
                double v = ring / (double) (SILHOUETTE_RINGS - 1);
                double y = baseY + v * SILHOUETTE_HEIGHT;
                double radius = profileRadius(v) * (0.35D + 0.65D * progress);
                for (int point = 0; point < SILHOUETTE_POINTS; point++) {
                    double angle = Math.PI * 2.0D * point / SILHOUETTE_POINTS
                            + this.age * 0.05D + ring * 0.4D;
                    this.level.sendParticles(ParticleTypes.SOUL_FIRE_FLAME,
                            this.hover.x + Math.cos(angle) * radius, y,
                            this.hover.z + Math.sin(angle) * radius,
                            1, spread, spread, spread, 0.0D);
                }
            }
            if (this.age % (SILHOUETTE_INTERVAL_TICKS * 4) == 0) {
                this.level.playSound(null, BlockPos.containing(this.hover),
                        EclipseSounds.BOSS_HERALD_TELEGRAPH_FAR.get(), SoundSource.HOSTILE,
                        0.8F, 0.6F + (float) progress * 0.4F);
            }
        }

        /** Silhouette half-width at height fraction {@code v} — a crowned godhead spindle. */
        private static double profileRadius(double v) {
            if (v < 0.35D) {
                return 0.35D + v * 1.4D; // legs widening into the torso
            }
            if (v < 0.62D) {
                return 1.25D; // shoulders
            }
            return Math.max(0.18D, 1.25D - (v - 0.62D) * 2.6D); // neck and crown
        }

        /** t=130: the rune cage closes again right before the body lands. */
        private void beatMaterialize() {
            FxPayloads.sendFxEvent(this.level, FxCues.CUE_HERALD_GLYPH_SWIRL,
                    this.hover.subtract(0.0D, 3.0D, 0.0D), 0.0F, 0.0F, FX_RANGE);
            PacketDistributor.sendToPlayersNear(this.level, null, this.center.x, this.center.y,
                    this.center.z, FX_RANGE,
                    new S2CQuasarPayload(S2CQuasarPayload.ALTAR_BEAM, this.center));
            this.level.playSound(null, this.altarPos, EclipseSounds.EVENT_RIFT_WHOOSH.get(),
                    SoundSource.HOSTILE, 1.5F, 0.5F);
            // FX-12: the rune cage closing throws one violet pulse over the held dim.
            FxPayloads.sendFxEvent(this.level, EndArrivalFxCues.CUE_TINT,
                    this.center, MATERIALIZE_TINT, MATERIALIZE_TINT_RAMP, FX_RANGE);
        }

        /** t=150: lightning, shockwave, shake — and the real boss. */
        private void beatArrival() {
            LightningBolt bolt = EntityType.LIGHTNING_BOLT.create(this.level);
            if (bolt != null) {
                bolt.moveTo(this.center.x, this.center.y, this.center.z);
                bolt.setVisualOnly(true); // Spectacle only: the arena must not catch fire.
                this.level.addFreshEntity(bolt);
            }
            FxPayloads.sendFxEvent(this.level, FxPayloads.FX_LIGHTNING_STRIKE,
                    this.center, 1.0F, 0.0F, FX_RANGE);
            // NOT the reserved (1.0, 50) giant signature — that pair is the intro/credits
            // burst ring's client seam.
            FxPayloads.sendFxEvent(this.level, FxPayloads.FX_SHOCKWAVE,
                    this.center, 0.8F, 30.0F, FX_RANGE);
            PacketDistributor.sendToPlayersNear(this.level, null, this.center.x, this.center.y,
                    this.center.z, FX_RANGE, S2CShakePayload.shake(0.85F, 22));
            releaseGrade(); // the light comes back with the boss
            summonNow();
        }

        private void summonNow() {
            this.spawned = true;
            HeraldEntity.summon(this.level, this.altarPos, this.groundY);
        }

        /**
         * FX-12: returns both world-grade lanes to 0. Both are HOLDS, so every exit of the
         * run has to pass through here — the arrival beat, the end/watchdog tail and the
         * dev abort. Re-sending a release is a no-op ramp (0 → 0), never a visual seam.
         */
        void releaseGrade() {
            FxPayloads.sendFxEvent(this.level, EndArrivalFxCues.CUE_GRADE,
                    this.center, 0.0F, GRADE_RELEASE_RAMP, FX_RANGE);
            FxPayloads.sendFxEvent(this.level, EndArrivalFxCues.CUE_TINT,
                    this.center, 0.0F, GRADE_RELEASE_RAMP, FX_RANGE);
        }

        // --- slabs ---

        private void spawnSlab(Vec3 ground, int stagger) {
            BlockPos groundPos = BlockPos.containing(ground.x, ground.y, ground.z);
            if (!this.level.isLoaded(groundPos)) {
                return;
            }
            BlockState state = this.level.getBlockState(groundPos);
            if (state.isAir() || !state.getFluidState().isEmpty()) {
                state = FALLBACK_PALETTE[this.random.nextInt(FALLBACK_PALETTE.length)];
            }
            Display.BlockDisplay display = EntityType.BLOCK_DISPLAY.create(this.level);
            if (display == null) {
                return;
            }
            Slab slab = new Slab(state, ground,
                    SLAB_SCALE_MIN + this.random.nextFloat() * (SLAB_SCALE_MAX - SLAB_SCALE_MIN),
                    SLAB_LIFT_MIN + this.random.nextDouble() * (SLAB_LIFT_MAX - SLAB_LIFT_MIN),
                    this.age + stagger,
                    (this.random.nextFloat() - 0.5F) * 2.0F * SLAB_TILT_MAX_DEG,
                    (this.random.nextFloat() - 0.5F) * 2.0F * SLAB_TILT_MAX_DEG,
                    this.random.nextFloat() * 360.0F,
                    this.slabs.size() % UPDATE_INTERVAL_TICKS);
            display.setBlockState(slab.state);
            display.moveTo(this.mount.x, this.mount.y, this.mount.z, 0.0F, 0.0F);
            display.addTag(ENTITY_TAG);
            // Displays are dropped past view_range × 64 blocks from their ENTITY anchor and
            // the whole ring anchors on the dais column, so the override is what keeps the
            // outer slabs visible from the arena rim.
            DisplayBrightnessFx.set(display, SLAB_BLOCK_LIGHT, MAX_SKY_LIGHT, VIEW_RANGE);
            display.setTransformationInterpolationDelay(0);
            display.setTransformationInterpolationDuration(0);
            display.setTransformation(poseAt(slab, this.age));
            LIVE_DISPLAYS.add(display.getUUID());
            this.level.addFreshEntity(display);
            slab.display = display;
            this.slabs.add(slab);
        }

        /**
         * One interpolated push per slab in this tick's slice, targeting the pose the
         * window ENDS on (keyframe lead) so the client tween covers the gap instead of
         * trailing a full interval behind the server.
         */
        private void animateSlabs() {
            if (this.slabs.isEmpty()) {
                return;
            }
            int slice = this.age % UPDATE_INTERVAL_TICKS;
            boolean missing = false;
            for (Slab slab : this.slabs) {
                if (slab.pushPhase != slice) {
                    continue;
                }
                Display.BlockDisplay display = slab.display;
                if (display == null || display.isRemoved()) {
                    missing = true;
                    continue;
                }
                display.setTransformationInterpolationDelay(0);
                display.setTransformationInterpolationDuration(UPDATE_INTERVAL_TICKS);
                display.setTransformation(poseAt(slab, this.age + UPDATE_INTERVAL_TICKS));
                if (slab.envelope(this.age) > 0.6D && this.random.nextInt(12) == 0) {
                    this.level.sendParticles(ParticleTypes.SMOKE,
                            slab.ground.x, slab.ground.y + 0.2D, slab.ground.z,
                            2, 0.25D, 0.05D, 0.25D, 0.01D);
                }
            }
            if (missing) {
                this.slabs.removeIf(slab -> slab.display == null || slab.display.isRemoved());
            }
        }

        /**
         * Absolute pose of one slab at run age {@code t}: its heave envelope drives both
         * the lift out of the floor and the tilt, folded into one translation relative to
         * the shared mount. Pure function of {@code t}, so pushes are stateless.
         */
        private Transformation poseAt(Slab slab, int t) {
            double eased = slab.envelope(t);
            float scale = slab.scale;
            Quaternionf rotation = new Quaternionf()
                    .rotateY((float) Math.toRadians(slab.yaw))
                    .rotateX((float) Math.toRadians(slab.tiltX * eased))
                    .rotateZ((float) Math.toRadians(slab.tiltZ * eased));
            // Slabs start BELOW the floor line so the rise reads as breaking out of it.
            Vector3f translation = new Vector3f(
                    (float) (slab.ground.x - this.mount.x),
                    (float) (slab.ground.y - this.mount.y - scale * 0.5D + slab.lift * eased),
                    (float) (slab.ground.z - this.mount.z));
            // Re-centre the [0,scale]^3 block mesh on the flight point through the rotation.
            Vector3f half = new Vector3f(scale * 0.5F, scale * 0.5F, scale * 0.5F);
            translation.sub(rotation.transform(half, new Vector3f()));
            return new Transformation(translation, rotation,
                    new Vector3f(scale, scale, scale), new Quaternionf());
        }

        void discardSlabs() {
            for (Slab slab : this.slabs) {
                Display.BlockDisplay display = slab.display;
                if (display != null) {
                    LIVE_DISPLAYS.remove(display.getUUID());
                    if (!display.isRemoved()) {
                        display.discard();
                    }
                    slab.display = null;
                }
            }
            this.slabs.clear();
        }
    }
}
