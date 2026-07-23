package dev.projecteclipse.eclipse.client.menu;

import javax.annotation.Nullable;

import com.mojang.blaze3d.systems.RenderSystem;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.CursorManager;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.Button;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * A vanilla {@link Button} with the shared Eclipse UI behavior: themed face, hover
 * edge-detect sound, four-tick glow fade and pointing cursor request. Click/keyboard
 * handling, focus, tooltips and narration remain inherited from vanilla.
 */
@OnlyIn(Dist.CLIENT)
public final class EclipseMenuButton extends Button {
    private static final ResourceLocation TEXTURE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/title/button.png");
    private static final ResourceLocation TEXTURE_HIGHLIGHTED =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/title/button_highlighted.png");
    private static final int TEXTURE_WIDTH = 200;
    private static final int TEXTURE_HEIGHT = 20;

    private static final int TEXT_COLOR = 0xE8E0F5;
    private static final int TEXT_COLOR_HOVERED = 0xFFFFFF;
    private static final int TEXT_COLOR_DISABLED = 0x8A80A0;
    private static final float GLOW_STEP_PER_TICK = 0.25F;

    private boolean wasHovered;
    private float glow;
    private long lastFrameMillis;
    @Nullable
    private final ResourceLocation icon;
    private final int iconTextureWidth;
    private final int iconTextureHeight;

    /** Use as {@code Button.builder(...).build(EclipseMenuButton::new)}. */
    public EclipseMenuButton(Button.Builder builder) {
        this(builder, null, 0, 0);
    }

    /** Icon-only variant; the builder message remains its narration/accessibility label. */
    public EclipseMenuButton(Button.Builder builder, @Nullable ResourceLocation icon,
            int iconTextureWidth, int iconTextureHeight) {
        super(builder);
        this.icon = icon;
        this.iconTextureWidth = iconTextureWidth;
        this.iconTextureHeight = iconTextureHeight;
    }

    /** The soft Quiet-Eclipse click instead of the vanilla button plink (B18). */
    @Override
    public void playDownSound(net.minecraft.client.sounds.SoundManager handler) {
        UiSounds.click();
    }

    @Override
    protected void renderWidget(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        boolean hovered = this.active && this.isHoveredOrFocused();
        if (hovered && !wasHovered) {
            UiSounds.hover();
        }
        wasHovered = hovered;
        advanceGlow(hovered);
        if (hovered) {
            CursorManager.requestPointer();
        }

        ResourceLocation texture = hovered ? TEXTURE_HIGHLIGHTED : TEXTURE;
        RenderSystem.enableBlend();
        float shade = this.active ? 1.0F : 0.55F;
        guiGraphics.setColor(shade, shade, shade, this.alpha);
        // Stretch the full 200x20 texture over the widget bounds so non-default sizes work too.
        guiGraphics.blit(texture, this.getX(), this.getY(), this.getWidth(), this.getHeight(),
                0.0F, 0.0F, TEXTURE_WIDTH, TEXTURE_HEIGHT, TEXTURE_WIDTH, TEXTURE_HEIGHT);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);

        if (icon != null) {
            int iconSize = Math.max(4, Math.min(this.getWidth(), this.getHeight()) - 4);
            guiGraphics.setColor(shade, shade, shade, this.alpha);
            guiGraphics.blit(icon, this.getX() + (this.getWidth() - iconSize) / 2,
                    this.getY() + (this.getHeight() - iconSize) / 2,
                    iconSize, iconSize, 0.0F, 0.0F, iconTextureWidth, iconTextureHeight,
                    iconTextureWidth, iconTextureHeight);
            guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        } else {
            int color = !this.active ? TEXT_COLOR_DISABLED
                    : this.isHoveredOrFocused() ? TEXT_COLOR_HOVERED : TEXT_COLOR;
            this.renderString(guiGraphics, Minecraft.getInstance().font,
                    color | Mth.ceil(this.alpha * 255.0F) << 24);
        }
        if (glow > 0.02F) {
            renderGlowBorder(guiGraphics);
        }
        RenderSystem.disableBlend();
    }

    private void advanceGlow(boolean hovered) {
        long now = System.currentTimeMillis();
        float elapsedTicks = lastFrameMillis == 0L ? 1.0F : Math.min(4.0F, (now - lastFrameMillis) / 50.0F);
        lastFrameMillis = now;
        float target = hovered ? 1.0F : 0.0F;
        float step = GLOW_STEP_PER_TICK * elapsedTicks;
        if (glow < target) {
            glow = Math.min(target, glow + step);
        } else if (glow > target) {
            glow = Math.max(target, glow - step);
        }
    }

    private void renderGlowBorder(GuiGraphics guiGraphics) {
        int color = ((int) (glow * 190.0F) << 24) | 0xB98CFF;
        int x0 = getX() - 1;
        int y0 = getY() - 1;
        int x1 = getX() + width + 1;
        int y1 = getY() + height + 1;
        guiGraphics.fill(x0, y0, x1, y0 + 2, color);
        guiGraphics.fill(x0, y1 - 2, x1, y1, color);
        guiGraphics.fill(x0, y0 + 2, x0 + 2, y1 - 2, color);
        guiGraphics.fill(x1 - 2, y0 + 2, x1, y1 - 2, color);
    }
}
