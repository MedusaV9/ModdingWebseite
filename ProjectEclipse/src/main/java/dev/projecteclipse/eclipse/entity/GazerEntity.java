package dev.projecteclipse.eclipse.entity;

import java.util.EnumSet;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoMob;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.tags.DamageTypeTags;
import net.minecraft.util.Mth;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityEvent;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.entity.ai.goal.LookAtPlayerGoal;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.network.PacketDistributor;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.AnimationState;
import software.bernie.geckolib.animation.PlayState;

/**
 * The Gazer — ambient watcher ({@code docs/ideas/04_content.md} §1.2). It never attacks and
 * never walks; it just stands at the edge of the light, hood tracking the nearest player.
 *
 * <p>{@link VanishWhenSeenGoal}: a player looking straight at it (look-vector dot
 * ≥ {@value VanishWhenSeenGoal#SEEN_DOT}) for {@value VanishWhenSeenGoal#SEEN_TICKS}
 * consecutive ticks makes it vanish — wisp puff + a cave-mood sound played privately to
 * that player. {@link RelocateGoal}: every 200–400 ticks it teleports to a surface point
 * 20–40 blocks away inside the nearest player's peripheral vision (view dot 0.3–0.8), so
 * it is always <em>almost</em> in frame.</p>
 *
 * <p>Unkillable: any non-bypass damage makes it vanish instead ({@link #hurt}) — since the
 * MC1 GeckoLib conversion with a short {@value #HURT_VANISH_DELAY_TICKS}t flinch
 * ({@code hurt} one-shot) before the wisp puff, so the strike reads on the body. At dawn it
 * quietly fades (spawns are night-only, day 3+ — see {@link EclipseSpawner}). Ambient
 * whisper loop {@code eclipse:ambient.gazer_whisper} is a fixed-range 12-block sound.</p>
 *
 * <p><b>Presentation</b> (MC1 GeckoLib conversion): geo/anims/textures live under
 * {@code geo/entity/gazer.geo.json}, {@code animations/entity/gazer.animation.json} and
 * {@code textures/entity/gazer(.png|_glowmask.png)}, rendered by
 * {@code client/entity/gazer/GazerGeoRenderer}. The {@code base} controller idles (the
 * gazer never walks — teleport relocation must not flick {@code walk}, census trap F-9);
 * the {@code action} controller carries {@code gaze_lock} (held pupil dilation),
 * {@code tether_snap} (the recoil when the stare tether tears), {@code hurt} and the held
 * {@code death}. The stare beat is driven by {@link #tickStareMirror}: a server-side
 * mirror of the client {@code MobPhotonFxRows.GazeTetherWatcher} constants (lock cone
 * {@value #LOCK_DEG}°, release cone {@value #RELEASE_DEG}°, {@value #LOCK_TICKS}t arm
 * time, {@value #TETHER_RANGE}/{@value #RELEASE_RANGE}-block band) so the pupil dilates
 * the same moment the client's {@code gazer_gaze_beam} thread arms, and the
 * {@code tether_snap} twitch lands with the {@code gazer_tether_snap} tear-off FX.</p>
 */
public class GazerEntity extends EclipseGeoMob {
    /** Frozen §6 entity path — geo/anim/texture triple + animation ids key off this. */
    public static final String GEO_ID = "gazer";
    /** Held one-shot: the pupil dilates and the lids pin open while the stare is locked. */
    public static final String ANIM_GAZE_LOCK = "gaze_lock";
    /** One-shot: the gaze tether tears — iris slams dark, hood whips, body shudders. */
    public static final String ANIM_TETHER_SNAP = "tether_snap";
    /** One-shot: flinch played in the {@value #HURT_VANISH_DELAY_TICKS}t before a hurt-vanish. */
    public static final String ANIM_HURT = "hurt";
    /** Scripted death window (sheet: 30t — the lids close forever; bypass-kills only). */
    public static final int DEATH_ANIM_TICKS = 30;
    /** Flinch window between a (blocked) hit and the vanish puff. */
    public static final int HURT_VANISH_DELAY_TICKS = 7;

    // Server-side mirror of the client gaze-tether watcher (MobPhotonFxRows.
    // GazeTetherWatcher) — SAME constants, so the gaze_lock/tether_snap anims land on
    // the beats the FX derives client-locally. Do not tune these independently.
    private static final double LOCK_DEG = 25.0D;
    private static final double RELEASE_DEG = 45.0D;
    private static final double LOCK_DOT = Math.cos(Math.toRadians(LOCK_DEG));
    private static final double RELEASE_DOT = Math.cos(Math.toRadians(RELEASE_DEG));
    private static final int LOCK_TICKS = 8;
    private static final double TETHER_RANGE = 20.0D;
    private static final double RELEASE_RANGE = 22.0D;

    /** Player the hood's stare is currently arming/holding on (server only). */
    @Nullable
    private UUID stareTargetId;
    private int stareTicks;
    private boolean stareLocked;
    /** Hurt-flinch countdown: > 0 means a vanish is pending ({@link #tick}). */
    private int pendingVanishTicks;
    @Nullable
    private ServerPlayer pendingVanishMood;

    public GazerEntity(EntityType<? extends GazerEntity> entityType, Level level) {
        super(entityType, level);
    }

    // --- GeckoLib (frozen two-controller layout from EclipseGeoMob) ---

    @Override
    public String geoId() {
        return GEO_ID;
    }

    @Override
    protected void registerActionTriggers(AnimationController<?> action) {
        super.registerActionTriggers(action); // death (played-and-held)
        // gaze_lock HOLDS its dilated last frame — the stare is a state, not a beat; it
        // is always resolved by tether_snap (every lock break fires one) or the discard.
        action.triggerableAnim(ANIM_GAZE_LOCK, EclipseGeoAnimations.hold(GEO_ID, ANIM_GAZE_LOCK));
        action.triggerableAnim(ANIM_TETHER_SNAP, EclipseGeoAnimations.once(GEO_ID, ANIM_TETHER_SNAP));
        action.triggerableAnim(ANIM_HURT, EclipseGeoAnimations.once(GEO_ID, ANIM_HURT));
    }

    /**
     * The gazer never walks (speed 0, relocation is teleport-only) — but a teleport IS a
     * position delta, so both {@code state.isMoving()} and the plain DriftLantern delta
     * check would flick {@code walk} for a frame on every relocation (census trap F-9).
     * Gate the delta from above too: only a sub-block glide (external push, water) plays
     * {@code walk}; a ≥half-block jump is a teleport and stays {@code idle}.
     */
    @Override
    protected PlayState handleBaseState(AnimationState<?> state) {
        double dx = this.getX() - this.xOld;
        double dz = this.getZ() - this.zOld;
        double driftSq = dx * dx + dz * dz;
        boolean gliding = driftSq > 1.0E-5D && driftSq < 0.25D;
        return state.setAndContinue(gliding ? walkAnim() : idleAnim());
    }

    @Override
    protected void registerGoals() {
        // NO movement goals by design; look goal only drives the hood yaw animation.
        this.goalSelector.addGoal(1, new VanishWhenSeenGoal(this));
        this.goalSelector.addGoal(2, new RelocateGoal(this));
        this.goalSelector.addGoal(3, new LookAtPlayerGoal(this, Player.class, 32.0F, 1.0F));
    }

    @Override
    public void tick() {
        super.tick();
        if (this.level().isClientSide || !this.isAlive()) {
            return;
        }
        // Hurt-flinch window: the stare mirror pauses (the flinch anim owns the face)
        // and the wisp puff fires when the countdown runs out (vanish() discards).
        if (this.pendingVanishTicks > 0) {
            if (--this.pendingVanishTicks == 0) {
                this.vanish(this.pendingVanishMood);
            }
            return;
        }
        // Night watcher: fade out quietly at dawn so gazers never accumulate into the day.
        if (this.level().isDay()) {
            this.vanish(null);
            return;
        }
        if (this.level() instanceof ServerLevel serverLevel) {
            tickStareMirror(serverLevel);
        }
    }

    /**
     * Server-side mirror of the client-local gaze-tether watcher: while the hood's look
     * vector holds a player inside the {@value #LOCK_DEG}° cone (with line of sight,
     * within the {@value #TETHER_RANGE}-block gate) for {@value #LOCK_TICKS}t, the stare
     * LOCKS — {@code gaze_lock} dilates the pupil and holds it. The lock survives inside
     * the wider {@value #RELEASE_DEG}°/{@value #RELEASE_RANGE}-block hysteresis band and
     * BREAKS the first tick it leaves it — {@code tether_snap} twitches the hood the same
     * tick the client watcher tears the thread FX. One canonical stare per gazer (the
     * client watcher is per-observer; the hood only points one way, so the server picks
     * the player it is actually looking at — the best-dot candidate).
     */
    private void tickStareMirror(ServerLevel level) {
        ServerPlayer target = this.stareTargetId != null
                ? level.getServer().getPlayerList().getPlayer(this.stareTargetId) : null;
        if (target != null && !target.isRemoved() && !target.isSpectator()
                && target.level() == level && holdsStare(target, this.stareLocked)) {
            if (this.stareTicks < LOCK_TICKS && ++this.stareTicks >= LOCK_TICKS) {
                this.stareLocked = true;
                triggerAction(ANIM_GAZE_LOCK);
            }
            return;
        }
        if (this.stareLocked) {
            // The cord recoils into the hood — same tick the client watcher fires the
            // gazer_tether_snap FX for its own broken thread.
            triggerAction(ANIM_TETHER_SNAP);
        }
        this.stareTargetId = null;
        this.stareTicks = 0;
        this.stareLocked = false;
        // Acquire: the player the hood is actually staring down (best look-dot inside
        // the arm cone, tether range and line of sight).
        ServerPlayer best = null;
        double bestDot = LOCK_DOT;
        for (ServerPlayer player : level.players()) {
            if (player.isSpectator()
                    || this.distanceToSqr(player.position()) > TETHER_RANGE * TETHER_RANGE) {
                continue;
            }
            Vec3 toPlayer = player.getEyePosition().subtract(this.getEyePosition());
            if (toPlayer.lengthSqr() < 1.0E-4D) {
                continue;
            }
            double dot = this.getLookAngle().dot(toPlayer.normalize());
            if (dot >= bestDot && this.hasLineOfSight(player)) {
                best = player;
                bestDot = dot;
            }
        }
        if (best != null) {
            this.stareTargetId = best.getUUID();
            this.stareTicks = 1;
        }
    }

    /** Range gate + hysteretic stare cone + line of sight — the watcher's own math. */
    private boolean holdsStare(ServerPlayer player, boolean locked) {
        double gate = locked ? RELEASE_RANGE : TETHER_RANGE;
        if (this.distanceToSqr(player.position()) > gate * gate) {
            return false;
        }
        Vec3 toPlayer = player.getEyePosition().subtract(this.getEyePosition());
        if (toPlayer.lengthSqr() < 1.0E-4D) {
            return true; // inside its own head: no meaningful direction to break
        }
        double dot = this.getLookAngle().dot(toPlayer.normalize());
        return dot >= (locked ? RELEASE_DOT : LOCK_DOT) && this.hasLineOfSight(player);
    }

    /**
     * Unkillable: damage (except /kill-style bypasses) makes it vanish instead — with a
     * {@value #HURT_VANISH_DELAY_TICKS}t {@code hurt} flinch first, so the strike reads
     * on the body before the wisp puff swallows it.
     */
    @Override
    public boolean hurt(DamageSource source, float amount) {
        if (source.is(DamageTypeTags.BYPASSES_INVULNERABILITY)) {
            return super.hurt(source, amount);
        }
        if (!this.level().isClientSide && this.isAlive() && this.pendingVanishTicks <= 0) {
            triggerAction(ANIM_HURT);
            // Drop any held stare SILENTLY (no tether_snap): the flinch replaces the
            // gaze_lock hold on the action controller, so a snap fired after the flinch
            // would pop from rest straight to the snap's dilated first frame.
            this.stareTargetId = null;
            this.stareTicks = 0;
            this.stareLocked = false;
            this.pendingVanishTicks = HURT_VANISH_DELAY_TICKS;
            this.pendingVanishMood = source.getEntity() instanceof ServerPlayer player ? player : null;
        }
        return false;
    }

    /**
     * Despawn with a wisp puff; when {@code moodTarget} is given, only that player hears
     * the cave-mood sting (the one who stared it down / struck it). Instant discard — a
     * broken stare tether is torn client-locally by the gaze watcher at the last seen eye.
     */
    public void vanish(@Nullable ServerPlayer moodTarget) {
        if (this.level() instanceof ServerLevel serverLevel) {
            serverLevel.sendParticles(ParticleTypes.PORTAL,
                    this.getX(), this.getY() + 1.0D, this.getZ(), 24, 0.3D, 0.8D, 0.3D, 0.05D);
            PacketDistributor.sendToPlayersNear(serverLevel, null,
                    this.getX(), this.getY(), this.getZ(), 64.0D,
                    new S2CQuasarPayload(S2CQuasarPayload.ARM_WISPS, this.position()));
            if (moodTarget != null) {
                moodTarget.playNotifySound(SoundEvents.AMBIENT_CAVE.value(), SoundSource.HOSTILE, 1.0F, 0.8F);
            }
        }
        this.discard();
    }

    // --- death (bypass-kills only; scripted upright gutter-out, renderer zeroes the flip) ---

    @Override
    public void die(DamageSource damageSource) {
        super.die(damageSource);
        if (!this.level().isClientSide) {
            triggerAction(EclipseGeoAnimations.ANIM_DEATH);
        }
    }

    @Override
    protected void tickDeath() {
        this.deathTime++;
        if (!(this.level() instanceof ServerLevel serverLevel)) {
            return; // Client: the held death anim plays; deathTime is cosmetic here.
        }
        if (this.deathTime % 5 == 0) {
            serverLevel.sendParticles(ParticleTypes.PORTAL,
                    this.getX(), this.getY() + 1.2D, this.getZ(), 2, 0.2D, 0.4D, 0.2D, 0.02D);
        }
        if (this.deathTime >= DEATH_ANIM_TICKS && !this.isRemoved()) {
            serverLevel.broadcastEntityEvent(this, EntityEvent.POOF);
            this.remove(Entity.RemovalReason.KILLED);
        }
    }

    /**
     * Altar-watch hook (spec §1.2: "1 guaranteed near altar during sacrifices"): spawns one
     * gazer on the surface 12–24 blocks from the altar, silently observing the ritual.
     * Called from {@code ritual.AltarBlockEntity}'s deposit/sacrifice paths. No-op during
     * the day (it would vanish instantly) or while another gazer already watches.
     */
    public static void watchSacrifice(ServerLevel level, BlockPos altarPos) {
        if (level.isDay()) {
            return;
        }
        boolean alreadyWatching = !level.getEntities(EclipseEntities.GAZER.get(),
                gazer -> gazer.isAlive() && gazer.blockPosition().closerThan(altarPos, 48.0D)).isEmpty();
        if (alreadyWatching) {
            return;
        }
        for (int attempt = 0; attempt < 24; attempt++) {
            double angle = level.getRandom().nextDouble() * Math.PI * 2.0D;
            double distance = 12.0D + level.getRandom().nextDouble() * 12.0D;
            int x = Mth.floor(altarPos.getX() + 0.5D + Math.cos(angle) * distance);
            int z = Mth.floor(altarPos.getZ() + 0.5D + Math.sin(angle) * distance);
            int y = level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z);
            if (y <= level.getMinBuildHeight()
                    || !level.getBlockState(new BlockPos(x, y - 1, z)).isSolid()) {
                continue;
            }
            GazerEntity gazer = EclipseEntities.GAZER.get().create(level);
            if (gazer == null) {
                return;
            }
            gazer.moveTo(x + 0.5D, y, z + 0.5D, 0.0F, 0.0F);
            level.addFreshEntity(gazer);
            return;
        }
    }

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return EclipseSounds.AMBIENT_GAZER_WHISPER.get();
    }

    @Override
    public int getAmbientSoundInterval() {
        return 160; // Sparse whisper loop; the sound event itself is range-capped at 12 blocks.
    }

    @Override
    public boolean isPushable() {
        return false;
    }

    @Override
    public boolean removeWhenFarAway(double distanceToClosestPlayer) {
        return true; // Ambience only — never worth keeping loaded.
    }

    /**
     * Vanish once a player has kept it dead-center in view ({@code dot ≥ }{@value #SEEN_DOT})
     * for {@value #SEEN_TICKS} consecutive ticks.
     */
    static class VanishWhenSeenGoal extends Goal {
        static final double SEEN_DOT = 0.985D;
        static final int SEEN_TICKS = 40;
        private static final double MAX_SEEN_RANGE = 64.0D;

        private final GazerEntity gazer;
        @Nullable
        private ServerPlayer watcher;
        private int seenTicks;

        VanishWhenSeenGoal(GazerEntity gazer) {
            this.gazer = gazer;
            this.setFlags(EnumSet.noneOf(Goal.Flag.class)); // Runs alongside everything.
        }

        @Override
        public boolean canUse() {
            this.watcher = findWatcher();
            return this.watcher != null;
        }

        @Override
        public boolean canContinueToUse() {
            return this.watcher != null && this.watcher.isAlive() && isLookingAtMe(this.watcher);
        }

        @Override
        public void start() {
            this.seenTicks = 0;
        }

        @Override
        public boolean requiresUpdateEveryTick() {
            return true;
        }

        @Override
        public void tick() {
            if (++this.seenTicks >= SEEN_TICKS && this.watcher != null) {
                this.gazer.vanish(this.watcher);
            }
        }

        @Nullable
        private ServerPlayer findWatcher() {
            if (!(this.gazer.level() instanceof ServerLevel serverLevel)) {
                return null;
            }
            for (ServerPlayer player : serverLevel.players()) {
                if (!player.isSpectator() && player.distanceToSqr(this.gazer) < MAX_SEEN_RANGE * MAX_SEEN_RANGE
                        && isLookingAtMe(player)) {
                    return player;
                }
            }
            return null;
        }

        private boolean isLookingAtMe(ServerPlayer player) {
            Vec3 look = player.getViewVector(1.0F).normalize();
            Vec3 toGazer = new Vec3(this.gazer.getX() - player.getX(),
                    this.gazer.getEyeY() - player.getEyeY(),
                    this.gazer.getZ() - player.getZ()).normalize();
            return look.dot(toGazer) >= SEEN_DOT;
        }
    }

    /**
     * Every 200–400 ticks: teleport to a surface point 20–40 blocks away that sits in the
     * nearest player's peripheral field of view (view dot 0.3–0.8) — close enough to
     * glimpse, never straight ahead.
     */
    static class RelocateGoal extends Goal {
        private static final int MIN_COOLDOWN = 200;
        private static final int MAX_COOLDOWN = 400;
        private static final int ATTEMPTS = 24;

        private final GazerEntity gazer;
        private int cooldown;

        RelocateGoal(GazerEntity gazer) {
            this.gazer = gazer;
            this.setFlags(EnumSet.noneOf(Goal.Flag.class));
            this.cooldown = MIN_COOLDOWN;
        }

        @Override
        public boolean canUse() {
            if (--this.cooldown > 0) {
                return false;
            }
            this.cooldown = MIN_COOLDOWN + this.gazer.getRandom().nextInt(MAX_COOLDOWN - MIN_COOLDOWN + 1);
            return true;
        }

        @Override
        public void start() {
            Player player = this.gazer.level().getNearestPlayer(this.gazer, 64.0D);
            if (player == null || this.gazer.level().isClientSide) {
                return;
            }
            Vec3 look = player.getViewVector(1.0F).normalize();
            for (int attempt = 0; attempt < ATTEMPTS; attempt++) {
                double angle = this.gazer.getRandom().nextDouble() * Math.PI * 2.0D;
                double distance = 20.0D + this.gazer.getRandom().nextDouble() * 20.0D;
                double x = player.getX() + Math.cos(angle) * distance;
                double z = player.getZ() + Math.sin(angle) * distance;
                int y = this.gazer.level().getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
                        Mth.floor(x), Mth.floor(z));
                if (y <= this.gazer.level().getMinBuildHeight()) {
                    continue; // Void column (beyond the disc rim).
                }
                Vec3 toSpot = new Vec3(x - player.getX(), y + 1.0D - player.getEyeY(), z - player.getZ()).normalize();
                double dot = look.dot(toSpot);
                if (dot < 0.3D || dot > 0.8D) {
                    continue; // Not peripheral: either behind them or right where they look.
                }
                BlockPos target = BlockPos.containing(x, y, z);
                if (!this.gazer.level().getBlockState(target.below()).isSolid()) {
                    continue;
                }
                this.gazer.teleportTo(x, y, z);
                this.gazer.getNavigation().stop();
                return;
            }
        }
    }
}
