package dev.projecteclipse.eclipse.entity.ambient;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoMob;
import dev.projecteclipse.eclipse.limbo.GhostShipBuilder;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.util.RandomSource;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityEvent;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.ai.attributes.AttributeSupplier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.AnimationState;
import software.bernie.geckolib.animation.PlayState;

/**
 * Drift Lantern / Treiblaterne — the GeckoLib pipeline pilot and limbo sea ambience
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.3): a soul-lantern "jellyfish" that
 * drifts 0–6 blocks above the limbo water along the buoy lane, glass cage aglow, four
 * kelp-chain tendrils trailing.
 *
 * <p>No goals — like {@link dev.projecteclipse.eclipse.entity.SunmoteEntity} the motion
 * is position-driven in {@link #tick()}: a slow glide toward a random waypoint within
 * {@value #WANDER_RADIUS} blocks of its anchor (first tick / spawn position, persisted),
 * with hover pauses between legs (the {@code base} controller reads the actual per-tick
 * position delta, so gliding plays {@code walk} = stronger tendril sway and hovering
 * plays {@code idle}). Every 12–24s it rolls the {@code flicker} trigger (flame gutter +
 * a soul-particle puff). Limbo-only: it discards itself anywhere else (Deckhand rule).
 * 6 HP, killable — drops one glowstone dust; death is a scripted upright
 * {@value #DEATH_ANIM_TICKS}t collapse ({@code death} anim held on the last frame, sink +
 * soul wisps, vanilla poof afterwards).</p>
 *
 * <p>Spawning is P6-W6's job (6–10 maintained along the lane while players are in
 * limbo) via the {@link #spawnLane(ServerLevel)} helper. No automatic spawning here.</p>
 */
public class DriftLanternEntity extends EclipseGeoMob {
    /** Frozen §6 entity path — geo/anim/texture triple + animation ids key off this. */
    public static final String GEO_ID = "drift_lantern";
    /** Extra triggerable on the {@code action} controller: flame-gutter flicker pulse. */
    public static final String ANIM_FLICKER = "flicker";
    /** Scripted death window (sheet: 30t — tendrils collapse, flame gutters). */
    public static final int DEATH_ANIM_TICKS = 30;

    /** Buoy-lane X range mirrored from {@code LimboSeascape} (buoys at x 32..240). */
    public static final int LANE_MIN_X = 32;
    public static final int LANE_MAX_X = 240;

    private static final double DRIFT_SPEED = 0.025D;
    private static final double WANDER_RADIUS = 10.0D;

    private static final String TAG_ANCHOR_X = "AnchorX";
    private static final String TAG_ANCHOR_Y = "AnchorY";
    private static final String TAG_ANCHOR_Z = "AnchorZ";

    /** Drift-band center this lantern belongs to; set on spawn, persisted. */
    @Nullable
    private Vec3 anchor;
    @Nullable
    private Vec3 waypoint;
    private int hoverTicks;
    private int repickTicks;
    private int flickerTicks = 100;
    private int waterlineY = Integer.MIN_VALUE;

    public DriftLanternEntity(EntityType<? extends DriftLanternEntity> entityType, Level level) {
        super(entityType, level);
        this.setNoGravity(true);
        this.noPhysics = true;
    }

    /** Spec §2.3: 6 HP; speed 0 (motion is tick-driven, not AI-driven). */
    public static AttributeSupplier.Builder createAttributes() {
        return Mob.createMobAttributes()
                .add(Attributes.MAX_HEALTH, 6.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.0D)
                .add(Attributes.FOLLOW_RANGE, 16.0D);
    }

    // --- GeckoLib (frozen base-class hooks) ---

    @Override
    public String geoId() {
        return GEO_ID;
    }

    @Override
    protected void registerActionTriggers(AnimationController<?> action) {
        super.registerActionTriggers(action); // death (hold on last frame)
        action.triggerableAnim(ANIM_FLICKER, EclipseGeoAnimations.once(GEO_ID, ANIM_FLICKER));
        action.triggerableAnim(EclipseGeoAnimations.ANIM_ATTACK,
                EclipseGeoAnimations.once(GEO_ID, EclipseGeoAnimations.ANIM_ATTACK)); // unused flare (sheet)
    }

    /**
     * Drift is too slow for vanilla's limb-swing threshold ({@code state.isMoving()}
     * stays false), so glide-vs-hover is read straight off the client-interpolated
     * per-tick position delta.
     */
    @Override
    protected PlayState handleBaseState(AnimationState<?> state) {
        double dx = this.getX() - this.xOld;
        double dz = this.getZ() - this.zOld;
        boolean gliding = dx * dx + dz * dz > 1.0E-5D;
        return state.setAndContinue(gliding ? walkAnim() : idleAnim());
    }

    // --- drift brain ---

    @Override
    public void tick() {
        super.tick();
        if (this.level().isClientSide || !this.isAlive()) {
            return;
        }
        // Limbo only: a drift lantern outside the ghost sea simply is not (Deckhand rule).
        if (!(this.level() instanceof ServerLevel serverLevel)
                || !this.level().dimension().equals(LimboDimension.LIMBO)) {
            this.discard();
            return;
        }
        if (this.anchor == null) {
            this.anchor = this.position();
        }
        if (--this.flickerTicks <= 0) {
            this.flickerTicks = 240 + this.random.nextInt(240);
            triggerAction(ANIM_FLICKER);
            serverLevel.sendParticles(ParticleTypes.SCULK_SOUL,
                    this.getX(), this.getY() + 0.7D, this.getZ(), 2, 0.08D, 0.08D, 0.08D, 0.005D);
        }
        if (this.hoverTicks > 0) {
            this.hoverTicks--;
            this.setDeltaMovement(Vec3.ZERO);
            return;
        }
        if (this.waypoint == null || --this.repickTicks <= 0) {
            pickWaypoint(serverLevel);
        }
        Vec3 to = this.waypoint.subtract(this.position());
        double distance = to.length();
        if (distance < 0.5D) {
            // Leg done: hang in the air a while (idle bob) before the next glide.
            this.waypoint = null;
            this.hoverTicks = 60 + this.random.nextInt(140);
            this.setDeltaMovement(Vec3.ZERO);
            return;
        }
        Vec3 step = to.scale(Math.min(DRIFT_SPEED, distance) / distance);
        this.setDeltaMovement(step);
        this.setPos(this.getX() + step.x, this.getY() + step.y, this.getZ() + step.z);
    }

    /** New drift target within {@value #WANDER_RADIUS} of the anchor, 0–6 above the water. */
    private void pickWaypoint(ServerLevel serverLevel) {
        if (this.waterlineY == Integer.MIN_VALUE) {
            this.waterlineY = GhostShipBuilder.waterlineY(serverLevel);
        }
        double x = this.anchor.x + (this.random.nextDouble() * 2.0D - 1.0D) * WANDER_RADIUS;
        double z = this.anchor.z + (this.random.nextDouble() * 2.0D - 1.0D) * WANDER_RADIUS;
        double y = this.waterlineY + this.random.nextDouble() * 6.0D;
        this.waypoint = new Vec3(x, y, z);
        this.repickTicks = 400 + this.random.nextInt(200);
    }

    // --- death (scripted upright collapse; renderer suppresses the vanilla flip) ---

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
        // The lantern gutters and settles toward the water while the tendrils fold.
        this.setDeltaMovement(0.0D, -0.02D, 0.0D);
        this.setPos(this.getX(), this.getY() - 0.02D, this.getZ());
        if (this.deathTime % 6 == 0) {
            serverLevel.sendParticles(ParticleTypes.SOUL,
                    this.getX(), this.getY() + 0.7D, this.getZ(), 1, 0.1D, 0.1D, 0.1D, 0.005D);
        }
        if (this.deathTime >= DEATH_ANIM_TICKS && !this.isRemoved()) {
            serverLevel.broadcastEntityEvent(this, EntityEvent.POOF);
            this.remove(RemovalReason.KILLED);
        }
    }

    @Override
    protected void dropCustomDeathLoot(ServerLevel level, DamageSource damageSource, boolean recentlyHit) {
        super.dropCustomDeathLoot(level, damageSource, recentlyHit);
        this.spawnAtLocation(new ItemStack(Items.GLOWSTONE_DUST)); // Sheet: 1 glowstone dust.
    }

    // --- ambience details ---

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return SoundEvents.AMETHYST_BLOCK_CHIME; // Soft glassy chime, pitched low.
    }

    @Override
    public int getAmbientSoundInterval() {
        return 240;
    }

    @Override
    public float getVoicePitch() {
        return 0.55F + this.random.nextFloat() * 0.1F;
    }

    @Override
    protected float getSoundVolume() {
        return 0.4F;
    }

    @Override
    @Nullable
    protected SoundEvent getHurtSound(DamageSource damageSource) {
        return SoundEvents.LANTERN_HIT;
    }

    @Override
    @Nullable
    protected SoundEvent getDeathSound() {
        return SoundEvents.LANTERN_BREAK;
    }

    @Override
    public boolean isPushable() {
        return false;
    }

    @Override
    protected void doPush(Entity entity) {
        // Never shoves ghosts drifting through the lane.
    }

    @Override
    public boolean removeWhenFarAway(double distanceToClosestPlayer) {
        return false; // Population is maintained (top-up/count) by P6-W6's spawn rules.
    }

    // --- persistence ---

    @Override
    public void addAdditionalSaveData(CompoundTag tag) {
        super.addAdditionalSaveData(tag);
        if (this.anchor != null) {
            tag.putDouble(TAG_ANCHOR_X, this.anchor.x);
            tag.putDouble(TAG_ANCHOR_Y, this.anchor.y);
            tag.putDouble(TAG_ANCHOR_Z, this.anchor.z);
        }
    }

    @Override
    public void readAdditionalSaveData(CompoundTag tag) {
        super.readAdditionalSaveData(tag);
        if (tag.contains(TAG_ANCHOR_X)) {
            this.anchor = new Vec3(tag.getDouble(TAG_ANCHOR_X),
                    tag.getDouble(TAG_ANCHOR_Y), tag.getDouble(TAG_ANCHOR_Z));
        }
    }

    // --- W6 hook ---

    /**
     * Places ONE drift lantern at a random open-air point of the limbo buoy lane
     * (x {@value #LANE_MIN_X}..{@value #LANE_MAX_X}, z ±6 around the axis, 0–6 above the
     * water — spec §2.8). Returns the spawned entity, or {@code null} if the level is not
     * limbo / no open spot was found / the type is not registered. P6-W6's spawn rules
     * own counting, gating (players present) and cadence — this helper only places.
     */
    @Nullable
    public static DriftLanternEntity spawnLane(ServerLevel limbo) {
        if (!limbo.dimension().equals(LimboDimension.LIMBO) || !AmbientEntities.DRIFT_LANTERN.isBound()) {
            return null;
        }
        int waterline = GhostShipBuilder.waterlineY(limbo);
        RandomSource random = limbo.getRandom();
        for (int attempt = 0; attempt < 8; attempt++) {
            double x = LANE_MIN_X + random.nextInt(LANE_MAX_X - LANE_MIN_X + 1) + 0.5D;
            double z = random.nextInt(13) - 6 + 0.5D;
            double y = waterline + random.nextInt(7);
            BlockPos pos = BlockPos.containing(x, y, z);
            if (!limbo.getBlockState(pos).isAir() || !limbo.getBlockState(pos.above()).isAir()) {
                continue;
            }
            DriftLanternEntity lantern = AmbientEntities.DRIFT_LANTERN.get().create(limbo);
            if (lantern == null) {
                return null;
            }
            lantern.moveTo(x, y, z, random.nextFloat() * 360.0F, 0.0F);
            lantern.anchor = lantern.position();
            limbo.addFreshEntity(lantern);
            return lantern;
        }
        return null;
    }
}
