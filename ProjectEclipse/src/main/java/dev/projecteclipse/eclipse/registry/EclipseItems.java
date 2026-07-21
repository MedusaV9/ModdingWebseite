package dev.projecteclipse.eclipse.registry;

import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.Item;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredRegister;

/** Item registry for Project: Eclipse. */
public final class EclipseItems {
    public static final DeferredRegister<Item> ITEMS =
            DeferredRegister.create(Registries.ITEM, EclipseMod.MOD_ID);

    /** Admin/debug item for the grave block; not obtainable in survival (grave has no loot table). */
    public static final Supplier<BlockItem> GRAVE = ITEMS.register("grave",
            () -> new BlockItem(EclipseBlocks.GRAVE.get(), new Item.Properties()));

    private EclipseItems() {}

    public static void register(IEventBus modEventBus) {
        ITEMS.register(modEventBus);
    }
}
