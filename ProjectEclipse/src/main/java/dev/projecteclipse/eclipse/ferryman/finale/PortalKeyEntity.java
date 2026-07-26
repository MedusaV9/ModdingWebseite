package dev.projecteclipse.eclipse.ferryman.finale;

import java.util.List;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoMob;
import net.minecraft.network.syncher.EntityDataAccessor;
import net.minecraft.network.syncher.EntityDataSerializers;
import net.minecraft.network.syncher.SynchedEntityData;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.tags.DamageTypeTags;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import software.bernie.geckolib.animation.AnimationState;
import software.bernie.geckolib.animation.PlayState;

/**
 * F-045b — the giant golden-violet finale key (~3 blocks) hovering over the altar once
 * the portal gate stands. Right-clicking it OR walking into it hands control to
 * {@link FinaleSequence#tryStartKeySequence}; the sequence then drives the key's ~10 s
 * flight to the gate keyhole (velocity-scripted like the Ferryman's own drift — the
 * vanilla tracker lerp keeps it smooth on clients).
 *
 * <p>Invulnerable and persisted while it waits (a restart mid-wait keeps the key), no
 * gravity, no AI. The synced {@code DATA_FLYING} flag switches the base controller from
 * the hover {@code idle} loop to the fast {@code fly} spin AND gates the client-side
 * Photon trail seam ({@code FerrymanFinaleFxRows.keyTrail} — the herald-shard-ribbon
 * exemption: entity-attached loop, auto-destroyed with the entity).</p>
 */
public class PortalKeyEntity extends EclipseGeoMob {
    public static final String ANIM_FLY = "fly";
    /** Walk-in trigger inflation around the hitbox. */
    private static final double TOUCH_RANGE = 0.6D;

    /** True while the flight script owns the key (drives fly anim + client trail). */
    private static final EntityDataAccessor<Boolean> DATA_FLYING =
            SynchedEntityData.defineId(PortalKeyEntity.class, EntityDataSerializers.BOOLEAN);

    public PortalKeyEntity(EntityType<? extends PortalKeyEntity> entityType, Level level) {
        super(entityType, level);
        this.setNoGravity(true);
        this.noCulling = true;
        this.setPersistenceRequired();
        this.setInvulnerable(true);
    }

    @Override
    public String geoId() {
        return "portal_key";
    }

    // --- state ---

    public boolean isFlying() {
        return this.entityData.get(DATA_FLYING);
    }

    public void setFlying(boolean flying) {
        this.entityData.set(DATA_FLYING, flying);
        this.noPhysics = flying; // the flight passes over water/rails unhindered
    }

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
        super.defineSynchedData(builder);
        builder.define(DATA_FLYING, false);
    }

    @Override
    protected PlayState handleBaseState(AnimationState<?> state) {
        return state.setAndContinue(isFlying()
                ? EclipseGeoAnimations.loop(geoId(), ANIM_FLY)
                : idleAnim());
    }

    // --- triggers ---

    @Override
    protected InteractionResult mobInteract(Player player, InteractionHand hand) {
        if (player instanceof ServerPlayer serverPlayer
                && FinaleSequence.tryStartKeySequence(serverPlayer, this)) {
            return InteractionResult.CONSUME;
        }
        return this.level().isClientSide ? InteractionResult.SUCCESS : InteractionResult.PASS;
    }

    @Override
    public void tick() {
        super.tick();
        if (this.level().isClientSide) {
            if (isFlying()) {
                dev.projecteclipse.eclipse.veilfx.FerrymanFinaleFxRows.keyTrail(this);
            }
            return;
        }
        if (!isFlying() && this.tickCount % 5 == 0) {
            // Walk-in trigger: any living player brushing the hover volume starts it.
            List<ServerPlayer> touching = this.level().getEntitiesOfClass(ServerPlayer.class,
                    this.getBoundingBox().inflate(TOUCH_RANGE),
                    player -> player.isAlive() && !player.isSpectator());
            for (ServerPlayer player : touching) {
                if (FinaleSequence.tryStartKeySequence(player, this)) {
                    break;
                }
            }
        }
    }

    // --- immovable-prop chassis (until the flight script drives the velocity) ---

    @Override
    protected void registerGoals() {
        // No AI.
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
        // Gravity-free: the flight script sets the velocity directly.
        if (this.isControlledByLocalInstance() && isFlying()) {
            this.move(net.minecraft.world.entity.MoverType.SELF, this.getDeltaMovement());
            this.setDeltaMovement(this.getDeltaMovement().scale(0.9D));
        }
    }

    @Override
    public void checkDespawn() {
        // Never despawns; FinaleSequence discards it at the keyhole.
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
