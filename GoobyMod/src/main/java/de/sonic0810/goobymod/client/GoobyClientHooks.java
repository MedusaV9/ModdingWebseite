package de.sonic0810.goobymod.client;

import de.sonic0810.goobymod.network.TrickMenuPayload;
import net.minecraft.client.Minecraft;

/** Client-only entry points invoked through NeoForge's sided executor. */
public final class GoobyClientHooks {
    public static void openHandbook() {
        Minecraft.getInstance().setScreen(new GoobyHandbookScreen());
    }

    /** Oeffnet den nativen Trick-Selection-Screen mit den S2C-Menuedaten. */
    public static void openTrickScreen(TrickMenuPayload payload) {
        Minecraft.getInstance().setScreen(new GoobyTrickScreen(payload));
    }

    private GoobyClientHooks() {
    }
}
