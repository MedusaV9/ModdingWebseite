package de.sonic0810.goobymod.registry;

import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.block.entity.NutellaJarBlockEntity;
import de.sonic0810.goobymod.block.entity.RabbitHutchBlockEntity;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.level.block.entity.BlockEntityType;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;

public final class ModBlockEntities {
    public static final DeferredRegister<BlockEntityType<?>> BLOCK_ENTITIES =
            DeferredRegister.create(Registries.BLOCK_ENTITY_TYPE, GoobyMod.MODID);

    public static final DeferredHolder<BlockEntityType<?>, BlockEntityType<NutellaJarBlockEntity>> NUTELLA_JAR =
            BLOCK_ENTITIES.register("nutella_jar",
                    () -> BlockEntityType.Builder.of(NutellaJarBlockEntity::new, ModBlocks.NUTELLA_JAR.get())
                            .build(null));

    public static final DeferredHolder<BlockEntityType<?>, BlockEntityType<RabbitHutchBlockEntity>> RABBIT_HUTCH =
            BLOCK_ENTITIES.register("rabbit_hutch",
                    () -> BlockEntityType.Builder.of(RabbitHutchBlockEntity::new, ModBlocks.RABBIT_HUTCH.get())
                            .build(null));

    public static void register(IEventBus bus) {
        BLOCK_ENTITIES.register(bus);
    }

    private ModBlockEntities() {
    }
}
