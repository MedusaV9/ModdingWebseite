package dev.projecteclipse.eclipse.entity.glitch;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.ai.attributes.AttributeInstance;
import net.minecraft.world.entity.ai.attributes.AttributeModifier;
import net.minecraft.world.entity.ai.attributes.AttributeSupplier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.ai.goal.FloatGoal;
import net.minecraft.world.entity.ai.goal.MeleeAttackGoal;
import net.minecraft.world.entity.ai.goal.RandomLookAroundGoal;
import net.minecraft.world.entity.ai.goal.RandomStrollGoal;
import net.minecraft.world.entity.ai.goal.target.HurtByTargetGoal;
import net.minecraft.world.entity.ai.goal.target.NearestAttackableTargetGoal;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;

/**
 * Glitched Husk / Glitch-Hülle — the humanoid corruption of the fresh map rings
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.3 "glitched", kind HUSK). A shape
 * like a man rendered wrong: torso split along a light-bleeding seam, half the face one
 * step behind the rest, one arm longer than the other. 30 HP / 5 dmg / speed 0.27;
 * loot: {@code eclipse:entities/glitched_husk} (corrupted vanilla scraps) + 1–2
 * {@code glitch_shard} from the shared {@code GlitchDrops} tag hook.
 *
 * <p><b>Unseen burst</b> (sheet: "burst of speed when player looks away"): while its
 * player target is NOT looking at it (enderman-style gaze test), a transient
 * +{@value #UNSEEN_SPEED_BOOST}×-total speed modifier kicks in — the shambler you
 * glanced away from arrives shockingly fast, portal static trailing. Look back and it
 * drops to the broken {@code walk} shamble. Re-evaluated every
 * {@value #GAZE_CHECK_INTERVAL_TICKS} t.</p>
 *
 * <p><b>Glitch blink:</b> shared {@link GlitchedMonster} stutter-teleport, on the lazy
 * husk cadence (200–280 t).</p>
 */
public class GlitchedHuskEntity extends GlitchedMonster {
    /** Frozen §6 entity path — geo/anim/texture triple + animation ids key off this. */
    public static final String GEO_ID = "glitched_husk";
    /** Scripted death window (anim file: 1.5 s freeze-then-collapse). */
    public static final int DEATH_ANIM_TICKS = 30;
    /** Speed bonus while unseen (multiply-total: 0.27 → ~0.4 effective). */
    private static final double UNSEEN_SPEED_BOOST = 0.5D;
    private static final int GAZE_CHECK_INTERVAL_TICKS = 5;
    private static final ResourceLocation UNSEEN_SPEED_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "glitched_husk_unseen_burst");
    private static final AttributeModifier UNSEEN_SPEED = new AttributeModifier(
            UNSEEN_SPEED_ID, UNSEEN_SPEED_BOOST, AttributeModifier.Operation.ADD_MULTIPLIED_TOTAL);

    public GlitchedHuskEntity(EntityType<? extends GlitchedHuskEntity> entityType, Level level) {
        super(entityType, level);
    }

    /** Spec §2.3 kind stats: HUSK 30 HP / 5 dmg / 0.27. */
    public static AttributeSupplier.Builder createAttributes() {
        return Monster.createMonsterAttributes()
                .add(Attributes.MAX_HEALTH, 30.0D)
                .add(Attributes.ATTACK_DAMAGE, 5.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.27D)
                .add(Attributes.FOLLOW_RANGE, 35.0D);
    }

    // --- GeckoLib / kind knobs ---

    @Override
    public String geoId() {
        return GEO_ID;
    }

    @Override
    protected int blinkCooldownMinTicks() {
        return 200;
    }

    @Override
    protected int blinkCooldownMaxTicks() {
        return 280;
    }

    @Override
    protected int deathAnimTicks() {
        return DEATH_ANIM_TICKS;
    }

    // --- AI ---

    @Override
    protected void registerGoals() {
        this.goalSelector.addGoal(0, new FloatGoal(this));
        this.goalSelector.addGoal(2, new MeleeAttackGoal(this, 1.1D, false));
        this.goalSelector.addGoal(6, new RandomStrollGoal(this, 0.8D, 100));
        this.goalSelector.addGoal(7, new RandomLookAroundGoal(this));
        this.targetSelector.addGoal(1, new HurtByTargetGoal(this));
        this.targetSelector.addGoal(2, new NearestAttackableTargetGoal<>(this, Player.class, true));
    }

    /** Unseen burst: toggle the transient speed modifier off the target's gaze. */
    @Override
    public void aiStep() {
        super.aiStep();
        if (this.level().isClientSide || !this.isAlive()
                || this.tickCount % GAZE_CHECK_INTERVAL_TICKS != 0) {
            return;
        }
        AttributeInstance speed = this.getAttribute(Attributes.MOVEMENT_SPEED);
        if (speed == null) {
            return;
        }
        boolean unseen = this.getTarget() instanceof Player player && player.isAlive()
                && !isLookedAtBy(player);
        boolean bursting = speed.hasModifier(UNSEEN_SPEED_ID);
        if (unseen && !bursting) {
            speed.addTransientModifier(UNSEEN_SPEED);
            if (this.level() instanceof ServerLevel serverLevel) {
                // The only tell for a player who isn't looking: a burst of static behind them.
                serverLevel.sendParticles(ParticleTypes.REVERSE_PORTAL,
                        this.getX(), this.getY() + 1.0D, this.getZ(), 6, 0.25D, 0.4D, 0.25D, 0.02D);
            }
        } else if (!unseen && bursting) {
            speed.removeModifier(UNSEEN_SPEED_ID);
        }
    }

    // --- presentation ---

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return SoundEvents.ZOMBIE_AMBIENT; // Corrupted playback of something familiar.
    }

    @Override
    public float getVoicePitch() {
        // Deliberately unstable: every vocalization plays back at a different rate.
        return 0.6F + this.random.nextFloat() * 0.8F;
    }

    @Override
    @Nullable
    protected SoundEvent getHurtSound(DamageSource damageSource) {
        return SoundEvents.ZOMBIE_HURT;
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return SoundEvents.ZOMBIE_DEATH;
    }

    /** Drops the unseen burst if the target slot clears (no lingering modifier). */
    @Override
    public void setTarget(@Nullable LivingEntity target) {
        super.setTarget(target);
        if (target == null && !this.level().isClientSide) {
            AttributeInstance speed = this.getAttribute(Attributes.MOVEMENT_SPEED);
            if (speed != null) {
                speed.removeModifier(UNSEEN_SPEED_ID);
            }
        }
    }
}
