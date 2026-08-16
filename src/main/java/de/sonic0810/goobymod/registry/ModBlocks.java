package de.sonic0810.goobymod.registry;

import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.block.DugDirtBlock;
import de.sonic0810.goobymod.block.GoobyPlushieBlock;
import de.sonic0810.goobymod.block.GoobyStatueBlock;
import de.sonic0810.goobymod.block.GoobyWoolBlock;
import de.sonic0810.goobymod.block.NutellaCakeBlock;
import de.sonic0810.goobymod.block.NutellaJarBlock;
import de.sonic0810.goobymod.block.RabbitHutchBlock;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.SoundType;
import net.minecraft.world.level.block.state.BlockBehaviour;
import net.minecraft.world.level.material.MapColor;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredBlock;
import net.neoforged.neoforge.registries.DeferredRegister;

public final class ModBlocks {
    public static final DeferredRegister.Blocks BLOCKS = DeferredRegister.createBlocks(GoobyMod.MODID);

    public static final DeferredBlock<NutellaJarBlock> NUTELLA_JAR = BLOCKS.register("nutella_jar",
            () -> new NutellaJarBlock(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_BROWN)
                    .strength(0.4F)
                    .sound(SoundType.GLASS)
                    .noOcclusion()
                    .randomTicks()));

    public static final DeferredBlock<NutellaCakeBlock> NUTELLA_CAKE = BLOCKS.register("nutella_cake",
            () -> new NutellaCakeBlock(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_BROWN)
                    .strength(0.5F)
                    .sound(SoundType.WOOL)
                    .noOcclusion()));

    public static final DeferredBlock<Block> GOOBY_WOOL = BLOCKS.register("gooby_wool",
            () -> new GoobyWoolBlock(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.TERRACOTTA_WHITE)
                    .strength(0.6F)
                    .sound(SoundType.WOOL)));

    public static final DeferredBlock<RabbitHutchBlock> RABBIT_HUTCH = BLOCKS.register("rabbit_hutch",
            () -> new RabbitHutchBlock(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.WOOD)
                    .strength(1.5F)
                    .sound(SoundType.WOOD)
                    .noOcclusion()));

    /** Sitzender Stoff-Gooby: knuddelbar, wasserloggbar und federweich. */
    public static final DeferredBlock<GoobyPlushieBlock> GOOBY_PLUSHIE = BLOCKS.register("gooby_plushie",
            () -> new GoobyPlushieBlock(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.COLOR_PINK)
                    .strength(0.4F)
                    .sound(SoundType.WOOL)
                    .noOcclusion()));

    /**
     * Steinernes Gooby-Denkmal mit Sockel; wasserloggbar fuer Brunnen.
     * BEWUSST ohne requiresCorrectToolForDrops(): der Eintrag im
     * minecraft:mineable/pickaxe-Tag beschleunigt nur den Abbau, die
     * gecraftete Deko droppt immer — auch von Hand (spielerfreundlich).
     */
    public static final DeferredBlock<GoobyStatueBlock> GOOBY_STATUE = BLOCKS.register("gooby_statue",
            () -> new GoobyStatueBlock(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.STONE)
                    .strength(1.5F, 6.0F)
                    .sound(SoundType.STONE)
                    .noOcclusion()));

    public static final DeferredBlock<DugDirtBlock> DUG_DIRT = BLOCKS.register("dug_dirt",
            () -> new DugDirtBlock(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.DIRT)
                    .strength(0.0F)
                    .sound(SoundType.ROOTED_DIRT)
                    .noCollission()
                    .noOcclusion()
                    .replaceable()));

    public static void register(IEventBus bus) {
        BLOCKS.register(bus);
    }

    private ModBlocks() {
    }
}
