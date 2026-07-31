package dev.projecteclipse.eclipse.entity;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.entity.ambient.DriftTracker;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoMob;
import net.minecraft.core.BlockPos;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.NbtUtils;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.util.Mth;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.EntityEvent;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.Level;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.AnimationState;
import software.bernie.geckolib.animation.PlayState;

/**
 * Sunmote — the altar swarm wisp ({@code docs/ideas/04_content.md} §1.5). A captured
 * spark of daylight orbiting the sanctum altar; {@link EclipseSpawner} maintains one per
 * altar level (radius {@code 6 + altarLevel}) and respawns killed motes at the next dawn.
 *
 * <p>MC3 (F-098 wave M-C) converted it from the hand-coded {@code SunmoteModel} to the
 * GeckoLib line: {@link EclipseGeoMob} + geo {@value #GEO_ID} (core shell + heartbeat
 * kernel + eight-point ray wreath + halo ring) with the mob's FIRST glowmask.</p>
 *
 * <p>The orbit is position-driven in {@link #tick()} (no physics, no gravity, no goals):
 * the angle advances {@value #ORBIT_STEP} rad/tick around the persisted anchor with a
 * slow sine bob, and the mote yaws into its own tangent so the wreath trails behind it.
 * Every ~15-25 s it BASKS: the angle holds for {@value #BASK_TICKS_MIN}+ ticks while the
 * bob keeps breathing — that pause is what the {@code idle} loop is for (gliding plays
 * {@code walk}). Killable — drops one glowstone dust; death is a scripted upright
 * {@value #DEATH_ANIM_TICKS}t collapse. Chimes softly every ~200 ticks, and the chime is
 * the visible {@code chime} flare beat ({@link #playAmbientSound()}).</p>
 */
public class SunmoteEntity extends EclipseGeoMob {
    /** Frozen §6 entity path — geo/anim/texture triple + animation ids key off this. */
    public static final String GEO_ID = "sunmote";
    /** Extra triggerable on the {@code action} controller: the corona flare on a chime. */
    public static final String ANIM_CHIME = "chime";
    /** Scripted death window (sheet: 24t — wreath collapses, core flares and gutters). */
    public static final int DEATH_ANIM_TICKS = 24;

    /** Orbit angle advance per tick (spec: {@code angle += 0.02}). */
    public static final double ORBIT_STEP = 0.02D;

    /** Ticks of orbiting between two basking pauses (plus jitter). */
    private static final int BASK_INTERVAL_MIN = 260;
    private static final int BASK_INTERVAL_JITTER = 240;
    /** Length of one basking pause (plus jitter) — the mote's only {@code idle} window. */
    private static final int BASK_TICKS_MIN = 45;
    private static final int BASK_TICKS_JITTER = 55;

    private static final String TAG_ANCHOR = "orbitAnchor";
    private static final String TAG_ANGLE = "orbitAngle";

    @Nullable
    private BlockPos anchor;
    private double angle;
    private int baskCooldown;
    private int baskTicks;
    /** F-9: the real per-tick travel verdict behind {@link #handleBaseState}. */
    private final DriftTracker drift = new DriftTracker();

    public SunmoteEntity(EntityType<? extends SunmoteEntity> entityType, Level level) {
        super(entityType, level);
        this.setNoGravity(true);
        this.noPhysics = true;
        this.angle = this.random.nextDouble() * Math.PI * 2.0D;
        this.baskCooldown = BASK_INTERVAL_MIN + this.random.nextInt(BASK_INTERVAL_JITTER);
    }

    /** Pins the orbit center + starting angle; called by the spawner right after creation. */
    public void setOrbit(BlockPos anchor, double startAngle) {
        this.anchor = anchor;
        this.angle = startAngle;
    }

    // --- GeckoLib (frozen base-class hooks) ---

    @Override
    public String geoId() {
        return GEO_ID;
    }

    @Override
    protected void registerActionTriggers(AnimationController<?> action) {
        super.registerActionTriggers(action); // death (hold on last frame)
        action.triggerableAnim(ANIM_CHIME, EclipseGeoAnimations.once(GEO_ID, ANIM_CHIME));
        action.triggerableAnim(EclipseGeoAnimations.ANIM_ATTACK,
                EclipseGeoAnimations.once(GEO_ID, EclipseGeoAnimations.ANIM_ATTACK)); // unused flare (sheet)
    }

    /**
     * Census falle F-9 — see {@link DriftTracker}: {@code state.isMoving()} is unusable
     * for a {@code setPos} drifter, so the base controller reads the mob's real per-tick
     * horizontal delta. The mote's own {@code idle} window is the basking pause; the
     * vertical bob is deliberately NOT counted as travel (it never stops).
     */
    @Override
    protected PlayState handleBaseState(AnimationState<?> state) {
        return state.setAndContinue(this.drift.gliding() ? walkAnim() : idleAnim());
    }

    // --- orbit brain ---

    @Override
    public void tick() {
        super.tick();
        if (!this.level().isClientSide && this.isAlive()) {
            orbitTick();
        }
        // Last, deliberately: on the client super.tick() has applied the interpolation
        // step, on the server orbitTick() has applied the teleport.
        this.drift.track(this.getX() - this.xOld, this.getZ() - this.zOld);
    }

    private void orbitTick() {
        if (this.anchor == null) {
            // Summoned ad hoc (e.g. /summon): orbit the sanctum altar if known, else the spawn point.
            BlockPos sanctum = this.level() instanceof ServerLevel serverLevel
                    ? EclipseWorldState.get(serverLevel.getServer()).getSanctumAltarPos()
                    : null;
            this.anchor = sanctum != null && sanctum.closerToCenterThan(this.position(), 48.0D)
                    ? sanctum : this.blockPosition();
        }
        int altarLevel = this.level() instanceof ServerLevel serverLevel
                ? EclipseWorldState.get(serverLevel.getServer()).getAltarLevel() : 0;
        double radius = 6.0D + altarLevel;
        boolean basking = tickBask();
        if (!basking) {
            this.angle += ORBIT_STEP;
            // Face the orbit tangent so walk's backswept wreath trails the travel
            // direction; a basking mote keeps the heading it drifted in on.
            float yaw = (float) (Mth.atan2(Math.cos(this.angle), -Math.sin(this.angle))
                    * Mth.RAD_TO_DEG) - 90.0F;
            this.setYRot(yaw);
            this.yBodyRot = yaw;
            this.yHeadRot = yaw;
        }
        double x = this.anchor.getX() + 0.5D + Math.cos(this.angle) * radius;
        double z = this.anchor.getZ() + 0.5D + Math.sin(this.angle) * radius;
        double y = this.anchor.getY() + 1.5D + Mth.sin((float) (this.tickCount * 0.05F)) * 0.6D;
        this.setDeltaMovement(x - this.getX(), y - this.getY(), z - this.getZ());
        this.setPos(x, y, z);
    }

    /**
     * Basking cadence: every {@value #BASK_INTERVAL_MIN}+ ticks the mote stops advancing
     * its orbit angle for {@value #BASK_TICKS_MIN}+ ticks and just hangs in the bob —
     * the sanctum reads as inhabited rather than as a clockwork, and it is the only
     * state in which the {@code idle} loop is reachable. Returns true while basking.
     */
    private boolean tickBask() {
        if (this.baskTicks > 0) {
            this.baskTicks--;
            return true;
        }
        if (--this.baskCooldown <= 0) {
            this.baskTicks = BASK_TICKS_MIN + this.random.nextInt(BASK_TICKS_JITTER);
            this.baskCooldown = BASK_INTERVAL_MIN + this.random.nextInt(BASK_INTERVAL_JITTER);
            return true;
        }
        return false;
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
        if (this.deathTime >= DEATH_ANIM_TICKS && !this.isRemoved()) {
            serverLevel.broadcastEntityEvent(this, EntityEvent.POOF);
            this.remove(RemovalReason.KILLED);
        }
    }

    @Override
    protected void dropCustomDeathLoot(ServerLevel level, DamageSource damageSource, boolean recentlyHit) {
        super.dropCustomDeathLoot(level, damageSource, recentlyHit);
        this.spawnAtLocation(new ItemStack(Items.GLOWSTONE_DUST));
    }

    // --- ambience details ---

    /**
     * The chime IS the flare: vanilla rolls the ambient sound in {@code Mob.baseTick},
     * so hooking it here couples the {@code chime} one-shot to the sound the player
     * actually hears instead of running a second, drifting timer.
     */
    @Override
    public void playAmbientSound() {
        super.playAmbientSound();
        if (!this.level().isClientSide && this.isAlive()) {
            triggerAction(ANIM_CHIME);
        }
    }

    @Override
    @Nullable
    protected SoundEvent getAmbientSound() {
        return SoundEvents.AMETHYST_BLOCK_CHIME;
    }

    @Override
    public int getAmbientSoundInterval() {
        return 200;
    }

    @Override
    public boolean isPushable() {
        return false;
    }

    @Override
    public boolean removeWhenFarAway(double distanceToClosestPlayer) {
        return false; // Maintained by the spawner; never despawns on its own.
    }

    @Override
    public void addAdditionalSaveData(CompoundTag tag) {
        super.addAdditionalSaveData(tag);
        if (this.anchor != null) {
            tag.put(TAG_ANCHOR, NbtUtils.writeBlockPos(this.anchor));
        }
        tag.putDouble(TAG_ANGLE, this.angle);
    }

    @Override
    public void readAdditionalSaveData(CompoundTag tag) {
        super.readAdditionalSaveData(tag);
        NbtUtils.readBlockPos(tag, TAG_ANCHOR).ifPresent(pos -> this.anchor = pos);
        if (tag.contains(TAG_ANGLE)) {
            this.angle = tag.getDouble(TAG_ANGLE);
        }
    }
}
