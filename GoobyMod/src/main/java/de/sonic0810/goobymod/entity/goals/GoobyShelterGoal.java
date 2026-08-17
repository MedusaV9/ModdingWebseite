package de.sonic0810.goobymod.entity.goals;

import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.registry.ModBlocks;
import java.util.EnumSet;
import javax.annotation.Nullable;
import net.minecraft.core.BlockPos;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;

/** Moves a weather-exposed Gooby under a roof/hutch or behind its owner. */
public final class GoobyShelterGoal extends Goal {
    private final GoobyEntity gooby;
    @Nullable
    private BlockPos shelter;
    private int searchCooldown;
    private int repathCooldown;
    private boolean thunder;

    public GoobyShelterGoal(GoobyEntity gooby) {
        this.gooby = gooby;
        setFlags(EnumSet.of(Flag.MOVE, Flag.LOOK, Flag.JUMP));
    }

    @Override
    public boolean canUse() {
        if (this.gooby.isAlerting() || this.gooby.isActivelyDigging()
                || this.gooby.isVehicle() || this.gooby.isPassenger()) {
            return false;
        }
        Level level = this.gooby.level();
        this.thunder = level.isThundering();
        boolean exposedToRain = level.isRaining() && level.canSeeSky(this.gooby.blockPosition());
        if (!this.thunder && !exposedToRain) {
            return false;
        }
        if (this.searchCooldown-- > 0) {
            return false;
        }
        this.searchCooldown = reducedTickDelay(20);
        this.shelter = this.thunder ? findBehindOwner() : findDryShelter();
        return this.shelter != null;
    }

    @Override
    public void start() {
        this.gooby.wakeUp();
        this.gooby.setSeekingShelter(true);
        if (this.thunder) {
            this.gooby.markHidingFromThunder();
            this.gooby.setMoodScaredImmediately();
        }
        this.repathCooldown = 0;
        moveToShelter();
    }

    @Override
    public boolean canContinueToUse() {
        if (this.shelter == null
                || (!this.gooby.level().isRaining() && !this.gooby.level().isThundering())) {
            return false;
        }
        if (!this.thunder) {
            // A wide Gooby can enter the navigator's arrival radius while its block position is
            // still one block outside the roof. Keep steering until it is actually dry.
            return this.gooby.level().canSeeSky(this.gooby.blockPosition());
        }
        return this.shelter.distToCenterSqr(this.gooby.position()) > 1.5;
    }

    @Override
    public void tick() {
        if (this.thunder) {
            this.gooby.markHidingFromThunder();
        }
        if (this.repathCooldown-- <= 0) {
            this.repathCooldown = 20;
            moveToShelter();
        }
    }

    @Override
    public void stop() {
        this.gooby.setSeekingShelter(false);
        this.shelter = null;
    }

    @Nullable
    private BlockPos findBehindOwner() {
        LivingEntity owner = this.gooby.getOwner();
        if (owner == null || owner.level() != this.gooby.level()
                || this.gooby.distanceToSqr(owner) > 16.0 * 16.0) {
            return findDryShelter();
        }
        Vec3 behind = owner.position().subtract(owner.getViewVector(1.0F).normalize().scale(1.8));
        BlockPos target = BlockPos.containing(behind);
        return isStandable(target) ? target : owner.blockPosition();
    }

    @Nullable
    private BlockPos findDryShelter() {
        BlockPos home = this.gooby.getHomePos();
        if (home != null && this.gooby.level().getBlockState(home).is(ModBlocks.RABBIT_HUTCH.get())) {
            return home;
        }
        BlockPos origin = this.gooby.blockPosition();
        return BlockPos.findClosestMatch(origin, 12, 4,
                        pos -> isFullyCovered(pos) && isStandable(pos))
                .or(() -> BlockPos.findClosestMatch(origin, 12, 4,
                        pos -> !this.gooby.level().canSeeSky(pos) && isStandable(pos)))
                .orElse(null);
    }

    private boolean isFullyCovered(BlockPos pos) {
        for (int x = -1; x <= 1; x++) {
            for (int z = -1; z <= 1; z++) {
                if (this.gooby.level().canSeeSky(pos.offset(x, 0, z))) {
                    return false;
                }
            }
        }
        return true;
    }

    private boolean isStandable(BlockPos pos) {
        Level level = this.gooby.level();
        return level.getBlockState(pos).getCollisionShape(level, pos).isEmpty()
                && level.getBlockState(pos.above()).getCollisionShape(level, pos.above()).isEmpty()
                && level.getBlockState(pos.below()).isSolidRender(level, pos.below())
                && level.getFluidState(pos).isEmpty()
                && level.getFluidState(pos.below()).isEmpty();
    }

    private void moveToShelter() {
        if (this.shelter != null) {
            this.gooby.getNavigation().moveTo(this.shelter.getX() + 0.5, this.shelter.getY(),
                    this.shelter.getZ() + 0.5, this.thunder ? 1.3 : 1.1);
        }
    }

    @Override
    public boolean requiresUpdateEveryTick() {
        return true;
    }
}
