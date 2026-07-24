package dev.projecteclipse.eclipse.classicblocks;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.Direction;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.DoubleHighBlockItem;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.StandingAndWallBlockItem;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredRegister;

/**
 * Items for the {@code eclipse:classic_*} blocks (plan §2.14): plain {@link BlockItem}s
 * (doors as {@link DoubleHighBlockItem}, torches as {@link StandingAndWallBlockItem}).
 *
 * <p>Souvenir discipline: no recipes reference them and they satisfy no vanilla
 * ingredient (own namespace, never added to any vanilla/common ITEM tag), no fuel value
 * (never registered as furnace fuel), hidden from vanilla creative tabs — they only show
 * in the dedicated {@link ClassicCreativeTab} and drop as Xbox-event loot.
 */
public final class ClassicBlockItems {

    public static final DeferredRegister<Item> ITEMS =
            DeferredRegister.create(Registries.ITEM, EclipseMod.MOD_ID);

    private static final Map<String, Supplier<Item>> BY_ID = new LinkedHashMap<>();

    static {
        for (ClassicBlockList.Entry entry : ClassicBlockList.ENTRIES) {
            if (entry.itemKind() == ClassicBlockList.ItemKind.NONE) {
                continue; // technical blocks (wall torches, piston head, stems)
            }
            BY_ID.put(entry.id(), ITEMS.register(entry.blockId(), () -> createItem(entry)));
        }
    }

    private ClassicBlockItems() {}

    private static Item createItem(ClassicBlockList.Entry entry) {
        Item.Properties props = new Item.Properties();
        return switch (entry.itemKind()) {
            case BLOCK -> new BlockItem(ClassicBlocks.byId(entry.id()).get(), props);
            case TALL -> new DoubleHighBlockItem(ClassicBlocks.byId(entry.id()).get(), props);
            case STANDING_WALL -> new StandingAndWallBlockItem(
                    ClassicBlocks.byId(entry.id()).get(),
                    ClassicBlocks.byId(entry.itemParam()).get(),
                    props, Direction.DOWN);
            case NONE -> throw new IllegalStateException("NONE items are never registered");
        };
    }

    /** Registered classic item for a vanilla twin path (e.g. {@code "oak_planks"}). */
    public static Supplier<Item> byId(String vanillaPath) {
        Supplier<Item> supplier = BY_ID.get(vanillaPath);
        if (supplier == null) {
            throw new IllegalArgumentException("classic block has no item: " + vanillaPath);
        }
        return supplier;
    }

    /** All classic items keyed by vanilla twin path, in registration order. */
    public static Map<String, Supplier<Item>> all() {
        return Collections.unmodifiableMap(BY_ID);
    }

    public static void register(IEventBus modEventBus) {
        ITEMS.register(modEventBus);
    }
}
