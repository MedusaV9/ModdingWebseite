package dev.projecteclipse.eclipse.registry;

import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.artifact.ArmArtifactItem;
import dev.projecteclipse.eclipse.ritual.ReviveSigilItem;
import net.minecraft.core.component.DataComponents;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.Rarity;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredRegister;

/** Item registry for Project: Eclipse. */
public final class EclipseItems {
    public static final DeferredRegister<Item> ITEMS =
            DeferredRegister.create(Registries.ITEM, EclipseMod.MOD_ID);

    /** Admin/debug item for the grave block; not obtainable in survival (grave has no loot table). */
    public static final Supplier<BlockItem> GRAVE = ITEMS.register("grave",
            () -> new BlockItem(EclipseBlocks.GRAVE.get(), new Item.Properties()));

    /** Dropped when a player voluntarily sacrifices a life at the altar. Revive-sigil ingredient. */
    public static final Supplier<Item> HEART_FRAGMENT = ITEMS.register("heart_fragment",
            () -> new Item(new Item.Properties()
                    .component(DataComponents.ENCHANTMENT_GLINT_OVERRIDE, Boolean.TRUE)));

    /**
     * Night-mob drop (The Other, Umbral Stalker). Crafting currency for boss summon items
     * and W13 economy recipes.
     */
    public static final Supplier<Item> UMBRAL_SHARD = ITEMS.register("umbral_shard",
            () -> new Item(new Item.Properties()));

    /** Consumed at the altar to start the revive ritual for a banned player. */
    public static final Supplier<ReviveSigilItem> REVIVE_SIGIL = ITEMS.register("revive_sigil",
            () -> new ReviveSigilItem(new Item.Properties()
                    .component(DataComponents.ENCHANTMENT_GLINT_OVERRIDE, Boolean.TRUE)));

    /** Admin/debug item for the altar block; not craftable (admins place the altar manually). */
    public static final Supplier<BlockItem> ALTAR = ITEMS.register("altar",
            () -> new BlockItem(EclipseBlocks.ALTAR.get(), new Item.Properties()));

    /**
     * The permanent in-game interface artifact, slot-locked to hotbar slot 8 by
     * {@code artifact.ArtifactSlotLock}. Id must stay exactly {@code eclipse:arm_artifact}
     * — other systems (e.g. {@code progression.PhaseInventoryLock}) resolve it by that id.
     */
    public static final Supplier<ArmArtifactItem> ARM_ARTIFACT = ITEMS.register("arm_artifact",
            () -> new ArmArtifactItem(new Item.Properties()
                    .stacksTo(1)
                    .fireResistant()
                    .rarity(Rarity.EPIC)
                    .component(DataComponents.ENCHANTMENT_GLINT_OVERRIDE, Boolean.TRUE)));

    private EclipseItems() {}

    public static void register(IEventBus modEventBus) {
        ITEMS.register(modEventBus);
    }
}
