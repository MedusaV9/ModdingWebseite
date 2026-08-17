package de.sonic0810.goobymod.client.config;

import net.neoforged.fml.ModContainer;
import net.neoforged.neoforge.client.gui.IConfigScreenFactory;

/**
 * Client-only entry point for the in-game configuration screen. This class
 * references {@link IConfigScreenFactory} (a client-only NeoForge class) and
 * must therefore only ever be classloaded behind a {@code Dist.CLIENT} check
 * — see the guarded call in {@code GoobyMod}'s constructor.
 */
public final class GoobyConfigScreens {

    /** Makes the "Config" button in the NeoForge mod list open our screen. */
    public static void register(ModContainer container) {
        container.registerExtensionPoint(IConfigScreenFactory.class,
                (modContainer, modListScreen) -> new GoobyConfigScreen(modListScreen));
    }

    private GoobyConfigScreens() {
    }
}
