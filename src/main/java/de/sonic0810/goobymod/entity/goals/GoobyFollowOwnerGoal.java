package de.sonic0810.goobymod.entity.goals;

import de.sonic0810.goobymod.entity.GoobyCommand;
import de.sonic0810.goobymod.entity.GoobyEntity;
import net.minecraft.world.entity.ai.goal.FollowOwnerGoal;

/**
 * Vanilla-FollowOwnerGoal (inkl. Teleport bei zu grossem Abstand), aber nur
 * aktiv, wenn der Besitzer per Pfeife FOLLOW befohlen hat und Gooby weder
 * schlaeft noch buddelt.
 */
public class GoobyFollowOwnerGoal extends FollowOwnerGoal {
    private final GoobyEntity gooby;

    public GoobyFollowOwnerGoal(GoobyEntity gooby, double speed, float startDistance, float stopDistance) {
        super(gooby, speed, startDistance, stopDistance);
        this.gooby = gooby;
    }

    private boolean commandAllows() {
        return !this.gooby.isBaby()
                && this.gooby.getCommandMode() == GoobyCommand.FOLLOW
                && !this.gooby.isGoobySleeping()
                && !this.gooby.isActivelyDigging()
                && !this.gooby.isAlerting()
                && !this.gooby.isSeekingShelter();
    }

    @Override
    public boolean canUse() {
        return commandAllows() && super.canUse();
    }

    @Override
    public boolean canContinueToUse() {
        return commandAllows() && super.canContinueToUse();
    }
}
