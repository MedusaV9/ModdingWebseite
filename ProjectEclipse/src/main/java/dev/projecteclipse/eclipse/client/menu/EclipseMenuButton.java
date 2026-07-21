package dev.projecteclipse.eclipse.client.menu;

import com.mojang.blaze3d.systems.RenderSystem;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.Button;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * A vanilla {@link Button} that draws the Eclipse title-screen textures instead of the
 * vanilla widget sprites. Built through {@link Button.Builder#build(java.util.function.Function)}
 * (see {@link EclipseTitleScreen}), so click/keyboard handling, tooltips and narration are
 * all inherited from vanilla — only {@link #renderWidget} is replaced.
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

    /** Use as {@code Button.builder(...).build(EclipseMenuButton::new)}. */
    public EclipseMenuButton(Button.Builder builder) {
        super(builder);
    }

    @Override
    protected void renderWidget(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        ResourceLocation texture = this.active && this.isHoveredOrFocused() ? TEXTURE_HIGHLIGHTED : TEXTURE;
        RenderSystem.enableBlend();
        float shade = this.active ? 1.0F : 0.55F;
        guiGraphics.setColor(shade, shade, shade, this.alpha);
        // Stretch the full 200x20 texture over the widget bounds so non-default sizes work too.
        guiGraphics.blit(texture, this.getX(), this.getY(), this.getWidth(), this.getHeight(),
                0.0F, 0.0F, TEXTURE_WIDTH, TEXTURE_HEIGHT, TEXTURE_WIDTH, TEXTURE_HEIGHT);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);

        int color = !this.active ? TEXT_COLOR_DISABLED : this.isHoveredOrFocused() ? TEXT_COLOR_HOVERED : TEXT_COLOR;
        this.renderString(guiGraphics, Minecraft.getInstance().font, color | Mth.ceil(this.alpha * 255.0F) << 24);
        RenderSystem.disableBlend();
    }
}
