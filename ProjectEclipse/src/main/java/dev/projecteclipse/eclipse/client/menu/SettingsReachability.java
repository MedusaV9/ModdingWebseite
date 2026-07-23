package dev.projecteclipse.eclipse.client.menu;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.components.AbstractWidget;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.components.Tooltip;
import net.minecraft.client.gui.components.events.GuiEventListener;
import net.minecraft.client.gui.screens.PauseScreen;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.gui.screens.TitleScreen;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.contents.TranslatableContents;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ScreenEvent;

/**
 * B1 hotfix (user-reported, {@code docs/plans_v3/P3_ui.md} §1.2/§3.4): with
 * {@code customMenu=false} the Eclipse settings used to be unreachable. This class injects the
 * two missing entry points via {@link ScreenEvent.Init.Post} (game bus, client only, no mixins):
 * <ol>
 *   <li><b>Pause menu — always</b>: an "Eclipse…" {@link EclipseMenuButton} in the free slot
 *       right of "Options…" (mirroring the Open-to-LAN slot geometry) or, when that slot is
 *       occupied (vanilla NeoForge always occupies it with LAN/player-reporting), directly
 *       below the button grid (§3.4 placement rule). Skipped on the F3+Esc pause variant
 *       (no buttons).</li>
 *   <li><b>Vanilla title screen</b> — only while {@code customMenu=false}: a 20x20 gear
 *       bottom-right (above the copyright/brand lines) opening {@link EclipseSettingsScreen}.
 *       Re-enabling {@code customMenu} from there returns through the vanilla title, which
 *       {@link TitleScreenSwap} immediately swaps back to the custom screen.</li>
 * </ol>
 *
 * <p><b>Parallel-safety / W3 handshake</b>: the settings PLATFORM (panel, screen v2, its own
 * {@code PauseMenuHook}/{@code VanillaTitleGear}) belongs to P3-W3 and may land in the same
 * merge window. This handler therefore (a) runs at {@link EventPriority#LOW} so W3's hooks
 * fire first, and (b) skips injection whenever the screen already carries ANY widget labelled
 * with a {@code gui.eclipse.*} translation key — so the two implementations can never double
 * up. The integrator may delete this class once W3's mounts are merged (wiring note).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class SettingsReachability {
    private static final ResourceLocation GEAR = ResourceLocation.fromNamespaceAndPath(
            EclipseMod.MOD_ID, "textures/gui/title/gear.png");
    private static final int PAUSE_BUTTON_WIDTH = 98;
    private static final int BUTTON_HEIGHT = 20;
    private static final int GEAR_SIZE = 20;

    private SettingsReachability() {}

    @SubscribeEvent(priority = EventPriority.LOW)
    static void onScreenInit(ScreenEvent.Init.Post event) {
        Screen screen = event.getScreen();
        if (screen instanceof PauseScreen) {
            injectPauseEntry(event, screen);
        } else if (screen instanceof TitleScreen && !EclipseClientConfig.customMenu()) {
            injectVanillaTitleGear(event, screen);
        }
    }

    private static void injectPauseEntry(ScreenEvent.Init.Post event, Screen screen) {
        if (hasEclipseWidget(event)) {
            return; // W3's PauseMenuHook (or an earlier pass) already provides the entry.
        }
        AbstractWidget options = findWidgetByKey(event, "menu.options");
        if (options == null) {
            return; // F3+Esc variant (buttonless) or an unrecognizably modded pause screen.
        }

        int x = options.getX() + options.getWidth() + 4;
        int y = options.getY();
        if (isOccupied(event, x, y)) {
            // Vanilla NeoForge always fills the LAN/reporting slot -> below the button grid.
            x = screen.width / 2 - PAUSE_BUTTON_WIDTH / 2;
            y = Math.min(lowestWidgetBottom(event) + 4, screen.height - BUTTON_HEIGHT - 2);
        }

        event.addListener(Button.builder(Component.translatable("gui.eclipse.journey.settings_entry"),
                        button -> Minecraft.getInstance().setScreen(new EclipseSettingsScreen(screen)))
                .bounds(x, y, PAUSE_BUTTON_WIDTH, BUTTON_HEIGHT)
                .tooltip(Tooltip.create(Component.translatable("gui.eclipse.settings.title")))
                .build(EclipseMenuButton::new));
    }

    private static void injectVanillaTitleGear(ScreenEvent.Init.Post event, Screen screen) {
        if (hasEclipseWidget(event)) {
            return; // W3's VanillaTitleGear already provides the entry.
        }
        // Bottom-right, lifted above the copyright line (height-10) and NeoForge brand lines.
        int x = screen.width - GEAR_SIZE - 4;
        int y = screen.height - GEAR_SIZE - 24;
        event.addListener(Button.builder(Component.translatable("gui.eclipse.settings.title"),
                        button -> Minecraft.getInstance().setScreen(new EclipseSettingsScreen(screen)))
                .bounds(x, y, GEAR_SIZE, GEAR_SIZE)
                .tooltip(Tooltip.create(Component.translatable("gui.eclipse.settings.open")))
                .build(builder -> new EclipseMenuButton(builder, GEAR, 48, 48)));
    }

    // ---------------------------------------------------------------- helpers

    /** True when any widget already carries a {@code gui.eclipse.*} label (dedup vs. W3). */
    private static boolean hasEclipseWidget(ScreenEvent.Init.Post event) {
        for (GuiEventListener listener : event.getListenersList()) {
            if (listener instanceof AbstractWidget widget
                    && widget.getMessage().getContents() instanceof TranslatableContents contents
                    && contents.getKey().startsWith("gui.eclipse.")) {
                return true;
            }
        }
        return false;
    }

    @Nullable
    private static AbstractWidget findWidgetByKey(ScreenEvent.Init.Post event, String translationKey) {
        for (GuiEventListener listener : event.getListenersList()) {
            if (listener instanceof AbstractWidget widget
                    && widget.getMessage().getContents() instanceof TranslatableContents contents
                    && translationKey.equals(contents.getKey())) {
                return widget;
            }
        }
        return null;
    }

    private static boolean isOccupied(ScreenEvent.Init.Post event, int x, int y) {
        for (GuiEventListener listener : event.getListenersList()) {
            if (listener instanceof AbstractWidget widget
                    && x < widget.getX() + widget.getWidth()
                    && x + SettingsReachability.PAUSE_BUTTON_WIDTH > widget.getX()
                    && y < widget.getY() + widget.getHeight()
                    && y + BUTTON_HEIGHT > widget.getY()) {
                return true;
            }
        }
        return false;
    }

    private static int lowestWidgetBottom(ScreenEvent.Init.Post event) {
        int bottom = 0;
        for (GuiEventListener listener : event.getListenersList()) {
            if (listener instanceof AbstractWidget widget) {
                bottom = Math.max(bottom, widget.getY() + widget.getHeight());
            }
        }
        return bottom;
    }
}
