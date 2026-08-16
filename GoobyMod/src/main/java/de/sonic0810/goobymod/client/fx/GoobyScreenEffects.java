package de.sonic0810.goobymod.client.fx;

import de.sonic0810.goobymod.GoobyClientConfig;
import de.sonic0810.goobymod.GoobyMod;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RenderGuiEvent;

/**
 * Warm cuddle/bond vignette plus a subtle alarm screen pulse, drawn with plain
 * translucent GUI quads over {@link RenderGuiEvent.Post} — no shaders involved.
 * The vignette is a static fade (allowed with reducedMotion); the animated
 * pulse additionally respects reducedMotion.
 */
@EventBusSubscriber(modid = GoobyMod.MODID, value = Dist.CLIENT)
public final class GoobyScreenEffects {
    /** Warm nutella-orange glow for the cuddle vignette. */
    private static final int VIGNETTE_RGB = 0xFF9A5C;
    private static final float VIGNETTE_MAX_ALPHA = 0.26F;
    private static final float VIGNETTE_BAND_FRACTION = 0.22F;
    private static final int VIGNETTE_SIDE_STEPS = 12;

    /** Soft red wash for the alarm pulse; deliberately faint. */
    private static final int PULSE_RGB = 0xFF5A44;
    private static final float PULSE_MAX_ALPHA = 0.11F;
    private static final float PULSE_SPEED = 0.45F;

    @SubscribeEvent
    public static void onRenderGui(RenderGuiEvent.Post event) {
        if (!GoobyClientConfig.screenEffects()) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null || minecraft.player == null || minecraft.options.hideGui) {
            return;
        }
        float partialTick = event.getPartialTick().getGameTimeDeltaPartialTick(true);
        GuiGraphics graphics = event.getGuiGraphics();

        float cuddle = GoobyClientFx.cuddleIntensity(partialTick);
        if (cuddle > 0.01F) {
            renderVignette(graphics, cuddle);
        }

        if (!GoobyClientConfig.reducedMotion()) {
            float pulse = GoobyClientFx.alarmPulse(partialTick);
            if (pulse > 0.01F) {
                float oscillation = 0.5F + 0.5F
                        * Mth.sin(GoobyClientFx.animationTime(partialTick) * PULSE_SPEED);
                float alpha = pulse * oscillation * PULSE_MAX_ALPHA;
                graphics.fill(0, 0, graphics.guiWidth(), graphics.guiHeight(),
                        withAlpha(PULSE_RGB, alpha));
            }
        }
    }

    private static void renderVignette(GuiGraphics graphics, float intensity) {
        int width = graphics.guiWidth();
        int height = graphics.guiHeight();
        int band = Math.max(8, (int) (Math.min(width, height) * VIGNETTE_BAND_FRACTION));
        float edgeAlpha = intensity * VIGNETTE_MAX_ALPHA;
        int edgeColor = withAlpha(VIGNETTE_RGB, edgeAlpha);
        int clearColor = VIGNETTE_RGB & 0x00FFFFFF;

        graphics.fillGradient(0, 0, width, band, edgeColor, clearColor);
        graphics.fillGradient(0, height - band, width, height, clearColor, edgeColor);

        // GuiGraphics only offers vertical gradients, so the side glow is stepped.
        int stripWidth = Math.max(1, band / VIGNETTE_SIDE_STEPS);
        for (int i = 0; i < VIGNETTE_SIDE_STEPS; i++) {
            float stripAlpha = edgeAlpha * (1.0F - (i + 0.5F) / VIGNETTE_SIDE_STEPS);
            int color = withAlpha(VIGNETTE_RGB, stripAlpha);
            int leftX = i * stripWidth;
            graphics.fill(leftX, 0, leftX + stripWidth, height, color);
            int rightX = width - (i + 1) * stripWidth;
            graphics.fill(rightX, 0, rightX + stripWidth, height, color);
        }
    }

    private static int withAlpha(int rgb, float alpha) {
        int a = Mth.clamp((int) (alpha * 255.0F), 0, 255);
        return (a << 24) | (rgb & 0x00FFFFFF);
    }

    private GoobyScreenEffects() {
    }
}
