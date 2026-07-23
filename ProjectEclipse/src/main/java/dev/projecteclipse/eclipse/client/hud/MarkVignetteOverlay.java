package dev.projecteclipse.eclipse.client.hud;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.resources.sounds.SimpleSoundInstance;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * The Ferryman's Lantern Gaze mark (W12, spec §2.2 P3): a pulsing purple edge vignette
 * only the hunted player sees, driven by the {@code marked} variant of
 * {@code S2CShakePayload}. Fades in over the first ~10 ticks and back out over the last
 * ~20; re-triggering restarts the timer. Cleared on level unload so a stale mark never
 * survives into another world.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class MarkVignetteOverlay {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "mark_vignette");

    private static final int FADE_IN_TICKS = 10;
    private static final int FADE_OUT_TICKS = 20;
    private static final float MAX_ALPHA = 0.34F;

    private static int ticksLeft = -1;
    private static int totalTicks = 1;

    private MarkVignetteOverlay() {}

    /** Starts (or refreshes) the mark for {@code ticks}, with a local bell toll. */
    public static void trigger(int ticks) {
        boolean fresh = ticksLeft <= 0;
        ticksLeft = Math.max(1, ticks);
        totalTicks = ticksLeft;
        if (fresh) {
            Minecraft.getInstance().getSoundManager().play(
                    SimpleSoundInstance.forUI(SoundEvents.BELL_RESONATE, 1.0F, 0.5F));
        }
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        if (Minecraft.getInstance().level == null) {
            ticksLeft = -1;
            return;
        }
        if (ticksLeft > 0) {
            ticksLeft--;
        }
    }

    /** GUI-layer body registered above the vanilla camera overlays; hidden under F1. */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        if (ticksLeft <= 0) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.player == null || minecraft.options.hideGui) {
            return;
        }
        float fadeIn = Mth.clamp((totalTicks - ticksLeft) / (float) FADE_IN_TICKS, 0.0F, 1.0F);
        float fadeOut = Mth.clamp(ticksLeft / (float) FADE_OUT_TICKS, 0.0F, 1.0F);
        float pulse = 0.75F + 0.25F * Mth.sin(minecraft.gui.getGuiTicks() * Mth.PI / 10.0F);
        float alpha = MAX_ALPHA * fadeIn * fadeOut * pulse;
        if (alpha <= 0.01F) {
            return;
        }

        int width = guiGraphics.guiWidth();
        int height = guiGraphics.guiHeight();
        int band = Math.max(12, height / 8);
        int solid = argb(alpha, 0x6A, 0x2A, 0xB8);
        int clear = argb(0.0F, 0x6A, 0x2A, 0xB8);
        // Soft purple wash bleeding in from all four edges.
        guiGraphics.fillGradient(0, 0, width, band, solid, clear);
        guiGraphics.fillGradient(0, height - band, width, height, clear, solid);
        fillGradientHorizontal(guiGraphics, 0, band, band, height - band, solid, clear);
        fillGradientHorizontal(guiGraphics, width - band, band, width, height - band, clear, solid);
    }

    private static void fillGradientHorizontal(GuiGraphics guiGraphics, int x0, int y0, int x1, int y1,
            int colorLeft, int colorRight) {
        int steps = Math.max(1, (x1 - x0) / 4);
        for (int i = 0; i < steps; i++) {
            float t0 = i / (float) steps;
            float t1 = (i + 1) / (float) steps;
            int sliceX0 = x0 + Math.round((x1 - x0) * t0);
            int sliceX1 = x0 + Math.round((x1 - x0) * t1);
            guiGraphics.fill(sliceX0, y0, sliceX1, y1, lerpColor(colorLeft, colorRight, (t0 + t1) * 0.5F));
        }
    }

    private static int lerpColor(int from, int to, float t) {
        int alpha = Mth.lerpInt(t, from >>> 24, to >>> 24);
        int red = Mth.lerpInt(t, (from >> 16) & 0xFF, (to >> 16) & 0xFF);
        int green = Mth.lerpInt(t, (from >> 8) & 0xFF, (to >> 8) & 0xFF);
        int blue = Mth.lerpInt(t, from & 0xFF, to & 0xFF);
        return (alpha << 24) | (red << 16) | (green << 8) | blue;
    }

    private static int argb(float alpha, int red, int green, int blue) {
        return (Mth.floor(Mth.clamp(alpha, 0.0F, 1.0F) * 255.0F) << 24)
                | (red << 16) | (green << 8) | blue;
    }
}
