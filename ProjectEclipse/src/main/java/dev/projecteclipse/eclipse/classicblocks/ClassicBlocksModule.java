package dev.projecteclipse.eclipse.classicblocks;

import net.neoforged.bus.api.IEventBus;

/**
 * P5-W8 entry point for the {@code eclipse:classic_*} decorative block set (plan §2.14).
 *
 * <p>Single wiring line for {@code EclipseMod}:
 * {@code ClassicBlocksModule.register(modEventBus);} — registers blocks, items and the
 * {@code eclipse.classic} creative tab. Everything else (assets, loot, tags, lang) ships
 * as generated resources from {@code tools/classicblocks/gen_assets.py}.
 */
public final class ClassicBlocksModule {

    private ClassicBlocksModule() {}

    public static void register(IEventBus modEventBus) {
        ClassicBlocks.register(modEventBus);
        ClassicBlockItems.register(modEventBus);
        ClassicCreativeTab.register(modEventBus);
    }
}
