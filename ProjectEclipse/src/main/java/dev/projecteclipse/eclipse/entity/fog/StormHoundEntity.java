package dev.projecteclipse.eclipse.entity.fog;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoMonster;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityEvent;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.ai.attributes.AttributeSupplier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.ai.goal.FloatGoal;
import net.minecraft.world.entity.ai.goal.LeapAtTargetGoal;
import net.minecraft.world.entity.ai.goal.MeleeAttackGoal;
import net.minecraft.world.entity.ai.goal.RandomLookAroundGoal;
import net.minecraft.world.entity.ai.goal.WaterAvoidingRandomStrollGoal;
import net.minecraft.world.entity.ai.goal.target.HurtByTargetGoal;
import net.minecraft.world.entity.ai.goal.target.NearestAttackableTargetGoal;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.AnimationState;
import software.bernie.geckolib.animation.PlayState;
import software.bernie.geckolib.animation.RawAnimation;

/**
 * Storm Hound / Sturmhund — the charged lunge pack hunter of the fog storms
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.3, P6-W7). 24 HP / 4 dmg / speed
 * 0.34; drops via the {@code eclipse:entities/storm_hound} loot table.
 *
 * <p><b>Pack kit</b> (Umbral Stalker precedent): leap, persistent melee (1.3, true), and
 * {@code HurtByTargetGoal().setAlertOthers()} — hit one hound and the whole pack turns.
 * W6's spawn rules place them in packs of 2–3.</p>
 *
 * <p><b>Locomotion:</b> the {@code base} controller runs three loops — idle, a diagonal
 * trot ({@code walk}) and a true gallop ({@code sprint}, two suspension phases) gated on
 * {@link #isAggressive()}. A stroll reads as a trot, a hunt reads as a gallop; the gate
 * is latched client-side so it cannot flicker mid-stride
 * (see {@link #handleBaseState}).</p>
 *
 * <p><b>Charged lunge</b> ({@link ChargedLungeGoal}): with a target 6–14 blocks out,
 * line of sight and the 160 t cooldown up, it roots for a 20 t windup (the
 * {@code charge_windup} one-shot crouches the body while the {@code glow_spine} shards
 * scale up = the glowmask visibly ramps) and then dashes a straight 12-block line at
 * 0.9 blocks/t. First entity clipped takes 6 dmg + Slowness IV 1 s ("static-locked") in
 * an ELECTRIC_SPARK burst; a whiffed dash self-staggers the hound for 2 s
 * (counterplay — sidestep the telegraphed line and punish).</p>
 *
 * <p><b>Howl:</b> one-shot {@code howl} the first time it acquires a target after
 * spawn/load (the Fog Colossus roar pattern) — head thrown back, storm-mane flared,
 * spine glow pulsing. Cosmetic only, deliberately not persisted to NBT (re-howls once
 * per load at worst); the pack-alert mechanics stay entirely on
 * {@code HurtByTargetGoal.setAlertOthers()}.</p>
 *
 * <p><b>Death:</b> scripted {@value #DEATH_ANIM_TICKS} t side collapse (the held
 * {@code death} anim rolls the root while the spine shards flicker out — the renderer's
 * {@code withUprightDeath()} suppresses the vanilla flip so the authored fall is the
 * only rotation), spark sputters, vanilla poof at the end.</p>
 */
public class StormHoundEntity extends EclipseGeoMonster {
    /** Frozen §6 entity path — geo/anim/texture triple + animation ids key off this. */
    public static final String GEO_ID = "storm_hound";
    /** Extra triggerables on the {@code action} controller (lunge sequence + howl). */
    public static final String ANIM_CHARGE_WINDUP = "charge_windup";
    public static final String ANIM_LUNGE = "lunge";
    public static final String ANIM_HOWL = "howl";
    /** Second locomotion loop on the {@code base} controller — the hunting gallop. */
    public static final String ANIM_SPRINT = "sprint";
    /** Scripted death window (sheet: side collapse + spine flicker-out). */
    public static final int DEATH_ANIM_TICKS = 30;
    /** Client-side gallop hold — see {@link #updateSprintGate()}. */
    private static final int SPRINT_HOLD_TICKS = 8;

    private boolean howled;
    private RawAnimation cachedSprintAnim;
    /** Client-only gallop latch (ticks remaining); never read or written server-side. */
    private int sprintHold;

    public StormHoundEntity(EntityType<? extends StormHoundEntity> entityType, Level level) {
        super(entityType, level);
    }

    /** Spec §2.3: 24 HP, dmg 4, speed 0.34. */
    public static AttributeSupplier.Builder createAttributes() {
        return Monster.createMonsterAttributes()
                .add(Attributes.MAX_HEALTH, 24.0D)
                .add(Attributes.ATTACK_DAMAGE, 4.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.34D)
                .add(Attributes.FOLLOW_RANGE, 40.0D);
    }

    // --- GeckoLib (frozen base-class hooks) ---

    @Override
    public String geoId() {
        return GEO_ID;
    }

    /**
     * Three-state locomotion on the frozen {@code base} controller: idle, the diagonal
     * trot ({@code walk}) and the hunting gallop ({@code sprint}) — no third controller.
     * The gallop gate is {@link #isAggressive()} (set by {@code MeleeAttackGoal}, synced
     * on the vanilla living-entity flag byte, so the client can read it) held open by the
     * {@link #updateSprintGate()} latch.
     */
    @Override
    protected PlayState handleBaseState(AnimationState<?> state) {
        if (!state.isMoving()) {
            return state.setAndContinue(idleAnim());
        }
        return state.setAndContinue(this.sprintHold > 0 ? sprintAnim() : walkAnim());
    }

    /** Cached {@code animation.storm_hound.sprint} loop (gallop with two flight phases). */
    private RawAnimation sprintAnim() {
        if (cachedSprintAnim == null) {
            cachedSprintAnim = EclipseGeoAnimations.loop(GEO_ID, ANIM_SPRINT);
        }
        return cachedSprintAnim;
    }

    /**
     * Client-side hysteresis on the gallop gate. {@code MeleeAttackGoal} clears
     * {@code isAggressive()} for a tick whenever {@code LeapAtTargetGoal} preempts it or
     * the path is recomputed; without the {@value #SPRINT_HOLD_TICKS} t latch the base
     * controller would flip trot/gallop mid-stride and re-blend every time.
     */
    private void updateSprintGate() {
        if (this.isAggressive() && this.isAlive()) {
            this.sprintHold = SPRINT_HOLD_TICKS;
        } else if (this.sprintHold > 0) {
            this.sprintHold--;
        }
    }

    @Override
    protected void registerActionTriggers(AnimationController<?> action) {
        super.registerActionTriggers(action); // death (hold on last frame)
        action.triggerableAnim(EclipseGeoAnimations.ANIM_ATTACK,
                EclipseGeoAnimations.once(GEO_ID, EclipseGeoAnimations.ANIM_ATTACK));
        action.triggerableAnim(ANIM_CHARGE_WINDUP, EclipseGeoAnimations.once(GEO_ID, ANIM_CHARGE_WINDUP));
        action.triggerableAnim(ANIM_LUNGE, EclipseGeoAnimations.once(GEO_ID, ANIM_LUNGE));
        action.triggerableAnim(ANIM_HOWL, EclipseGeoAnimations.once(GEO_ID, ANIM_HOWL));
    }

    /**
     * POLISH2 (contract v2): only the bite blends — it fires out of {@code sprint}
     * (worst single-frame snap 52.0° on {@code leg_fl.rotx} → 17.3°/frame with 3 t)
     * after the damage already landed ({@code doHurtTarget} / lunge strike), so the 3 t
     * clip delay is cosmetic follow-through. Everything else MUST stay hard:
     * {@code charge_windup} is frame-exact against {@code ChargedLungeGoal}'s 20 t
     * windup AND the 20 t Photon collapsing-spiral cue ({@code CUE_HOUND_WINDUP});
     * {@code lunge} is motion-locked (dash velocity starts on the trigger tick);
     * {@code howl} is a notice-style cue with its sound on the trigger tick;
     * {@code death} feeds the scripted 30 t {@link #tickDeath} window.
     */
    @Override
    protected int actionTransitionTicks(String animName) {
        return EclipseGeoAnimations.ANIM_ATTACK.equals(animName) ? 3 : 0;
    }

    /** Howl one-shot on the FIRST target acquisition (Fog Colossus roar pattern). */
    @Override
    public void setTarget(@Nullable LivingEntity target) {
        if (target != null && this.getTarget() == null && !this.howled
                && !this.level().isClientSide && this.isAlive()) {
            this.howled = true;
            triggerAction(ANIM_HOWL);
            this.playSound(SoundEvents.WOLF_HOWL, 1.2F, 0.75F);
        }
        super.setTarget(target);
    }

    // --- AI (stalker pack kit + the charged lunge) ---

    @Override
    protected void registerGoals() {
        this.goalSelector.addGoal(0, new FloatGoal(this));
        this.goalSelector.addGoal(2, new ChargedLungeGoal(this));
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
        if (this.level().isClientSide) {
            updateSprintGate();
        }
        if (this.level().isClientSide && this.isAlive() && this.random.nextInt(14) == 0) {
            // Ambient static crackle off the spine shards.
            this.level().addParticle(ParticleTypes.ELECTRIC_SPARK,
                    this.getRandomX(0.5D), this.getY() + 0.75D + this.random.nextDouble() * 0.25D,
                    this.getRandomZ(0.5D), 0.0D, 0.02D, 0.0D);
        }
    }

    // --- combat/death hooks (GeckoLib one-shots) ---

    @Override
    public boolean doHurtTarget(Entity target) {
        boolean hurt = super.doHurtTarget(target);
        if (hurt && !this.level().isClientSide) {
            triggerAction(EclipseGeoAnimations.ANIM_ATTACK); // bite
            this.level().playSound(null, this.blockPosition(), SoundEvents.WOLF_GROWL,
                    SoundSource.HOSTILE, 0.9F, 1.3F);
        }
        return hurt;
    }

    @Override
    public void die(DamageSource damageSource) {
        super.die(damageSource);
        if (!this.level().isClientSide) {
            triggerAction(EclipseGeoAnimations.ANIM_DEATH);
        }
    }

    /** Scripted 30 t side collapse with spark sputters, then the vanilla poof. */
    @Override
    protected void tickDeath() {
        this.deathTime++;
        if (!(this.level() instanceof ServerLevel serverLevel)) {
            return; // Client: the held death anim plays; deathTime is cosmetic here.
        }
        if (this.deathTime % 5 == 0) {
            serverLevel.sendParticles(ParticleTypes.ELECTRIC_SPARK,
                    this.getX(), this.getY() + 0.5D, this.getZ(), 3, 0.4D, 0.2D, 0.4D, 0.04D);
        }
        if (this.deathTime >= DEATH_ANIM_TICKS && !this.isRemoved()) {
            serverLevel.broadcastEntityEvent(this, EntityEvent.POOF);
            this.remove(RemovalReason.KILLED);
        }
    }

    // --- presentation ---

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return SoundEvents.WOLF_GROWL; // Deep charged growl (stalker precedent, own pitch).
    }

    @Override
    public float getVoicePitch() {
        return 0.7F + this.random.nextFloat() * 0.1F;
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
}
