package dev.projecteclipse.eclipse.client.menu;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.components.StringWidget;
import net.minecraft.client.gui.screens.options.OptionsScreen;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ScreenEvent;

/**
 * Light-touch Eclipse theming of the vanilla {@link OptionsScreen} (game bus, client only) —
 * the screen itself is NOT forked or replaced, so every vanilla widget keeps working:
 * <ul>
 *   <li>{@link ScreenEvent.Init.Post}: adds a small purple "Project Eclipse" accent line
 *       above the vanilla title (a passive {@link StringWidget}, no input handling).</li>
 *   <li>{@link ScreenEvent.BackgroundRendered}: draws a translucent dark-purple gradient
 *       right after the vanilla background, i.e. behind all widgets/tooltips.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class OptionsThemer {
    private static final int ACCENT_COLOR = 0xFFB98CFF;
    private static final int GRADIENT_TOP = 0x66240A48;
    private static final int GRADIENT_BOTTOM = 0x99070112;

    private OptionsThemer() {}

    @SubscribeEvent
    static void onOptionsInit(ScreenEvent.Init.Post event) {
        if (!(event.getScreen() instanceof OptionsScreen screen)) {
            return;
        }
        // The vanilla title sits at y=12 inside the 61px header; the accent goes just above it.
        StringWidget accent = new StringWidget(0, 2, screen.width, 9,
                EclipseLang.tr("gui.eclipse.options.accent"),
                Minecraft.getInstance().font).alignCenter();
        accent.setColor(ACCENT_COLOR);
        event.addListener(accent);
    }

    // BackgroundRendered is deprecated-for-removal upstream but is the only hook that fires
    // between the vanilla background and the widgets; revisit when NeoForge drops it.
    @SuppressWarnings("removal")
    @SubscribeEvent
    static void onOptionsBackground(ScreenEvent.BackgroundRendered event) {
        if (!(event.getScreen() instanceof OptionsScreen screen)) {
            return;
        }
        event.getGuiGraphics().fillGradient(0, 0, screen.width, screen.height, GRADIENT_TOP, GRADIENT_BOTTOM);
    }
}
