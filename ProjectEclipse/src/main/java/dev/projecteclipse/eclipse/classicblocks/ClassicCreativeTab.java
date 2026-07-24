package dev.projecteclipse.eclipse.classicblocks;

import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.registries.Registries;
import net.minecraft.network.chat.Component;
import net.minecraft.world.item.CreativeModeTab;
import net.minecraft.world.item.ItemStack;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredRegister;

/**
 * Dedicated {@code eclipse.classic} creative tab (plan §2.14 "Visibility"): classic blocks
 * never join vanilla tabs — this tab exists for ops/testing convenience only. Survival
 * players obtain them exclusively as Xbox-event loot.
 */
public final class ClassicCreativeTab {

    public static final DeferredRegister<CreativeModeTab> TABS =
            DeferredRegister.create(Registries.CREATIVE_MODE_TAB, EclipseMod.MOD_ID);

    public static final Supplier<CreativeModeTab> CLASSIC = TABS.register("classic",
            () -> CreativeModeTab.builder()
                    .title(Component.translatable("itemGroup.eclipse.classic"))
                    .icon(() -> new ItemStack(ClassicBlockItems.byId("grass_block").get()))
                    .displayItems((parameters, output) ->
                            ClassicBlockItems.all().values().forEach(item -> output.accept(item.get())))
                    .build());

    private ClassicCreativeTab() {}

    public static void register(IEventBus modEventBus) {
        TABS.register(modEventBus);
    }
}
