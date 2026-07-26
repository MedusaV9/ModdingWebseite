package dev.projecteclipse.eclipse.ferryman.finale;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoMob;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import net.minecraft.network.syncher.EntityDataAccessor;
import net.minecraft.network.syncher.EntityDataSerializers;
import net.minecraft.network.syncher.SynchedEntityData;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.tags.DamageTypeTags;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.AnimationState;
import software.bernie.geckolib.animation.PlayState;

/**
 * F-045 — the standing finale portal gate: a ~12-block GeckoLib arch entity anchored
 * over the water off the center island by {@link PortalFormation}. Pure
 * scenery-with-state: invulnerable, immobile (gravity-free, {@code travel} no-op),
 * persisted so the monument survives restarts, and it refuses to despawn.
 *
 * <p><b>Animation</b>: {@code idle} loops the rune/keystone pulse; the one-shot
 * {@code unlock} (2 s quake + door wings breaking open, held) fires exactly once via
 * {@link #unlock()} — the synced {@code DATA_OPEN} flag replays the held-open end pose
 * for late joiners (the {@code base} controller switches to the unlock hold once open,
 * so a client that never saw the trigger still renders open doors).</p>
 *
 * <p><b>Portal interior</b>: while the gate stands, the server re-fires the
 * {@link FxCues#CUE_PORTAL_VEIL} soul-veil one-shot every {@value #VEIL_REFIRE_TICKS}t
 * (the kneel-corona sustain law — Photon dedups while the 100t runtime lives), carrying
 * the gate yaw in {@code a} so the client aligns the flat veil plane with the door.</p>
 */
public class PortalGateEntity extends EclipseGeoMob {
    /** Veil sustain cadence (fx runtime 100t; the overlap hides the seam). */
    private static final int VEIL_REFIRE_TICKS = 80;
    private static final double VEIL_RANGE = 128.0D;
    /** Veil plane center height above the gate's feet (the arch midpoint). */
    private static final double VEIL_CENTER_Y = 5.5D;

    /** True once the key unlocked the doors (drives the held-open pose for late joiners). */
    private static final EntityDataAccessor<Boolean> DATA_OPEN =
            SynchedEntityData.defineId(PortalGateEntity.class, EntityDataSerializers.BOOLEAN);

    public static final String ANIM_UNLOCK = "unlock";

    public PortalGateEntity(EntityType<? extends PortalGateEntity> entityType, Level level) {
        super(entityType, level);
        this.setNoGravity(true);
        this.noCulling = true;
        this.setPersistenceRequired();
        this.setInvulnerable(true);
    }

    @Override
    public String geoId() {
        return "portal_gate";
    }

    // --- state ---

    public boolean isOpen() {
        return this.entityData.get(DATA_OPEN);
    }

    /** Fires the one-shot unlock (quake + wings) and pins the open pose for late joiners. */
    public void unlock() {
        if (isOpen()) {
            return;
        }
        this.entityData.set(DATA_OPEN, true);
        triggerAction(ANIM_UNLOCK);
    }

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
        super.defineSynchedData(builder);
        builder.define(DATA_OPEN, false);
    }

    // --- animation wiring ---

    @Override
    protected PlayState handleBaseState(AnimationState<?> state) {
        if (isOpen()) {
            // Held-open replay for clients that never saw the trigger; on the client
            // that DID, the action controller's live unlock one-shot wins the blend.
            return state.setAndContinue(EclipseGeoAnimations.hold(geoId(), ANIM_UNLOCK));
        }
        return state.setAndContinue(idleAnim());
    }

    @Override
    protected void registerActionTriggers(AnimationController<?> action) {
        super.registerActionTriggers(action);
        action.triggerableAnim(ANIM_UNLOCK, EclipseGeoAnimations.hold(geoId(), ANIM_UNLOCK));
    }

    // --- ticking ---

    @Override
    public void tick() {
        super.tick();
        if (!this.level().isClientSide && this.level() instanceof ServerLevel serverLevel
                && this.tickCount % VEIL_REFIRE_TICKS == 0) {
            Vec3 center = this.position().add(0.0D, VEIL_CENTER_Y, 0.0D);
            FxPayloads.sendFxEvent(serverLevel, FxCues.CUE_PORTAL_VEIL, center,
                    this.getYRot(), 0.0F, VEIL_RANGE);
        }
    }

    // --- immovable-prop chassis ---

    @Override
    protected void registerGoals() {
        // No AI: the gate stands.
    }

    @Override
    public boolean isInvulnerableTo(DamageSource source) {
        return !source.is(DamageTypeTags.BYPASSES_INVULNERABILITY) || super.isInvulnerableTo(source);
    }

    @Override
    public boolean isPushable() {
        return false;
    }

    @Override
    public void knockback(double strength, double x, double z) {
        // Anchored.
    }

    @Override
    public void travel(Vec3 travelVector) {
        // Immobile: no drift, no gravity, no fluid push.
    }

    @Override
    public void checkDespawn() {
        // Never despawns.
    }

    @Override
    public boolean removeWhenFarAway(double distanceToClosestPlayer) {
        return false;
    }

    @Override
    protected boolean shouldDespawnInPeaceful() {
        return false;
    }

    @Override
    public boolean isPersistenceRequired() {
        return true;
    }
}
