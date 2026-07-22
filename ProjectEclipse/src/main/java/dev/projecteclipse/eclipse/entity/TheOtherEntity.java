package dev.projecteclipse.eclipse.entity;

import java.util.EnumSet;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.ai.goal.FloatGoal;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.entity.ai.goal.LookAtPlayerGoal;
import net.minecraft.world.entity.ai.goal.MeleeAttackGoal;
import net.minecraft.world.entity.ai.goal.WaterAvoidingRandomStrollGoal;
import net.minecraft.world.entity.ai.goal.target.HurtByTargetGoal;
import net.minecraft.world.entity.ai.goal.target.NearestAttackableTargetGoal;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.Level;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * "The Other" — the doppelganger event mob ({@code docs/ideas/04_content.md} §1.1). Wears a
 * copy of the anonymity uniform skin (pure-black eyes, faint purple face seam) over vanilla
 * humanoid geometry, so at distance it is indistinguishable from a teammate. Spawned ONLY
 * during Pale Night events by {@link EclipseSpawner} (2–3 per event, ≥24 blocks from
 * players, surface); despawns at dawn with a soul-escape cue + {@code arm_wisps} Quasar
 * burst.
 *
 * <p>Behavior: strolls and mimics — {@link MimicWalkGoal} paths toward the nearest player
 * at walking pace and STOPS at 5 blocks to stare. It only fights when a player closes to
 * ≤{@value #ATTACK_TRIGGER_RANGE} blocks (target selector predicate) or hits it
 * (retaliation); on aggro the head snaps a full 180° within 2 ticks. Random sprint-flag
 * flickers fake player mannerisms.</p>
 *
 * <p>Drops 1–2 {@code eclipse:umbral_shard} (+5 XP via the Monster default). Silent idle;
 * hurt = player hurt at pitch 0.8; death = a quiet warden sonic charge.</p>
 */
public class TheOtherEntity extends Monster {
    /** Players closer than this may be attacked unprovoked (spec: "within 3 blocks"). */
    public static final double ATTACK_TRIGGER_RANGE = 3.0D;
    /** MimicWalkGoal stops and stares at this distance (spec: "stops at 5 blocks"). */
    public static final double STARE_RANGE = 5.0D;

    /** Remaining ticks of the 180°-in-2t aggro head snap (server-side). */
    private int headSnapTicks;

    public TheOtherEntity(EntityType<? extends TheOtherEntity> entityType, Level level) {
        super(entityType, level);
    }

    @Override
    protected void registerGoals() {
        this.goalSelector.addGoal(0, new FloatGoal(this));
        this.goalSelector.addGoal(2, new MeleeAttackGoal(this, 1.2D, false));
        this.goalSelector.addGoal(3, new MimicWalkGoal(this, 0.42D));
        this.goalSelector.addGoal(5, new WaterAvoidingRandomStrollGoal(this, 1.0D));
        this.goalSelector.addGoal(6, new LookAtPlayerGoal(this, Player.class, 32.0F));
        this.targetSelector.addGoal(1, new HurtByTargetGoal(this));
        // Unprovoked aggression only against players that get too close.
        this.targetSelector.addGoal(2, new NearestAttackableTargetGoal<>(this, Player.class, 10, true, false,
                target -> target.distanceToSqr(this) <= ATTACK_TRIGGER_RANGE * ATTACK_TRIGGER_RANGE));
    }

    @Override
    public void setTarget(@Nullable LivingEntity target) {
        if (target != null && this.getTarget() == null) {
            this.headSnapTicks = 2; // 180° in 2 ticks — the mannequin turns around.
        }
        super.setTarget(target);
    }

    @Override
    public void aiStep() {
        super.aiStep();
        if (this.level().isClientSide) {
            return;
        }
        if (this.headSnapTicks > 0) {
            this.headSnapTicks--;
            this.setYHeadRot(this.getYHeadRot() + 90.0F);
            this.yBodyRot = this.getYHeadRot();
        }
        // Fake player mannerisms: random sprint-flag flickers while wandering.
        if (this.getTarget() == null && this.random.nextInt(120) == 0) {
            this.setSprinting(!this.isSprinting());
        }
    }

    @Override
    public void tick() {
        super.tick();
        // Event mob: dawn dissolves it (Pale Nights end at sunrise).
        if (!this.level().isClientSide && this.isAlive() && this.level().isDay()) {
            despawnAtDawn();
        }
    }

    /** Soul-escape cue + {@code arm_wisps} Quasar burst, then gone (no drops). */
    private void despawnAtDawn() {
        if (this.level() instanceof ServerLevel serverLevel) {
            serverLevel.playSound(null, this.blockPosition(), SoundEvents.SOUL_ESCAPE.value(),
                    SoundSource.HOSTILE, 1.0F, 0.9F);
            serverLevel.sendParticles(ParticleTypes.SOUL,
                    this.getX(), this.getY() + 1.0D, this.getZ(), 20, 0.3D, 0.6D, 0.3D, 0.02D);
            PacketDistributor.sendToPlayersNear(serverLevel, null,
                    this.getX(), this.getY(), this.getZ(), 64.0D,
                    new S2CQuasarPayload(S2CQuasarPayload.ARM_WISPS, this.position()));
        }
        this.discard();
    }

    @Override
    protected void dropCustomDeathLoot(ServerLevel level, DamageSource damageSource, boolean recentlyHit) {
        super.dropCustomDeathLoot(level, damageSource, recentlyHit);
        this.spawnAtLocation(new ItemStack(EclipseItems.UMBRAL_SHARD.get(), 1 + this.random.nextInt(2)));
    }

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return null; // Unsettlingly silent.
    }

    @Override
    protected SoundEvent getHurtSound(DamageSource damageSource) {
        return SoundEvents.PLAYER_HURT;
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return null; // Played manually in die() so the hurt sound keeps full volume.
    }

    @Override
    public float getVoicePitch() {
        return 0.8F;
    }

    @Override
    public void die(DamageSource damageSource) {
        if (!this.level().isClientSide) {
            this.level().playSound(null, this.blockPosition(), SoundEvents.WARDEN_SONIC_CHARGE,
                    SoundSource.HOSTILE, 0.3F, 1.0F);
        }
        super.die(damageSource);
    }

    /**
     * The mimicry goal: paths toward the nearest player at walking pace (speed modifier
     * 0.42 over the 0.3 base ≈ player walk speed), stops at {@value #STARE_RANGE} blocks
     * and just STARES. Yields to combat (runs only while no target is set).
     */
    static class MimicWalkGoal extends Goal {
        private final TheOtherEntity mob;
        private final double speedModifier;
        @Nullable
        private Player followed;

        MimicWalkGoal(TheOtherEntity mob, double speedModifier) {
            this.mob = mob;
            this.speedModifier = speedModifier;
            this.setFlags(EnumSet.of(Goal.Flag.MOVE, Goal.Flag.LOOK));
        }

        @Override
        public boolean canUse() {
            if (this.mob.getTarget() != null) {
                return false;
            }
            this.followed = this.mob.level().getNearestPlayer(this.mob, 32.0D);
            return this.followed != null && !this.followed.isSpectator();
        }

        @Override
        public boolean canContinueToUse() {
            return this.mob.getTarget() == null && this.followed != null && this.followed.isAlive()
                    && !this.followed.isSpectator() && this.mob.distanceToSqr(this.followed) < 48.0D * 48.0D;
        }

        @Override
        public void stop() {
            this.followed = null;
            this.mob.getNavigation().stop();
        }

        @Override
        public boolean requiresUpdateEveryTick() {
            return true;
        }

        @Override
        public void tick() {
            if (this.followed == null) {
                return;
            }
            this.mob.getLookControl().setLookAt(this.followed, 30.0F, 30.0F);
            if (this.mob.distanceToSqr(this.followed) > STARE_RANGE * STARE_RANGE) {
                this.mob.getNavigation().moveTo(this.followed, this.speedModifier);
            } else {
                this.mob.getNavigation().stop(); // Close enough. Stand still. Stare.
            }
        }
    }
}
