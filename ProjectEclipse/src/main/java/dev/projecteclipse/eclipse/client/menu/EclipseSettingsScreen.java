package dev.projecteclipse.eclipse.client.menu;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.client.handbook.CursorManager;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.gui.screens.TitleScreen;
import net.minecraft.network.chat.CommonComponents;
import net.minecraft.network.chat.Component;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Eclipse settings v2 ({@code docs/plans_v3/P3_ui.md} §3.4): one Quiet-Eclipse panel hosting
 * the shared {@link SettingsPanel} (single source of truth — the same composite the handbook
 * Settings tab mounts) plus a Done button. Reached from the pause menu
 * ({@code PauseMenuHook}), the custom title gear ({@code EclipseTitleScreen}), the vanilla
 * title gear ({@code VanillaTitleGear}, {@code customMenu=false}) and NeoForge's Mods screen
 * ({@code ClientMenuExtensions} {@code IConfigScreenFactory}) — B1 is dead from every mount.
 *
 * <p>Values write through the typed {@code ModConfigSpec} handles inside
 * {@link SettingsPanel} ({@code set()+save()}, B13 — the v1 {@code valueMap()} string lookup
 * is gone) and apply live. All widget audio runs through {@code UiSounds} (B18). Motion per
 * §2.3: 5-tick fade + 4px chrome rise on open, mirrored fade on close ({@code reducedFx} =
 * instant); animation never moves hitboxes. ESC (or Done) returns to the parent screen;
 * {@link #isPauseScreen()} is {@code true}, so opening it from the singleplayer pause menu
 * actually keeps the game paused.</p>
 */
@OnlyIn(Dist.CLIENT)
public final class EclipseSettingsScreen extends Screen {
    /** §2.3 open/close: fade ticks + chrome rise distance. */
    private static final int OPEN_TICKS = 5;
    private static final int RISE_PX = 4;
    /** Fade cover tint (near-black aubergine, matches the VEIL family). */
    private static final int COVER_RGB = 0x04020A;

    private final Screen parent;

    @Nullable
    private SettingsPanel panel;
    private int panelX;
    private int panelY;
    private int panelW;
    private int panelH;

    private int openTicks;
    private boolean closing;
    private int closeTicks;

    public EclipseSettingsScreen(Screen parent) {
        super(Component.translatable("gui.eclipse.settings.title"));
        this.parent = parent;
    }

    @Override
    protected void init() {
        panelW = Mth.clamp(this.width - 24, 300, 400);
        panelH = Mth.clamp(this.height - 24, 200, 320);
        panelX = (this.width - panelW) / 2;
        panelY = (this.height - panelH) / 2;

        // Header block (title + subtitle) 38px, footer (Done) 32px, list between.
        int listX = panelX + 12;
        int listY = panelY + 38;
        int listW = panelW - 24;
        int listH = panelY + panelH - 32 - listY;

        double keepScroll = panel != null ? panel.scrollAmount() : 0.0D;
        panel = new SettingsPanel(listX, listY, listW, listH);
        panel.setScrollAmount(keepScroll);
        for (var widget : panel.widgets()) {
            addRenderableWidget(widget);
        }

        int doneW = 120;
        addRenderableWidget(Button.builder(CommonComponents.GUI_DONE, button -> onClose())
                .bounds(panelX + (panelW - doneW) / 2, panelY + panelH - 26, doneW, 20)
                .build(EclipseMenuButton::new));
    }

    @Override
    public void tick() {
        if (openTicks < OPEN_TICKS) {
            openTicks++;
        }
        if (closing && --closeTicks <= 0) {
            returnToParent();
        }
    }

    /** Panel fade progress 0..1 (open and close mirrored; instant with reducedFx). */
    private float fade(float partialTick) {
        if (EclipseClientConfig.reducedFx()) {
            return closing ? 0.0F : 1.0F;
        }
        float progress = closing
                ? Mth.clamp((closeTicks - partialTick) / OPEN_TICKS, 0.0F, 1.0F)
                : Mth.clamp((openTicks + partialTick) / OPEN_TICKS, 0.0F, 1.0F);
        float inv = 1.0F - progress;
        return 1.0F - inv * inv * inv; // ease-out cubic
    }

    /** Flat VEIL backdrop + panel chrome + header — everything below the widgets. */
    @Override
    public void renderBackground(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        float alpha = fade(partialTick);
        int rise = Math.round((1.0F - alpha) * RISE_PX);
        int py = panelY + rise;

        guiGraphics.fill(0, 0, this.width, this.height,
                EclipseUiTheme.withAlpha(EclipseUiTheme.VEIL, alpha));
        EclipseUiTheme.drawPanel(guiGraphics, panelX, py, panelW, panelH, alpha);
        guiGraphics.drawCenteredString(this.font, this.title, this.width / 2, py + 10,
                EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha));
        guiGraphics.drawCenteredString(this.font, EclipseLang.tr("gui.eclipse.settings.subtitle"),
                this.width / 2, py + 22, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha));
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        super.render(guiGraphics, mouseX, mouseY, partialTick);
        // Widgets do not carry a per-element alpha — a thin cover fading out on top gives
        // the whole screen the §2.3 open/close fade without moving any hitbox.
        float alpha = fade(partialTick);
        if (alpha < 0.98F) {
            guiGraphics.fill(0, 0, this.width, this.height,
                    EclipseUiTheme.withAlpha(0xFF000000 | COVER_RGB, 1.0F - alpha));
        }
        CursorManager.endFrame();
    }

    @Override
    public boolean keyPressed(int keyCode, int scanCode, int modifiers) {
        if (closing) {
            return true;
        }
        return super.keyPressed(keyCode, scanCode, modifiers);
    }

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        if (closing) {
            return true;
        }
        return super.mouseClicked(mouseX, mouseY, button);
    }

    /** Mirrored 5-tick fade-out, then the parent; instant under reducedFx or a second press. */
    @Override
    public void onClose() {
        if (closing || EclipseClientConfig.reducedFx()) {
            returnToParent();
            return;
        }
        closing = true;
        closeTicks = OPEN_TICKS;
    }

    /**
     * Turning the custom menu off from its own gear returns directly to a fresh vanilla
     * title screen. The Opening-event guard reads the just-saved value and leaves it alone.
     */
    private void returnToParent() {
        if (this.parent instanceof EclipseTitleScreen && !EclipseClientConfig.customMenu()) {
            this.minecraft.setScreen(new TitleScreen());
        } else {
            this.minecraft.setScreen(this.parent);
        }
    }

    /** Singleplayer pause menu → settings must actually stay paused (B1 follow-up, W8 note). */
    @Override
    public boolean isPauseScreen() {
        return true;
    }

    /** ALWAYS hand the system cursor back, whatever screen comes next (risk R12). */
    @Override
    public void removed() {
        CursorManager.reset();
        super.removed();
    }
}
