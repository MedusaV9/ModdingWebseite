package de.sonic0810.goobymod.entity.goals;

import de.sonic0810.goobymod.entity.GoobyEntity;
import java.util.Comparator;
import java.util.EnumSet;
import javax.annotation.Nullable;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.entity.animal.Cat;

/** Cats stop and suspiciously watch nearby Goobys without attacking them. */
public final class CatStareAtGoobyGoal extends Goal {
    private final Cat cat;
    @Nullable
    private GoobyEntity target;
    private int stareTicks;

    public CatStareAtGoobyGoal(Cat cat) {
        this.cat = cat;
        setFlags(EnumSet.of(Flag.LOOK));
    }

    @Override
    public boolean canUse() {
        if (this.cat.getRandom().nextInt(reducedTickDelay(80)) != 0) {
            return false;
        }
        this.target = this.cat.level().getEntitiesOfClass(GoobyEntity.class,
                        this.cat.getBoundingBox().inflate(10.0), GoobyEntity::isAlive)
                .stream()
                .min(Comparator.comparingDouble(this.cat::distanceToSqr))
                .orElse(null);
        return this.target != null;
    }

    @Override
    public boolean canContinueToUse() {
        return this.target != null && this.target.isAlive() && this.stareTicks > 0
                && this.cat.distanceToSqr(this.target) < 12.0 * 12.0;
    }

    @Override
    public void start() {
        this.stareTicks = 40 + this.cat.getRandom().nextInt(40);
    }

    @Override
    public void tick() {
        this.stareTicks--;
        this.cat.getLookControl().setLookAt(this.target, 35.0F, 35.0F);
    }

    @Override
    public void stop() {
        this.target = null;
        this.stareTicks = 0;
    }
}
