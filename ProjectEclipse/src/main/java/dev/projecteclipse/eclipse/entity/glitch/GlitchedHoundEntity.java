package dev.projecteclipse.eclipse.entity.glitch;

import javax.annotation.Nullable;

import net.minecraft.core.BlockPos;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.ai.attributes.AttributeSupplier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.ai.goal.FloatGoal;
import net.minecraft.world.entity.ai.goal.LeapAtTargetGoal;
import net.minecraft.world.entity.ai.goal.MeleeAttackGoal;
import net.minecraft.world.entity.ai.goal.RandomLookAroundGoal;
import net.minecraft.world.entity.ai.goal.RandomStrollGoal;
import net.minecraft.world.entity.ai.goal.target.HurtByTargetGoal;
import net.minecraft.world.entity.ai.goal.target.NearestAttackableTargetGoal;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.state.BlockState;

/**
 * Glitched Hound / Glitch-Hund — the fast quadruped corruption of the fresh map rings
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.3 "glitched", kind HOUND; stalker
 * proportions with datamosh offsets — the head floats detached inside a fragmented neck
 * segment, the jaw arrives before the skull). 24 HP / 4 dmg / speed 0.35; loot:
 * {@code eclipse:entities/glitched_hound} (corrupted vanilla scraps) + 1–2
 * {@code glitch_shard} from the shared {@code GlitchDrops} tag hook.
 *
 * <p><b>Teleport-stutter:</b> the shared {@link GlitchedMonster} blink on the hound's
 * aggressive cadence — every 120–200 t (the plan's "every few seconds") it drops a
 * frame and re-renders up to 4 blocks away, which mid-chase reads as the world losing
 * track of it. Combined with {@link LeapAtTargetGoal} pounces, closing the last blocks
 * is its whole design.</p>
 */
public class GlitchedHoundEntity extends GlitchedMonster {
    /** Frozen §6 entity path — geo/anim/texture triple + animation ids key off this. */
    public static final String GEO_ID = "glitched_hound";
    /** Scripted death window (anim file: 1.5 s freeze-then-side-collapse). */
    public static final int DEATH_ANIM_TICKS = 30;

    public GlitchedHoundEntity(EntityType<? extends GlitchedHoundEntity> entityType, Level level) {
        super(entityType, level);
    }

    /** Spec §2.3 kind stats: HOUND 24 HP / 4 dmg / 0.35. */
    public static AttributeSupplier.Builder createAttributes() {
        return Monster.createMonsterAttributes()
                .add(Attributes.MAX_HEALTH, 24.0D)
                .add(Attributes.ATTACK_DAMAGE, 4.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.35D)
                .add(Attributes.FOLLOW_RANGE, 35.0D);
    }

    // --- GeckoLib / kind knobs ---

    @Override
    public String geoId() {
        return GEO_ID;
    }

    @Override
    protected int blinkCooldownMinTicks() {
        return 120;
    }

    @Override
    protected int blinkCooldownMaxTicks() {
        return 200;
    }

    @Override
    protected int deathAnimTicks() {
        return DEATH_ANIM_TICKS;
    }

    // --- AI ---

    @Override
    protected void registerGoals() {
        this.goalSelector.addGoal(0, new FloatGoal(this));
        this.goalSelector.addGoal(2, new LeapAtTargetGoal(this, 0.4F));
        this.goalSelector.addGoal(3, new MeleeAttackGoal(this, 1.2D, true));
        this.goalSelector.addGoal(6, new RandomStrollGoal(this, 0.9D, 80));
        this.goalSelector.addGoal(7, new RandomLookAroundGoal(this));
        this.targetSelector.addGoal(1, new HurtByTargetGoal(this));
        this.targetSelector.addGoal(2, new NearestAttackableTargetGoal<>(this, Player.class, true));
    }

    // --- presentation ---

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return SoundEvents.WOLF_GROWL; // A growl chopped into misplaced frames.
    }

    @Override
    public float getVoicePitch() {
        return 0.7F + this.random.nextFloat() * 0.6F; // Unstable playback rate.
    }

    @Override
    @Nullable
    protected SoundEvent getHurtSound(DamageSource damageSource) {
        return SoundEvents.WOLF_HURT;
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return SoundEvents.WOLF_DEATH;
    }

    @Override
    protected void playStepSound(BlockPos pos, BlockState state) {
        this.playSound(SoundEvents.WOLF_STEP, 0.15F, 1.2F);
    }
}
