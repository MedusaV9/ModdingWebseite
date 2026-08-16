package de.sonic0810.goobymod;

import de.sonic0810.goobymod.compat.CreateCompat;
import de.sonic0810.goobymod.registry.ModBlocks;
import de.sonic0810.goobymod.registry.ModBlockEntities;
import de.sonic0810.goobymod.registry.ModCreativeTabs;
import de.sonic0810.goobymod.registry.ModEntities;
import de.sonic0810.goobymod.registry.ModItems;
import de.sonic0810.goobymod.registry.ModMenus;
import de.sonic0810.goobymod.registry.ModParticles;
import de.sonic0810.goobymod.registry.ModSounds;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.fml.ModContainer;
import net.neoforged.fml.common.Mod;
import net.neoforged.fml.config.ModConfig;

/**
 * GOOBY MOD — der dicke, grosse, niedliche Hase, der immer laechelt.
 * Made with love by Sonic0810.
 */
@Mod(GoobyMod.MODID)
public final class GoobyMod {
    public static final String MODID = "goobymod";

    public GoobyMod(IEventBus modEventBus, ModContainer container) {
        ModSounds.register(modEventBus);
        ModBlocks.register(modEventBus);
        ModBlockEntities.register(modEventBus);
        ModItems.register(modEventBus);
        ModMenus.MENUS.register(modEventBus);
        ModEntities.register(modEventBus);
        ModParticles.register(modEventBus);
        ModCreativeTabs.register(modEventBus);
        container.registerConfig(ModConfig.Type.SERVER, GoobyConfig.SPEC);
        container.registerConfig(ModConfig.Type.CLIENT, GoobyClientConfig.SPEC);
        CreateCompat.logDiagnostics();
    }
}
