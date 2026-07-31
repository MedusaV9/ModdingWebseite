package dev.projecteclipse.eclipse.ferryman.finale;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
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
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import software.bernie.geckolib.animation.AnimationController;
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
 *
 * <p><b>MA5 seating beat</b>: {@link FinaleSequence} ends the flight by simply
 * {@code discard()}ing the key, which left its {@code unlock_turn} sheet no frame to
 * render on. {@link #remove(Entity.RemovalReason)} therefore intercepts exactly that
 * one call (server side, still flying, not yet seated) and hands it to
 * {@link #seatIntoKeyhole()}: the key freezes in the keyhole, plays the three-detent
 * tumbler turn and is removed {@value #SEAT_TURN_TICKS}t later by {@link SeatWatch} —
 * inside the {@code UNLOCK_HOLD_TICKS} window and before {@code BREACH_AT_TICK}.
 * Removal rides the SERVER tick, not this entity's, so a gate whose chunk is loaded
 * but not entity-ticking cannot strand a key (see {@link #SEATED}); and while seated
 * the key is neither persisted nor saved, so a crash mid-turn leaves nothing behind
 * either.</p>
 */
public class PortalKeyEntity extends EclipseGeoMob {
    public static final String ANIM_FLY = "fly";
    /**
     * Three-detent tumbler turn (MA5). The sheet's detents sit at 0.40 s / 1.10 s /
     * 1.80 s = UNLOCK tick 8 / 22 / 36 — the exact ticks {@code FinaleSequence}'s
     * {@code KEYGLYPH_CLICKS_AT} stings and B7's baked glyph-ring snaps land on.
     */
    public static final String ANIM_UNLOCK_TURN = "unlock_turn";
    /** Walk-in trigger inflation around the hitbox. */
    private static final double TOUCH_RANGE = 0.6D;
    /** Sheet is 2.4 s = 48t; leaving at 46t keeps the t=50 breach beat clean. */
    private static final int SEAT_TURN_TICKS = 46;

    /** True while the flight script owns the key (drives fly anim + client trail). */
    private static final EntityDataAccessor<Boolean> DATA_FLYING =
            SynchedEntityData.defineId(PortalKeyEntity.class, EntityDataSerializers.BOOLEAN);
    /** True once the key sits in the keyhole (holds the turn pose for late joiners). */
    private static final EntityDataAccessor<Boolean> DATA_SEATED =
            SynchedEntityData.defineId(PortalKeyEntity.class, EntityDataSerializers.BOOLEAN);

    /**
     * Seated keys still playing out their turn. The countdown deliberately rides the
     * SERVER tick ({@link SeatWatch}), not {@link #tick()}: the gate can stand far
     * enough from every player that its chunk is loaded but NOT entity-ticking (a
     * headless run reproduces it exactly), and an entity-tick countdown then never
     * reaches zero — the key would sit in the keyhole until the world unloaded and
     * greet the next player who walks up. The old code's unconditional
     * {@code discard()} could not leak; neither may this one.
     */
    private static final List<PortalKeyEntity> SEATED = new ArrayList<>();

    /** Server-tick countdown to the self-discard at the end of the turn (−1 = idle). */
    private int seatTicks = -1;

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

    /** True while the key sits in the keyhole playing (or holding) the tumbler turn. */
    public boolean isSeated() {
        return this.entityData.get(DATA_SEATED);
    }

    /**
     * Seats the key: freeze in place, fire the three-detent {@code unlock_turn} and
     * arm the self-discard. Idempotent; the sequence never has to know about it
     * (see the {@link #remove(Entity.RemovalReason)} interception).
     */
    public void seatIntoKeyhole() {
        if (isSeated() || this.level().isClientSide) {
            return;
        }
        setFlying(false);
        this.entityData.set(DATA_SEATED, true);
        this.setDeltaMovement(Vec3.ZERO);
        this.hurtMarked = true;
        this.noPhysics = true;
        this.seatTicks = SEAT_TURN_TICKS;
        SEATED.add(this);
        snapToKeyhole();
        triggerAction(ANIM_UNLOCK_TURN);
    }

    /**
     * Drives every seated key's countdown off the server tick and removes it when the
     * turn has played out — the leak guard described on {@link #SEATED}.
     */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID)
    public static final class SeatWatch {
        private SeatWatch() {
        }

        @SubscribeEvent
        static void onServerTick(ServerTickEvent.Post event) {
            if (SEATED.isEmpty()) {
                return;
            }
            for (Iterator<PortalKeyEntity> it = SEATED.iterator(); it.hasNext();) {
                PortalKeyEntity key = it.next();
                if (key.isRemoved()) {
                    it.remove();
                } else if (--key.seatTicks <= 0) {
                    key.discard(); // seated + not flying -> the interception passes it through
                    it.remove();
                }
            }
        }

        @SubscribeEvent
        static void onServerStopped(ServerStoppedEvent event) {
            SEATED.clear(); // the statics outlive the integrated server between worlds
        }
    }

    /**
     * Squares the key up in the keyhole before the turn starts: the flight can end up
     * to ~1 block short (its arrival check is a distance test), and a key turning
     * askew next to the door reads as a bug. Same keyhole derivation as
     * {@code FinaleSequence} (gate feet + 4.5, one block out along the door's local
     * −Z), yaw = the gate's facing + 180° so the key points INTO the door — which is
     * exactly the axis the sheet drives it along.
     */
    private void snapToKeyhole() {
        PortalGateEntity gate = this.level()
                .getEntitiesOfClass(PortalGateEntity.class,
                        this.getBoundingBox().inflate(8.0D), PortalGateEntity::isAlive)
                .stream().findFirst().orElse(null);
        if (gate == null) {
            return;
        }
        float yaw = gate.getYRot();
        double rad = Math.toRadians(yaw);
        Vec3 forward = new Vec3(-Math.sin(rad), 0.0D, Math.cos(rad));
        Vec3 keyhole = gate.position().add(0.0D, 4.5D, 0.0D).add(forward);
        this.moveTo(keyhole.x, keyhole.y, keyhole.z, yaw + 180.0F, 0.0F);
        this.setYBodyRot(this.getYRot());
        this.setYHeadRot(this.getYRot());
    }

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
        super.defineSynchedData(builder);
        builder.define(DATA_FLYING, false);
        builder.define(DATA_SEATED, false);
    }

    @Override
    protected PlayState handleBaseState(AnimationState<?> state) {
        if (isSeated()) {
            // Late-joiner replay of the held end pose (the gate's DATA_OPEN pattern);
            // on a client that saw the trigger the action one-shot wins the blend.
            return state.setAndContinue(
                    EclipseGeoAnimations.hold(geoId(), ANIM_UNLOCK_TURN));
        }
        return state.setAndContinue(isFlying()
                ? EclipseGeoAnimations.loop(geoId(), ANIM_FLY)
                : idleAnim());
    }

    @Override
    protected void registerActionTriggers(AnimationController<?> action) {
        super.registerActionTriggers(action);
        action.triggerableAnim(ANIM_UNLOCK_TURN,
                EclipseGeoAnimations.hold(geoId(), ANIM_UNLOCK_TURN));
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
        if (isSeated()) {
            return; // SeatWatch owns the rest of this key's life
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

    /**
     * The sequence's "the key is consumed" call ({@code Entity.discard()} is final, so
     * the interception sits one level down on the removal itself). While the flight
     * owns the key, a DISCARDED removal IS the seating beat and becomes the tumbler
     * turn instead of an instant vanish; every other removal — the duplicate-key sweep
     * (never flying), chunk unload/world teardown (other reasons) and the self-discard
     * at the end of the turn (already seated) — passes straight through.
     */
    @Override
    public void remove(Entity.RemovalReason reason) {
        if (reason == Entity.RemovalReason.DISCARDED && !this.level().isClientSide
                && isFlying() && !isSeated() && !this.isRemoved()) {
            seatIntoKeyhole();
            return;
        }
        super.remove(reason);
    }

    @Override
    public void checkDespawn() {
        // Never despawns; the seating beat discards it at the keyhole.
    }

    @Override
    public boolean removeWhenFarAway(double distanceToClosestPlayer) {
        return false;
    }

    @Override
    protected boolean shouldDespawnInPeaceful() {
        return false;
    }

    /** Persisted while it waits — but NEVER while seated (no key may survive a crash
     * mid-turn stuck in the keyhole; the wisp's despawn-guarantee doctrine). */
    @Override
    public boolean isPersistenceRequired() {
        return !isSeated();
    }

    @Override
    public boolean shouldBeSaved() {
        return !isSeated() && super.shouldBeSaved();
    }
}
