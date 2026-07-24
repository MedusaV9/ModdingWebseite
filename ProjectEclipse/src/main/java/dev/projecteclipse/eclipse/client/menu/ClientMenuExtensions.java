package dev.projecteclipse.eclipse.client.menu;

import java.util.function.Supplier;

import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.fml.ModContainer;
import net.neoforged.neoforge.client.gui.IConfigScreenFactory;

/** Client-only extension-point registration kept out of the dedicated-server class path. */
@OnlyIn(Dist.CLIENT)
public final class ClientMenuExtensions {
    private ClientMenuExtensions() {}

    public static void register(ModContainer modContainer) {
        modContainer.registerExtensionPoint(IConfigScreenFactory.class,
                (Supplier<IConfigScreenFactory>) () ->
                        (container, parent) -> new EclipseSettingsScreen(parent));
    }
}
