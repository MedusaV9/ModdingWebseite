package de.sonic0810.goobymod.entity.goals;

import de.sonic0810.goobymod.entity.GoobyEntity;
import java.util.EnumSet;
import javax.annotation.Nullable;
import net.minecraft.world.entity.ai.goal.Goal;

/** Babies follow their persisted ritual parents instead of player commands. */
public final class GoobyFollowParentGoal extends Goal {
    private final GoobyEntity baby;
    @Nullable
    private GoobyEntity parent;
    private int repathTicks;

    public GoobyFollowParentGoal(GoobyEntity baby) {
        this.baby = baby;
        setFlags(EnumSet.of(Flag.MOVE, Flag.LOOK));
    }

    @Override
    public boolean canUse() {
        if (!this.baby.isBaby() || this.baby.isGoobySleeping() || this.baby.isOrderedToSit()) {
            return false;
        }
        this.parent = this.baby.findLoadedParent();
        return this.parent != null && this.parent.isAlive()
                && this.baby.distanceToSqr(this.parent) > 3.0 * 3.0
                && this.baby.distanceToSqr(this.parent) < 24.0 * 24.0;
    }

    @Override
    public boolean canContinueToUse() {
        return this.baby.isBaby() && this.parent != null && this.parent.isAlive()
                && !this.baby.isGoobySleeping()
                && this.baby.distanceToSqr(this.parent) > 2.5 * 2.5
                && this.baby.distanceToSqr(this.parent) < 28.0 * 28.0;
    }

    @Override
    public void start() {
        this.repathTicks = 0;
    }

    @Override
    public void tick() {
        if (this.parent == null) {
            return;
        }
        this.baby.getLookControl().setLookAt(this.parent, 30.0F, 30.0F);
        if (--this.repathTicks <= 0) {
            this.repathTicks = adjustedTickDelay(10);
            this.baby.getNavigation().moveTo(this.parent, 1.18);
        }
    }

    @Override
    public void stop() {
        this.baby.getNavigation().stop();
        this.parent = null;
    }
}
