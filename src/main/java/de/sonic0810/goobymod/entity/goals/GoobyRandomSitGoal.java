package de.sonic0810.goobymod.entity.goals;

import de.sonic0810.goobymod.entity.GoobyDayRhythm;
import de.sonic0810.goobymod.entity.GoobyEntity;
import java.util.EnumSet;
import net.minecraft.world.entity.ai.goal.Goal;

/**
 * Gooby setzt sich manchmal einfach hin und geniesst das Leben.
 * Rund sein ist anstrengend.
 */
public class GoobyRandomSitGoal extends Goal {
    private final GoobyEntity gooby;
    private int sitTicks;

    public GoobyRandomSitGoal(GoobyEntity gooby) {
        this.gooby = gooby;
        setFlags(EnumSet.of(Flag.MOVE, Flag.JUMP));
    }

    @Override
    public boolean canUse() {
        return this.gooby.onGround()
                && !this.gooby.isGoobySleeping()
                && !this.gooby.isActivelyDigging()
                && !this.gooby.isOrderedToSit()
                && !this.gooby.isVehicle()
                && !this.gooby.isPassenger()
                && !this.gooby.isAlerting()
                && !this.gooby.isSeekingShelter()
                && this.gooby.getNavigation().isDone()
                && this.gooby.getRandom().nextInt(reducedTickDelay(
                        GoobyDayRhythm.at(this.gooby.level().getDayTime()).sitInterval())) == 0;
    }

    @Override
    public void start() {
        this.sitTicks = 100 + this.gooby.getRandom().nextInt(200);
        this.gooby.setSitting(true);
        this.gooby.getNavigation().stop();
    }

    @Override
    public boolean canContinueToUse() {
        // wakeUp() (Streicheln, Fuettern, Pfeife, ...) loescht das Sitz-Flag extern.
        // Ohne diese Pruefung hielte der Goal die MOVE/JUMP-Flags bis zu 15 s weiter
        // fest: Gooby stand nach dem Aufstehen eingefroren da.
        return this.sitTicks > 0 && this.gooby.isSitting() && !this.gooby.isVehicle();
    }

    @Override
    public void tick() {
        this.sitTicks--;
    }

    @Override
    public void stop() {
        this.gooby.setSitting(false);
    }

    @Override
    public boolean requiresUpdateEveryTick() {
        return true;
    }
}
