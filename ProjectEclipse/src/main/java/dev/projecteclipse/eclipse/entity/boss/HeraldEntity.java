package dev.projecteclipse.eclipse.entity.boss;

import javax.annotation.Nullable;

import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.syncher.EntityDataAccessor;
import net.minecraft.network.syncher.EntityDataSerializers;
import net.minecraft.network.syncher.SynchedEntityData;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.util.Mth;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;

/**
 * The Herald of the Eclipse — day-7 boss ({@code docs/ideas/04_content.md} §2.1): a broken
 * godhead of black glass hovering over the sanctum dais. This class carries the shared
 * boss chassis: gravity-free floating flight, the phase/telegraph/shard-count synced state
 * the model animates from, damage/knockback immunities and persistence. The three-phase
 * fight (volley, gaze, collapse), arena lock, scaling, bossbar and drops are layered on in
 * the fight update.
 *
 * <p><b>Phases</b> derive from the health fraction (bossbar NOTCHED_6 alignment): P1 above
 * 2/3, P2 above 1/3, P3 below. {@code DATA_SHARDS_LEFT} counts the still-attached corona
 * shards (8 → 0 across P3); the model hides detached ones. {@code DATA_TELEGRAPH} makes
 * the shards glow via the renderer's emissive pass during volley wind-ups.</p>
 */
public class HeraldEntity extends Monster {
    public static final int CORONA_SHARDS = 8;
    public static final float BASE_MAX_HEALTH = 300.0F;

    /** Current phase 1..3 (synced; drives model animation speed + shard tilt). */
    private static final EntityDataAccessor<Integer> DATA_PHASE =
            SynchedEntityData.defineId(HeraldEntity.class, EntityDataSerializers.INT);
    /** True while a volley is winding up (shards glow emissive). */
    private static final EntityDataAccessor<Boolean> DATA_TELEGRAPH =
            SynchedEntityData.defineId(HeraldEntity.class, EntityDataSerializers.BOOLEAN);
    /** Corona shards still attached to the ring (P3 detaches them as HP drops). */
    private static final EntityDataAccessor<Integer> DATA_SHARDS_LEFT =
            SynchedEntityData.defineId(HeraldEntity.class, EntityDataSerializers.INT);

    // Client-side smooth animation clock: advances at the phase speed (x2 in P3) with an
    // eased ramp so the ring spin / bobs never snap on a phase change.
    private float animAge;
    private float animAgePrev;
    private float animSpeed = 1.0F;
    private float shardTilt;
    private float shardTiltPrev;

    public HeraldEntity(EntityType<? extends HeraldEntity> entityType, Level level) {
        super(entityType, level);
        this.setNoGravity(true);
        this.noCulling = true;
        this.setPersistenceRequired();
        this.xpReward = 50;
    }

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
        super.defineSynchedData(builder);
        builder.define(DATA_PHASE, 1);
        builder.define(DATA_TELEGRAPH, false);
        builder.define(DATA_SHARDS_LEFT, CORONA_SHARDS);
    }

    // --- synced state accessors ---

    public int getPhase() {
        return this.entityData.get(DATA_PHASE);
    }

    protected void setPhase(int phase) {
        this.entityData.set(DATA_PHASE, Mth.clamp(phase, 1, 3));
    }

    public boolean isTelegraphing() {
        return this.entityData.get(DATA_TELEGRAPH);
    }

    protected void setTelegraphing(boolean telegraphing) {
        this.entityData.set(DATA_TELEGRAPH, telegraphing);
    }

    public int getShardsLeft() {
        return this.entityData.get(DATA_SHARDS_LEFT);
    }

    protected void setShardsLeft(int shardsLeft) {
        this.entityData.set(DATA_SHARDS_LEFT, Mth.clamp(shardsLeft, 0, CORONA_SHARDS));
    }

    // --- ticking ---

    @Override
    public void tick() {
        super.tick();
        if (this.level().isClientSide) {
            tickClientAnim();
        }
    }

    /** Advances the smooth animation clock and the P3 shard tilt-out lerp (client only). */
    private void tickClientAnim() {
        float targetSpeed = getPhase() >= 3 ? 2.0F : 1.0F;
        this.animSpeed += (targetSpeed - this.animSpeed) * 0.05F;
        this.animAgePrev = this.animAge;
        this.animAge += this.animSpeed;
        this.shardTiltPrev = this.shardTilt;
        float targetTilt = getPhase() >= 3 ? 0.6F : 0.0F;
        this.shardTilt += (targetTilt - this.shardTilt) * 0.05F;
    }

    /** Smooth model animation age (spec anims run off this; advances x2 in P3). */
    public float animAge(float partialTick) {
        return Mth.lerp(partialTick, this.animAgePrev, this.animAge);
    }

    /** P3 corona tilt-out amount, lerped toward {@code zRot 0.6} per spec. */
    public float shardTilt(float partialTick) {
        return Mth.lerp(partialTick, this.shardTiltPrev, this.shardTilt);
    }

    // --- floating-boss chassis ---

    @Override
    public boolean isPushable() {
        return false;
    }

    @Override
    public void knockback(double strength, double x, double z) {
        // Anchored: the fight's movement script owns the velocity.
    }

    @Override
    public boolean causeFallDamage(float fallDistance, float multiplier, DamageSource source) {
        return false;
    }

    @Override
    public boolean onClimbable() {
        return false;
    }

    @Override
    public void checkDespawn() {
        // Never despawns naturally; the fight controller handles reset/despawn itself.
    }

    @Override
    public boolean removeWhenFarAway(double distanceToClosestPlayer) {
        return false;
    }

    @Override
    public void travel(Vec3 travelVector) {
        // Gravity-free drift: velocity is set directly by the movement script each tick.
        if (this.isControlledByLocalInstance()) {
            this.move(net.minecraft.world.entity.MoverType.SELF, this.getDeltaMovement());
            this.setDeltaMovement(this.getDeltaMovement().scale(0.91D));
        }
    }

    // --- sounds ---

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return dev.projecteclipse.eclipse.registry.EclipseSounds.BOSS_HERALD_AMBIENT.get();
    }

    @Override
    protected SoundEvent getHurtSound(DamageSource damageSource) {
        return SoundEvents.AMETHYST_BLOCK_HIT;
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return SoundEvents.WITHER_DEATH;
    }

    @Override
    public float getVoicePitch() {
        return 0.6F;
    }

    // --- persistence ---

    @Override
    public void addAdditionalSaveData(CompoundTag compound) {
        super.addAdditionalSaveData(compound);
        compound.putInt("ShardsLeft", getShardsLeft());
    }

    @Override
    public void readAdditionalSaveData(CompoundTag compound) {
        super.readAdditionalSaveData(compound);
        if (compound.contains("ShardsLeft")) {
            setShardsLeft(compound.getInt("ShardsLeft"));
        }
    }

    /** Look helper for the fight: turns body + head toward a target position. */
    protected void faceTowards(Vec3 pos) {
        Vec3 delta = pos.subtract(this.position());
        float yaw = (float) (Mth.atan2(delta.z, delta.x) * Mth.RAD_TO_DEG) - 90.0F;
        this.setYRot(yaw);
        this.yBodyRot = yaw;
        this.yHeadRot = yaw;
    }

    /** The eye of the storm: world position of the emissive inner eye (projectile origin). */
    public Vec3 eyePos() {
        return new Vec3(this.getX(), this.getY() + 2.5D, this.getZ());
    }
}
