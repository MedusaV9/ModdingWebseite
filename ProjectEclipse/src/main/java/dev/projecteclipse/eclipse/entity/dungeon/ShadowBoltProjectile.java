package dev.projecteclipse.eclipse.entity.dungeon;

import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import net.minecraft.core.particles.ParticleOptions;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.monster.Enemy;
import net.minecraft.world.entity.projectile.AbstractHurtingProjectile;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.BlockHitResult;
import net.minecraft.world.phys.EntityHitResult;
import net.minecraft.world.phys.HitResult;
import net.minecraft.world.phys.Vec3;
import software.bernie.geckolib.animatable.GeoEntity;
import software.bernie.geckolib.animatable.instance.AnimatableInstanceCache;
import software.bernie.geckolib.animation.AnimatableManager;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.util.GeckoLibUtil;

/**
 * Shadow Bolt — the purple seeker fired by the Eclipse Cultist's 3-bolt fan and the Rift
 * Warden's volleys ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.3/§2.4). A
 * {@link AbstractHurtingProjectile} in the {@code SmallFireball} mold (self-accelerating
 * along its heading, {@code WITCH} trail from {@link #getTrailParticle}, fullbright), plus
 * two twists:
 *
 * <ul>
 *   <li><b>Homing-lite</b> (HeraldShardProjectile precedent, gentler): when spawned with a
 *       target, the heading blends {@value #STEERING} per tick toward the target's chest —
 *       the side bolts of a fan launch angled outward and curve back in late, so the fan
 *       stays readable and strafing outruns it;</li>
 *   <li><b>Wither-lite hit:</b> {@value #DAMAGE} magic-projectile damage + Wither I for
 *       {@value #WITHER_TICKS}t (2 s — a dread tick, not a death sentence).</li>
 * </ul>
 *
 * <p>Breaks on any block, despawns after {@value #LIFETIME_TICKS}t (no bolts circling a
 * reset fight), and passes through {@link Enemy} mobs so the warden's volleys never shred
 * its own cultist adds. Renders through GeckoLib ({@link GeoEntity} — the tiny
 * {@code shadow_bolt.geo.json} spike-orb spinning on its {@code idle} loop; no custom
 * items involved).</p>
 */
public class ShadowBoltProjectile extends AbstractHurtingProjectile implements GeoEntity {
    public static final String GEO_ID = "shadow_bolt";
    public static final float DAMAGE = 5.0F;
    /** Wither I duration on hit (40t = 2 s — the sheet's "wither-lite"). */
    public static final int WITHER_TICKS = 40;

    /** Per-tick heading blend toward the target (0 = straight, 1 = instant snap). */
    private static final double STEERING = 0.055D;
    private static final int LIFETIME_TICKS = 100;
    /** Self-acceleration per tick; terminal speed ≈ 19× this (inertia 0.95) ≈ 1.5 b/t. */
    private static final double ACCELERATION = 0.08D;

    private final AnimatableInstanceCache geoCache = GeckoLibUtil.createInstanceCache(this);

    @Nullable
    private Entity target;
    @Nullable
    private UUID targetId;
    private int life;

    public ShadowBoltProjectile(EntityType<? extends ShadowBoltProjectile> entityType, Level level) {
        super(entityType, level);
        this.accelerationPower = ACCELERATION;
    }

    /**
     * Spawns at the shooter's eye, flying along {@code direction} (normalized internally),
     * homing-lite on {@code homingTarget} when non-null (straight flight otherwise).
     */
    public ShadowBoltProjectile(Level level, LivingEntity shooter, Vec3 direction, @Nullable Entity homingTarget) {
        this(DungeonEntities.SHADOW_BOLT.get(), level);
        this.setOwner(shooter);
        Vec3 eye = shooter.getEyePosition();
        this.moveTo(eye.x, eye.y - 0.2D, eye.z, shooter.getYRot(), shooter.getXRot());
        this.target = homingTarget;
        this.targetId = homingTarget != null ? homingTarget.getUUID() : null;
        if (direction.lengthSqr() > 1.0E-6D) {
            // Launch already at cruise speed so the fan spread reads immediately.
            this.setDeltaMovement(direction.normalize().scale(ACCELERATION * 12.0D));
        }
    }

    @Override
    public void tick() {
        if (!this.level().isClientSide) {
            if (++this.life > LIFETIME_TICKS) {
                burst();
                return;
            }
            steerTowardsTarget();
        }
        super.tick();
    }

    /** Homing-lite: rotate the heading a little toward the target's chest, keep the speed. */
    private void steerTowardsTarget() {
        if (this.target == null && this.targetId != null && this.level() instanceof ServerLevel serverLevel) {
            this.target = serverLevel.getEntity(this.targetId);
            if (this.target == null) {
                this.targetId = null; // Target gone: fly straight from here on.
            }
        }
        if (this.target == null || !this.target.isAlive()) {
            return;
        }
        Vec3 velocity = this.getDeltaMovement();
        double speed = velocity.length();
        if (speed < 1.0E-4D) {
            return;
        }
        Vec3 toTarget = new Vec3(this.target.getX(), this.target.getY(0.5D), this.target.getZ())
                .subtract(this.position());
        if (toTarget.lengthSqr() < 1.0E-4D) {
            return;
        }
        Vec3 heading = velocity.scale(1.0D / speed);
        Vec3 blended = heading.scale(1.0D - STEERING).add(toTarget.normalize().scale(STEERING));
        this.setDeltaMovement(blended.normalize().scale(speed));
    }

    @Override
    protected boolean canHitEntity(Entity hit) {
        // Passes through hostile mobs: the warden's volleys must never shred its own adds
        // (and cultist crossfire in a spawner room would be free pest control).
        return super.canHitEntity(hit) && !(hit instanceof ShadowBoltProjectile) && !(hit instanceof Enemy);
    }

    @Override
    protected void onHitEntity(EntityHitResult result) {
        super.onHitEntity(result);
        if (this.level().isClientSide) {
            return;
        }
        Entity owner = this.getOwner();
        DamageSource source = this.damageSources().mobProjectile(this,
                owner instanceof LivingEntity living ? living : null);
        if (result.getEntity().hurt(source, DAMAGE)
                && result.getEntity() instanceof LivingEntity living) {
            living.addEffect(new MobEffectInstance(MobEffects.WITHER, WITHER_TICKS),
                    owner instanceof LivingEntity livingOwner ? livingOwner : this);
        }
    }

    @Override
    protected void onHitBlock(BlockHitResult result) {
        super.onHitBlock(result);
        this.playSound(SoundEvents.SCULK_CLICKING_STOP, 0.8F, 0.7F);
    }

    @Override
    protected void onHit(HitResult result) {
        super.onHit(result);
        if (!this.level().isClientSide) {
            burst();
        }
    }

    /** Small purple pop (impact and timeout both end here). */
    private void burst() {
        if (this.level() instanceof ServerLevel serverLevel) {
            serverLevel.sendParticles(ParticleTypes.WITCH,
                    this.getX(), this.getY(), this.getZ(), 8, 0.12D, 0.12D, 0.12D, 0.05D);
            serverLevel.sendParticles(ParticleTypes.REVERSE_PORTAL,
                    this.getX(), this.getY(), this.getZ(), 6, 0.1D, 0.1D, 0.1D, 0.08D);
        }
        this.discard();
    }

    // --- SmallFireball-style projectile chassis tweaks ---

    @Override
    protected ParticleOptions getTrailParticle() {
        return ParticleTypes.WITCH; // Purple mote trail (spec: purple trail particles).
    }

    @Override
    protected boolean shouldBurn() {
        return false; // Shadow, not fire: no flame trail, no burning visual.
    }

    @Override
    public boolean isOnFire() {
        return false;
    }

    // --- persistence (targets survive chunk reloads like the Herald shard) ---

    @Override
    public void addAdditionalSaveData(CompoundTag compound) {
        super.addAdditionalSaveData(compound);
        if (this.targetId != null) {
            compound.putUUID("Target", this.targetId);
        }
        compound.putInt("Life", this.life);
    }

    @Override
    public void readAdditionalSaveData(CompoundTag compound) {
        super.readAdditionalSaveData(compound);
        if (compound.hasUUID("Target")) {
            this.targetId = compound.getUUID("Target");
        }
        this.life = compound.getInt("Life");
    }

    // --- GeckoLib (tiny spike-orb spins on a single idle loop) ---

    @Override
    public void registerControllers(AnimatableManager.ControllerRegistrar controllers) {
        controllers.add(new AnimationController<>(this, EclipseGeoAnimations.CONTROLLER_BASE, 0,
                state -> state.setAndContinue(
                        EclipseGeoAnimations.loop(GEO_ID, EclipseGeoAnimations.ANIM_IDLE))));
    }

    @Override
    public AnimatableInstanceCache getAnimatableInstanceCache() {
        return geoCache;
    }
}
