package de.sonic0810.goobymod.entity.goals;

import de.sonic0810.goobymod.entity.GoobyEntity;
import java.util.Comparator;
import java.util.EnumSet;
import javax.annotation.Nullable;
import net.minecraft.world.entity.ai.goal.Goal;

/**
 * Deliberately lowest-priority social handshake. Commands, sleep, danger,
 * shelter, family, and ordinary movement all win its MOVE/LOOK flags.
 */
public final class GoobySocialGoal extends Goal {
    private final GoobyEntity gooby;
    @Nullable
    private GoobyEntity partner;

    public GoobySocialGoal(GoobyEntity gooby) {
        this.gooby = gooby;
        setFlags(EnumSet.of(Flag.MOVE, Flag.LOOK));
    }

    @Override
    public boolean canUse() {
        if (!this.gooby.canStartSocialBehavior() || this.gooby.getRandom().nextInt(reducedTickDelay(100)) != 0) {
            return false;
        }
        this.partner = this.gooby.level().getEntitiesOfClass(GoobyEntity.class,
                        this.gooby.getBoundingBox().inflate(6.0),
                        candidate -> candidate != this.gooby && this.gooby.canSocializeWith(candidate))
                .stream()
                .min(Comparator.comparingDouble(this.gooby::distanceToSqr))
                .orElse(null);
        return this.partner != null;
    }

    @Override
    public void start() {
        if (this.partner != null) {
            boolean preferChase = this.gooby.getRandom().nextInt(4) == 0;
            this.gooby.startSocialInteraction(
                    this.partner, this.gooby.level().getGameTime(), preferChase);
        }
    }

    @Override
    public boolean canContinueToUse() {
        return this.partner != null && this.partner.isAlive()
                && this.gooby.canContinueSocialBehavior();
    }

    @Override
    public void tick() {
        if (this.partner != null) {
            this.gooby.getLookControl().setLookAt(this.partner, 35.0F, 30.0F);
        }
    }

    @Override
    public void stop() {
        this.partner = null;
    }
}
