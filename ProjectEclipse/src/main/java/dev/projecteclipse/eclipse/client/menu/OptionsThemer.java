package dev.projecteclipse.eclipse.client.menu;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.StringWidget;
import net.minecraft.client.gui.components.events.GuiEventListener;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.gui.screens.options.OptionsScreen;
import net.minecraft.network.chat.Component;
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
    /** The vanilla title sits at y=12 inside the header; the accent goes just above it. */
    private static final int ACCENT_Y = 2;
    private static final int ACCENT_HEIGHT = 9;

    private OptionsThemer() {}

    @SubscribeEvent
    static void onOptionsInit(ScreenEvent.Init.Post event) {
        if (!(event.getScreen() instanceof OptionsScreen screen)) {
            return;
        }
        // Init fires again from Screen#rebuildWidgets (which clears the widget list first),
        // so a surviving accent means some other injector already added one.
        for (GuiEventListener listener : event.getListenersList()) {
            if (listener instanceof AccentLine) {
                return;
            }
        }
        event.addListener(new AccentLine(screen, EclipseLang.tr("gui.eclipse.options.accent"),
                Minecraft.getInstance().font));
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

    /**
     * Full-width centered label that re-derives its bounds from the live screen.
     *
     * <p>A GUI-scale change (or a window resize) re-runs {@code Screen#init(Minecraft,int,int)}
     * on the SAME already-initialized screen instance, which then only calls
     * {@code repositionElements()}. {@link OptionsScreen} overrides that to
     * {@code layout.arrangeElements()} — it neither rebuilds the widget list nor re-fires
     * {@link ScreenEvent.Init}, both of which only happen through
     * {@code Screen#rebuildWidgets()}. A width captured once at init time therefore stays at
     * the PREVIOUS screen width and the accent visibly drifts out of the centre while every
     * vanilla widget re-centres. Reading {@code screen.width} per frame is immune to that,
     * whichever reposition path a screen takes.</p>
     */
    private static final class AccentLine extends StringWidget {
        private final Screen screen;

        AccentLine(Screen screen, Component message, Font font) {
            super(0, ACCENT_Y, screen.width, ACCENT_HEIGHT, message, font);
            this.screen = screen;
            alignCenter();
            setColor(ACCENT_COLOR);
        }

        @Override
        public void renderWidget(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
            if (getX() != 0 || getY() != ACCENT_Y || getWidth() != screen.width) {
                setX(0);
                setY(ACCENT_Y);
                setWidth(screen.width);
            }
            super.renderWidget(guiGraphics, mouseX, mouseY, partialTick);
        }
    }
}
