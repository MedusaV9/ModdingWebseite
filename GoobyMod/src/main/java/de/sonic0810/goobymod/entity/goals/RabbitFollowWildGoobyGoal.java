package de.sonic0810.goobymod.entity.goals;

import de.sonic0810.goobymod.entity.GoobyEntity;
import java.util.Comparator;
import java.util.EnumSet;
import javax.annotation.Nullable;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.entity.animal.Rabbit;

/** Rabbits treat a nearby wild Gooby like a reassuring big sibling. */
public final class RabbitFollowWildGoobyGoal extends Goal {
    private final Rabbit rabbit;
    @Nullable
    private GoobyEntity gooby;
    private int recalculatePath;
    private int nextScanTick;

    public RabbitFollowWildGoobyGoal(Rabbit rabbit) {
        this.rabbit = rabbit;
        setFlags(EnumSet.of(Flag.MOVE, Flag.LOOK));
    }

    @Override
    public boolean canUse() {
        if (this.rabbit.tickCount < this.nextScanTick) {
            return false;
        }
        this.nextScanTick = this.rabbit.tickCount + 20 + Math.floorMod(this.rabbit.getId(), 7);
        this.gooby = this.rabbit.level().getEntitiesOfClass(GoobyEntity.class,
                        this.rabbit.getBoundingBox().inflate(12.0),
                        candidate -> candidate.isAlive() && !candidate.isTame())
                .stream()
                .min(Comparator.comparingDouble(this.rabbit::distanceToSqr))
                .orElse(null);
        return this.gooby != null && this.rabbit.distanceToSqr(this.gooby) > 6.25;
    }

    @Override
    public boolean canContinueToUse() {
        return this.gooby != null && this.gooby.isAlive() && !this.gooby.isTame()
                && this.rabbit.distanceToSqr(this.gooby) < 16.0 * 16.0
                && this.rabbit.distanceToSqr(this.gooby) > 4.0;
    }

    @Override
    public void tick() {
        if (this.gooby == null) {
            return;
        }
        this.rabbit.getLookControl().setLookAt(this.gooby, 25.0F, 25.0F);
        if (--this.recalculatePath <= 0) {
            this.recalculatePath = 10;
            this.rabbit.getNavigation().moveTo(this.gooby, 1.05);
        }
    }

    @Override
    public void stop() {
        this.rabbit.getNavigation().stop();
        this.gooby = null;
    }
}
