package dev.projecteclipse.eclipse.entity.fog;

import java.util.EnumSet;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.phys.Vec3;

/**
 * Storm Hound special (plan §2.3): with a target {@value #MIN_RANGE}–{@value #MAX_RANGE}
 * blocks out, line of sight, solid footing and the {@value #COOLDOWN_TICKS} t cooldown
 * up, the hound roots for a {@value #WINDUP_TICKS} t windup ({@code charge_windup}
 * one-shot — crouch + the {@code glow_spine} shards scale up, so the glowmask visibly
 * ramps; spark ticks underline it), then dashes a straight line at {@value #DASH_SPEED}
 * blocks/t for up to {@value #MAX_DASH_TICKS} t (≈ 12 blocks).
 *
 * <p><b>Hit:</b> the first living non-hound clipped takes {@value #LUNGE_DAMAGE} dmg +
 * Slowness IV 1 s ("static-locked") in an ELECTRIC_SPARK burst; the dash ends in a bite
 * ({@code attack} one-shot). <b>Miss</b> (dash runs out or the hound slams a wall): a
 * {@value #STAGGER_TICKS} t self-stagger — the hound stands sparking and helpless, the
 * sidestep counterplay window. The dash direction locks at windup end, so strafing
 * during the crouch dodges the whole line.</p>
 *
 * <p>Holds MOVE+LOOK+JUMP above the leap/melee goals so nothing else steers mid-charge.</p>
 */
public class ChargedLungeGoal extends Goal {
    private static final int WINDUP_TICKS = 20;
    private static final int STAGGER_TICKS = 40; // 2 s
    private static final int COOLDOWN_TICKS = 160;
    private static final double MIN_RANGE = 6.0D;
    private static final double MAX_RANGE = 14.0D;
    private static final double DASH_SPEED = 0.9D;
    /** 12-block dash line at {@value #DASH_SPEED}/t. */
    private static final int MAX_DASH_TICKS = 14;
    private static final float LUNGE_DAMAGE = 6.0F;
    private static final int SLOWNESS_TICKS = 20; // 1 s, amplifier IV

    private enum Phase { IDLE, WINDUP, DASH, STAGGER }

    private final StormHoundEntity hound;
    private Phase phase = Phase.IDLE;
    private int phaseTicks;
    /** Entity tick the lunge becomes available again ({@code tickCount} clock). */
    private int readyAtTick;
    private Vec3 dashDirection = Vec3.ZERO;
    private boolean connected;

    public ChargedLungeGoal(StormHoundEntity hound) {
        this.hound = hound;
        this.readyAtTick = 60; // Fresh spawns close the distance once before charging.
        this.setFlags(EnumSet.of(Goal.Flag.MOVE, Goal.Flag.LOOK, Goal.Flag.JUMP));
    }

    @Override
    public boolean canUse() {
        if (this.hound.tickCount < this.readyAtTick || !this.hound.onGround()) {
            return false;
        }
        LivingEntity target = this.hound.getTarget();
        if (target == null || !target.isAlive() || !this.hound.hasLineOfSight(target)) {
            return false;
        }
        double distance = this.hound.distanceTo(target);
        return distance >= MIN_RANGE && distance <= MAX_RANGE;
    }

    @Override
    public boolean canContinueToUse() {
        return this.phase != Phase.IDLE;
    }

    @Override
    public boolean requiresUpdateEveryTick() {
        return true;
    }

    @Override
    public void start() {
        this.phase = Phase.WINDUP;
        this.phaseTicks = WINDUP_TICKS;
        this.connected = false;
        this.hound.getNavigation().stop();
        this.hound.triggerAction(StormHoundEntity.ANIM_CHARGE_WINDUP);
        this.hound.level().playSound(null, this.hound.blockPosition(),
                SoundEvents.WARDEN_SONIC_CHARGE, SoundSource.HOSTILE, 0.6F, 1.9F);
        EclipseMod.LOGGER.info("Storm Hound {} winds up a charged lunge at {}",
                this.hound.getId(), this.hound.blockPosition());
    }

    @Override
    public void stop() {
        this.phase = Phase.IDLE;
        this.readyAtTick = this.hound.tickCount + COOLDOWN_TICKS;
    }

    @Override
    public void tick() {
        switch (this.phase) {
            case WINDUP -> tickWindup();
            case DASH -> tickDash();
            case STAGGER -> tickStagger();
            default -> { }
        }
    }

    // --- phases ---

    private void tickWindup() {
        LivingEntity target = this.hound.getTarget();
        if (target == null || !target.isAlive()) {
            this.phase = Phase.IDLE; // Aborted windup; stop() applies the cooldown.
            return;
        }
        this.hound.getNavigation().stop();
        this.hound.setDeltaMovement(0.0D, this.hound.getDeltaMovement().y, 0.0D);
        this.hound.getLookControl().setLookAt(target, 30.0F, 30.0F);
        if (this.hound.level() instanceof ServerLevel serverLevel && this.phaseTicks % 2 == 0) {
            serverLevel.sendParticles(ParticleTypes.ELECTRIC_SPARK,
                    this.hound.getX(), this.hound.getY() + 0.8D, this.hound.getZ(),
                    2, 0.35D, 0.25D, 0.35D, 0.05D);
        }
        if (--this.phaseTicks <= 0) {
            // Commit: the dash line locks on the target's CURRENT position (dodgeable).
            Vec3 line = target.position().subtract(this.hound.position());
            this.dashDirection = new Vec3(line.x, 0.0D, line.z).normalize();
            if (this.dashDirection.lengthSqr() < 1.0E-4D) {
                this.dashDirection = Vec3.directionFromRotation(0.0F, this.hound.getYRot());
            }
            this.phase = Phase.DASH;
            this.phaseTicks = MAX_DASH_TICKS;
            this.hound.triggerAction(StormHoundEntity.ANIM_LUNGE);
            this.hound.level().playSound(null, this.hound.blockPosition(),
                    SoundEvents.TRIDENT_RIPTIDE_1.value(), SoundSource.HOSTILE, 1.0F, 1.3F);
        }
    }

    private void tickDash() {
        // Steer the whole dash manually: locked line, gravity untouched.
        this.hound.setDeltaMovement(this.dashDirection.x * DASH_SPEED,
                this.hound.getDeltaMovement().y, this.dashDirection.z * DASH_SPEED);
        this.hound.setYRot((float) (Math.atan2(this.dashDirection.x, -this.dashDirection.z)
                * -(180.0D / Math.PI)));
        this.hound.setYBodyRot(this.hound.getYRot());
        if (!(this.hound.level() instanceof ServerLevel serverLevel)) {
            return;
        }
        serverLevel.sendParticles(ParticleTypes.ELECTRIC_SPARK,
                this.hound.getX(), this.hound.getY() + 0.6D, this.hound.getZ(),
                2, 0.25D, 0.2D, 0.25D, 0.08D);
        // First living non-hound clipped by the dash takes the arc.
        List<LivingEntity> hits = serverLevel.getEntitiesOfClass(LivingEntity.class,
                this.hound.getBoundingBox().inflate(0.4D),
                entity -> entity != this.hound && entity.isAlive()
                        && !(entity instanceof StormHoundEntity)
                        && (!(entity instanceof Player player) || !player.isSpectator()));
        if (!hits.isEmpty()) {
            strike(serverLevel, hits.get(0));
            return;
        }
        if (this.hound.horizontalCollision || --this.phaseTicks <= 0) {
            beginStagger(serverLevel);
        }
    }

    private void strike(ServerLevel serverLevel, LivingEntity victim) {
        this.connected = true;
        victim.hurt(this.hound.damageSources().mobAttack(this.hound), LUNGE_DAMAGE);
        victim.addEffect(new MobEffectInstance(MobEffects.MOVEMENT_SLOWDOWN, SLOWNESS_TICKS, 3),
                this.hound); // Slowness IV: "static-locked"
        serverLevel.sendParticles(ParticleTypes.ELECTRIC_SPARK,
                victim.getX(), victim.getY() + victim.getBbHeight() * 0.6D, victim.getZ(),
                16, 0.4D, 0.5D, 0.4D, 0.25D);
        serverLevel.playSound(null, victim.blockPosition(), SoundEvents.TRIDENT_THUNDER.value(),
                SoundSource.HOSTILE, 0.5F, 1.6F);
        this.hound.triggerAction(EclipseGeoAnimations.ANIM_ATTACK); // Bite finish.
        this.hound.setDeltaMovement(this.hound.getDeltaMovement().scale(0.2D));
        EclipseMod.LOGGER.info("Storm Hound {} lunge connected: {} static-locked",
                this.hound.getId(), victim.getName().getString());
        this.phase = Phase.IDLE; // Done; stop() applies the cooldown.
    }

    private void beginStagger(ServerLevel serverLevel) {
        this.phase = Phase.STAGGER;
        this.phaseTicks = STAGGER_TICKS;
        this.hound.setDeltaMovement(Vec3.ZERO);
        serverLevel.playSound(null, this.hound.blockPosition(), SoundEvents.WOLF_WHINE,
                SoundSource.HOSTILE, 0.9F, 0.8F);
        EclipseMod.LOGGER.info("Storm Hound {} lunge missed — staggered {}t",
                this.hound.getId(), STAGGER_TICKS);
    }

    private void tickStagger() {
        this.hound.getNavigation().stop();
        this.hound.setDeltaMovement(0.0D, this.hound.getDeltaMovement().y, 0.0D);
        if (this.hound.level() instanceof ServerLevel serverLevel && this.phaseTicks % 6 == 0) {
            // Discharge fizzle: the missed charge bleeds off harmlessly.
            serverLevel.sendParticles(ParticleTypes.SMOKE,
                    this.hound.getX(), this.hound.getY() + 0.7D, this.hound.getZ(),
                    2, 0.25D, 0.2D, 0.25D, 0.01D);
            serverLevel.sendParticles(ParticleTypes.ELECTRIC_SPARK,
                    this.hound.getX(), this.hound.getY() + 0.5D, this.hound.getZ(),
                    1, 0.3D, 0.15D, 0.3D, 0.02D);
        }
        if (--this.phaseTicks <= 0) {
            this.phase = Phase.IDLE;
        }
    }

    /** Whether the last completed lunge connected (test/telemetry hook). */
    public boolean lastLungeConnected() {
        return this.connected;
    }
}
