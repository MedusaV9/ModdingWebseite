package dev.projecteclipse.eclipse.client.handbook.tabs;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.HandbookScreen;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.AbstractWidget;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * One page of the handbook. {@link HandbookScreen} assigns the content rect via
 * {@link #init} (re-run on every resize), forwards input while the tab is active, calls
 * {@link #tick()} EVERY client tick — for every tab, hidden or not (B6: tabs decide
 * themselves how to react while hidden, e.g. Status fires its level-up sting even when
 * another page is open) — and {@link #onShown()} when the tab becomes the active page
 * (reset entry animations there). Rendering happens inside a scissor set by the screen,
 * with {@code alpha} from the panel fade / tab crossfade — multiply text colors through
 * {@link #withAlpha} and skip sub-10% frames (the vanilla font treats near-zero alpha as
 * opaque).
 *
 * <p><b>Frozen v3 API additions (plans_v3 P3 §7.2):</b> {@link #widgets()} returns real
 * {@link AbstractWidget}s that the screen adds/removes on tab switch (focus, narration and
 * input routing come from the screen — no more phantom widgets, B4; note they are rendered
 * by the screen UNTRANSFORMED, so they do not ride the crossfade slide), and
 * {@link #keyPressed} is consulted BEFORE the screen's 1–8/arrow hotkeys so future text
 * fields are never hijacked (B-audit). Colors delegate to {@link EclipseUiTheme}.</p>
 */
@OnlyIn(Dist.CLIENT)
public abstract class HandbookTab {
    protected static final int TEXT_COLOR = EclipseUiTheme.TEXT & 0xFFFFFF;
    protected static final int ACCENT_COLOR = EclipseUiTheme.ACCENT & 0xFFFFFF;
    protected static final int DIM_COLOR = EclipseUiTheme.DIM & 0xFFFFFF;

    protected Minecraft minecraft;
    protected Font font;
    protected HandbookScreen screen;
    protected int x;
    protected int y;
    protected int width;
    protected int height;

    public final void init(HandbookScreen screen, Minecraft minecraft, int x, int y, int width, int height) {
        this.screen = screen;
        this.minecraft = minecraft;
        this.font = minecraft.font;
        this.x = x;
        this.y = y;
        this.width = width;
        this.height = height;
        onInit();
    }

    /** Layout hook after the content rect changed (open + resize). */
    protected void onInit() {}

    /** The tab became the active page. */
    public void onShown() {}

    /**
     * One client tick while the handbook is open — called for EVERY tab, not just the
     * active one (B6). Tabs that animate entry states should gate on {@link #onShown()}
     * bookkeeping rather than assuming they are visible.
     */
    public void tick() {}

    /** Stable id: lang keys ({@code gui.eclipse.handbook.tab.<id>}) and textures derive from it. */
    public abstract String id();

    public Component title() {
        return EclipseLang.tr("gui.eclipse.handbook.tab." + id());
    }

    /**
     * Frozen API §7.2: the tab's real widgets. The screen {@code addRenderableWidget}s them
     * when the tab becomes active and removes them when it stops being active — rendering,
     * input, focus and narration are all screen-driven (B4). Widgets are rendered
     * untransformed (they do not slide with the tab-switch crossfade); reposition them in
     * {@link #onShown()} / {@link #onInit()} if the layout moved.
     */
    public List<AbstractWidget> widgets() {
        return List.of();
    }

    /**
     * Frozen API §7.2: first shot at key input, consulted BEFORE the screen's close key and
     * 1–8/arrow/PgUp/PgDn hotkeys. Return {@code true} to consume (e.g. an {@code EditBox}
     * swallowing digits).
     */
    public boolean keyPressed(int keyCode, int scanCode, int modifiers) {
        return false;
    }

    /**
     * 16x16 monochrome-white rail glyph ({@code textures/gui/handbook/rail_<id>.png}),
     * tinted by the rail (ACCENT active / DIM idle). The screen falls back to the title's
     * first letter when the texture is missing, so new tabs render before their art lands.
     */
    public ResourceLocation railIcon() {
        return handbookTexture("rail_" + id());
    }

    /**
     * 64x64 spine-tongue icon of the v2 book spread.
     *
     * @deprecated the v3 panel frame renders {@link #railIcon()} instead; kept so v2 art
     *             stays addressable until the P2 asset pass retires it.
     */
    @Deprecated
    public ResourceLocation icon() {
        return handbookTexture("tab_" + id());
    }

    /**
     * 1024x768 left-page hero art of the v2 book spread.
     *
     * @deprecated the v3 frame has no hero page (content gets the full width, §3.1); kept
     *             so v2 art stays addressable until the P2 asset pass retires it.
     */
    @Deprecated
    public ResourceLocation hero() {
        return handbookTexture("hero_" + id());
    }

    /**
     * Renders the page content into the content rect. {@code alpha} is the panel/crossfade
     * fade (0..1); slide animation is already on the pose stack.
     */
    public abstract void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick, float alpha);

    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        return false;
    }

    public boolean mouseDragged(double mouseX, double mouseY, int button, double dragX, double dragY) {
        return false;
    }

    public boolean mouseReleased(double mouseX, double mouseY, int button) {
        return false;
    }

    public boolean mouseScrolled(double mouseX, double mouseY, double scrollX, double scrollY) {
        return false;
    }

    /** True while the tab is drag-scrolling (the screen shows the grab cursor). */
    public boolean dragging() {
        return false;
    }

    protected final boolean inRect(double mouseX, double mouseY) {
        return mouseX >= x && mouseX < x + width && mouseY >= y && mouseY < y + height;
    }

    protected static ResourceLocation handbookTexture(String name) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/handbook/" + name + ".png");
    }

    /** Single-line ellipsis clamp — delegates to the frozen {@link EclipseUiTheme#ellipsize}. */
    protected static String ellipsize(Font font, String text, int maxWidth) {
        return EclipseUiTheme.ellipsize(font, text, maxWidth);
    }

    /** RGB color with the fade alpha applied — delegates to the frozen {@link EclipseUiTheme#withAlpha}. */
    protected static int withAlpha(int rgb, float alpha) {
        return EclipseUiTheme.withAlpha(rgb, alpha);
    }
}
