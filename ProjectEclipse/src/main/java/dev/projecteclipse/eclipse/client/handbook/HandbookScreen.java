package dev.projecteclipse.eclipse.client.handbook;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.EclipseKeyMappings;
import dev.projecteclipse.eclipse.client.handbook.tabs.BestiaryTab;
import dev.projecteclipse.eclipse.client.handbook.tabs.HandbookTab;
import dev.projecteclipse.eclipse.client.handbook.tabs.MapTab;
import dev.projecteclipse.eclipse.client.handbook.tabs.RewardsTab;
import dev.projecteclipse.eclipse.client.handbook.tabs.RulesTab;
import dev.projecteclipse.eclipse.client.handbook.tabs.StatusTab;
import dev.projecteclipse.eclipse.client.handbook.tabs.TimelineTab;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.Tooltip;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import org.joml.Matrix4f;
import org.lwjgl.glfw.GLFW;

/**
 * "The Ledger of the Drowned" — the six-tab full-screen codex ({@code docs/ideas/03_ui_ux.md}
 * §B) that replaced the v1 176x166 artifact popup. Layout is 100% percentage-derived: a
 * centered book spread sized {@value #BOOK_WIDTH_PCT}w x {@value #BOOK_HEIGHT_PCT}h of the
 * screen over a full-bleed vignette, parchment tab tongues on the far-left spine (active
 * tongue slides out + glows), left page = hero art + nav, right page = the active
 * {@link HandbookTab}, bottom = page dots + key hint. Opens via the J keybind
 * ({@code ArtifactKeyHandler}) or the artifact right-click ({@code S2COpenArtifactPayload}
 * → {@code ArtifactScreenOpener}); every value renders live from
 * {@code client.ClientStateCache}. The book unfolds over {@value #UNFOLD_TICKS} ticks
 * (ease-out cubic scale + fade); tab switches play a {@value #TURN_TICKS}-tick page-turn
 * (old page skews + compresses toward the spine hinge, new page unfolds back out — with the
 * {@code ui.page_turn} sound on keyboard switches, while tongue clicks sound their own
 * {@code ui.tab} press only); the backdrop parallax layer shifts up to 8px opposite the
 * mouse and the hero art (mid layer) 4px. All animation honors {@code reducedFx}. Cursors:
 * interactive widgets request the pointing hand ({@link EclipseWidget}), timeline dragging
 * requests the grab fist, and {@link CursorManager#endFrame()} applies exactly one cursor
 * per frame — {@code removed()} ALWAYS resets to the system cursor.
 */
@OnlyIn(Dist.CLIENT)
public class HandbookScreen extends Screen {
    protected static final ResourceLocation BOOK_SPREAD = ResourceLocation.fromNamespaceAndPath(
            EclipseMod.MOD_ID, "textures/gui/handbook/book_spread.png");
    protected static final ResourceLocation DIVIDER = ResourceLocation.fromNamespaceAndPath(
            EclipseMod.MOD_ID, "textures/gui/handbook/divider.png");
    protected static final ResourceLocation PARCHMENT_TILE = ResourceLocation.fromNamespaceAndPath(
            EclipseMod.MOD_ID, "textures/gui/handbook/parchment_tile.png");

    private static final float BOOK_WIDTH_PCT = 0.90F;
    private static final float BOOK_HEIGHT_PCT = 0.85F;
    /** Below these content dims the percentage layout collapses → compact fallbacks kick in. */
    private static final int MIN_CONTENT_WIDTH = 96;
    private static final int MIN_CONTENT_HEIGHT = 72;
    private static final int UNFOLD_TICKS = 8;
    private static final int TURN_TICKS = 6;
    /** Parallax shift in px: background (backdrop) layer and mid (hero art) layer. */
    private static final float PARALLAX_BG = 8.0F;
    private static final float PARALLAX_MID = 4.0F;
    private static final int TEXT_COLOR = 0xE8E0F5;
    private static final int ACCENT_COLOR = 0xB98CFF;
    private static final int DIM_COLOR = 0x9A8FB8;

    private final List<HandbookTab> tabs = List.of(new StatusTab(), new TimelineTab(), new RulesTab(),
            new RewardsTab(), new BestiaryTab(), new MapTab());
    private final TabButton[] tabButtons = new TabButton[tabs.size()];
    private int activeTab;
    private int openTicks;
    /** Page-turn animation: the tab being turned away from; -1 = no turn running. */
    private int turnFrom = -1;
    private int turnTicks;
    /** Parallax mouse offset, normalized -1..1 (0 with {@code reducedFx}). */
    private float parallaxX;
    private float parallaxY;

    // Book geometry, recomputed in init() (open + resize).
    private int bookX;
    private int bookY;
    private int bookW;
    private int bookH;
    private int leftPageX;
    private int leftPageW;
    private int contentX;
    private int contentY;
    private int contentW;
    private int contentH;

    public HandbookScreen() {
        super(Component.translatable("gui.eclipse.handbook.title"));
    }

    @Override
    protected void init() {
        bookW = Math.round(this.width * BOOK_WIDTH_PCT);
        bookH = Math.round(this.height * BOOK_HEIGHT_PCT);
        int pageMargin = Math.round(bookW * 0.045F);
        int spineHalf = Math.round(bookW * 0.045F);
        int topBottomPad = Math.round(bookH * 0.06F);

        // Small-window guards (320x240 @ guiScale >= 2 and worse): the pure percentage
        // layout collapses the content below readability, so the book grows toward the
        // full window and the decorative padding drops to fixed compact values. Sane
        // sizes never trip these branches — the normal look is untouched.
        if (bookW / 2 - pageMargin - spineHalf < MIN_CONTENT_WIDTH) {
            bookW = this.width;
            pageMargin = 4;
            spineHalf = 4;
        }
        if (bookH - topBottomPad * 2 - 14 < MIN_CONTENT_HEIGHT) {
            bookH = this.height;
            topBottomPad = 4;
        }
        bookX = (this.width - bookW) / 2;
        bookY = (this.height - bookH) / 2;

        leftPageX = bookX + pageMargin;
        leftPageW = bookW / 2 - pageMargin - spineHalf;
        contentX = bookX + bookW / 2 + spineHalf;
        contentW = leftPageW;
        contentY = bookY + topBottomPad;
        contentH = bookH - topBottomPad * 2 - 14;

        // Spine tab tongues down the far-left edge. At small book heights the default
        // minimum (six 18px tongues + 4px gaps = 128px) overflows the book bottom, so
        // the gap and then the tongue height shrink until all six fit (floor 10px);
        // at tiny widths the tongues clamp to x=0 and overlap the book edge instead of
        // leaving the screen.
        int tabWidth = 24;
        int tabsY = contentY + 4;
        int tabGap = 4;
        int tabHeight = Mth.clamp(bookH / 9, 18, 30);
        int tabsAvailable = bookY + bookH - tabsY;
        if (tabs.size() * (tabHeight + tabGap) - tabGap > tabsAvailable) {
            tabGap = 2;
            tabHeight = Math.max(10, (tabsAvailable - (tabs.size() - 1) * tabGap) / tabs.size());
        }
        int tabX = Math.max(0, bookX - tabWidth + 8);
        for (int i = 0; i < tabs.size(); i++) {
            TabButton button = new TabButton(i, tabX, tabsY + i * (tabHeight + tabGap),
                    tabWidth, tabHeight);
            tabButtons[i] = button;
            addWidget(button); // input only — rendered inside the book transform
        }

        for (HandbookTab tab : tabs) {
            tab.init(this, this.minecraft, contentX, contentY, contentW, contentH);
        }
    }

    @Override
    public void tick() {
        if (openTicks < UNFOLD_TICKS) {
            openTicks++;
        }
        if (turnFrom >= 0 && ++turnTicks >= TURN_TICKS) {
            turnFrom = -1;
        }
        tabs.get(activeTab).tick();
    }

    /** Unfold progress 0..1 (1 immediately with {@code reducedFx}). */
    private float openProgress(float partialTick) {
        if (EclipseClientConfig.reducedFx()) {
            return 1.0F;
        }
        return Mth.clamp((openTicks + partialTick) / UNFOLD_TICKS, 0.0F, 1.0F);
    }

    /** Turn progress 0..1 (1 = finished / not turning). */
    private float turnProgress(float partialTick) {
        if (turnFrom < 0 || EclipseClientConfig.reducedFx()) {
            return 1.0F;
        }
        return Mth.clamp((turnTicks + partialTick) / TURN_TICKS, 0.0F, 1.0F);
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        // Parallax offset, normalized -1..1 from the screen center (frozen with reducedFx).
        if (!EclipseClientConfig.reducedFx()) {
            parallaxX = Mth.clamp(mouseX / Math.max(1.0F, this.width) * 2.0F - 1.0F, -1.0F, 1.0F);
            parallaxY = Mth.clamp(mouseY / Math.max(1.0F, this.height) * 2.0F - 1.0F, -1.0F, 1.0F);
        } else {
            parallaxX = 0.0F;
            parallaxY = 0.0F;
        }

        renderVignette(guiGraphics);

        float progress = openProgress(partialTick);
        float eased = 1.0F - (1.0F - progress) * (1.0F - progress) * (1.0F - progress); // ease-out cubic
        float alpha = eased;
        float scaleY = 0.9F + 0.1F * eased;
        float scaleX = 0.97F + 0.03F * eased;

        float centerX = this.width / 2.0F;
        float centerY = this.height / 2.0F;
        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(centerX, centerY, 0);
        guiGraphics.pose().scale(scaleX, scaleY, 1.0F);
        guiGraphics.pose().translate(-centerX, -centerY, 0);

        renderBook(guiGraphics, alpha);
        renderLeftPage(guiGraphics, mouseX, mouseY, alpha);
        renderRightPage(guiGraphics, mouseX, mouseY, partialTick, alpha);
        renderTabTongues(guiGraphics, mouseX, mouseY, partialTick, alpha);
        renderPageDots(guiGraphics, alpha);

        guiGraphics.pose().popPose();

        renderHint(guiGraphics, alpha);

        // One cursor per frame: grab while the tab drags, pointer if a widget asked, arrow else.
        if (currentTab().dragging()) {
            CursorManager.requestGrab();
        }
        CursorManager.endFrame();
    }

    /**
     * Full-bleed dark vignette over the world (edges darker than the center) with a faint
     * parchment texture as the {@value #PARALLAX_BG}px parallax background layer.
     */
    private void renderVignette(GuiGraphics guiGraphics) {
        guiGraphics.fill(0, 0, this.width, this.height, 0xA8060310);
        // Backdrop texture drifts opposite the mouse (u/v shift; the tile wraps).
        int shiftU = Math.round(parallaxX * PARALLAX_BG);
        int shiftV = Math.round(parallaxY * PARALLAX_BG);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 0.07F);
        guiGraphics.blit(PARCHMENT_TILE, 0, 0, shiftU, shiftV, this.width, this.height, 256, 256);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        int edge = Math.max(24, this.height / 8);
        guiGraphics.fillGradient(0, 0, this.width, edge, 0xB0000000, 0x00000000);
        guiGraphics.fillGradient(0, this.height - edge, this.width, this.height, 0x00000000, 0xB0000000);
    }

    private void renderBook(GuiGraphics guiGraphics, float alpha) {
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
        guiGraphics.blit(BOOK_SPREAD, bookX, bookY, 0, 0, bookW, bookH, bookW, bookH);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
    }

    /** Left page: ledger title, active tab title, divider ornament, hero art. */
    private void renderLeftPage(GuiGraphics guiGraphics, int mouseX, int mouseY, float alpha) {
        if (alpha < 0.1F) {
            return;
        }
        HandbookTab tab = tabs.get(activeTab);
        int pageCenterX = leftPageX + leftPageW / 2;
        int textY = contentY;
        guiGraphics.drawCenteredString(this.font, this.title, pageCenterX, textY, color(DIM_COLOR, alpha));
        textY += 12;

        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(pageCenterX, textY, 0);
        guiGraphics.pose().scale(1.5F, 1.5F, 1.0F);
        guiGraphics.drawCenteredString(this.font, tab.title(), 0, 0, color(ACCENT_COLOR, alpha));
        guiGraphics.pose().popPose();
        textY += 18;

        int dividerW = Math.min(leftPageW - 8, 96);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
        guiGraphics.blit(DIVIDER, pageCenterX - dividerW / 2, textY, 0, 0, dividerW, 12, dividerW, 12);

        // Hero art fills the rest of the page, aspect-fit 4:3.
        int heroTop = textY + 16;
        int heroMaxH = contentY + contentH - heroTop;
        int heroW = leftPageW - 4;
        int heroH = Math.round(heroW * 0.75F);
        if (heroH > heroMaxH) {
            heroH = heroMaxH;
            heroW = Math.round(heroH / 0.75F);
        }
        if (heroH > 24) {
            renderHero(guiGraphics, tab, pageCenterX - heroW / 2, heroTop, heroW, heroH, mouseX, mouseY, alpha);
        }
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
    }

    /**
     * Hero art, the {@value #PARALLAX_MID}px parallax mid layer: blitted slightly oversized
     * and shifted opposite the mouse, scissored to the frame so the edges never show.
     */
    protected void renderHero(GuiGraphics guiGraphics, HandbookTab tab, int heroX, int heroY,
            int heroW, int heroH, int mouseX, int mouseY, float alpha) {
        int pad = Math.round(PARALLAX_MID);
        int shiftX = Math.round(-parallaxX * PARALLAX_MID);
        int shiftY = Math.round(-parallaxY * PARALLAX_MID);
        guiGraphics.enableScissor(heroX, heroY, heroX + heroW, heroY + heroH);
        guiGraphics.blit(tab.hero(), heroX - pad + shiftX, heroY - pad + shiftY, 0, 0,
                heroW + pad * 2, heroH + pad * 2, heroW + pad * 2, heroH + pad * 2);
        guiGraphics.disableScissor();
    }

    /**
     * Right page content; during a tab switch the old page skews + compresses into the
     * spine hinge over the first half of the turn, the new page unfolds back out over the
     * second half ({@code ui.page_turn} plays from {@link #switchTab}).
     */
    private void renderRightPage(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick, float alpha) {
        guiGraphics.enableScissor(contentX - 2, contentY - 2, contentX + contentW + 2, contentY + contentH + 2);
        float turn = turnProgress(partialTick);
        if (turn >= 1.0F) {
            tabs.get(activeTab).render(guiGraphics, mouseX, mouseY, partialTick, alpha);
        } else if (turn < 0.5F) {
            float fold = turn * 2.0F; // 0 = flat, 1 = folded into the spine
            renderTurningPage(guiGraphics, tabs.get(turnFrom), 1.0F - fold, alpha * (1.0F - fold),
                    mouseX, mouseY, partialTick);
        } else {
            float unfold = (turn - 0.5F) * 2.0F;
            renderTurningPage(guiGraphics, tabs.get(activeTab), unfold, alpha * unfold,
                    mouseX, mouseY, partialTick);
        }
        guiGraphics.disableScissor();
    }

    /** One half of the page-turn: page sheared + x-compressed toward the spine hinge. */
    private void renderTurningPage(GuiGraphics guiGraphics, HandbookTab tab, float open, float alpha,
            int mouseX, int mouseY, float partialTick) {
        float hingeX = contentX; // spine edge of the right page
        float centerY = contentY + contentH / 2.0F;
        float folded = 1.0F - open;
        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(hingeX, centerY, 0);
        Matrix4f shear = new Matrix4f();
        shear.m10(-0.18F * folded); // x' = x - k*y: the page top leans into the spine
        guiGraphics.pose().mulPose(shear);
        guiGraphics.pose().scale(Math.max(0.02F, open), 1.0F - 0.06F * folded, 1.0F);
        guiGraphics.pose().translate(-hingeX, -centerY, 0);
        tab.render(guiGraphics, mouseX, mouseY, partialTick, alpha);
        guiGraphics.pose().popPose();
    }

    private void renderTabTongues(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick, float alpha) {
        for (TabButton button : tabButtons) {
            button.renderTongue(guiGraphics, mouseX, mouseY, partialTick, alpha);
        }
    }

    private void renderPageDots(GuiGraphics guiGraphics, float alpha) {
        int dotSpacing = 12;
        int dotsWidth = tabs.size() * dotSpacing - dotSpacing + 4;
        int dotX = bookX + bookW / 2 - dotsWidth / 2;
        int dotY = bookY + bookH - 16;
        for (int i = 0; i < tabs.size(); i++) {
            boolean active = i == activeTab;
            int color = color(active ? ACCENT_COLOR : 0x554A70, alpha);
            int size = active ? 4 : 3;
            int offset = active ? 0 : 1;
            guiGraphics.fill(dotX + i * dotSpacing + offset, dotY + offset,
                    dotX + i * dotSpacing + offset + size, dotY + offset + size, color);
        }
    }

    private void renderHint(GuiGraphics guiGraphics, float alpha) {
        if (alpha < 0.1F) {
            return;
        }
        Component hint = Component.translatable("gui.eclipse.handbook.hint",
                EclipseKeyMappings.OPEN_MENU.getTranslatedKeyMessage());
        guiGraphics.drawCenteredString(this.font, hint, this.width / 2,
                Math.min(this.height - 10, bookY + bookH + 3), color(DIM_COLOR, alpha * 0.9F));
    }

    /** Switches the active tab with the page-turn animation + sound (keyboard/programmatic path). */
    protected void switchTab(int index) {
        switchTab(index, false);
    }

    /**
     * Tab-switch core. Tongue clicks pass {@code fromTabButton=true} so only their
     * {@code ui.tab} press sounds ({@link TabButton#playDownSound} already played it);
     * keyboard/arrow/number-key switches keep the {@code ui.page_turn} whoosh.
     */
    private void switchTab(int index, boolean fromTabButton) {
        if (index == activeTab || index < 0 || index >= tabs.size()) {
            return;
        }
        if (!EclipseClientConfig.reducedFx()) {
            turnFrom = activeTab;
            turnTicks = 0;
        }
        if (!fromTabButton) {
            UiSounds.pageTurn();
        }
        activeTab = index;
        tabs.get(index).onShown();
    }

    protected int activeTab() {
        return activeTab;
    }

    /** The active tab reports drag state (grab cursor + input routing). */
    protected HandbookTab currentTab() {
        return tabs.get(activeTab);
    }

    @Override
    public boolean keyPressed(int keyCode, int scanCode, int modifiers) {
        if (EclipseKeyMappings.OPEN_MENU.matches(keyCode, scanCode)) {
            onClose();
            return true;
        }
        if (keyCode >= GLFW.GLFW_KEY_1 && keyCode <= GLFW.GLFW_KEY_1 + tabs.size() - 1) {
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
        return super.keyPressed(keyCode, scanCode, modifiers);
    }

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        if (super.mouseClicked(mouseX, mouseY, button)) {
            return true;
        }
        return tabs.get(activeTab).mouseClicked(mouseX, mouseY, button);
    }

    @Override
    public boolean mouseDragged(double mouseX, double mouseY, int button, double dragX, double dragY) {
        if (tabs.get(activeTab).mouseDragged(mouseX, mouseY, button, dragX, dragY)) {
            return true;
        }
        return super.mouseDragged(mouseX, mouseY, button, dragX, dragY);
    }

    @Override
    public boolean mouseReleased(double mouseX, double mouseY, int button) {
        if (tabs.get(activeTab).mouseReleased(mouseX, mouseY, button)) {
            return true;
        }
        return super.mouseReleased(mouseX, mouseY, button);
    }

    @Override
    public boolean mouseScrolled(double mouseX, double mouseY, double scrollX, double scrollY) {
        if (tabs.get(activeTab).mouseScrolled(mouseX, mouseY, scrollX, scrollY)) {
            return true;
        }
        return super.mouseScrolled(mouseX, mouseY, scrollX, scrollY);
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

    protected static int color(int rgb, float alpha) {
        int a = Math.max(4, (int) (alpha * 255.0F));
        return (a << 24) | (rgb & 0xFFFFFF);
    }

    /** Parchment tongue on the spine; the active one slides out 6px and glows. */
    private class TabButton extends EclipseWidget {
        private final int index;
        private final int restX;
        private float slide;

        TabButton(int index, int x, int y, int width, int height) {
            super(x, y, width, height, tabs.get(index).title());
            this.index = index;
            this.restX = x;
            // The tongues are icon-only; hovering reveals the tab name as a tooltip.
            setTooltip(Tooltip.create(getMessage()));
        }

        @Override
        public void onClick(double mouseX, double mouseY) {
            switchTab(index, true);
        }

        /** Replace the vanilla button click with the ui.tab tongue press (no re-click plink). */
        @Override
        public void playDownSound(net.minecraft.client.sounds.SoundManager handler) {
            if (index != activeTab()) {
                UiSounds.tab(); // Clicking the already-open tab switches nothing — stay silent.
            }
        }

        /** Rendered from the screen inside the book transform (widget is input-only). */
        void renderTongue(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick, float alpha) {
            boolean active = index == activeTab();
            float targetSlide = active ? 6.0F : 0.0F;
            slide += (targetSlide - slide) * (EclipseClientConfig.reducedFx() ? 1.0F : 0.35F);
            setX(restX - Math.round(slide));

            // Reuse the base-class glow/hover bookkeeping by rendering through renderWidget.
            render(guiGraphics, mouseX, mouseY, partialTick);

            if (active) {
                renderGlowBorder(guiGraphics, Math.max(glow, 0.55F * alpha));
            }
        }

        @Override
        protected void renderContent(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
            float alpha = openProgress(partialTick);
            boolean active = index == activeTab();
            int base = active ? 0x2E1F4A : 0x1E1432;
            guiGraphics.fill(getX(), getY(), getX() + width, getY() + height, color(base, alpha * 0.95F));
            int edge = color(active ? ACCENT_COLOR : 0x453A5E, alpha);
            guiGraphics.fill(getX(), getY(), getX() + width, getY() + 1, edge);
            guiGraphics.fill(getX(), getY() + height - 1, getX() + width, getY() + height, edge);
            guiGraphics.fill(getX(), getY(), getX() + 1, getY() + height, edge);

            guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
            int iconSize = Math.min(16, height - 4);
            guiGraphics.blit(tabs.get(index).icon(), getX() + (width - iconSize) / 2 - 2,
                    getY() + (height - iconSize) / 2, 0, 0, iconSize, iconSize, iconSize, iconSize);
            guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        }
    }
}
