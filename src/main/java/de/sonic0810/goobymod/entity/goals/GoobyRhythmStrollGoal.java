package de.sonic0810.goobymod.entity.goals;

import de.sonic0810.goobymod.entity.GoobyDayRhythm;
import de.sonic0810.goobymod.entity.GoobyEntity;
import net.minecraft.world.entity.ai.goal.WaterAvoidingRandomStrollGoal;

/** Existing random stroll with its attempt interval modulated by day phase. */
public final class GoobyRhythmStrollGoal extends WaterAvoidingRandomStrollGoal {
    private final GoobyEntity gooby;

    public GoobyRhythmStrollGoal(GoobyEntity gooby, double speed) {
        super(gooby, speed);
        this.gooby = gooby;
    }

    @Override
    public boolean canUse() {
        GoobyDayRhythm rhythm = GoobyDayRhythm.at(this.gooby.level().getDayTime());
        setInterval(rhythm.strollInterval());
        return !this.gooby.isAlerting() && !this.gooby.isSeekingShelter() && super.canUse();
    }
}
