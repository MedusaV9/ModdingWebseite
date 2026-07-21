package dev.projecteclipse.eclipse.client.menu;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.gui.screens.TitleScreen;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ScreenEvent;

/**
 * Replaces the vanilla title screen with {@link EclipseTitleScreen} via
 * {@link ScreenEvent.Opening} (game bus, client only). Guards: an opening
 * {@link EclipseTitleScreen} is left alone (no recursion), and only the exact vanilla
 * {@link TitleScreen} class is swapped — if another mod already substituted its own
 * screen (a {@code TitleScreen} subclass or anything else), we do nothing.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class TitleScreenSwap {
    private TitleScreenSwap() {}

    @SubscribeEvent
    static void onScreenOpening(ScreenEvent.Opening event) {
        // Respect earlier handlers' replacements by checking the effective new screen.
        Screen opening = event.getNewScreen();
        if (opening instanceof EclipseTitleScreen) {
            return;
        }
        if (opening != null && opening.getClass() == TitleScreen.class) {
            event.setNewScreen(new EclipseTitleScreen());
        }
    }
}
