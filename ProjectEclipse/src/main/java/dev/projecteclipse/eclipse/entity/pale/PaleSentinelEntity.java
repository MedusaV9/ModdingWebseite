package dev.projecteclipse.eclipse.entity.pale;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoMonster;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.network.syncher.EntityDataAccessor;
import net.minecraft.network.syncher.EntityDataSerializers;
import net.minecraft.network.syncher.SynchedEntityData;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.tags.DamageTypeTags;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityEvent;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.ai.attributes.AttributeSupplier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.ai.goal.FloatGoal;
import net.minecraft.world.entity.ai.goal.MeleeAttackGoal;
import net.minecraft.world.entity.ai.goal.RandomLookAroundGoal;
import net.minecraft.world.entity.ai.goal.WaterAvoidingRandomStrollGoal;
import net.minecraft.world.entity.ai.goal.target.HurtByTargetGoal;
import net.minecraft.world.entity.ai.goal.target.NearestAttackableTargetGoal;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.AnimationState;
import software.bernie.geckolib.animation.PlayState;

/**
 * Pale Sentinel / Fahler Wächter — the Pale Garden's weeping-angel guardian
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.3, worker P6-W9/W910): a 2.4-block
 * gaunt birch-white tree-revenant that creeps toward players fast and jerky — and
 * freezes solid into a statue the instant ANY player looks at it.
 *
 * <p><b>Freeze mechanic (server-authoritative, rock-solid by construction):</b> every
 * tick {@link ObservedFreezeHelper} runs the FOV-cone + raycast-occlusion check; the
 * result drives the synced {@link #DATA_FROZEN} flag with asymmetric hysteresis —
 * <em>freeze is instant</em> the tick it is seen (a weeping angel must never take a step
 * on-screen) but <em>unfreezing needs {@value #UNSEEN_GRACE_TICKS} consecutive unseen
 * ticks</em>, so signal flicker at the player's screen edge keeps it frozen instead of
 * strobing. While frozen the sentinel is a true statue:</p>
 * <ul>
 *   <li>{@link #isImmobile()} returns true → vanilla skips {@code serverAiStep} outright
 *       (goals, navigation, move/look control all halt mid-state — no drift, ever);</li>
 *   <li>horizontal velocity is zeroed and the yaw/pitch snapshot from the freeze moment
 *       is re-asserted every tick (nothing can turn the statue);</li>
 *   <li>vanilla knockback is suppressed ({@link #knockback}) — hits produce only the
 *       controlled 1-block root-step flinch;</li>
 *   <li>bark hardens: non-bypass damage is halved ({@value #FROZEN_DAMAGE_FACTOR}×),
 *       answered with a pale petal burst + flinch backward;</li>
 *   <li>the {@code base} animation controller plays the held {@code freeze} statue pose
 *       (blended over {@link #baseTransitionTicks()} ticks — a dead stop, no snap);</li>
 *   <li>dread garnish: players within {@value #CREAK_RANGE} blocks hear faint private
 *       wood creaks at their ear every ~{@value #CREAK_INTERVAL_TICKS}t
 *       ({@code playNotifySound} — the {@code EclipseSpawner.howlAround} trick).</li>
 * </ul>
 *
 * <p>Unobserved it pursues at speed 0.45 (fast creep — the dread is looking away). 40 HP,
 * 6 dmg overhead double-claw. Night-only: by day with sky above it burrows over
 * {@value #BURROW_TICKS}t (bark-flake particles, sinks) and despawns. Death is a scripted
 * {@value #DEATH_ANIM_TICKS}t upright crumble. Drops via loot table
 * {@code eclipse:entities/pale_sentinel} (pale-oak stuff + phantom membrane) plus a
 * {@code pale_resin} P4-registry lookup (skipped while P4 hasn't landed it).</p>
 */
public class PaleSentinelEntity extends EclipseGeoMonster {
    /** Frozen §6 entity path — geo/anim/texture triple + animation ids key off this. */
    public static final String GEO_ID = "pale_sentinel";
    /** Statue-pose loop played on the {@code base} controller while observed. */
    public static final String ANIM_FREEZE = "freeze";
    /** Scripted death window (sheet: 35t crumble to a bark pile). */
    public static final int DEATH_ANIM_TICKS = 35;
    /** Consecutive unseen ticks required before a frozen sentinel may move again. */
    public static final int UNSEEN_GRACE_TICKS = 5;
    /** Damage multiplier while frozen (bark hardened; /kill-style bypasses ignore it). */
    public static final float FROZEN_DAMAGE_FACTOR = 0.5F;
    /** Day burrow-out duration (bark particles, sink, despawn). */
    public static final int BURROW_TICKS = 40;

    private static final int CREAK_INTERVAL_TICKS = 60;
    private static final double CREAK_RANGE = 8.0D;
    private static final double FLINCH_STRENGTH = 0.35D;

    /** True while observed (statue). Synced so the client plays the freeze pose. */
    private static final EntityDataAccessor<Boolean> DATA_FROZEN =
            SynchedEntityData.defineId(PaleSentinelEntity.class, EntityDataSerializers.BOOLEAN);

    /** Consecutive server ticks WITHOUT any observer (hysteresis counter). */
    private int unseenTicks;
    /** Yaw/pitch snapshot taken at the freeze moment, re-asserted while frozen. */
    private float frozenYaw;
    private float frozenPitch;
    private int creakTimer = CREAK_INTERVAL_TICKS;
    /** {@code -1} while active; counts up through the day burrow-out. */
    private int burrowTicks = -1;

    public PaleSentinelEntity(EntityType<? extends PaleSentinelEntity> entityType, Level level) {
        super(entityType, level);
        this.xpReward = 10;
    }

    /** Spec §2.3: 40 HP, dmg 6, unobserved pursuit speed 0.45 (deliberately fast). */
    public static AttributeSupplier.Builder createAttributes() {
        return Monster.createMonsterAttributes()
                .add(Attributes.MAX_HEALTH, 40.0D)
                .add(Attributes.ATTACK_DAMAGE, 6.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.45D)
                .add(Attributes.FOLLOW_RANGE, 40.0D)
                .add(Attributes.KNOCKBACK_RESISTANCE, 0.6D);
    }

    // --- GeckoLib (frozen base-class hooks) ---

    @Override
    public String geoId() {
        return GEO_ID;
    }

    /** Frozen → held statue pose; otherwise the default walk/idle switch. */
    @Override
    protected PlayState handleBaseState(AnimationState<?> state) {
        if (isFrozen()) {
            return state.setAndContinue(EclipseGeoAnimations.loop(GEO_ID, ANIM_FREEZE));
        }
        return super.handleBaseState(state);
    }

    /** Snappier blend so the dead stop reads within 3t (default 4). */
    @Override
    protected int baseTransitionTicks() {
        return 3;
    }

    @Override
    protected void registerActionTriggers(AnimationController<?> action) {
        super.registerActionTriggers(action); // death (played-and-held)
        action.triggerableAnim(EclipseGeoAnimations.ANIM_ATTACK,
                EclipseGeoAnimations.once(GEO_ID, EclipseGeoAnimations.ANIM_ATTACK));
    }

    // --- AI (plain goal kit; the freeze gates ALL of it at once via isImmobile) ---

    @Override
    protected void registerGoals() {
        this.goalSelector.addGoal(0, new FloatGoal(this));
        this.goalSelector.addGoal(3, new MeleeAttackGoal(this, 1.0D, true));
        this.goalSelector.addGoal(6, new WaterAvoidingRandomStrollGoal(this, 0.6D));
        this.goalSelector.addGoal(7, new RandomLookAroundGoal(this));
        this.targetSelector.addGoal(1, new HurtByTargetGoal(this));
        this.targetSelector.addGoal(2, new NearestAttackableTargetGoal<>(this, Player.class, true));
    }

    /**
     * The single freeze gate: while frozen, vanilla's {@code aiStep} zeroes all movement
     * input AND skips {@code serverAiStep} entirely — goals, navigation, move/look
     * control all halt mid-state. No per-goal gating can leak movement past this.
     */
    @Override
    protected boolean isImmobile() {
        return super.isImmobile() || isFrozen();
    }

    // --- frozen state ---

    public boolean isFrozen() {
        return this.entityData.get(DATA_FROZEN);
    }

    private void setFrozen(boolean frozen) {
        this.entityData.set(DATA_FROZEN, frozen);
    }

    @Override
    public void tick() {
        super.tick();
        if (this.level().isClientSide || !this.isAlive()
                || !(this.level() instanceof ServerLevel serverLevel)) {
            return;
        }
        if (tickDayBurrow(serverLevel)) {
            return;
        }
        tickObservedFreeze(serverLevel);
    }

    /**
     * Per-tick sensing + asymmetric hysteresis: observed → frozen NOW (and the unseen
     * counter resets); unobserved → only after {@value #UNSEEN_GRACE_TICKS} consecutive
     * clear ticks does it thaw. Signal flicker at a screen edge therefore holds the
     * statue instead of strobing it (P6-W9 acceptance #2).
     */
    private void tickObservedFreeze(ServerLevel serverLevel) {
        boolean observed = ObservedFreezeHelper.isObservedByAnyPlayer(serverLevel, this);
        if (observed) {
            this.unseenTicks = 0;
            if (!isFrozen()) {
                freezeNow();
            }
        } else if (isFrozen() && ++this.unseenTicks >= UNSEEN_GRACE_TICKS) {
            setFrozen(false);
            EclipseMod.LOGGER.debug("Pale Sentinel {} thawed after {} unseen ticks",
                    this.getId(), this.unseenTicks);
        }
        if (isFrozen()) {
            holdStatuePose(serverLevel);
        }
    }

    /** The dead stop: kill motion, stop pathing, snapshot the pose rotations. */
    private void freezeNow() {
        setFrozen(true);
        this.getNavigation().stop();
        Vec3 velocity = this.getDeltaMovement();
        this.setDeltaMovement(0.0D, Math.min(velocity.y, 0.0D), 0.0D);
        this.setJumping(false);
        this.frozenYaw = this.getYRot();
        this.frozenPitch = this.getXRot();
        this.creakTimer = CREAK_INTERVAL_TICKS / 2;
    }

    /** Re-asserts the frozen rotations every tick + the private creak channel. */
    private void holdStatuePose(ServerLevel serverLevel) {
        this.setYRot(this.frozenYaw);
        this.yBodyRot = this.frozenYaw;
        this.yHeadRot = this.frozenYaw;
        this.setXRot(this.frozenPitch);
        if (--this.creakTimer <= 0) {
            this.creakTimer = CREAK_INTERVAL_TICKS + this.random.nextInt(20);
            for (ServerPlayer player : serverLevel.players()) {
                if (!player.isSpectator() && player.isAlive()
                        && player.distanceToSqr(this) <= CREAK_RANGE * CREAK_RANGE) {
                    // Private sound AT the player's ear (howlAround trick): the statue
                    // is silent, yet the wood creaks right beside you.
                    player.playNotifySound(SoundEvents.WOOD_STEP, SoundSource.HOSTILE,
                            0.6F, 0.45F + this.random.nextFloat() * 0.1F);
                }
            }
        }
    }

    // --- frozen-hit reaction (bark hardened + petal burst + root-step flinch) ---

    @Override
    public boolean hurt(DamageSource source, float amount) {
        boolean wasFrozen = isFrozen() && !this.level().isClientSide
                && !source.is(DamageTypeTags.BYPASSES_INVULNERABILITY);
        if (wasFrozen) {
            amount *= FROZEN_DAMAGE_FACTOR;
        }
        boolean hurt = super.hurt(source, amount);
        if (hurt && wasFrozen && this.isAlive() && this.level() instanceof ServerLevel serverLevel) {
            petalBurstAndFlinch(serverLevel, source);
        }
        return hurt;
    }

    /** While frozen, all knockback is replaced by the controlled root-step flinch. */
    @Override
    public void knockback(double strength, double x, double z) {
        if (!isFrozen()) {
            super.knockback(strength, x, z);
        }
    }

    /** Pale petal burst + a 1-block root-step flinch away from the attacker (spec §2.3). */
    private void petalBurstAndFlinch(ServerLevel serverLevel, DamageSource source) {
        serverLevel.sendParticles(ParticleTypes.CHERRY_LEAVES,
                this.getX(), this.getY() + 1.6D, this.getZ(), 10, 0.5D, 0.8D, 0.5D, 0.02D);
        serverLevel.sendParticles(ParticleTypes.WHITE_ASH,
                this.getX(), this.getY() + 1.2D, this.getZ(), 16, 0.4D, 0.9D, 0.4D, 0.05D);
        serverLevel.playSound(null, this.blockPosition(), SoundEvents.WOOD_BREAK,
                SoundSource.HOSTILE, 0.8F, 0.5F);
        Entity attacker = source.getEntity();
        Vec3 away;
        if (attacker != null && attacker != this) {
            away = this.position().subtract(attacker.position()).multiply(1.0D, 0.0D, 1.0D);
        } else {
            away = new Vec3(-Math.sin(this.frozenYaw * ((float) Math.PI / 180.0F)), 0.0D,
                    Math.cos(this.frozenYaw * ((float) Math.PI / 180.0F))).scale(-1.0D);
        }
        if (away.lengthSqr() > 1.0E-4D) {
            Vec3 flinch = away.normalize().scale(FLINCH_STRENGTH);
            this.setDeltaMovement(flinch.x, 0.08D, flinch.z);
        }
    }

    // --- combat ---

    @Override
    public boolean doHurtTarget(Entity target) {
        boolean hurt = super.doHurtTarget(target);
        if (hurt && !this.level().isClientSide) {
            triggerAction(EclipseGeoAnimations.ANIM_ATTACK); // overhead double-claw
            this.level().playSound(null, this.blockPosition(), SoundEvents.WOOD_HIT,
                    SoundSource.HOSTILE, 1.0F, 0.5F);
        }
        return hurt;
    }

    // --- night gate: day burrow-out (spec §2.3 "day → burrows") ---

    /** Returns true while the burrow sequence owns the tick. */
    private boolean tickDayBurrow(ServerLevel serverLevel) {
        boolean daylit = serverLevel.isDay() && serverLevel.canSeeSky(this.blockPosition());
        if (this.burrowTicks < 0) {
            if (!daylit) {
                return false;
            }
            this.burrowTicks = 0;
            this.getNavigation().stop();
            setFrozen(false);
            EclipseMod.LOGGER.info("Pale Sentinel {} caught by daylight at {} — burrowing out over {}t",
                    this.getId(), this.blockPosition().toShortString(), BURROW_TICKS);
        } else if (!daylit) {
            this.burrowTicks = -1; // /time set night mid-burrow: resume the vigil.
            return false;
        }
        // Sink into the loam under a shroud of bark flakes and pale motes.
        this.setDeltaMovement(0.0D, -0.045D, 0.0D);
        this.noPhysics = true;
        if (this.burrowTicks % 4 == 0) {
            serverLevel.sendParticles(ParticleTypes.WHITE_ASH,
                    this.getX(), this.getY() + 1.0D, this.getZ(), 8, 0.35D, 0.9D, 0.35D, 0.03D);
            serverLevel.sendParticles(ParticleTypes.SPORE_BLOSSOM_AIR,
                    this.getX(), this.getY() + 0.4D, this.getZ(), 3, 0.3D, 0.3D, 0.3D, 0.0D);
        }
        if (this.burrowTicks % 8 == 0) {
            serverLevel.playSound(null, this.blockPosition(), SoundEvents.ROOTED_DIRT_BREAK,
                    SoundSource.HOSTILE, 0.7F, 0.7F);
        }
        if (++this.burrowTicks >= BURROW_TICKS) {
            serverLevel.sendParticles(ParticleTypes.WHITE_ASH,
                    this.getX(), this.getY() + 0.5D, this.getZ(), 24, 0.5D, 0.4D, 0.5D, 0.05D);
            this.discard();
        }
        return true;
    }

    // --- death (scripted upright crumble; renderer suppresses the vanilla flip) ---

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
            serverLevel.sendParticles(ParticleTypes.WHITE_ASH,
                    this.getX(), this.getY() + 1.0D, this.getZ(), 10, 0.4D, 0.8D, 0.4D, 0.04D);
            serverLevel.playSound(null, this.blockPosition(), SoundEvents.WOOD_STEP,
                    SoundSource.HOSTILE, 0.8F, 0.4F);
        }
        if (this.deathTime >= DEATH_ANIM_TICKS && !this.isRemoved()) {
            serverLevel.playSound(null, this.blockPosition(), SoundEvents.WOOD_BREAK,
                    SoundSource.HOSTILE, 1.0F, 0.4F);
            serverLevel.broadcastEntityEvent(this, EntityEvent.POOF);
            this.remove(RemovalReason.KILLED);
        }
    }

    /** P4 economy hook: pale_resin by registry lookup, skipped while unregistered. */
    @Override
    protected void dropCustomDeathLoot(ServerLevel level, DamageSource damageSource, boolean recentlyHit) {
        super.dropCustomDeathLoot(level, damageSource, recentlyHit);
        net.minecraft.core.registries.BuiltInRegistries.ITEM.getOptional(
                        net.minecraft.resources.ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "pale_resin"))
                .ifPresentOrElse(
                        item -> this.spawnAtLocation(new net.minecraft.world.item.ItemStack(item, 2)),
                        () -> EclipseMod.LOGGER.debug(
                                "Pale Sentinel drop: eclipse:pale_resin not registered yet (P4) — skipped"));
    }

    // --- sounds (statues are silent; the moving thing barely creaks) ---

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return isFrozen() ? null : SoundEvents.WOOD_STEP;
    }

    @Override
    public int getAmbientSoundInterval() {
        return 200;
    }

    @Override
    public float getVoicePitch() {
        return 0.45F + this.random.nextFloat() * 0.1F;
    }

    @Override
    protected SoundEvent getHurtSound(DamageSource damageSource) {
        return SoundEvents.WOOD_HIT;
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return SoundEvents.WOOD_BREAK;
    }

    @Override
    public boolean isPushable() {
        return !isFrozen(); // Nothing shoves a rooted statue.
    }

    // --- boilerplate ---

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
        super.defineSynchedData(builder);
        builder.define(DATA_FROZEN, false);
    }

    /** Helper for {@link Mob} anti-cheese checks and tests: current freeze state. */
    public boolean isStatue() {
        return isFrozen();
    }
}
