package de.sonic0810.goobymod.entity.goals;

import de.sonic0810.goobymod.GoobyConfig;
import de.sonic0810.goobymod.entity.GoobyEntity;
import java.util.Comparator;
import java.util.EnumSet;
import javax.annotation.Nullable;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.entity.animal.Wolf;
import net.minecraft.world.entity.monster.Creeper;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;

/**
 * Non-combat awareness: Gooby points out a nearby hostile, alarms its owner,
 * and places itself between owner and threat without ever acquiring an attack
 * target. A short hold window prevents alert flicker at the detection edge.
 */
public final class GoobyAlertGoal extends Goal {
    public static final double CREEPER_EARLY_WARNING_BONUS = 4.0;
    private static final int ALERT_HOLD_TICKS = 60;

    private final GoobyEntity gooby;
    @Nullable
    private LivingEntity threat;
    private int scanCooldown;
    private int alertHoldTicks;
    private int alarmCooldown;
    private int moveCooldown;

    public GoobyAlertGoal(GoobyEntity gooby) {
        this.gooby = gooby;
        setFlags(EnumSet.of(Flag.MOVE, Flag.LOOK, Flag.JUMP));
    }

    @Override
    public boolean canUse() {
        if (this.gooby.isActivelyDigging() || this.gooby.isVehicle() || this.gooby.isPassenger()) {
            return false;
        }
        if (this.scanCooldown-- > 0) {
            return false;
        }
        this.scanCooldown = reducedTickDelay(10);
        this.threat = findThreat();
        return this.threat != null;
    }

    @Override
    public boolean canContinueToUse() {
        return this.alertHoldTicks > 0 && !this.gooby.isActivelyDigging()
                && !this.gooby.isVehicle() && !this.gooby.isPassenger();
    }

    @Override
    public void start() {
        this.gooby.wakeUp();
        this.gooby.setAlerting(true);
        this.gooby.setMoodScaredImmediately();
        this.alertHoldTicks = ALERT_HOLD_TICKS;
        this.alarmCooldown = 0;
        this.moveCooldown = 0;
        soundAlarm();
    }

    @Override
    public void tick() {
        if (this.threat != null && this.threat.isAlive()) {
            double hysteresisRadius = detectionRadius(this.threat) + 2.0;
            if (this.gooby.distanceToSqr(this.threat) <= hysteresisRadius * hysteresisRadius) {
                this.alertHoldTicks = ALERT_HOLD_TICKS;
                this.gooby.getLookControl().setLookAt(this.threat, 45.0F, 40.0F);
            } else {
                this.alertHoldTicks--;
            }
        } else {
            this.alertHoldTicks--;
        }

        if (this.alarmCooldown-- <= 0) {
            soundAlarm();
        }
        if (this.moveCooldown-- <= 0) {
            this.moveCooldown = 10;
            moveBetweenOwnerAndThreat();
        }
        if (this.gooby.onGround() && this.gooby.tickCount % 20 == 0
                && this.gooby.getNavigation().isInProgress()) {
            this.gooby.setDeltaMovement(this.gooby.getDeltaMovement().add(0.0, 0.24, 0.0));
        }
    }

    @Override
    public void stop() {
        this.gooby.setAlerting(false);
        this.gooby.getNavigation().stop();
        this.threat = null;
        this.alertHoldTicks = 0;
    }

    @Nullable
    private LivingEntity findThreat() {
        double radius = GoobyConfig.alertRadius() + CREEPER_EARLY_WARNING_BONUS;
        AABB search = this.gooby.getBoundingBox().inflate(radius, 5.0, radius);
        return this.gooby.level().getEntitiesOfClass(LivingEntity.class, search,
                        candidate -> candidate.isAlive()
                                && (candidate instanceof Monster
                                        || candidate instanceof Wolf wolf && !wolf.isTame())
                                && this.gooby.distanceToSqr(candidate)
                                <= detectionRadius(candidate) * detectionRadius(candidate)
                                && this.gooby.getSensing().hasLineOfSight(candidate))
                .stream()
                .min(Comparator.comparingDouble(this.gooby::distanceToSqr))
                .orElse(null);
    }

    public static double detectionRadius(LivingEntity threat) {
        if (threat instanceof Creeper && GoobyConfig.creeperAlarm()) {
            return GoobyConfig.alertRadius() + CREEPER_EARLY_WARNING_BONUS;
        }
        return GoobyConfig.alertRadius();
    }

    private void soundAlarm() {
        if (this.threat == null) {
            return;
        }
        boolean creeper = this.threat instanceof Creeper && GoobyConfig.creeperAlarm();
        this.gooby.raiseAlarm(creeper);
        this.alarmCooldown = creeper ? 40 : 80;
    }

    private void moveBetweenOwnerAndThreat() {
        LivingEntity owner = this.gooby.getOwner();
        if (owner == null || this.threat == null || owner.level() != this.gooby.level()
                || this.gooby.distanceToSqr(owner) > 16.0 * 16.0) {
            return;
        }
        Vec3 towardThreat = this.threat.position().subtract(owner.position());
        if (towardThreat.horizontalDistanceSqr() < 0.01) {
            return;
        }
        Vec3 guardPoint = owner.position().add(towardThreat.normalize().scale(2.2));
        this.gooby.getNavigation().moveTo(guardPoint.x, guardPoint.y, guardPoint.z, 1.25);
    }

    @Override
    public boolean requiresUpdateEveryTick() {
        return true;
    }
}
