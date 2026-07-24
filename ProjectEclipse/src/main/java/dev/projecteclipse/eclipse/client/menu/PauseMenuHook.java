package dev.projecteclipse.eclipse.client.menu;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.components.AbstractWidget;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.components.Tooltip;
import net.minecraft.client.gui.components.events.GuiEventListener;
import net.minecraft.client.gui.screens.PauseScreen;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.contents.TranslatableContents;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ScreenEvent;

/**
 * The permanent pause-menu settings entry ({@code docs/plans_v3/P3_ui.md} §3.4, R12 —
 * replaces the pause half of the interim {@code SettingsReachability} B1 hotfix): an
 * "Eclipse…" {@link EclipseMenuButton} injected into the vanilla pause menu via
 * {@link ScreenEvent.Init.Post} (game bus, client only, no mixins), opening
 * {@link EclipseSettingsScreen} with the pause screen as parent. Because the settings
 * screen keeps {@code isPauseScreen()==true}, a singleplayer game stays actually paused
 * for the whole visit and ESC unwinds Settings → Pause → world.
 *
 * <p><b>Placement</b> (§3.4 rule, kept from the interim fix): the free half-width slot
 * right of "Options…" — which mirrors the Open-to-LAN slot — or, when that slot is
 * occupied (vanilla NeoForge always fills it with LAN/player-reporting), a full row
 * directly below the button grid. The F3+Esc pause variant has no buttons and is skipped
 * (no "Options…" anchor).</p>
 *
 * <p><b>Dedupe guard</b> (kept from the interim fix): injection is skipped when the screen
 * already carries ANY widget labelled with a {@code gui.eclipse.*} translation key, so
 * this hook can never double up with another Eclipse injector in a mixed merge window.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class PauseMenuHook {
    /** Vanilla pause grid half-width ({@code PauseScreen} columns are 98px + 4px gutter). */
    private static final int BUTTON_WIDTH = 98;
    private static final int BUTTON_HEIGHT = 20;

    private PauseMenuHook() {}

    @SubscribeEvent
    static void onScreenInit(ScreenEvent.Init.Post event) {
        if (!(event.getScreen() instanceof PauseScreen screen)) {
            return;
        }
        if (hasEclipseWidget(event)) {
            return; // another Eclipse injector already provided the entry (dedupe guard)
        }
        AbstractWidget options = findWidgetByKey(event, "menu.options");
        if (options == null) {
            return; // F3+Esc variant (buttonless) or an unrecognizably modded pause screen
        }

        int x = options.getX() + options.getWidth() + 4;
        int y = options.getY();
        if (isOccupied(event, x, y)) {
            // Vanilla NeoForge always fills the LAN/reporting slot -> below the grid.
            x = screen.width / 2 - BUTTON_WIDTH / 2;
            y = Math.min(lowestWidgetBottom(event) + 4, screen.height - BUTTON_HEIGHT - 2);
        }

        event.addListener(Button.builder(EclipseLang.tr("gui.eclipse.settings.pause_entry"),
                        button -> Minecraft.getInstance().setScreen(new EclipseSettingsScreen(screen)))
                .bounds(x, y, BUTTON_WIDTH, BUTTON_HEIGHT)
                .tooltip(Tooltip.create(EclipseLang.tr("gui.eclipse.settings.title")))
                .build(EclipseMenuButton::new));
    }

    /**
     * True when any widget already carries a {@code gui.eclipse.*} label or is an Eclipse
     * button (labels resolved through {@code EclipseLang.tr} are literals on the override
     * path, so the key check alone would no longer see them — M-1).
     */
    private static boolean hasEclipseWidget(ScreenEvent.Init.Post event) {
        for (GuiEventListener listener : event.getListenersList()) {
            if (listener instanceof EclipseMenuButton) {
                return true;
            }
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
                    && x + BUTTON_WIDTH > widget.getX()
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
