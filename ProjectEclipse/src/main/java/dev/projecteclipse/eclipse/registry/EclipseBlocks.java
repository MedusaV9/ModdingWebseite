package dev.projecteclipse.eclipse.registry;

import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lives.GraveBlock;
import dev.projecteclipse.eclipse.ritual.AltarBlock;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockBehaviour;
import net.minecraft.world.level.material.MapColor;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredRegister;

/** Block registry for Project: Eclipse. */
public final class EclipseBlocks {
    public static final DeferredRegister<Block> BLOCKS =
            DeferredRegister.create(Registries.BLOCK, EclipseMod.MOD_ID);

    /** Player grave holding death drops. Stone-like strength, breakable by hand, never drops itself. */
    public static final Supplier<GraveBlock> GRAVE = BLOCKS.register("grave",
            () -> new GraveBlock(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.STONE)
                    .strength(1.5F, 6.0F)
                    .noLootTable()));

    /** Ritual altar (milestones, heart sacrifice, revive ritual). Obsidian-like, never drops itself. */
    public static final Supplier<AltarBlock> ALTAR = BLOCKS.register("altar",
            () -> new AltarBlock(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_BLACK)
                    .strength(50.0F, 1200.0F)
                    .requiresCorrectToolForDrops()
                    .noLootTable()));

    private EclipseBlocks() {}

    public static void register(IEventBus modEventBus) {
        BLOCKS.register(modEventBus);
    }
}
