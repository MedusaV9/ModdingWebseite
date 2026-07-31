package dev.projecteclipse.eclipse.woah.mansiondome;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoMob;
import net.minecraft.network.syncher.EntityDataAccessor;
import net.minecraft.network.syncher.EntityDataSerializers;
import net.minecraft.network.syncher.SynchedEntityData;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.tags.DamageTypeTags;
import net.minecraft.util.Mth;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.AnimationState;
import software.bernie.geckolib.animation.PlayState;

/**
 * WOAH-01 §3.3 — the GLITCH EMITTER standing on the mansion roof: rotating rings, a
 * pulsing green core (glowmask) and the antenna the sky beam rises from. Scenery-with-
 * state on the {@code PortalGateEntity} chassis: gravity-free, immobile, persisted,
 * never despawns.
 *
 * <p><b>Hit handling</b> — deliberately NOT vanilla health: only a direct player MELEE
 * blow counts (no projectiles, no explosions, no fire — cheese gets a deflection chime
 * instead). Valid hits are gated by a {@value #HIT_IFRAME_TICKS}-tick i-frame window,
 * play the {@value #ANIM_HIT} ring-desync flinch (except the killing blow, which yields
 * the action controller to the collapse) and delegate the counting to
 * {@link MansionDomeService#onDeviceHit} — {@code MansionDomeState.hitsRemaining} is the
 * authority, the synced {@link #DATA_HITS} only drives client crack/spark feedback
 * (renderer tint + jitter below 4/2 hits).</p>
 */
public class DomeEmitterEntity extends EclipseGeoMob {
    /** I-frame window between two counted melee hits. */
    public static final int HIT_IFRAME_TICKS = 10;
    public static final String ANIM_HIT = "hit";

    /** Mirrors {@code MansionDomeState.hitsRemaining} for client crack stages. */
    private static final EntityDataAccessor<Integer> DATA_HITS =
            SynchedEntityData.defineId(DomeEmitterEntity.class, EntityDataSerializers.INT);

    /** Game time of the last COUNTED hit (the i-frame gate). Server only. */
    private long lastHitGameTime = Long.MIN_VALUE;

    public DomeEmitterEntity(EntityType<? extends DomeEmitterEntity> entityType, Level level) {
        super(entityType, level);
        this.setNoGravity(true);
        this.noCulling = true;
        this.setPersistenceRequired();
    }

    @Override
    public String geoId() {
        return "glitch_emitter";
    }

    // --- state ---

    public int hitsRemaining() {
        return this.entityData.get(DATA_HITS);
    }

    /** Service-side mirror write (state → entity, never the other way around). */
    public void setHitsRemaining(int hits) {
        this.entityData.set(DATA_HITS, Mth.clamp(hits, 0, MansionDomeState.MAX_HITS));
    }

    @Override
    protected void defineSynchedData(SynchedEntityData.Builder builder) {
        super.defineSynchedData(builder);
        builder.define(DATA_HITS, MansionDomeState.MAX_HITS);
    }

    // --- hit handling (§3.3) ---

    @Override
    public boolean hurt(DamageSource source, float amount) {
        if (source.is(DamageTypeTags.BYPASSES_INVULNERABILITY)) {
            return super.hurt(source, amount); // /kill and the void always work.
        }
        if (this.level().isClientSide) {
            return false;
        }
        // Only a direct player melee blow counts: the attacking entity must BE the direct
        // entity (a projectile's direct entity is the projectile, an explosion has none).
        if (!(source.getDirectEntity() instanceof Player player)
                || source.getEntity() != source.getDirectEntity()) {
            deflect();
            return false;
        }
        long now = this.level().getGameTime();
        if (now - this.lastHitGameTime < HIT_IFRAME_TICKS) {
            return false; // Inside the i-frame window: silently absorbed.
        }
        this.lastHitGameTime = now;
        // Manual flinch feedback: super.hurt is never called (no vanilla health flow),
        // so drive the red-flash timers the renderer reads directly.
        this.hurtTime = this.hurtDuration = 10;
        // The KILLING blow skips the flinch: onDeviceHit below starts the collapse, whose
        // t0 beat fires "death" on the SAME action controller a tick later, and GeckoLib
        // hard-swaps a newly triggered animation mid-play (handleAnimationState ->
        // setAnimation, no blend at transitionLength 0). The flinch would be cut off one
        // tick in — at the peak of its recoil — and pop into the collapse's neutral pose.
        if (this.hitsRemaining() > 1) {
            triggerAction(ANIM_HIT);
        }
        if (player instanceof ServerPlayer serverPlayer) {
            MansionDomeService.onDeviceHit(this, serverPlayer);
        }
        return false; // No vanilla damage pipeline (knockback/anger/death) ever runs.
    }

    /** "That did nothing" chime for projectiles/explosions/fire (plan §6). */
    private void deflect() {
        this.level().playSound(null, this.blockPosition(), SoundEvents.AMETHYST_BLOCK_CHIME,
                SoundSource.NEUTRAL, 0.8F, 1.6F);
    }

    @Override
    public InteractionResult mobInteract(Player player, InteractionHand hand) {
        return InteractionResult.PASS; // The device only answers to fists.
    }

    // --- animation wiring ---

    @Override
    protected PlayState handleBaseState(AnimationState<?> state) {
        return state.setAndContinue(idleAnim()); // Always the ring-spin idle; never walk.
    }

    @Override
    protected void registerActionTriggers(AnimationController<?> action) {
        super.registerActionTriggers(action); // death (held) — the t0 collapse pose.
        action.triggerableAnim(ANIM_HIT, EclipseGeoAnimations.once(geoId(), ANIM_HIT));
    }

    // --- immovable-prop chassis (PortalGateEntity pattern) ---

    @Override
    protected void registerGoals() {
        // No AI: the emitter stands.
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
    public void travel(net.minecraft.world.phys.Vec3 travelVector) {
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
