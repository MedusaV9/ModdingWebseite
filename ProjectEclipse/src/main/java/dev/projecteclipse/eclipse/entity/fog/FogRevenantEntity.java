package dev.projecteclipse.eclipse.entity.fog;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoMonster;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityEvent;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.ai.attributes.AttributeSupplier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.ai.goal.FloatGoal;
import net.minecraft.world.entity.ai.goal.MeleeAttackGoal;
import net.minecraft.world.entity.ai.goal.RandomLookAroundGoal;
import net.minecraft.world.entity.ai.goal.RandomStrollGoal;
import net.minecraft.world.entity.ai.goal.target.HurtByTargetGoal;
import net.minecraft.world.entity.ai.goal.target.NearestAttackableTargetGoal;
import net.minecraft.world.entity.ai.util.DefaultRandomPos;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import software.bernie.geckolib.animation.AnimationController;

/**
 * Fog Revenant / Nebel-Wiedergänger — the tall fog-consumed wraith of the storm patches
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.3, P6-W7). 30 HP / 5 dmg / speed
 * 0.26; drops via the {@code eclipse:entities/fog_revenant} loot table (umbral shards +
 * fog-themed vanilla mats).
 *
 * <p><b>Phase-drift movement:</b> it walks the ground path net like any monster but is
 * never truly ON the ground — descent is clamped to a mist-settle
 * ({@value #DRIFT_FALL_SPEED}/t, no fall damage), so ledges and knockback turn into a
 * slow ghostly float instead of a drop. Its stroll goal ({@link DriftStrollGoal}) picks
 * short aimless legs at reduced speed for the drifting read; the {@code walk} animation
 * is a robe-trailing glide.</p>
 *
 * <p><b>Fog-blind burst</b> ({@link FogBlindBurstGoal}, priority above melee): every
 * 240–320 t with a target inside 6 blocks it channels 30 t (the {@code cast_blind}
 * one-shot raises both claws, the wisps flare) and detonates a r=5 AoE — Blindness 4 s +
 * Slowness II 3 s + a fog puff (Quasar cue with vanilla CLOUD backup). Melee is a claw
 * rake ({@code attack} one-shot from {@link #doHurtTarget}).</p>
 *
 * <p><b>Death:</b> scripted {@value #DEATH_ANIM_TICKS} t upward dispersal (the held
 * {@code death} anim folds the robe while the body rises into the wisps), soul wisps
 * escaping every few ticks, vanilla poof at the end — the renderer suppresses the
 * vanilla tip-over ({@code withUprightDeath()}).</p>
 */
public class FogRevenantEntity extends EclipseGeoMonster {
    /** Frozen §6 entity path — geo/anim/texture triple + animation ids key off this. */
    public static final String GEO_ID = "fog_revenant";
    /** Extra triggerable on the {@code action} controller: the 30 t blind-burst channel. */
    public static final String ANIM_CAST_BLIND = "cast_blind";
    /** Scripted death window (sheet: 40 t — disperse upward into wisps, upright). */
    public static final int DEATH_ANIM_TICKS = 40;
    /** Terminal mist-settle velocity — the wraith never falls faster than this. */
    private static final double DRIFT_FALL_SPEED = -0.06D;

    public FogRevenantEntity(EntityType<? extends FogRevenantEntity> entityType, Level level) {
        super(entityType, level);
    }

    /** Spec §2.3: 30 HP, dmg 5, speed 0.26; sturdy against shoving (a walking fog bank). */
    public static AttributeSupplier.Builder createAttributes() {
        return Monster.createMonsterAttributes()
                .add(Attributes.MAX_HEALTH, 30.0D)
                .add(Attributes.ATTACK_DAMAGE, 5.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.26D)
                .add(Attributes.FOLLOW_RANGE, 40.0D)
                .add(Attributes.KNOCKBACK_RESISTANCE, 0.4D);
    }

    // --- GeckoLib (frozen base-class hooks) ---

    @Override
    public String geoId() {
        return GEO_ID;
    }

    @Override
    protected void registerActionTriggers(AnimationController<?> action) {
        super.registerActionTriggers(action); // death (hold on last frame)
        action.triggerableAnim(EclipseGeoAnimations.ANIM_ATTACK,
                EclipseGeoAnimations.once(GEO_ID, EclipseGeoAnimations.ANIM_ATTACK));
        action.triggerableAnim(ANIM_CAST_BLIND, EclipseGeoAnimations.once(GEO_ID, ANIM_CAST_BLIND));
    }

    // --- AI ---

    @Override
    protected void registerGoals() {
        this.goalSelector.addGoal(0, new FloatGoal(this));
        this.goalSelector.addGoal(1, new FogBlindBurstGoal(this));
        this.goalSelector.addGoal(2, new MeleeAttackGoal(this, 1.1D, false));
        this.goalSelector.addGoal(6, new DriftStrollGoal(this));
        this.goalSelector.addGoal(7, new RandomLookAroundGoal(this));
        this.targetSelector.addGoal(1, new HurtByTargetGoal(this));
        this.targetSelector.addGoal(2, new NearestAttackableTargetGoal<>(this, Player.class, true));
    }

    // --- phase drift ---

    @Override
    public void tick() {
        super.tick();
        // Mist-settle: clamp any descent to a slow ghostly float (both sides — the
        // client clamps too so the interpolated fall never visibly overshoots).
        Vec3 movement = this.getDeltaMovement();
        if (!this.onGround() && movement.y < DRIFT_FALL_SPEED) {
            this.setDeltaMovement(movement.x, DRIFT_FALL_SPEED, movement.z);
        }
        this.fallDistance = 0.0F;
        if (this.level().isClientSide && this.isAlive() && this.random.nextInt(8) == 0) {
            // Fog sloughing off the robe hem.
            this.level().addParticle(ParticleTypes.CAMPFIRE_COSY_SMOKE,
                    this.getRandomX(0.6D), this.getY() + 0.15D + this.random.nextDouble() * 0.3D,
                    this.getRandomZ(0.6D), 0.0D, 0.012D, 0.0D);
        }
    }

    @Override
    public boolean causeFallDamage(float fallDistance, float multiplier, DamageSource source) {
        return false; // Fog does not land.
    }

    // --- combat/death hooks (GeckoLib one-shots) ---

    @Override
    public boolean doHurtTarget(Entity target) {
        boolean hurt = super.doHurtTarget(target);
        if (hurt && !this.level().isClientSide) {
            triggerAction(EclipseGeoAnimations.ANIM_ATTACK); // claw rake
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

    /** Scripted 40 t upward dispersal, then the vanilla poof (Ferryman precedent). */
    @Override
    protected void tickDeath() {
        this.deathTime++;
        if (!(this.level() instanceof ServerLevel serverLevel)) {
            return; // Client: the held death anim plays; deathTime is cosmetic here.
        }
        if (this.deathTime % 4 == 0) {
            serverLevel.sendParticles(ParticleTypes.SCULK_SOUL,
                    this.getX(), this.getY() + 1.0D + this.deathTime * 0.05D, this.getZ(),
                    2, 0.3D, 0.2D, 0.3D, 0.015D);
            serverLevel.sendParticles(ParticleTypes.CLOUD,
                    this.getX(), this.getY() + 0.4D, this.getZ(), 1, 0.25D, 0.1D, 0.25D, 0.01D);
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
        return SoundEvents.PHANTOM_AMBIENT; // Breathy rasp, pitched into a moan.
    }

    @Override
    public float getVoicePitch() {
        return 0.55F + this.random.nextFloat() * 0.1F;
    }

    @Override
    protected float getSoundVolume() {
        return 0.8F;
    }

    @Override
    @Nullable
    protected SoundEvent getHurtSound(DamageSource damageSource) {
        return SoundEvents.PHANTOM_HURT;
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return SoundEvents.PHANTOM_DEATH;
    }

    @Override
    protected void playStepSound(net.minecraft.core.BlockPos pos, net.minecraft.world.level.block.state.BlockState state) {
        // Hovers — no footsteps.
    }

    /**
     * Drift stroll: short aimless legs (≤ 6 blocks) at {@value #SPEED_FACTOR}× walk
     * speed on a quick repick interval, so an idle revenant wanders its fog patch in
     * slow arcs instead of marching vanilla-style toward distant points (sheet:
     * "hover-drift").
     */
    static class DriftStrollGoal extends RandomStrollGoal {
        private static final double SPEED_FACTOR = 0.8D;

        DriftStrollGoal(FogRevenantEntity revenant) {
            super(revenant, SPEED_FACTOR, 80);
        }

        @Override
        @Nullable
        protected Vec3 getPosition() {
            return DefaultRandomPos.getPos(this.mob, 6, 4);
        }
    }
}
