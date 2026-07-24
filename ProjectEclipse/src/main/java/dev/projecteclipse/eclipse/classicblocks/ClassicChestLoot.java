package dev.projecteclipse.eclipse.classicblocks;

import java.util.List;
import java.util.function.BiFunction;

import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.item.ItemStack;

/**
 * Hand-off point for P5-W9's baked chest loot (plan §2.14 "Chest loot"): the Xbox bake
 * step blanks chest block entities and records their contents in
 * {@code data/eclipse/xboxworlds/<world>_loot.json}; breaking a classic chest inside an
 * event dimension spills the recorded stacks.
 *
 * <p>W9 wires {@code ClassicChestLoot.setProvider(XboxEventService::lootFor)} during
 * common setup. The provider returns the recorded stacks for (level, pos) or an empty
 * list when the level is not an event dimension / the position has no recorded loot.
 * Unset provider = chests everywhere just drop themselves (their normal loot table).
 */
public final class ClassicChestLoot {

    private static volatile BiFunction<ServerLevel, BlockPos, List<ItemStack>> provider;

    private ClassicChestLoot() {}

    /** W9 installs the {@code XboxEventService} lookup here; call once during setup. */
    public static void setProvider(BiFunction<ServerLevel, BlockPos, List<ItemStack>> lootProvider) {
        provider = lootProvider;
    }

    /** Recorded loot for a classic chest at {@code pos}, or an empty list. */
    public static List<ItemStack> lootFor(ServerLevel level, BlockPos pos) {
        BiFunction<ServerLevel, BlockPos, List<ItemStack>> current = provider;
        return current == null ? List.of() : current.apply(level, pos);
    }
}
