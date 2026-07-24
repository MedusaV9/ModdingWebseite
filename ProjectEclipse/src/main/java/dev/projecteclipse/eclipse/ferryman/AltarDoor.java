package dev.projecteclipse.eclipse.ferryman;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.limbo.door.DoorRegistry;
import dev.projecteclipse.eclipse.limbo.door.DoorState;
import dev.projecteclipse.eclipse.limbo.door.RespawnDoorBlock;
import dev.projecteclipse.eclipse.limbo.door.RespawnDoorBlockEntity;
import dev.projecteclipse.eclipse.limbo.door.RespawnDoorFillerBlock;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The DEAD DOOR at the altar (C10.1): the existing {@code eclipse:respawn_door}
 * multiblock (registry reused via its blocks, never edited) stamped in the overworld at
 * finale arm time. Walking into the {@link #walkVolume walk-through volume} in front of
 * it teleports the player onto the limbo ghost ship behind a
 * {@code PortalTransitionController} fade — {@code ArenaFight} owns that tick check;
 * this class only places/removes the blocks and remembers them in {@link ArenaState}
 * (restart-safe cleanup, the {@code XboxPortal} place/remove discipline).
 *
 * <p>Placement scans the four horizontal directions {@value #DOOR_DISTANCE} blocks out
 * from the altar and stamps the 3×5 aperture into the plane with the most air (front
 * face toward the altar, so the purple spill greets the offering). Cells the door
 * replaces are almost always air on the altar dais; removal restores plain air either
 * way (logged when it had to overwrite terrain).</p>
 */
public final class AltarDoor {
    /** Blocks between the altar and the stamped door plane. */
    private static final int DOOR_DISTANCE = 4;
    /** Depth of the walk-through trigger volume in front of the aperture. */
    private static final double WALK_DEPTH = 1.25D;
    private static final double FX_RANGE = 96.0D;

    private AltarDoor() {}

    // ------------------------------------------------------------------ place / remove

    /**
     * Stamps the dead door near {@code altarPos} and records it in {@link ArenaState}.
     * Returns {@code false} (no block changes) while {@code DoorRegistry} is unbound —
     * the caller falls back to the doorless crossing.
     */
    public static boolean place(ServerLevel level, BlockPos altarPos) {
        if (!DoorRegistry.isBound()) {
            EclipseMod.LOGGER.warn("Altar dead door skipped: respawn door blocks are not registered");
            return false;
        }
        ArenaState state = ArenaState.get(level.getServer());
        if (state.doorPos() != null) {
            remove(level.getServer()); // Never two doors; re-arm replaces the old stamp.
        }
        Direction facing = bestFacing(level, altarPos);
        // Controller = bottom-center of the aperture, front face looking back at the altar.
        BlockPos controller = altarPos.relative(facing, DOOR_DISTANCE);
        int overwritten = countNonAir(level, controller, facing.getOpposite());
        BlockState controllerState = DoorRegistry.RESPAWN_DOOR.get().defaultBlockState()
                .setValue(RespawnDoorBlock.FACING, facing.getOpposite())
                .setValue(RespawnDoorBlock.LIT, true);
        level.setBlock(controller, controllerState, Block.UPDATE_ALL);
        RespawnDoorBlock.placeFillers(level, controller, facing.getOpposite(), true);
        if (level.getBlockEntity(controller) instanceof RespawnDoorBlockEntity door) {
            // The BE defaults to CLOSED; this door stands wide open for the whole gate.
            // (The client-side ghost rule still shows it closed to ghosts — they cross fine.)
            door.setDoorState(DoorState.OPEN);
        }
        state.setDoor(level.dimension(), controller, facing.getOpposite());

        Vec3 center = doorCenter(controller);
        PacketDistributor.sendToPlayersNear(level, null, center.x, center.y, center.z, FX_RANGE,
                new S2CQuasarPayload(S2CQuasarPayload.CUTSCENE_VEIL, center));
        level.playSound(null, controller, SoundEvents.END_PORTAL_SPAWN, SoundSource.BLOCKS, 1.0F, 0.4F);
        level.playSound(null, controller, SoundEvents.WOODEN_DOOR_OPEN, SoundSource.BLOCKS, 1.2F, 0.5F);
        EclipseMod.LOGGER.info("Altar dead door stamped at {} facing {} ({} terrain cell(s) overwritten)",
                controller.toShortString(), facing.getOpposite(), overwritten);
        return true;
    }

    /** Removes the stamped door (controller removal cascades the fillers) + clears state. */
    public static void remove(MinecraftServer server) {
        ArenaState state = ArenaState.get(server);
        BlockPos controller = state.doorPos();
        if (controller == null || state.doorDimension() == null) {
            return;
        }
        ServerLevel level = server.getLevel(state.doorDimension());
        if (level != null) {
            level.getChunk(controller); // force-load: cleanup must never silently miss
            Direction facing = state.doorFacing();
            // Controller first (its onRemove cascades live fillers), then a belt-and-braces
            // sweep of all 15 cells for orphans left by a partial stamp.
            if (level.getBlockState(controller).getBlock() instanceof RespawnDoorBlock) {
                level.setBlock(controller, Blocks.AIR.defaultBlockState(), Block.UPDATE_ALL);
            }
            for (int col = 0; col < RespawnDoorBlock.WIDTH; col++) {
                for (int row = 0; row < RespawnDoorBlock.HEIGHT; row++) {
                    BlockPos cell = RespawnDoorBlock.cellPos(controller, facing, col, row);
                    Block block = level.getBlockState(cell).getBlock();
                    if (block instanceof RespawnDoorBlock || block instanceof RespawnDoorFillerBlock) {
                        level.setBlock(cell, Blocks.AIR.defaultBlockState(), Block.UPDATE_ALL);
                    }
                }
            }
            level.playSound(null, controller, SoundEvents.IRON_DOOR_CLOSE, SoundSource.BLOCKS, 1.0F, 0.5F);
            EclipseMod.LOGGER.info("Altar dead door removed at {}", controller.toShortString());
        } else {
            EclipseMod.LOGGER.warn("Altar dead door dimension {} not loaded; clearing the record only",
                    state.doorDimension().location());
        }
        state.clearDoor();
    }

    // ------------------------------------------------------------------ walk-through

    /**
     * Trigger volume in front of the recorded door: aperture width × 3 high ×
     * {@value #WALK_DEPTH} deep on the front side. {@code null} while no door stands.
     */
    @Nullable
    public static AABB walkVolume(MinecraftServer server) {
        ArenaState state = ArenaState.get(server);
        BlockPos controller = state.doorPos();
        if (controller == null) {
            return null;
        }
        Direction facing = state.doorFacing();
        Vec3 base = Vec3.atBottomCenterOf(controller.relative(facing));
        Vec3 out = new Vec3(facing.getStepX(), 0.0D, facing.getStepZ());
        Vec3 across = new Vec3(Math.abs(facing.getStepZ()), 0.0D, Math.abs(facing.getStepX()));
        Vec3 a = base.subtract(across.scale(1.5D)).subtract(out.scale(0.25D));
        Vec3 b = base.add(across.scale(1.5D)).add(out.scale(WALK_DEPTH)).add(0.0D, 3.0D, 0.0D);
        return new AABB(a, b);
    }

    // ------------------------------------------------------------------ helpers

    /** Direction from the altar with the most breathable 3×5 plane (ties → EAST first). */
    private static Direction bestFacing(ServerLevel level, BlockPos altarPos) {
        Direction best = Direction.EAST;
        int bestScore = -1;
        for (Direction direction : new Direction[] {Direction.EAST, Direction.WEST,
                Direction.SOUTH, Direction.NORTH}) {
            BlockPos controller = altarPos.relative(direction, DOOR_DISTANCE);
            int score = 15 - countNonAir(level, controller, direction.getOpposite());
            if (score > bestScore) {
                bestScore = score;
                best = direction;
            }
        }
        return best;
    }

    private static int countNonAir(ServerLevel level, BlockPos controller, Direction doorFacing) {
        int nonAir = 0;
        for (int col = 0; col < RespawnDoorBlock.WIDTH; col++) {
            for (int row = 0; row < RespawnDoorBlock.HEIGHT; row++) {
                if (!level.getBlockState(RespawnDoorBlock.cellPos(controller, doorFacing, col, row)).isAir()) {
                    nonAir++;
                }
            }
        }
        return nonAir;
    }

    private static Vec3 doorCenter(BlockPos controller) {
        return Vec3.atCenterOf(controller.above(2));
    }
}
