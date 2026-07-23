package dev.projecteclipse.eclipse.entity.dungeon;

import java.util.EnumSet;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.phys.Vec3;

/**
 * The Eclipse Cultist's caster brain ({@code docs/plans_v3/P6_mobs_models_builds.md}
 * §2.3): kite to the {@value #MIN_RANGE}–{@value #MAX_RANGE} band, and every
 * {@value #CAST_INTERVAL}t run a {@value #CAST_WINDUP_TICKS}t cast (the {@code cast}
 * trigger anim — runes flare, both arms raise — plus an audible evoker-style tell), then
 * release a <b>3-bolt fan</b> of {@link ShadowBoltProjectile}s: the center bolt aimed at
 * the target's chest, the side bolts angled ±{@value #FAN_SPREAD_DEG}° outward — all three
 * homing-lite, so the fan curves back in late but strafing through a gap works.
 *
 * <p>Kiting: closer than {@value #MIN_RANGE} → scurry away; beyond {@value #MAX_RANGE} or
 * no line of sight → approach; inside the band → hold ground and cast. Crowded (target
 * within {@value #PANIC_RANGE} blocks) → panic knife swipe through
 * {@code doHurtTarget} (which fires the {@code attack} anim) on a
 * {@value #PANIC_COOLDOWN_TICKS}t cooldown, still backpedaling. Casting roots the cultist
 * for the windup — a readable, interruptible tell (any hit does not cancel it, but the
 * stillness telegraphs the release timing).</p>
 */
public class RangedShadowBoltGoal extends Goal {
    public static final double MIN_RANGE = 8.0D;
    public static final double MAX_RANGE = 14.0D;
    public static final int CAST_INTERVAL = 60;
    public static final int CAST_WINDUP_TICKS = 20;
    public static final int FAN_BOLTS = 3;
    public static final double FAN_SPREAD_DEG = 12.0D;

    private static final double PANIC_RANGE = 2.0D;
    private static final int PANIC_COOLDOWN_TICKS = 20;
    private static final double FLEE_SPEED = 1.25D;
    private static final double APPROACH_SPEED = 1.0D;

    private final EclipseCultistEntity cultist;
    private int castTimer;
    /** {@code -1} when not casting; counts the windup down to the release. */
    private int windupTicks = -1;
    private int panicCooldown;

    public RangedShadowBoltGoal(EclipseCultistEntity cultist) {
        this.cultist = cultist;
        this.setFlags(EnumSet.of(Goal.Flag.MOVE, Goal.Flag.LOOK));
    }

    @Override
    public boolean canUse() {
        LivingEntity target = this.cultist.getTarget();
        return target != null && target.isAlive();
    }

    @Override
    public void start() {
        // First cast comes quickly (spawner ambush pacing), but never instantly.
        this.castTimer = CAST_INTERVAL / 2;
        this.windupTicks = -1;
        this.panicCooldown = 0;
    }

    @Override
    public void stop() {
        this.windupTicks = -1;
        this.cultist.getNavigation().stop();
    }

    @Override
    public boolean requiresUpdateEveryTick() {
        return true;
    }

    @Override
    public void tick() {
        LivingEntity target = this.cultist.getTarget();
        if (target == null) {
            return;
        }
        this.cultist.getLookControl().setLookAt(target, 30.0F, 30.0F);
        if (this.panicCooldown > 0) {
            this.panicCooldown--;
        }
        if (this.windupTicks >= 0) {
            tickCastWindup(target);
            return;
        }
        double dist = this.cultist.distanceTo(target);
        tickKite(target, dist);
        tickPanicSwipe(target, dist);
        // Cast cadence: begin the windup when the tell can land fairly (visible target).
        if (--this.castTimer <= 0 && dist <= MAX_RANGE + 6.0D
                && this.cultist.hasLineOfSight(target)) {
            beginCast();
        }
    }

    /** Hold the band: flee under {@value #MIN_RANGE}, chase past {@value #MAX_RANGE}/no-LOS. */
    private void tickKite(LivingEntity target, double dist) {
        if (dist < MIN_RANGE) {
            Vec3 away = this.cultist.position().subtract(target.position());
            if (away.lengthSqr() > 1.0E-4D) {
                Vec3 fleeTo = this.cultist.position().add(away.normalize().scale(MIN_RANGE));
                this.cultist.getNavigation().moveTo(fleeTo.x, fleeTo.y, fleeTo.z, FLEE_SPEED);
            }
        } else if (dist > MAX_RANGE || !this.cultist.hasLineOfSight(target)) {
            this.cultist.getNavigation().moveTo(target, APPROACH_SPEED);
        } else {
            this.cultist.getNavigation().stop();
        }
    }

    /** Crowded (≤{@value #PANIC_RANGE} blocks): knife swipe through {@code doHurtTarget}. */
    private void tickPanicSwipe(LivingEntity target, double dist) {
        if (dist <= PANIC_RANGE && this.panicCooldown <= 0
                && this.cultist.getSensing().hasLineOfSight(target)) {
            this.panicCooldown = PANIC_COOLDOWN_TICKS;
            this.cultist.swing(net.minecraft.world.InteractionHand.MAIN_HAND);
            this.cultist.doHurtTarget(target); // Fires the attack anim + swipe sound.
        }
    }

    private void beginCast() {
        this.windupTicks = CAST_WINDUP_TICKS;
        this.cultist.getNavigation().stop();
        this.cultist.triggerAction(EclipseCultistEntity.ANIM_CAST);
        this.cultist.level().playSound(null, this.cultist.blockPosition(),
                SoundEvents.EVOKER_PREPARE_ATTACK, SoundSource.HOSTILE, 1.0F, 1.3F);
    }

    /** Rooted windup: rune-flare particles, then the 3-bolt fan on release. */
    private void tickCastWindup(LivingEntity target) {
        this.cultist.getNavigation().stop();
        if (this.cultist.level() instanceof ServerLevel serverLevel && this.windupTicks % 4 == 0) {
            serverLevel.sendParticles(ParticleTypes.WITCH,
                    this.cultist.getX(), this.cultist.getY() + 1.4D, this.cultist.getZ(),
                    4, 0.4D, 0.3D, 0.4D, 0.02D);
        }
        if (--this.windupTicks >= 0) {
            return;
        }
        this.windupTicks = -1;
        this.castTimer = CAST_INTERVAL;
        if (!target.isAlive() || !(this.cultist.level() instanceof ServerLevel serverLevel)) {
            return;
        }
        Vec3 aim = new Vec3(target.getX(), target.getY(0.5D), target.getZ())
                .subtract(this.cultist.getEyePosition());
        if (aim.lengthSqr() < 1.0E-4D) {
            return;
        }
        Vec3 center = aim.normalize();
        float spread = (float) Math.toRadians(FAN_SPREAD_DEG);
        for (int i = 0; i < FAN_BOLTS; i++) {
            Vec3 direction = center.yRot(spread * (i - (FAN_BOLTS - 1) / 2.0F));
            serverLevel.addFreshEntity(
                    new ShadowBoltProjectile(serverLevel, this.cultist, direction, target));
        }
        serverLevel.playSound(null, this.cultist.blockPosition(), SoundEvents.SHULKER_SHOOT,
                SoundSource.HOSTILE, 1.0F, 0.6F);
        EclipseMod.LOGGER.debug("Eclipse Cultist {} released a {}-bolt shadow fan at {}",
                this.cultist.getId(), FAN_BOLTS, target.getScoreboardName());
    }
}
