package dev.projecteclipse.eclipse.entity.glitch;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoMonster;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityEvent;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import software.bernie.geckolib.animation.AnimationController;

/**
 * Shared base for the three GLITCHED variants (plan §2.3 "glitched" sheet): the
 * behaviors every corruption shares, so husk/hound/tick stay thin kind classes.
 *
 * <ul>
 *   <li><b>Glitch blink</b> (husk + hound; the tick opts out): every
 *       {@link #blinkCooldownMinTicks()}–{@link #blinkCooldownMaxTicks()} t with a live
 *       target, the mob teleports to a random spot within {@value #BLINK_RANGE} blocks
 *       (ground-snapped via {@code randomTeleport}), leaving paired
 *       {@code REVERSE_PORTAL} bursts at origin and exit plus the {@code glitch_blink}
 *       one-shot — the plan's "teleport-stutter". P2's {@code eclipse:glitch_pop}
 *       emitter replaces the vanilla burst later (§4.2).</li>
 *   <li><b>Glitch ambience:</b> sparse client-side {@code WHITE_ASH} static motes with
 *       an occasional {@code REVERSE_PORTAL} spark.</li>
 *   <li><b>Scripted dissolve death:</b> the held {@code death} anims freeze-frame and
 *       collapse into the glow seams; the entity mirrors that with a
 *       {@link #deathAnimTicks()} t window of portal static before the poof (renderers
 *       suppress the vanilla tip-over).</li>
 * </ul>
 */
public abstract class GlitchedMonster extends EclipseGeoMonster {
    /** Extra triggerable on the {@code action} controller (husk + hound anim files). */
    public static final String ANIM_GLITCH_BLINK = "glitch_blink";
    /** Blink displacement radius, blocks (plan: "4-block random offset teleport"). */
    private static final double BLINK_RANGE = 4.0D;
    private static final int BLINK_ATTEMPTS = 8;

    /** Entity tick the next blink unlocks ({@code tickCount} clock); husk/hound only. */
    private int blinkReadyAtTick;

    protected GlitchedMonster(EntityType<? extends GlitchedMonster> entityType, Level level) {
        super(entityType, level);
        this.blinkReadyAtTick = rollBlinkCooldown(60); // Never blink in the first seconds.
    }

    // --- kind knobs ---

    /** Min blink cooldown in ticks, or {@code -1} to disable blinking (tick kind). */
    protected int blinkCooldownMinTicks() {
        return -1;
    }

    /** Max blink cooldown in ticks (only read when blinking is enabled). */
    protected int blinkCooldownMaxTicks() {
        return blinkCooldownMinTicks();
    }

    /** Scripted death window in ticks — matches the kind's held {@code death} anim. */
    protected abstract int deathAnimTicks();

    // --- GeckoLib (frozen base-class hooks) ---

    @Override
    protected void registerActionTriggers(AnimationController<?> action) {
        super.registerActionTriggers(action); // death (hold on last frame)
        action.triggerableAnim(EclipseGeoAnimations.ANIM_ATTACK,
                EclipseGeoAnimations.once(geoId(), EclipseGeoAnimations.ANIM_ATTACK));
        if (blinkCooldownMinTicks() > 0) {
            action.triggerableAnim(ANIM_GLITCH_BLINK,
                    EclipseGeoAnimations.once(geoId(), ANIM_GLITCH_BLINK));
        }
    }

    // --- shared behavior ---

    @Override
    public void aiStep() {
        super.aiStep();
        if (this.level().isClientSide) {
            if (this.isAlive() && this.random.nextInt(12) == 0) {
                // Static sloughing off the seams; the rare spark is the "dropped frame".
                this.level().addParticle(
                        this.random.nextInt(6) == 0 ? ParticleTypes.REVERSE_PORTAL
                                : ParticleTypes.WHITE_ASH,
                        this.getRandomX(0.7D), this.getRandomY(), this.getRandomZ(0.7D),
                        0.0D, 0.01D, 0.0D);
            }
            return;
        }
        if (blinkCooldownMinTicks() > 0 && this.isAlive() && this.getTarget() != null
                && this.getTarget().isAlive() && this.tickCount >= this.blinkReadyAtTick) {
            if (tryBlink()) {
                this.blinkReadyAtTick = this.tickCount
                        + rollBlinkCooldown(blinkCooldownMinTicks());
            } else {
                this.blinkReadyAtTick = this.tickCount + 20; // Cramped spot: retry soon.
            }
        }
    }

    private int rollBlinkCooldown(int min) {
        int max = Math.max(min, blinkCooldownMaxTicks());
        return min + this.random.nextInt(max - min + 1);
    }

    /** The stutter-blink: random ground-snapped hop within {@value #BLINK_RANGE} blocks. */
    private boolean tryBlink() {
        if (!(this.level() instanceof ServerLevel serverLevel)) {
            return false;
        }
        Vec3 origin = this.position();
        for (int attempt = 0; attempt < BLINK_ATTEMPTS; attempt++) {
            double x = this.getX() + (this.random.nextDouble() * 2.0D - 1.0D) * BLINK_RANGE;
            double y = this.getY() + (this.random.nextInt(5) - 2);
            double z = this.getZ() + (this.random.nextDouble() * 2.0D - 1.0D) * BLINK_RANGE;
            if (this.randomTeleport(x, y, z, false)) {
                // Paired bursts: where it was, and where it re-renders.
                serverLevel.sendParticles(ParticleTypes.REVERSE_PORTAL,
                        origin.x, origin.y + this.getBbHeight() * 0.5D, origin.z,
                        12, 0.3D, 0.4D, 0.3D, 0.03D);
                serverLevel.sendParticles(ParticleTypes.REVERSE_PORTAL,
                        this.getX(), this.getY() + this.getBbHeight() * 0.5D, this.getZ(),
                        12, 0.3D, 0.4D, 0.3D, 0.03D);
                serverLevel.playSound(null, this.blockPosition(), SoundEvents.ENDERMAN_TELEPORT,
                        SoundSource.HOSTILE, 0.5F, 1.5F);
                triggerAction(ANIM_GLITCH_BLINK);
                return true;
            }
        }
        return false;
    }

    // --- combat/death hooks (GeckoLib one-shots) ---

    @Override
    public boolean doHurtTarget(Entity target) {
        boolean hurt = super.doHurtTarget(target);
        if (hurt && !this.level().isClientSide) {
            triggerAction(EclipseGeoAnimations.ANIM_ATTACK);
        }
        return hurt;
    }

    @Override
    public void die(DamageSource damageSource) {
        super.die(damageSource);
        if (!this.level().isClientSide) {
            triggerAction(EclipseGeoAnimations.ANIM_DEATH);
        }
    }

    /** Frame-freeze collapse: portal static while the held anim folds, then the poof. */
    @Override
    protected void tickDeath() {
        this.deathTime++;
        if (!(this.level() instanceof ServerLevel serverLevel)) {
            return; // Client: the held death anim plays; deathTime is cosmetic here.
        }
        if (this.deathTime % 3 == 0) {
            serverLevel.sendParticles(ParticleTypes.REVERSE_PORTAL,
                    this.getX(), this.getY() + this.getBbHeight() * 0.4D, this.getZ(),
                    3, 0.25D, 0.3D, 0.25D, 0.02D);
            serverLevel.sendParticles(ParticleTypes.WHITE_ASH,
                    this.getX(), this.getY() + this.getBbHeight() * 0.6D, this.getZ(),
                    2, 0.3D, 0.3D, 0.3D, 0.01D);
        }
        if (this.deathTime >= deathAnimTicks() && !this.isRemoved()) {
            serverLevel.broadcastEntityEvent(this, EntityEvent.POOF);
            this.remove(RemovalReason.KILLED);
        }
    }

    /**
     * Enderman-style gaze test: is {@code observer} actually looking at this mob (view
     * ray within the angular tolerance AND line of sight)? Used by the husk's
     * unseen-burst and handy for future kinds.
     */
    protected boolean isLookedAtBy(LivingEntity observer) {
        Vec3 view = observer.getViewVector(1.0F).normalize();
        Vec3 toMob = new Vec3(this.getX() - observer.getX(),
                this.getEyeY() - observer.getEyeY(), this.getZ() - observer.getZ());
        double distance = toMob.length();
        if (distance < 1.0E-4D) {
            return true;
        }
        double dot = view.dot(toMob.normalize());
        return dot > 1.0D - 0.025D / distance && observer.hasLineOfSight(this);
    }
}
