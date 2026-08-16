package de.sonic0810.goobymod.registry;

import de.sonic0810.goobymod.GoobyMod;
import net.minecraft.core.registries.Registries;
import net.minecraft.network.chat.Component;
import net.minecraft.world.item.CreativeModeTab;
import net.minecraft.world.item.ItemStack;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;

public final class ModCreativeTabs {
    public static final DeferredRegister<CreativeModeTab> TABS =
            DeferredRegister.create(Registries.CREATIVE_MODE_TAB, GoobyMod.MODID);

    public static final DeferredHolder<CreativeModeTab, CreativeModeTab> GOOBY_TAB =
            TABS.register("gooby", () -> CreativeModeTab.builder()
                    .title(Component.translatable("itemGroup.goobymod"))
                    .icon(() -> new ItemStack(ModItems.NUTELLA.get()))
                    .displayItems((params, output) -> {
                        output.accept(ModItems.NUTELLA.get());
                        output.accept(ModItems.EMPTY_JAR.get());
                        output.accept(ModItems.NUTELLA_TOAST.get());
                        output.accept(ModItems.GOOBY_BRUSH.get());
                        output.accept(ModItems.TRAINING_TREAT.get());
                        output.accept(ModItems.GOOBY_BALL.get());
                        output.accept(ModItems.GOOBY_WHISTLE.get());
                        output.accept(ModItems.GOOBY_HANDBOOK.get());
                        output.accept(ModItems.GOOBY_FLUFF.get());
                        output.accept(ModItems.SHIMMER_FLUFF.get());
                        output.accept(ModItems.GOOBY_SCARF.get());
                        output.accept(ModItems.GOOBY_BOWTIE.get());
                        output.accept(ModItems.TINY_SATCHEL.get());
                        output.accept(ModItems.FLOWER_CROWN.get());
                        output.accept(ModItems.ADVENTURE_BANDANA.get());
                        output.accept(ModItems.PICNIC_BACKPACK.get());
                        output.accept(ModItems.TORN_MAP_SCRAP.get());
                        output.accept(ModItems.GOOBY_TREASURE_MAP.get());
                        output.accept(ModItems.BUTTON_EYE.get());
                        output.accept(ModItems.GOOBY_WOOL.get());
                        output.accept(ModItems.GOOBY_PLUSHIE.get());
                        output.accept(ModItems.GOOBY_STATUE.get());
                        output.accept(ModItems.RABBIT_HUTCH.get());
                        output.accept(ModItems.GOOBY_SPAWN_EGG.get());
                    })
                    .build());

    public static void register(IEventBus bus) {
        TABS.register(bus);
    }

    private ModCreativeTabs() {
    }
}
