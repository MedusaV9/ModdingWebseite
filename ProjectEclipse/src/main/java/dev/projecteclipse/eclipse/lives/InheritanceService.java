package dev.projecteclipse.eclipse.lives;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.Container;
import net.minecraft.world.Containers;
import net.minecraft.world.inventory.PlayerEnderChestContainer;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.entity.ChestBlockEntity;
import net.minecraft.world.level.block.state.BlockState;

/**
 * "Inheritance" for banned players: empties their ender chest and deposits the
 * stacks into chest blocks around the overworld shared spawn (9x9 search; new
 * vanilla chests are placed if the existing ones are full). Anything that still
 * does not fit is dropped as item entities at spawn — nothing is ever voided.
 */
public final class InheritanceService {
    /** Horizontal half-extent of the search square around spawn (4 → 9x9 columns). */
    private static final int SEARCH_RADIUS = 4;
    /** Vertical search range relative to the spawn Y, inclusive. */
    private static final int SEARCH_DOWN = 2;
    private static final int SEARCH_UP = 4;

    private InheritanceService() {}

    /**
     * Empties the player's ender chest and deposits the contents into chests at the
     * overworld shared spawn. Safe to call with a dead player; no-op when the ender
     * chest is empty.
     */
    public static void inherit(ServerPlayer player) {
        if (player == null) {
            return;
        }
        PlayerEnderChestContainer enderChest = player.getEnderChestInventory();
        List<ItemStack> stacks = new ArrayList<>();
        for (int slot = 0; slot < enderChest.getContainerSize(); slot++) {
            ItemStack stack = enderChest.getItem(slot);
            if (!stack.isEmpty()) {
                stacks.add(stack.copy());
                enderChest.setItem(slot, ItemStack.EMPTY);
            }
        }
        if (stacks.isEmpty()) {
            return;
        }
        ServerLevel overworld = player.server.overworld();
        if (overworld == null) {
            EclipseMod.LOGGER.warn("No overworld available; dropping {} inherited stacks at {}'s position",
                    stacks.size(), player.getScoreboardName());
            for (ItemStack stack : stacks) {
                Containers.dropItemStack(player.level(), player.getX(), player.getY(), player.getZ(), stack);
            }
            return;
        }
        depositAtSpawn(overworld, stacks);
        EclipseMod.LOGGER.info("Inherited ender chest of {} to spawn chests", player.getScoreboardName());
    }

    /**
     * Deposits the given stacks into chests in a 9x9 area around the level's shared
     * spawn, placing new vanilla chests where needed and dropping any remainder at
     * spawn. The list is consumed (emptied stacks removed).
     */
    public static void depositAtSpawn(ServerLevel level, List<ItemStack> stacks) {
        if (level == null || stacks == null || stacks.isEmpty()) {
            return;
        }
        BlockPos spawn = level.getSharedSpawnPos();

        // Pass 1: fill existing chests that have space.
        for (BlockPos pos : BlockPos.betweenClosed(
                spawn.offset(-SEARCH_RADIUS, -SEARCH_DOWN, -SEARCH_RADIUS),
                spawn.offset(SEARCH_RADIUS, SEARCH_UP, SEARCH_RADIUS))) {
            if (stacks.isEmpty()) {
                return;
            }
            if (!level.isOutsideBuildHeight(pos) && level.getBlockEntity(pos) instanceof ChestBlockEntity chest) {
                insertAll(chest, stacks);
            }
        }

        // Pass 2: place new chests on replaceable spots and fill them.
        for (BlockPos pos : BlockPos.betweenClosed(
                spawn.offset(-SEARCH_RADIUS, -SEARCH_DOWN, -SEARCH_RADIUS),
                spawn.offset(SEARCH_RADIUS, SEARCH_UP, SEARCH_RADIUS))) {
            if (stacks.isEmpty()) {
                return;
            }
            if (level.isOutsideBuildHeight(pos)) {
                continue;
            }
            BlockState state = level.getBlockState(pos);
            if (state.isAir() || state.canBeReplaced()) {
                level.setBlockAndUpdate(pos.immutable(), Blocks.CHEST.defaultBlockState());
                if (level.getBlockEntity(pos) instanceof ChestBlockEntity chest) {
                    insertAll(chest, stacks);
                }
            }
        }

        // Pass 3: nothing left to fill or place — drop the rest at spawn (never void items).
        if (!stacks.isEmpty()) {
            EclipseMod.LOGGER.warn("Spawn chests full; dropping {} leftover inherited stacks at spawn", stacks.size());
            for (ItemStack stack : stacks) {
                Containers.dropItemStack(level, spawn.getX() + 0.5D, spawn.getY() + 1.0D, spawn.getZ() + 0.5D, stack);
            }
            stacks.clear();
        }
    }

    private static void insertAll(Container container, List<ItemStack> stacks) {
        stacks.replaceAll(stack -> insert(container, stack));
        stacks.removeIf(ItemStack::isEmpty);
    }

    /** Inserts as much of {@code stack} as possible into the container; returns the remainder. */
    private static ItemStack insert(Container container, ItemStack stack) {
        for (int slot = 0; slot < container.getContainerSize() && !stack.isEmpty(); slot++) {
            ItemStack existing = container.getItem(slot);
            if (existing.isEmpty()) {
                container.setItem(slot, stack);
                return ItemStack.EMPTY;
            }
            if (ItemStack.isSameItemSameComponents(existing, stack)) {
                int transfer = Math.min(stack.getCount(), existing.getMaxStackSize() - existing.getCount());
                if (transfer > 0) {
                    existing.grow(transfer);
                    stack.shrink(transfer);
                    container.setChanged();
                }
            }
        }
        return stack;
    }
}
