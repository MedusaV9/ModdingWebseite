package dev.projecteclipse.eclipse.entity;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoMonster;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.network.syncher.EntityDataAccessor;
import net.minecraft.network.syncher.EntityDataSerializers;
import net.minecraft.network.syncher.SynchedEntityData;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityEvent;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.ai.goal.FloatGoal;
import net.minecraft.world.entity.ai.goal.LeapAtTargetGoal;
import net.minecraft.world.entity.ai.goal.MeleeAttackGoal;
import net.minecraft.world.entity.ai.goal.RandomLookAroundGoal;
import net.minecraft.world.entity.ai.goal.WaterAvoidingRandomStrollGoal;
import net.minecraft.world.entity.ai.goal.target.HurtByTargetGoal;
import net.minecraft.world.entity.ai.goal.target.NearestAttackableTargetGoal;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.AnimationState;
import software.bernie.geckolib.animation.PlayState;
import software.bernie.geckolib.animation.RawAnimation;

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
 *
 * <p><b>GeckoLib (MC2 conversion).</b> Renders through
 * {@code client/entity/stalker/UmbralStalkerGeoRenderer} off the {@value #GEO_ID} asset
 * triple. The mob is read almost entirely off its SILHOUETTE (it hunts at light 0), so
 * the {@code base} controller runs a four-state posture machine instead of the frozen
 * idle/walk pair — see {@link #handleBaseState}:</p>
 * <ul>
 *   <li>{@code crawl} — the calm double gait: a deep, belly-low four-beat prowl
 *       ({@link #walkAnim()} substitutes it for the frozen {@code walk}).</li>
 *   <li>{@code sprint} — the hunt gait: an explosive bounding gallop, shoulder hump
 *       pumping. Gated on the {@link #isAggressive()} / {@link #isFleeing()} latch.</li>
 *   <li>{@code stalk_low} — aggro but stationary: the crouched lurk. This is the pose the
 *       player is meant to spot across a dark field before it commits.</li>
 *   <li>{@code idle} — calm and stationary.</li>
 * </ul>
 *
 * <p>The {@code action} controller carries {@code attack} (the tusk bite),
 * {@code hurt} (flinch) and the held {@code death}: a {@value #DEATH_ANIM_TICKS}t
 * scripted forward collapse — the renderer's {@code withUprightDeath()} suppresses the
 * vanilla tip-over so the authored fall is the only rotation.</p>
 */
public class UmbralStalkerEntity extends EclipseGeoMonster {
    /** Frozen §6 entity path — geo/anim/texture triple + animation ids key off this. */
    public static final String GEO_ID = "umbral_stalker";
    /** Hunt gait on the {@code base} controller: the explosive bounding gallop. */
    public static final String ANIM_SPRINT = "sprint";
    /** Calm gait on the {@code base} controller: the deep belly-low prowl. */
    public static final String ANIM_CRAWL = "crawl";
    /** Aggro-but-stationary pose on the {@code base} controller: the crouched lurk. */
    public static final String ANIM_STALK_LOW = "stalk_low";
    /** One-shot flinch on the {@code action} controller. */
    public static final String ANIM_HURT = "hurt";

    /** How long the dawn flight lasts before the stalker dissolves. */
    public static final int FLEE_DESPAWN_TICKS = 100;
    /** Scripted death window (sheet: 1.4 s forward collapse, held on the last frame). */
    public static final int DEATH_ANIM_TICKS = 28;
    /** Client-side gallop hold — see {@link #updateSprintGate()}. */
    private static final int SPRINT_HOLD_TICKS = 8;
    /** Client-side smear latch — see {@link #updateSmearGate()}. */
    private static final int SMEAR_HOLD_TICKS = 6;
    /**
     * Horizontal speed² gate (blocks²/tick²) below which the gallop is not visibly
     * covering ground: 0.08 b/t = 1.6 b/s. A* micro-pauses and wall-pinned pathing dip
     * under it; the bounding hunt gallop (~0.3+ b/t) sits far above.
     */
    private static final double SMEAR_MIN_SPEED_SQ = 0.08D * 0.08D;

    /** Synced so the client can play {@code sprint} during the dawn flight, when the
     * target (and with it {@code isAggressive()}) has already been dropped. */
    private static final EntityDataAccessor<Boolean> DATA_FLEEING =
            SynchedEntityData.defineId(UmbralStalkerEntity.class, EntityDataSerializers.BOOLEAN);

    /** {@code -1} while it is night; counts up once the dawn flight has started. */
    private int fleeTicks = -1;

    /** Client-only smoothed skulk blend (0 = upright prowl, 1 = full crouch), driven by
     * the synced {@code isAggressive()} flag — eases in fast, out slower. */
    private float stalkAmount;
    private float stalkAmountO;

    /** Client-only gallop latch (ticks remaining); never read or written server-side. */
    private int sprintHold;
    /** Client-only smear latch (ticks remaining); never read or written server-side. */
    private int smearHold;
    private RawAnimation cachedCrawlAnim;
    private RawAnimation cachedSprintAnim;
    private RawAnimation cachedStalkLowAnim;

    public UmbralStalkerEntity(EntityType<? extends UmbralStalkerEntity> entityType, Level level) {
        super(entityType, level);
    }

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
        super.defineSynchedData(builder);
        builder.define(DATA_FLEEING, false);
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

    // --- GeckoLib (frozen base-class hooks) ---

    @Override
    public String geoId() {
        return GEO_ID;
    }

    /**
     * Four-state posture machine on the frozen {@code base} controller (no third
     * controller). Movement picks the gait — {@code crawl} when calm, {@code sprint} when
     * hunting or bolting; standing still picks the pose — {@code stalk_low} when it holds
     * a target, {@code idle} otherwise. The hunt gate is {@link #isAggressive()} (set by
     * {@code MeleeAttackGoal}, synced on the vanilla living-entity flag byte) held open by
     * the {@link #updateSprintGate()} latch.
     */
    @Override
    protected PlayState handleBaseState(AnimationState<?> state) {
        boolean hunting = this.sprintHold > 0;
        boolean bolting = this.isFleeing();
        if (state.isMoving()) {
            return state.setAndContinue(hunting || bolting ? sprintAnim() : walkAnim());
        }
        // A stalker that stopped mid-flight is cowering, not lurking — no stalk_low.
        return state.setAndContinue(hunting && !bolting ? stalkLowAnim() : idleAnim());
    }

    /**
     * The calm gait is a belly-low crawl, not a walk — substitute it for the frozen
     * {@code walk} id so {@code EclipseGeoMonster}'s default paths stay valid.
     */
    @Override
    protected RawAnimation walkAnim() {
        if (cachedCrawlAnim == null) {
            cachedCrawlAnim = EclipseGeoAnimations.loop(GEO_ID, ANIM_CRAWL);
        }
        return cachedCrawlAnim;
    }

    /** Cached {@code animation.umbral_stalker.sprint} loop (the bounding hunt gallop). */
    private RawAnimation sprintAnim() {
        if (cachedSprintAnim == null) {
            cachedSprintAnim = EclipseGeoAnimations.loop(GEO_ID, ANIM_SPRINT);
        }
        return cachedSprintAnim;
    }

    /** Cached {@code animation.umbral_stalker.stalk_low} loop (the crouched lurk). */
    private RawAnimation stalkLowAnim() {
        if (cachedStalkLowAnim == null) {
            cachedStalkLowAnim = EclipseGeoAnimations.loop(GEO_ID, ANIM_STALK_LOW);
        }
        return cachedStalkLowAnim;
    }

    /**
     * Client-side hysteresis on the hunt gate. {@code MeleeAttackGoal} clears
     * {@code isAggressive()} for a tick whenever {@code LeapAtTargetGoal} preempts it or
     * the path is recomputed; without the {@value #SPRINT_HOLD_TICKS}t latch the base
     * controller would flip crawl/sprint mid-stride and re-blend every time.
     */
    private void updateSprintGate() {
        if (this.isAggressive() && this.isAlive()) {
            this.sprintHold = SPRINT_HOLD_TICKS;
        } else if (this.sprintHold > 0) {
            this.sprintHold--;
        }
    }

    /**
     * MC2 §0/§9.4.6 / POLISH1: the sprint-smear gate behind the {@code
     * stalker_sprint_smear} loop row in {@code veilfx/PhotonMobFx}. Same verdict the
     * base controller uses for the {@code sprint} gait — hunt latch OR dawn flight —
     * but additionally requires the gallop to actually COVER GROUND (client per-tick
     * position delta ≥ {@value #SMEAR_MIN_SPEED_SQ}²-gate): a stalker snarling in
     * melee range is sprint-postured yet stationary, and a speed smear on a standing
     * mob would be a lie. Its own {@value #SMEAR_HOLD_TICKS}t latch bridges A*
     * micro-pauses so the ribbons fade once per chase, not once per repath.
     */
    private void updateSmearGate() {
        double dx = this.getX() - this.xOld;
        double dz = this.getZ() - this.zOld;
        boolean galloping = (this.sprintHold > 0 || this.isFleeing())
                && dx * dx + dz * dz >= SMEAR_MIN_SPEED_SQ;
        if (galloping && this.isAlive()) {
            this.smearHold = SMEAR_HOLD_TICKS;
        } else if (this.smearHold > 0) {
            this.smearHold--;
        }
    }

    /**
     * True while the client-side gallop is visibly covering ground — the attach
     * predicate of the {@code stalker_sprint_smear} row ({@code veilfx/PhotonMobFx}).
     * Client-only, like the {@code sprintHold} latch it derives from.
     */
    public boolean isSprintSmearing() {
        return this.smearHold > 0;
    }

    @Override
    protected void registerActionTriggers(AnimationController<?> action) {
        super.registerActionTriggers(action); // death (played-and-held)
        action.triggerableAnim(EclipseGeoAnimations.ANIM_ATTACK,
                EclipseGeoAnimations.once(GEO_ID, EclipseGeoAnimations.ANIM_ATTACK));
        action.triggerableAnim(ANIM_HURT, EclipseGeoAnimations.once(GEO_ID, ANIM_HURT));
    }

    /**
     * POLISH2 contract-v2 blend-in (EVAL2-C H-4): {@code attack} snaps 52° out of
     * {@code sprint} (the hunt gait) and up to 97.5° out of {@code stalk_low} — the
     * identical bite-out-of-sprint situation the Storm Hound got a 3 t blend for in
     * POLISH2 §3, so 3 t here too; {@code hurt} is a flinch whose damage precedes the
     * trigger (follow-through class) → 2 t. {@code death} stays hard: the scripted
     * {@value #DEATH_ANIM_TICKS} t collapse window equals the clip length exactly.
     */
    @Override
    protected int actionTransitionTicks(String animName) {
        return switch (animName) {
            case EclipseGeoAnimations.ANIM_ATTACK -> 3;
            case ANIM_HURT -> 2;
            default -> 0;
        };
    }

    /** True while the dawn flight is running (synced — the client gait reads it). */
    public boolean isFleeing() {
        return this.entityData.get(DATA_FLEEING);
    }

    @Override
    public void tick() {
        super.tick();
        if (this.level().isClientSide) {
            this.stalkAmountO = this.stalkAmount;
            this.stalkAmount = Mth.clamp(
                    this.stalkAmount + (this.isAggressive() ? 0.08F : -0.05F), 0.0F, 1.0F);
            updateSprintGate();
            updateSmearGate();
        }
        if (this.level().isClientSide || !this.isAlive()) {
            return;
        }
        if (this.level().isDay()) {
            tickDawnFlight();
        } else {
            this.fleeTicks = -1; // Manual /time set night mid-flight: resume the hunt.
            this.entityData.set(DATA_FLEEING, false);
        }
    }

    /** Dawn: drop the target, sprint away from the nearest player, then dissolve. */
    private void tickDawnFlight() {
        if (this.fleeTicks < 0) {
            this.fleeTicks = 0;
            this.setTarget(null);
            this.entityData.set(DATA_FLEEING, true);
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
            if (!this.level().isClientSide) {
                triggerAction(EclipseGeoAnimations.ANIM_ATTACK); // tusk bite
            }
            this.level().playSound(null, this.blockPosition(), SoundEvents.RAVAGER_ATTACK,
                    SoundSource.HOSTILE, 1.0F, 1.4F);
        }
        return hurt;
    }

    @Override
    public boolean hurt(DamageSource source, float amount) {
        boolean hurt = super.hurt(source, amount);
        if (hurt && !this.level().isClientSide && this.isAlive()) {
            triggerAction(ANIM_HURT);
        }
        return hurt;
    }

    // --- death (scripted forward collapse; the renderer zeroes the vanilla flip) ---

    @Override
    public void die(DamageSource damageSource) {
        super.die(damageSource);
        if (!this.level().isClientSide) {
            triggerAction(EclipseGeoAnimations.ANIM_DEATH);
        }
    }

    /** Scripted {@value #DEATH_ANIM_TICKS}t collapse with shard sputters, then the poof. */
    @Override
    protected void tickDeath() {
        this.deathTime++;
        if (!(this.level() instanceof ServerLevel serverLevel)) {
            return; // Client: the held death anim plays; deathTime is cosmetic here.
        }
        if (this.deathTime % 6 == 0) {
            serverLevel.sendParticles(ParticleTypes.SOUL,
                    this.getX(), this.getY() + 0.5D, this.getZ(), 2, 0.3D, 0.2D, 0.3D, 0.02D);
        }
        if (this.deathTime >= DEATH_ANIM_TICKS && !this.isRemoved()) {
            serverLevel.broadcastEntityEvent(this, EntityEvent.POOF);
            this.remove(RemovalReason.KILLED);
        }
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

    /**
     * Client anim hook: smoothed skulk-crouch blend.
     *
     * @deprecated MC2 GeckoLib conversion — the crouch is now the {@code stalk_low} loop
     *             on the {@code base} controller. Only the deprecated
     *             {@code UmbralStalkerModel} still reads this.
     */
    @Deprecated
    public float stalkAmount(float partialTick) {
        return Mth.lerp(partialTick, this.stalkAmountO, this.stalkAmount);
    }

    /**
     * Client anim hook: the head lowers up to 0.3 rad while hunting.
     *
     * @deprecated MC2 GeckoLib conversion — the {@code neck} bone carries the lowering in
     *             {@code stalk_low}/{@code crawl}. See {@link #stalkAmount(float)}.
     */
    @Deprecated
    public float headLower(float partialTick) {
        return stalkAmount(partialTick) * 0.3F;
    }

    /**
     * Client anim hook: spine shards pulse-breathe.
     *
     * @deprecated MC2 GeckoLib conversion — the shard breath is Molang on the
     *             {@code glow_spine_*} bones. See {@link #stalkAmount(float)}.
     */
    @Deprecated
    public float shardPulse(float ageInTicks, int index) {
        return Mth.sin(ageInTicks * 0.15F + index * 0.9F);
    }
}
