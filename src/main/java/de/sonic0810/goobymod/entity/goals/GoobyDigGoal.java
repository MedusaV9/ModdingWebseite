package de.sonic0810.goobymod.entity.goals;

import de.sonic0810.goobymod.entity.GoobyDayRhythm;
import de.sonic0810.goobymod.entity.GoobyEntity;
import java.util.EnumSet;
import net.minecraft.world.entity.ai.goal.Goal;

/**
 * Gooby buddelt gelegentlich im Boden und findet Karotten (manchmal sogar
 * goldene!). Die eigentliche Buddel-Logik lebt testbar in der Entity.
 */
public class GoobyDigGoal extends Goal {
    private final GoobyEntity gooby;

    public GoobyDigGoal(GoobyEntity gooby) {
        this.gooby = gooby;
        setFlags(EnumSet.of(Flag.MOVE, Flag.LOOK, Flag.JUMP));
    }

    @Override
    public boolean canUse() {
        return this.gooby.onGround()
                && !this.gooby.isGoobySleeping()
                && !this.gooby.isSitting()
                && !this.gooby.isOrderedToSit()
                && !this.gooby.isVehicle()
                && !this.gooby.isPassenger()
                && !this.gooby.isAlerting()
                && !this.gooby.isSeekingShelter()
                && this.gooby.isOnDiggableGround()
                && this.gooby.getRandom().nextInt(reducedTickDelay(
                        GoobyDayRhythm.at(this.gooby.level().getDayTime()).digInterval())) == 0;
    }

    @Override
    public void start() {
        this.gooby.beginDig(60);
    }

    @Override
    public boolean canContinueToUse() {
        return this.gooby.isActivelyDigging();
    }

    @Override
    public boolean requiresUpdateEveryTick() {
        return true;
    }
}
