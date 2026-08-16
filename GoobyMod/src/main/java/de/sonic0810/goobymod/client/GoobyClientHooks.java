package de.sonic0810.goobymod.client;

import net.minecraft.client.Minecraft;

/** Client-only entry points invoked through NeoForge's sided executor. */
public final class GoobyClientHooks {
    public static void openHandbook() {
        Minecraft.getInstance().setScreen(new GoobyHandbookScreen());
    }

    private GoobyClientHooks() {
    }
}
