package de.sonic0810.goobymod.compat;

import com.simibubi.create.content.contraptions.AbstractContraptionEntity;
import com.simibubi.create.content.contraptions.actors.seat.SeatBlock;
import com.simibubi.create.content.contraptions.bearing.MechanicalBearingBlockEntity;
import com.simibubi.create.content.kinetics.base.KineticBlockEntity;
import de.sonic0810.goobymod.entity.GoobyEntity;
import javax.annotation.Nullable;
import net.minecraft.core.BlockPos;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.entity.BlockEntity;

/**
 * The only class with compile-time Create references.
 *
 * <p>Callers must first check that Create is loaded. Keeping this boundary
 * isolated lets the rest of Gooby Mod classload unchanged without Create.</p>
 */
final class CreateBridge {
    static boolean trySeatGooby(GoobyEntity gooby) {
        Level level = gooby.level();
        for (BlockPos pos : BlockPos.betweenClosed(
                gooby.blockPosition().offset(-3, -1, -3),
                gooby.blockPosition().offset(3, 2, 3))) {
            if (level.getBlockState(pos).getBlock() instanceof SeatBlock
                    && !SeatBlock.isSeatOccupied(level, pos)) {
                SeatBlock.sitDown(level, pos.immutable(), gooby);
                return gooby.isPassenger();
            }
        }
        return false;
    }

    static boolean isOnContraption(Entity entity) {
        return findContraption(entity) != null;
    }

    static boolean isOnMovingContraption(Entity entity) {
        AbstractContraptionEntity contraption = findContraption(entity);
        if (contraption == null || contraption.isStalled()) {
            return false;
        }
        return contraption.getDeltaMovement().lengthSqr() > 1.0E-6
                || contraption.position().distanceToSqr(contraption.getPrevPositionVec()) > 1.0E-6
                || contraption.getContactPointMotion(entity.position()).lengthSqr() > 1.0E-6;
    }

    static double contraptionMotionSqr(Entity entity) {
        AbstractContraptionEntity contraption = findContraption(entity);
        if (contraption == null) {
            return 0.0;
        }
        return Math.max(contraption.getDeltaMovement().lengthSqr(),
                Math.max(contraption.position().distanceToSqr(contraption.getPrevPositionVec()),
                        contraption.getContactPointMotion(entity.position()).lengthSqr()));
    }

    static boolean hasRunningMachineNearby(Level level, BlockPos center, int radius) {
        for (BlockPos pos : BlockPos.betweenClosed(
                center.offset(-radius, -radius, -radius),
                center.offset(radius, radius, radius))) {
            BlockEntity blockEntity = level.getBlockEntity(pos);
            if (blockEntity instanceof KineticBlockEntity kinetic
                    && Math.abs(kinetic.getSpeed()) > 0.01F
                    && !kinetic.isOverStressed()) {
                return true;
            }
        }
        return false;
    }

    static boolean tryAssembleBearing(Level level, BlockPos pos, float speed) {
        BlockEntity blockEntity = level.getBlockEntity(pos);
        if (!(blockEntity instanceof MechanicalBearingBlockEntity bearing)) {
            return false;
        }
        bearing.setSpeed(speed);
        bearing.assemble();
        return bearing.getMovedContraption() != null;
    }

    static boolean tryDisassembleVehicle(Entity entity) {
        AbstractContraptionEntity contraption = findContraption(entity);
        if (contraption == null) {
            return false;
        }
        contraption.disassemble();
        return true;
    }

    @Nullable
    private static AbstractContraptionEntity findContraption(Entity entity) {
        Entity vehicle = entity.getVehicle();
        while (vehicle != null) {
            if (vehicle instanceof AbstractContraptionEntity contraption) {
                return contraption;
            }
            vehicle = vehicle.getVehicle();
        }
        return null;
    }

    private CreateBridge() {
    }
}
