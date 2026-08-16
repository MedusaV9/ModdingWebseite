package de.sonic0810.goobymod.entity.goals;

import de.sonic0810.goobymod.entity.GoobyEntity;
import java.util.EnumSet;
import javax.annotation.Nullable;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.phys.Vec3;

/**
 * Low-priority family flavor: a baby darts around one parent, occasionally
 * tumbles, and receives a nuzzle. The entity enforces the one-minute tumble
 * cooldown even if several AI triggers coincide.
 */
public final class GoobyFamilyPlayGoal extends Goal {
    private final GoobyEntity baby;
    @Nullable
    private GoobyEntity parent;
    private int playTicks;
    private int repathTicks;

    public GoobyFamilyPlayGoal(GoobyEntity baby) {
        this.baby = baby;
        setFlags(EnumSet.of(Flag.MOVE, Flag.LOOK));
    }

    @Override
    public boolean canUse() {
        if (!this.baby.isBaby() || this.baby.isGoobySleeping()
                || this.baby.getRandom().nextInt(reducedTickDelay(700)) != 0) {
            return false;
        }
        this.parent = this.baby.findLoadedParent();
        return this.parent != null && this.parent.isAlive()
                && this.baby.distanceToSqr(this.parent) < 12.0 * 12.0;
    }

    @Override
    public boolean canContinueToUse() {
        return this.playTicks > 0 && this.baby.isBaby() && this.parent != null
                && this.parent.isAlive() && !this.baby.isGoobySleeping();
    }

    @Override
    public void start() {
        this.playTicks = 55 + this.baby.getRandom().nextInt(26);
        this.repathTicks = 0;
        if (this.parent != null) {
            this.parent.tryTriggerAction("parent_nuzzle", 34);
        }
        if (this.baby.getRandom().nextInt(3) == 0) {
            this.baby.tryBabyTumble();
        }
    }

    @Override
    public void tick() {
        this.playTicks--;
        if (this.parent == null) {
            return;
        }
        this.baby.getLookControl().setLookAt(this.parent, 40.0F, 35.0F);
        if (--this.repathTicks <= 0) {
            this.repathTicks = adjustedTickDelay(8);
            double angle = (this.playTicks * 0.22) + (this.baby.getId() & 7);
            double radius = 2.2 + Mth.sin(this.playTicks * 0.15F) * 0.45;
            Vec3 target = this.parent.position().add(Math.cos(angle) * radius, 0.0, Math.sin(angle) * radius);
            this.baby.getNavigation().moveTo(target.x, target.y, target.z, 1.32);
        }
    }

    @Override
    public void stop() {
        this.baby.getNavigation().stop();
        this.parent = null;
        this.playTicks = 0;
    }
}
