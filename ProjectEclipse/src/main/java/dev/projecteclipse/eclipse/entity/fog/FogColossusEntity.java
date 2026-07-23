package dev.projecteclipse.eclipse.entity.fog;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoMonster;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityEvent;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LivingEntity;
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
import net.minecraft.world.level.block.state.BlockState;
import net.neoforged.neoforge.network.PacketDistributor;
import software.bernie.geckolib.animation.AnimationController;

/**
 * Fog Colossus / Nebelkoloss — the rare heavy elite inside fog storms
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.3, P6-W8). A 3.4-block
 * round-shouldered brute of cracked storm slate overgrown by fog coral; walks
 * half-gorilla on massive flat-knuckle arms. 80 HP / 10 dmg / speed 0.22 / KB resist
 * 1.0; drops via the {@code eclipse:entities/fog_colossus} loot table (umbral shards +
 * rare Mending book; the planned {@code fog_essence} entries follow once P4 registers
 * the item — §2.3 fallback rule).
 *
 * <p><b>Ground slam</b> ({@link GroundSlamGoal}, priority above melee): every ~200 t
 * with a target inside {@value GroundSlamGoal#TRIGGER_RANGE} blocks it roots in place
 * and raises both arms for {@value GroundSlamGoal#IMPACT_TICK} t (the {@code slam}
 * one-shot — fissures flare with the pose), then hammers the ground: r=6 shockwave,
 * 8 dmg at the core with distance falloff, launch + Slowness. The shockwave hugs the
 * ground — jumping while outside r=3 clears it entirely (plan: "jumpable").</p>
 *
 * <p><b>Roar:</b> one-shot {@code roar} the first time it acquires a target after
 * spawn/load — the storm announcing its elite. Cosmetic only, deliberately not
 * persisted to NBT (re-roars once per load at worst).</p>
 *
 * <p><b>Death:</b> scripted {@value #DEATH_ANIM_TICKS} t forward collapse (renderer
 * suppresses the vanilla tip-over via {@code withUprightDeath()}); when the body hits
 * the ground at t={@value #DEATH_IMPACT_TICK} nearby players get
 * {@code S2CShakePayload.shake(0.6f, 15)} plus a dust-ring stamp.</p>
 */
public class FogColossusEntity extends EclipseGeoMonster {
    /** Frozen §6 entity path — geo/anim/texture triple + animation ids key off this. */
    public static final String GEO_ID = "fog_colossus";
    /** Extra triggerables on the {@code action} controller (sheet anim set). */
    public static final String ANIM_SLAM = "slam";
    public static final String ANIM_ROAR = "roar";
    /** Scripted death window (sheet: 50 t forward collapse). */
    public static final int DEATH_ANIM_TICKS = 50;
    /** Death-anim keyframe where the torso lands (1.4 s) — shake + dust fire here. */
    private static final int DEATH_IMPACT_TICK = 28;
    /** Sheet: death screen-shake for players near the collapse. */
    private static final float DEATH_SHAKE_STRENGTH = 0.6F;
    private static final int DEATH_SHAKE_TICKS = 15;
    private static final double DEATH_SHAKE_RANGE = 24.0D;

    private boolean roared;

    public FogColossusEntity(EntityType<? extends FogColossusEntity> entityType, Level level) {
        super(entityType, level);
    }

    /** Spec §2.3: 80 HP, dmg 10, speed 0.22, KB resist 1.0 — an unshovable wall. */
    public static AttributeSupplier.Builder createAttributes() {
        return Monster.createMonsterAttributes()
                .add(Attributes.MAX_HEALTH, 80.0D)
                .add(Attributes.ATTACK_DAMAGE, 10.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.22D)
                .add(Attributes.KNOCKBACK_RESISTANCE, 1.0D)
                .add(Attributes.FOLLOW_RANGE, 40.0D)
                .add(Attributes.ATTACK_KNOCKBACK, 1.5D)
                .add(Attributes.STEP_HEIGHT, 1.1D);
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
        action.triggerableAnim(ANIM_SLAM, EclipseGeoAnimations.once(GEO_ID, ANIM_SLAM));
        action.triggerableAnim(ANIM_ROAR, EclipseGeoAnimations.once(GEO_ID, ANIM_ROAR));
    }

    // --- AI ---

    @Override
    protected void registerGoals() {
        this.goalSelector.addGoal(0, new FloatGoal(this));
        this.goalSelector.addGoal(1, new GroundSlamGoal(this));
        this.goalSelector.addGoal(2, new MeleeAttackGoal(this, 1.0D, true));
        this.goalSelector.addGoal(6, new RandomStrollGoal(this, 0.7D, 160));
        this.goalSelector.addGoal(7, new RandomLookAroundGoal(this));
        this.targetSelector.addGoal(1, new HurtByTargetGoal(this));
        this.targetSelector.addGoal(2, new NearestAttackableTargetGoal<>(this, Player.class, true));
    }

    /** Roar one-shot on the FIRST target acquisition (sheet: "roar — trigger on first target"). */
    @Override
    public void setTarget(@Nullable LivingEntity target) {
        if (target != null && this.getTarget() == null && !this.roared
                && !this.level().isClientSide && this.isAlive()) {
            this.roared = true;
            triggerAction(ANIM_ROAR);
            this.playSound(SoundEvents.RAVAGER_ROAR, 1.6F, 0.55F);
        }
        super.setTarget(target);
    }

    // --- combat/death hooks (GeckoLib one-shots) ---

    @Override
    public boolean doHurtTarget(Entity target) {
        boolean hurt = super.doHurtTarget(target);
        if (hurt && !this.level().isClientSide) {
            triggerAction(EclipseGeoAnimations.ANIM_ATTACK); // flat-knuckle backhand
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

    /** Scripted 50 t forward collapse; ground-shake + dust when the torso lands. */
    @Override
    protected void tickDeath() {
        this.deathTime++;
        if (!(this.level() instanceof ServerLevel serverLevel)) {
            return; // Client: the held death anim plays; deathTime is cosmetic here.
        }
        if (this.deathTime == DEATH_IMPACT_TICK) {
            PacketDistributor.sendToPlayersNear(serverLevel, null,
                    this.getX(), this.getY(), this.getZ(), DEATH_SHAKE_RANGE,
                    S2CShakePayload.shake(DEATH_SHAKE_STRENGTH, DEATH_SHAKE_TICKS));
            serverLevel.playSound(null, this.blockPosition(),
                    SoundEvents.GENERIC_EXPLODE.value(), SoundSource.HOSTILE, 0.7F, 0.5F);
            stampDustRing(serverLevel, 3.0D, 24);
        }
        if (this.deathTime % 6 == 0 && this.deathTime < DEATH_IMPACT_TICK) {
            // Fissure light bleeding out while it keels over.
            serverLevel.sendParticles(ParticleTypes.WHITE_ASH,
                    this.getX(), this.getY() + 1.8D, this.getZ(), 4, 0.7D, 0.9D, 0.7D, 0.01D);
        }
        if (this.deathTime >= DEATH_ANIM_TICKS && !this.isRemoved()) {
            serverLevel.broadcastEntityEvent(this, EntityEvent.POOF);
            this.remove(RemovalReason.KILLED);
        }
    }

    /** Ground-hugging smoke ring around the colossus (slam + death impact stamp). */
    void stampDustRing(ServerLevel serverLevel, double radius, int count) {
        for (int i = 0; i < count; i++) {
            double angle = (Math.PI * 2.0D / count) * i;
            serverLevel.sendParticles(ParticleTypes.CAMPFIRE_COSY_SMOKE,
                    this.getX() + Mth.cos((float) angle) * radius, this.getY() + 0.2D,
                    this.getZ() + Mth.sin((float) angle) * radius,
                    1, 0.1D, 0.05D, 0.1D, 0.02D);
        }
    }

    // --- presentation ---

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return SoundEvents.RAVAGER_AMBIENT; // Grinding stone breath.
    }

    @Override
    public float getVoicePitch() {
        return 0.5F + this.random.nextFloat() * 0.1F;
    }

    @Override
    protected float getSoundVolume() {
        return 1.4F;
    }

    @Override
    @Nullable
    protected SoundEvent getHurtSound(DamageSource damageSource) {
        return SoundEvents.RAVAGER_HURT;
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return SoundEvents.RAVAGER_DEATH;
    }

    @Override
    protected void playStepSound(BlockPos pos, BlockState state) {
        this.playSound(SoundEvents.RAVAGER_STEP, 0.5F, 0.6F); // Knuckle-and-stump gait.
    }
}
