package dev.projecteclipse.eclipse;

import com.mojang.logging.LogUtils;

import org.slf4j.Logger;

import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.network.EclipsePayloads;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import dev.projecteclipse.eclipse.registry.EclipseBlockEntities;
import dev.projecteclipse.eclipse.registry.EclipseBlocks;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import dev.projecteclipse.eclipse.registry.EclipseMenus;
import dev.projecteclipse.eclipse.registry.EclipseParticles;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.registry.EclipseWorldgen;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.fml.ModContainer;
import net.neoforged.fml.common.Mod;
import net.neoforged.fml.event.lifecycle.FMLCommonSetupEvent;

/**
 * Main entry point for Project: Eclipse (mod id {@value #MOD_ID}).
 */
@Mod(EclipseMod.MOD_ID)
public final class EclipseMod {
    public static final String MOD_ID = "eclipse";
    public static final Logger LOGGER = LogUtils.getLogger();

    public EclipseMod(IEventBus modEventBus, ModContainer modContainer) {
        EclipseItems.register(modEventBus);
        EclipseBlocks.register(modEventBus);
        EclipseBlockEntities.register(modEventBus);
        EclipseSounds.register(modEventBus);
        EclipseParticles.register(modEventBus);
        EclipseAttachments.register(modEventBus);
        EclipseMenus.register(modEventBus);
        EclipseWorldgen.register(modEventBus);

        EclipsePayloads.register(modEventBus);
        EclipseClientConfig.register(modContainer);
        modEventBus.addListener(EclipseMod::onCommonSetup);

        LOGGER.info("Project: Eclipse core initialized");
    }

    private static void onCommonSetup(FMLCommonSetupEvent event) {
        // Creates config/eclipse/*.json with defaults on first run.
        EclipseConfig.reload();
    }
}
