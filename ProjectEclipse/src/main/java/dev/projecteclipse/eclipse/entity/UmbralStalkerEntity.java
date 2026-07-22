package dev.projecteclipse.eclipse.entity;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.registry.EclipseItems;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.ai.goal.FloatGoal;
import net.minecraft.world.entity.ai.goal.LeapAtTargetGoal;
import net.minecraft.world.entity.ai.goal.MeleeAttackGoal;
import net.minecraft.world.entity.ai.goal.RandomLookAroundGoal;
import net.minecraft.world.entity.ai.goal.WaterAvoidingRandomStrollGoal;
import net.minecraft.world.entity.ai.goal.target.HurtByTargetGoal;
import net.minecraft.world.entity.ai.goal.target.NearestAttackableTargetGoal;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;

/**
 * Umbral Stalker — the night pack hunter ({@code docs/ideas/04_content.md} §1.3).
 * Spawned by {@link EclipseSpawner} in packs of 3–4 at night from day 5 on (the pack cap
 * doubles on Umbral Nights). 20 HP / 4 dmg / speed 0.32 / follow 40 (attributes in
 * {@link EclipseEntities}).
 *
 * <p>Standard wolf-like combat kit: float, leap, melee(1.3, persistent), stroll, random
 * look; retaliation alerts the whole pack ({@code HurtByTargetGoal().setAlertOthers()})
 * and players are hunted on sight ({@code NearestAttackableTargetGoal<Player>(true)}).</p>
 *
 * <p>At dawn it disengages, flees away from the nearest player and dissolves after
 * {@value #FLEE_DESPAWN_TICKS} ticks (soul-particle poof). Drops 0–2 umbral shards plus a
 * 20% chance of one heart fragment.</p>
 */
public class UmbralStalkerEntity extends Monster {
    /** How long the dawn flight lasts before the stalker dissolves. */
    public static final int FLEE_DESPAWN_TICKS = 100;

    /** {@code -1} while it is night; counts up once the dawn flight has started. */
    private int fleeTicks = -1;

    public UmbralStalkerEntity(EntityType<? extends UmbralStalkerEntity> entityType, Level level) {
        super(entityType, level);
    }

    @Override
    protected void registerGoals() {
        this.goalSelector.addGoal(0, new FloatGoal(this));
        this.goalSelector.addGoal(3, new LeapAtTargetGoal(this, 0.4F));
        this.goalSelector.addGoal(4, new MeleeAttackGoal(this, 1.3D, true));
        this.goalSelector.addGoal(6, new WaterAvoidingRandomStrollGoal(this, 1.0D));
        this.goalSelector.addGoal(7, new RandomLookAroundGoal(this));
        this.targetSelector.addGoal(1, new HurtByTargetGoal(this).setAlertOthers());
        this.targetSelector.addGoal(2, new NearestAttackableTargetGoal<>(this, Player.class, true));
    }

    @Override
    public void tick() {
        super.tick();
        if (this.level().isClientSide || !this.isAlive()) {
            return;
        }
        if (this.level().isDay()) {
            tickDawnFlight();
        } else {
            this.fleeTicks = -1; // Manual /time set night mid-flight: resume the hunt.
        }
    }

    /** Dawn: drop the target, sprint away from the nearest player, then dissolve. */
    private void tickDawnFlight() {
        if (this.fleeTicks < 0) {
            this.fleeTicks = 0;
            this.setTarget(null);
        }
        this.fleeTicks++;
        if (this.fleeTicks >= FLEE_DESPAWN_TICKS) {
            if (this.level() instanceof ServerLevel serverLevel) {
                serverLevel.sendParticles(ParticleTypes.SOUL,
                        this.getX(), this.getY() + 0.6D, this.getZ(), 12, 0.4D, 0.3D, 0.4D, 0.02D);
            }
            this.discard();
            return;
        }
        if (this.getNavigation().isDone()) {
            Player nearest = this.level().getNearestPlayer(this, 48.0D);
            Vec3 away = nearest != null
                    ? this.position().subtract(nearest.position()).normalize()
                    : new Vec3(this.random.nextDouble() - 0.5D, 0.0D, this.random.nextDouble() - 0.5D).normalize();
            Vec3 fleeTo = this.position().add(away.scale(16.0D));
            this.getNavigation().moveTo(fleeTo.x, fleeTo.y, fleeTo.z, 1.3D);
        }
    }

    @Override
    public boolean doHurtTarget(Entity target) {
        boolean hurt = super.doHurtTarget(target);
        if (hurt) {
            this.level().playSound(null, this.blockPosition(), SoundEvents.RAVAGER_ATTACK,
                    SoundSource.HOSTILE, 1.0F, 1.4F);
        }
        return hurt;
    }

    @Override
    protected void dropCustomDeathLoot(ServerLevel level, DamageSource damageSource, boolean recentlyHit) {
        super.dropCustomDeathLoot(level, damageSource, recentlyHit);
        int shards = this.random.nextInt(3); // 0-2
        if (shards > 0) {
            this.spawnAtLocation(new ItemStack(EclipseItems.UMBRAL_SHARD.get(), shards));
        }
        if (this.random.nextFloat() < 0.2F) {
            this.spawnAtLocation(new ItemStack(EclipseItems.HEART_FRAGMENT.get()));
        }
    }

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return SoundEvents.WOLF_GROWL;
    }

    @Override
    public float getVoicePitch() {
        return 0.5F; // Deep, wrong growl.
    }

    @Override
    protected SoundEvent getHurtSound(DamageSource damageSource) {
        return SoundEvents.WOLF_HURT;
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return SoundEvents.WOLF_DEATH;
    }

    /** Client anim hook: the head lowers 0.3 rad while hunting ({@code isAggressive()} is synced). */
    public float headLower(float partialTick) {
        return this.isAggressive() ? 0.3F : 0.0F;
    }

    /** Client anim hook: spine shards pulse-breathe. */
    public float shardPulse(float ageInTicks, int index) {
        return Mth.sin(ageInTicks * 0.15F + index * 0.9F);
    }
}
