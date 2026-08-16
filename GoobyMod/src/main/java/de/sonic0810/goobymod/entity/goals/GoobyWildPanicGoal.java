package de.sonic0810.goobymod.entity.goals;

import de.sonic0810.goobymod.entity.GoobyEntity;
import net.minecraft.world.entity.ai.goal.PanicGoal;

/** Vanilla damage-source panic, deliberately restricted to untamed Goobys. */
public final class GoobyWildPanicGoal extends PanicGoal {
    private final GoobyEntity gooby;

    public GoobyWildPanicGoal(GoobyEntity gooby) {
        super(gooby, 1.4);
        this.gooby = gooby;
    }

    @Override
    public boolean canUse() {
        return !this.gooby.isTame() && super.canUse();
    }

    @Override
    public boolean canContinueToUse() {
        return !this.gooby.isTame() && super.canContinueToUse();
    }
}
