package dev.projecteclipse.eclipse.woah.chronostasis;

import java.util.List;
import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.component.DataComponents;
import net.minecraft.core.registries.Registries;
import net.minecraft.network.chat.Component;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.Rarity;
import net.minecraft.world.item.component.ItemLore;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredRegister;

/**
 * WOAH-03 item registry. The central {@code registry/EclipseItems} is a shared file
 * (ITEMS-B ownership), so this feature carries its OWN deferred register, bootstrapped
 * from the WOAH-03 anchor in {@code woah/WoahFeatures.register}.
 *
 * <p>{@code chrono_core} follows the §2.3 rarity/glint/lore discipline of the house
 * registry: trophy → EPIC, NO {@code ENCHANTMENT_GLINT_OVERRIDE}, one baked poetic
 * {@code item.eclipse.chrono_core.lore} line (keys ship via
 * {@code docs/plans_v3/langdrop/woah_chrono.json}).</p>
 */
public final class ChronoStasisItems {
    public static final DeferredRegister<Item> ITEMS =
            DeferredRegister.create(Registries.ITEM, EclipseMod.MOD_ID);

    /**
     * "Stillstands-Kern" — the Chrono-Stasis first-discharge trophy (plan §7). Spawned
     * once out of the Chronosphere at DISCHARGE t=120 for the triggering player
     * ({@code rewardClaimed} gate); nothing consumes it yet. Deliberately unstackable —
     * the one frozen instant stays "the one".
     */
    public static final Supplier<Item> CHRONO_CORE = ITEMS.register("chrono_core",
            () -> new Item(new Item.Properties()
                    .stacksTo(1)
                    .rarity(Rarity.EPIC)
                    .component(DataComponents.LORE, new ItemLore(List.of(
                            Component.translatable("item.eclipse.chrono_core.lore"))))));

    private ChronoStasisItems() {}

    public static void register(IEventBus modEventBus) {
        ITEMS.register(modEventBus);
    }
}
