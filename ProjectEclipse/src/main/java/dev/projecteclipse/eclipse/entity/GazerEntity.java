package dev.projecteclipse.eclipse.entity;

import java.util.EnumSet;

import javax.annotation.Nullable;

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
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.PathfinderMob;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.entity.ai.goal.LookAtPlayerGoal;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.network.PacketDistributor;

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
 * <p>Unkillable: any non-bypass damage makes it vanish instead ({@link #hurt}). At dawn it
 * quietly fades (spawns are night-only, day 3+ — see {@link EclipseSpawner}). Ambient
 * whisper loop {@code eclipse:ambient.gazer_whisper} is a fixed-range 12-block sound.</p>
 */
public class GazerEntity extends PathfinderMob {
    public GazerEntity(EntityType<? extends GazerEntity> entityType, Level level) {
        super(entityType, level);
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
        // Night watcher: fade out quietly at dawn so gazers never accumulate into the day.
        if (!this.level().isClientSide && this.isAlive() && this.level().isDay()) {
            this.vanish(null);
        }
    }

    /** Unkillable: damage (except /kill-style bypasses) makes it vanish instead. */
    @Override
    public boolean hurt(DamageSource source, float amount) {
        if (source.is(DamageTypeTags.BYPASSES_INVULNERABILITY)) {
            return super.hurt(source, amount);
        }
        if (!this.level().isClientSide && this.isAlive()) {
            this.vanish(source.getEntity() instanceof ServerPlayer player ? player : null);
        }
        return false;
    }

    /**
     * Despawn with a wisp puff; when {@code moodTarget} is given, only that player hears
     * the cave-mood sting (the one who stared it down / struck it).
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
