package dev.projecteclipse.eclipse.client.handbook.tabs;

import java.util.List;

import dev.projecteclipse.eclipse.client.menu.SettingsPanel;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.AbstractWidget;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Settings page of the handbook ({@code docs/plans_v3/P3_ui.md} §3.4, R12): embeds the
 * shared {@link SettingsPanel} composite — the exact same widget the standalone
 * {@code EclipseSettingsScreen} v2 mounts — so every client setting is editable from the
 * artifact/handbook UI in-game without leaving the world. Rail icon:
 * {@code textures/gui/handbook/rail_settings.png} (derives from {@link #id()}).
 *
 * <p>The panel is a REAL widget through the frozen {@link #widgets()} API (B4): the
 * screen mounts it while this tab is active, so mouse routing (clicks, wheel scroll,
 * slider drags), focus traversal and narration all come from the screen for free.
 * {@link #keyPressed} forwards to the panel whenever one of its rows holds focus —
 * consulted BEFORE the screen's 1–8/←/→ hotkeys (frozen §7.2 ordering), so arrow keys
 * nudge a focused slider instead of flipping pages. Scroll position survives resizes.</p>
 */
@OnlyIn(Dist.CLIENT)
public class SettingsTab extends HandbookTab {
    private SettingsPanel panel;

    @Override
    public String id() {
        return "settings";
    }

    @Override
    protected void onInit() {
        double keepScroll = panel != null ? panel.scrollAmount() : 0.0D;
        panel = new SettingsPanel(x, y, width, height);
        panel.setScrollAmount(keepScroll);
    }

    @Override
    public List<AbstractWidget> widgets() {
        return panel == null ? List.of() : panel.widgets();
    }

    @Override
    public boolean keyPressed(int keyCode, int scanCode, int modifiers) {
        // Only while a row holds focus: ←/→ then adjust the focused slider (Enter/Space
        // flip toggles) instead of reaching the screen's tab-switch hotkeys.
        return panel != null && panel.getFocused() != null
                && panel.keyPressed(keyCode, scanCode, modifiers);
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick, float alpha) {
        // Everything renders through the mounted panel widget (frozen §7.2, B4). Screen
        // widgets are drawn untransformed, so the panel deliberately sits out the
        // tab-switch crossfade — exactly like every other tab's widgets.
    }
}
