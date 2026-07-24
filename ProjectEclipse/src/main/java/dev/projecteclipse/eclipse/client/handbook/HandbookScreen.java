package dev.projecteclipse.eclipse.client.handbook;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.EclipseKeyMappings;
import dev.projecteclipse.eclipse.client.handbook.tabs.BestiaryTab;
import dev.projecteclipse.eclipse.client.handbook.tabs.HandbookTab;
import dev.projecteclipse.eclipse.client.handbook.tabs.MapTab;
import dev.projecteclipse.eclipse.client.handbook.tabs.RevivalTab;
import dev.projecteclipse.eclipse.client.handbook.tabs.RewardsTab;
import dev.projecteclipse.eclipse.client.handbook.tabs.RulesTab;
import dev.projecteclipse.eclipse.client.handbook.tabs.SettingsTab;
import dev.projecteclipse.eclipse.client.handbook.tabs.StatusTab;
import dev.projecteclipse.eclipse.client.handbook.tabs.TimelineTab;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.hearts.HeartsService;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.AbstractWidget;
import net.minecraft.client.gui.components.Tooltip;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import org.lwjgl.glfw.GLFW;

/**
 * "Das Logbuch" — the handbook, v3 (plans_v3 P3 §3.1, design system §2 "Quiet Eclipse").
 * One centered flat panel over a {@link EclipseUiTheme#VEIL} backdrop: a 24px icon rail on
 * the left (active tab = 2px accent bar + tinted glyph + tooltip), a header row (tab title
 * left, day + hearts glance right), the active {@link HandbookTab} at FULL content width,
 * and a footer hint row inside the panel. No book spread, no parchment, no parallax, no
 * page fold — everything renders from {@code fill}/{@code text} + 1:1 icon blits, so
 * nothing can stretch or distort at any window size (kills B2/B9).
 *
 * <p>Motion (§2.3, all {@code reducedFx}-gated): open/close is a 5-tick fade with a 4px
 * rise of the panel; tab switches crossfade over 4 ticks with a 6px horizontal slide of
 * the CONTENT only. Rail buttons are real {@code addRenderableWidget}s rendered outside
 * any animated transform — hitboxes always match pixels (fixes B3) — and every tab's
 * {@link HandbookTab#widgets()} are added/removed on switch so they get genuine focus,
 * narration and input routing (fixes B4). ALL tabs tick every tick (fixes B6). The close
 * binding works from the keyboard AND as a mouse button ({@code matchesMouse}, fixes B8);
 * ESC and 1–8/←/→/PgUp/PgDn all work, with the active tab consulted FIRST on key input
 * (frozen API §7.2). Sounds run through {@link UiSounds} only: page turn on keyboard
 * switches, tab click on rail presses, hover blips from {@link EclipseWidget}.</p>
 *
 * <p>Opens via the J keybind ({@code ArtifactKeyHandler}) or a right-click on the pinned
 * slot-17 artifact ({@code ArmArtifactItem} → {@code ArtifactScreenOpener}); every value
 * renders live from {@code client.ClientStateCache}. Cursor lifecycle:
 * {@link CursorManager#endFrame()} once per frame, {@link CursorManager#reset()} in
 * {@link #removed()} — the system cursor ALWAYS comes back (risk R12).</p>
 */
@OnlyIn(Dist.CLIENT)
public class HandbookScreen extends Screen {
    private static final ResourceLocation HEART_FULL =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/heart_full.png");
    private static final ResourceLocation HEART_EMPTY =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/heart_empty.png");

    /** §3.1 layout clamps: {@code min(0.86*w, 560) x min(0.86*h, 320)}, content ≥ 96x72. */
    private static final float PANEL_PCT = 0.86F;
    private static final int MAX_PANEL_W = 560;
    private static final int MAX_PANEL_H = 320;
    private static final int MIN_CONTENT_W = 96;
    private static final int MIN_CONTENT_H = 72;
    /** Icon rail width inside the panel; a 1px hairline separates it from the body. */
    private static final int RAIL_W = 24;
    /** Header block height (title row + hairline); content starts 7px below. */
    private static final int HEADER_H = 25;
    /** Footer block height (hairline + hint row). */
    private static final int FOOTER_H = 16;
    /** Open/close: fade + rise ticks and distance (§2.3). */
    private static final int OPEN_TICKS = 5;
    private static final int RISE_PX = 4;
    /** Tab switch: crossfade ticks + content slide distance (§2.3). */
    private static final int SWITCH_TICKS = 4;
    private static final int SLIDE_PX = 6;

    // Tab roster in the frozen §3.1 order (W1 ledger applied by W2): status, timeline,
    // rules, revival, rewards, bestiary, map, settings. Keep Settings LAST — the rail,
    // 1-8 hotkeys, footer counter and crossfade all derive from tabs.size(), and
    // StatusTab's settings link reaches this page via the last hotkey.
    private final List<HandbookTab> tabs = List.of(new StatusTab(), new TimelineTab(), new RulesTab(),
            new RevivalTab(), new RewardsTab(), new BestiaryTab(), new MapTab(), new SettingsTab());
    /** Widgets currently mounted for the active tab (removed on switch — B4). */
    private final List<AbstractWidget> activeTabWidgets = new ArrayList<>();

    private int activeTab;
    private boolean shownOnce;

    private int openTicks;
    private boolean closing;
    private int closeTicks;

    /** Crossfade bookkeeping: tab being faded out; -1 = no switch running. */
    private int switchFrom = -1;
    private int switchTicks;
    private int switchDir = 1;

    // Panel geometry, recomputed in init() (open + resize). Fixed per layout — animation
    // never moves hitboxes, only drawn pixels.
    private int panelX;
    private int panelY;
    private int panelW;
    private int panelH;
    private int railSepX;
    private int contentX;
    private int contentY;
    private int contentW;
    private int contentH;
    private int footerHairlineY;

    public HandbookScreen() {
        super(EclipseLang.tr("gui.eclipse.handbook.title"));
    }

    @Override
    protected void init() {
        panelW = Math.min(Math.round(this.width * PANEL_PCT), MAX_PANEL_W);
        panelH = Math.min(Math.round(this.height * PANEL_PCT), MAX_PANEL_H);
        // Content minimums win over the percentage until the window itself is smaller.
        panelW = Math.max(panelW, Math.min(this.width, RAIL_W + 1 + 2 * EclipseUiTheme.PAD + MIN_CONTENT_W));
        panelH = Math.max(panelH, Math.min(this.height, HEADER_H + 7 + MIN_CONTENT_H + 6 + FOOTER_H));
        panelX = (this.width - panelW) / 2;
        panelY = (this.height - panelH) / 2;

        railSepX = panelX + RAIL_W;
        contentX = railSepX + 1 + EclipseUiTheme.PAD;
        contentW = Math.max(40, panelX + panelW - EclipseUiTheme.PAD - contentX);
        contentY = panelY + HEADER_H + 7;
        footerHairlineY = panelY + panelH - FOOTER_H;
        contentH = Math.max(40, footerHairlineY - 6 - contentY);

        // Rail buttons: top-aligned, fixed positions (no animated transform — B3). At
        // tiny panel heights the gap, then the button height, shrink until all fit.
        int buttonW = RAIL_W - 4;
        int buttonH = 20;
        int gap = 4;
        int railTop = panelY + 8;
        int available = panelH - 16;
        if (tabs.size() * (buttonH + gap) - gap > available) {
            gap = 2;
            buttonH = Mth.clamp((available - (tabs.size() - 1) * gap) / tabs.size(), 14, 20);
        }
        for (int i = 0; i < tabs.size(); i++) {
            addRenderableWidget(new RailButton(i, panelX + 2, railTop + i * (buttonH + gap), buttonW, buttonH));
        }

        for (HandbookTab tab : tabs) {
            tab.init(this, this.minecraft, contentX, contentY, contentW, contentH);
        }

        if (!shownOnce) {
            shownOnce = true;
            tabs.get(activeTab).onShown();
            UiSounds.pageTurn(); // soft opening rustle — the one open sound
        }
        activeTabWidgets.clear();
        for (AbstractWidget widget : tabs.get(activeTab).widgets()) {
            activeTabWidgets.add(addRenderableWidget(widget));
        }
    }

    @Override
    public void tick() {
        if (openTicks < OPEN_TICKS) {
            openTicks++;
        }
        if (closing && --closeTicks <= 0) {
            this.minecraft.setScreen(null);
            return;
        }
        if (switchFrom >= 0 && ++switchTicks >= SWITCH_TICKS) {
            switchFrom = -1;
        }
        for (HandbookTab tab : tabs) {
            tab.tick(); // ALL tabs, hidden or not (B6)
        }
    }

    // --- animation state ---

    /** Panel fade/rise progress 0..1 (open and close mirrored; instant with reducedFx). */
    private float panelProgress(float partialTick) {
        if (EclipseClientConfig.reducedFx()) {
            return closing ? 0.0F : 1.0F;
        }
        if (closing) {
            return Mth.clamp((closeTicks - partialTick) / OPEN_TICKS, 0.0F, 1.0F);
        }
        return Mth.clamp((openTicks + partialTick) / OPEN_TICKS, 0.0F, 1.0F);
    }

    /** Eased panel alpha for this frame; rail widgets fade with it (they never move). */
    float panelAlpha(float partialTick) {
        return easeOutCubic(panelProgress(partialTick));
    }

    /** Drawn-pixels-only vertical offset of the panel (4px rise while fading in). */
    private int panelRise(float partialTick) {
        return Math.round((1.0F - easeOutCubic(panelProgress(partialTick))) * RISE_PX);
    }

    private float switchProgress(float partialTick) {
        if (switchFrom < 0 || EclipseClientConfig.reducedFx()) {
            return 1.0F;
        }
        return Mth.clamp((switchTicks + partialTick) / SWITCH_TICKS, 0.0F, 1.0F);
    }

    private static float easeOutCubic(float t) {
        float inv = 1.0F - t;
        return 1.0F - inv * inv * inv;
    }

    // --- rendering ---

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        super.render(guiGraphics, mouseX, mouseY, partialTick); // backdrop+panel+content, then widgets
        if (currentTab().dragging()) {
            CursorManager.requestGrab();
        }
        CursorManager.endFrame(); // exactly one cursor per frame
    }

    /**
     * Backdrop, panel chrome and tab content — everything that must render BELOW the
     * widgets. Replaces the vanilla blur/gradient background entirely with the flat
     * {@link EclipseUiTheme#VEIL} dim.
     */
    @Override
    public void renderBackground(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        float alpha = panelAlpha(partialTick);
        int rise = panelRise(partialTick);
        int py = panelY + rise;

        guiGraphics.fill(0, 0, this.width, this.height, EclipseUiTheme.withAlpha(EclipseUiTheme.VEIL, alpha));
        EclipseUiTheme.drawPanel(guiGraphics, panelX, py, panelW, panelH, alpha);
        guiGraphics.fill(railSepX, py + 1, railSepX + 1, py + panelH - 1,
                EclipseUiTheme.withAlpha(EclipseUiTheme.HAIRLINE, alpha));

        renderHeader(guiGraphics, py, alpha);
        renderFooter(guiGraphics, py, alpha);
        renderContent(guiGraphics, mouseX, mouseY, partialTick, rise, alpha);
    }

    /** Header row: active tab title left (ACCENT), day + heart glance right, hairline under. */
    private void renderHeader(GuiGraphics guiGraphics, int py, float alpha) {
        int textY = py + 9;
        int right = contentX + contentW;

        // Glance, right-aligned: "Tag N" + heart icons; pieces drop when space runs out.
        int lives = Mth.clamp(ClientStateCache.lives, 0, HeartsService.MAX_HEARTS);
        Component dayText = EclipseLang.tr("gui.eclipse.artifact.day", ClientStateCache.day);
        int dayW = this.font.width(dayText);
        int heartsW = HeartsService.MAX_HEARTS * 10 - 1;
        boolean showHearts = dayW + 8 + heartsW + 60 <= contentW;
        boolean showDay = dayW + 60 <= contentW;
        int glanceW = showDay ? dayW + (showHearts ? 8 + heartsW : 0) : 0;

        if (showDay) {
            guiGraphics.drawString(this.font, dayText, right - glanceW, textY,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
        }
        if (showHearts) {
            int heartX = right - heartsW;
            int heartY = textY - 1;
            guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
            for (int i = 0; i < HeartsService.MAX_HEARTS; i++) {
                guiGraphics.blit(i < lives ? HEART_FULL : HEART_EMPTY,
                        heartX + i * 10, heartY, 0, 0, 9, 9, 9, 9);
            }
            guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        }

        int titleMax = contentW - (glanceW > 0 ? glanceW + 10 : 0);
        guiGraphics.drawString(this.font,
                EclipseUiTheme.ellipsize(this.font, currentTab().title().getString(), Math.max(20, titleMax)),
                contentX, textY, EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha));
        EclipseUiTheme.drawHairline(guiGraphics, contentX, right, py + HEADER_H, alpha);
    }

    /** Footer row inside the panel (replaces the outer hint — B9): pages + close key, DIM. */
    private void renderFooter(GuiGraphics guiGraphics, int py, float alpha) {
        int hairY = py + (footerHairlineY - panelY);
        EclipseUiTheme.drawHairline(guiGraphics, contentX, contentX + contentW, hairY, alpha);
        Component hint = EclipseLang.tr("gui.eclipse.handbook.footer", tabs.size(),
                EclipseKeyMappings.OPEN_MENU.getTranslatedKeyMessage());
        guiGraphics.drawString(this.font,
                EclipseUiTheme.ellipsize(this.font, hint.getString(), contentW),
                contentX, hairY + 5, EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, alpha * 0.9F));
    }

    /**
     * Active tab content, full width, scissored to the content rect. During a switch the
     * outgoing page fades while sliding {@value #SLIDE_PX}px out and the incoming page
     * fades in sliding from the opposite side — content only, widgets/rail never move.
     */
    private void renderContent(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick,
            int rise, float alpha) {
        guiGraphics.enableScissor(contentX - 2, contentY - 2 + rise,
                contentX + contentW + 2, contentY + contentH + 2 + rise);
        float turn = switchProgress(partialTick);
        if (turn >= 1.0F) {
            renderTabContent(guiGraphics, tabs.get(activeTab), 0.0F, rise, mouseX, mouseY, partialTick, alpha);
        } else {
            float eased = easeOutCubic(turn);
            renderTabContent(guiGraphics, tabs.get(switchFrom), -switchDir * SLIDE_PX * eased, rise,
                    mouseX, mouseY, partialTick, alpha * (1.0F - eased));
            renderTabContent(guiGraphics, tabs.get(activeTab), switchDir * SLIDE_PX * (1.0F - eased), rise,
                    mouseX, mouseY, partialTick, alpha * eased);
        }
        guiGraphics.disableScissor();
    }

    private void renderTabContent(GuiGraphics guiGraphics, HandbookTab tab, float dx, int rise,
            int mouseX, int mouseY, float partialTick, float alpha) {
        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(dx, rise, 0.0F);
        tab.render(guiGraphics, mouseX, mouseY, partialTick, alpha);
        guiGraphics.pose().popPose();
    }

    // --- tab switching ---

    /** Switches with the crossfade + page-turn sound (keyboard/programmatic path). */
    protected void switchTab(int index) {
        switchTab(index, false);
    }

    /**
     * Tab-switch core. Rail presses pass {@code fromRail=true}: their {@code ui.tab} press
     * already sounded ({@link RailButton#playDownSound}), keyboard switches whoosh with
     * {@link UiSounds#pageTurn()} instead (§2.3).
     */
    private void switchTab(int index, boolean fromRail) {
        if (closing || index == activeTab || index < 0 || index >= tabs.size()) {
            return;
        }
        int from = activeTab;
        activeTab = index;
        if (!EclipseClientConfig.reducedFx()) {
            switchFrom = from;
            switchTicks = 0;
            switchDir = index > from ? 1 : -1;
        } else {
            switchFrom = -1;
        }
        if (!fromRail) {
            UiSounds.pageTurn();
        }

        // Real widget lifecycle (B4): unmount the old page's widgets, mount the new page's.
        for (AbstractWidget widget : activeTabWidgets) {
            removeWidget(widget);
        }
        activeTabWidgets.clear();
        setFocused(null);
        tabs.get(index).onShown();
        for (AbstractWidget widget : tabs.get(index).widgets()) {
            activeTabWidgets.add(addRenderableWidget(widget));
        }
    }

    protected int activeTab() {
        return activeTab;
    }

    /** The active tab (drag state → grab cursor; input routing). */
    protected HandbookTab currentTab() {
        return tabs.get(activeTab);
    }

    // --- input ---

    @Override
    public boolean keyPressed(int keyCode, int scanCode, int modifiers) {
        if (closing) {
            return true;
        }
        // Frozen §7.2 ordering: the active tab sees keys BEFORE the hotkeys, so future
        // text fields are never hijacked by 1-8/arrows.
        if (currentTab().keyPressed(keyCode, scanCode, modifiers)) {
            return true;
        }
        if (EclipseKeyMappings.OPEN_MENU.matches(keyCode, scanCode)) {
            onClose();
            return true;
        }
        int hotkeys = Math.min(tabs.size(), 8);
        if (keyCode >= GLFW.GLFW_KEY_1 && keyCode < GLFW.GLFW_KEY_1 + hotkeys) {
            switchTab(keyCode - GLFW.GLFW_KEY_1);
            return true;
        }
        if (keyCode == GLFW.GLFW_KEY_LEFT || keyCode == GLFW.GLFW_KEY_PAGE_UP) {
            switchTab(Math.floorMod(activeTab - 1, tabs.size()));
            return true;
        }
        if (keyCode == GLFW.GLFW_KEY_RIGHT || keyCode == GLFW.GLFW_KEY_PAGE_DOWN) {
            switchTab(Math.floorMod(activeTab + 1, tabs.size()));
            return true;
        }
        return super.keyPressed(keyCode, scanCode, modifiers); // ESC + focus navigation
    }

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        if (closing) {
            return true;
        }
        if (super.mouseClicked(mouseX, mouseY, button)) { // widgets first
            return true;
        }
        if (currentTab().mouseClicked(mouseX, mouseY, button)) {
            return true;
        }
        // B8: a menu key rebound to a mouse button must still close the handbook. Checked
        // LAST so widgets/tab content always win the click.
        if (EclipseKeyMappings.OPEN_MENU.matchesMouse(button)) {
            onClose();
            return true;
        }
        return false;
    }

    @Override
    public boolean mouseDragged(double mouseX, double mouseY, int button, double dragX, double dragY) {
        if (currentTab().mouseDragged(mouseX, mouseY, button, dragX, dragY)) {
            return true;
        }
        return super.mouseDragged(mouseX, mouseY, button, dragX, dragY);
    }

    @Override
    public boolean mouseReleased(double mouseX, double mouseY, int button) {
        if (currentTab().mouseReleased(mouseX, mouseY, button)) {
            return true;
        }
        return super.mouseReleased(mouseX, mouseY, button);
    }

    @Override
    public boolean mouseScrolled(double mouseX, double mouseY, double scrollX, double scrollY) {
        if (currentTab().mouseScrolled(mouseX, mouseY, scrollX, scrollY)) {
            return true;
        }
        return super.mouseScrolled(mouseX, mouseY, scrollX, scrollY);
    }

    /** Mirrored 5-tick fade-out, then the actual close; instant under reducedFx or a second press. */
    @Override
    public void onClose() {
        if (closing || EclipseClientConfig.reducedFx()) {
            super.onClose();
            return;
        }
        closing = true;
        closeTicks = OPEN_TICKS;
    }

    @Override
    public boolean isPauseScreen() {
        return false;
    }

    /** ALWAYS hand the system cursor back, whatever screen comes next (risk R12). */
    @Override
    public void removed() {
        CursorManager.reset();
        super.removed();
    }

    /**
     * Rail icon button: quiet glyph, tooltip label, real widget (screen-space hitbox ==
     * drawn pixels, B3). Active tab shows a 2px accent bar on the panel's left edge and an
     * accent-tinted glyph; hover tints toward TEXT and blips via {@link EclipseWidget}.
     */
    private class RailButton extends EclipseWidget {
        private final int index;
        private final boolean iconPresent;

        RailButton(int index, int x, int y, int width, int height) {
            super(x, y, width, height, tabs.get(index).title());
            this.index = index;
            this.iconPresent = Minecraft.getInstance().getResourceManager()
                    .getResource(tabs.get(index).railIcon()).isPresent();
            setTooltip(Tooltip.create(getMessage())); // icon-only: the name lives in the tooltip
        }

        @Override
        public void onClick(double mouseX, double mouseY) {
            switchTab(index, true);
        }

        /** Rail presses keep the {@code ui.tab} click; re-pressing the open tab stays silent. */
        @Override
        public void playDownSound(net.minecraft.client.sounds.SoundManager handler) {
            if (index != activeTab()) {
                UiSounds.tab();
            }
        }

        @Override
        protected void renderContent(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
            float alpha = panelAlpha(partialTick);
            boolean active = index == activeTab();
            if (active) {
                guiGraphics.fill(panelX + 1, getY() + 1, panelX + 3, getY() + this.height - 1,
                        EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha));
            }

            int tint = active ? EclipseUiTheme.ACCENT : isHoveredOrFocused() ? EclipseUiTheme.TEXT
                    : EclipseUiTheme.DIM;
            int iconSize = Math.min(16, this.height - 4);
            int iconX = getX() + (this.width - iconSize) / 2 + 1; // optically centered next to the bar
            int iconY = getY() + (this.height - iconSize) / 2;
            if (iconPresent) {
                guiGraphics.setColor((tint >> 16 & 0xFF) / 255.0F, (tint >> 8 & 0xFF) / 255.0F,
                        (tint & 0xFF) / 255.0F, alpha);
                guiGraphics.blit(tabs.get(index).railIcon(), iconX, iconY, 0, 0,
                        iconSize, iconSize, iconSize, iconSize);
                guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
            } else {
                // Glyph not shipped yet (future tabs): the title's first letter keeps the
                // rail readable instead of a missing-texture checker.
                String letter = getMessage().getString().isEmpty() ? "?"
                        : getMessage().getString().substring(0, 1).toUpperCase();
                guiGraphics.drawCenteredString(HandbookScreen.this.font, letter,
                        getX() + this.width / 2, getY() + (this.height - 8) / 2,
                        EclipseUiTheme.withAlpha(tint, alpha));
            }
        }
    }
}
