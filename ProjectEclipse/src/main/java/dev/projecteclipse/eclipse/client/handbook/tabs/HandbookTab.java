package dev.projecteclipse.eclipse.client.handbook.tabs;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.HandbookScreen;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * One page of the handbook. {@link HandbookScreen} assigns the right-page content rect via
 * {@link #init} (re-run on every resize), forwards input while the tab is active, calls
 * {@link #tick()} each client tick and {@link #onShown()} when the tab becomes the active
 * page (reset entry animations there). Rendering happens inside a scissor set by the
 * screen, with {@code alpha} from the book unfold/page-turn animation — multiply text
 * colors through {@link #withAlpha} and skip sub-10% text (the vanilla font treats near-zero
 * alpha as opaque).
 */
@OnlyIn(Dist.CLIENT)
public abstract class HandbookTab {
    protected static final int TEXT_COLOR = 0xE8E0F5;
    protected static final int ACCENT_COLOR = 0xB98CFF;
    protected static final int DIM_COLOR = 0x9A8FB8;

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

    /** One client tick while the handbook is open (active tab only). */
    public void tick() {}

    /** Stable id: lang keys ({@code gui.eclipse.handbook.tab.<id>}) and textures derive from it. */
    public abstract String id();

    public Component title() {
        return Component.translatable("gui.eclipse.handbook.tab." + id());
    }

    /** 64x64 spine-tongue icon. */
    public ResourceLocation icon() {
        return handbookTexture("tab_" + id());
    }

    /** 1024x768 left-page hero art. */
    public ResourceLocation hero() {
        return handbookTexture("hero_" + id());
    }

    /**
     * Renders the page content into the content rect. {@code alpha} is the book fade
     * (0..1); geometry animation (unfold/page turn) is already on the pose stack.
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

    /** True while the tab is spine-dragging (the screen shows the grab cursor). */
    public boolean dragging() {
        return false;
    }

    protected final boolean inRect(double mouseX, double mouseY) {
        return mouseX >= x && mouseX < x + width && mouseY >= y && mouseY < y + height;
    }

    protected static ResourceLocation handbookTexture(String name) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/handbook/" + name + ".png");
    }

    /** RGB color with the book-fade alpha applied (min 4/255 so 0 never flips to opaque). */
    protected static int withAlpha(int rgb, float alpha) {
        int a = Math.max(4, (int) (alpha * 255.0F));
        return (a << 24) | (rgb & 0xFFFFFF);
    }
}
