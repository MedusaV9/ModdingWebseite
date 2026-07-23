package dev.projecteclipse.eclipse.cutscene.client;

import java.util.Set;

import dev.projecteclipse.eclipse.EclipseMod;
import foundry.veil.api.client.util.Easing;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RenderGuiLayerEvent;

/**
 * Cinematic letterbox bars + HUD suppression during cutscene flights.
 *
 * <p>The layer itself (registered above all in {@code client.EclipseGuiLayers}) eases two
 * black bars in/out over ~{@value #EASE_NANOS} ns and shows a "space skips" hint when the
 * active path allows skipping. The bars deliberately stay up under F1 ({@code hideGui} —
 * they are cinematic framing, not HUD), but the skip-hint text is suppressed. While the active path requests {@code hideHud}, every other
 * GUI layer is cancelled via {@link RenderGuiLayerEvent.Pre} EXCEPT the id whitelist wired
 * by {@code EclipseGuiLayers} — the letterbox itself, W2's heart-burst overlay (a mid-death
 * burst must never be hidden) and the v1 wave overlay (the intro's water wash renders THROUGH
 * the cutscene by design).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class LetterboxLayer {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "cutscene_letterbox");

    /** Bar ease-in/out time (~0.4 s). */
    private static final long EASE_NANOS = 400_000_000L;
    /** Each bar covers this fraction of the screen height when fully in. */
    private static final float BAR_FRACTION = 0.12F;

    /** Layers that must keep rendering while the HUD is suppressed (set by EclipseGuiLayers). */
    private static volatile Set<ResourceLocation> hudWhitelist = Set.of(LAYER_ID);

    private static boolean active;
    private static boolean showSkipHint;
    private static float fromProgress;
    private static long toggleNanos;

    private LetterboxLayer() {}

    /** Wired once from {@code EclipseGuiLayers} so the layer-id constants stay authoritative. */
    public static void setHudWhitelist(Set<ResourceLocation> whitelist) {
        hudWhitelist = Set.copyOf(whitelist);
    }

    /** Driven by {@link CameraDirector} at flight start/end. */
    static void setActive(boolean nowActive, boolean allowSkip) {
        if (active != nowActive) {
            fromProgress = progress();
            toggleNanos = System.nanoTime();
            active = nowActive;
        }
        showSkipHint = nowActive && allowSkip;
    }

    /** Current 0..1 bar deployment, eased from the last toggle. */
    private static float progress() {
        float target = active ? 1.0F : 0.0F;
        if (toggleNanos == 0L) {
            return target;
        }
        float f = Mth.clamp((System.nanoTime() - toggleNanos) / (float) EASE_NANOS, 0.0F, 1.0F);
        return Mth.lerp(Easing.EASE_OUT_CUBIC.ease(f), fromProgress, target);
    }

    /** {@code LayeredDraw.Layer} body, registered above all by {@code EclipseGuiLayers}. */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        float p = progress();
        if (p <= 0.002F) {
            return;
        }
        int width = guiGraphics.guiWidth();
        int height = guiGraphics.guiHeight();
        int bar = Math.round(height * BAR_FRACTION * p);
        guiGraphics.fill(0, 0, width, bar, 0xFF000000);
        guiGraphics.fill(0, height - bar, width, height, 0xFF000000);

        if (showSkipHint && p > 0.6F && !Minecraft.getInstance().options.hideGui) {
            Font font = Minecraft.getInstance().font;
            Component hint = Component.translatable("gui.eclipse.cutscene.skip_hint");
            int alpha = (int) (Mth.clamp((p - 0.6F) / 0.4F, 0.0F, 1.0F) * 160.0F) + 40;
            int x = width - font.width(hint) - 8;
            int y = height - bar / 2 - font.lineHeight / 2;
            guiGraphics.drawString(font, hint, x, y, (alpha << 24) | 0xFFFFFF, false);
        }
    }

    /** HUD suppression: cancel every non-whitelisted layer while the active path hides the HUD. */
    @SubscribeEvent
    static void onRenderGuiLayerPre(RenderGuiLayerEvent.Pre event) {
        if (CameraDirector.isHudSuppressed() && !hudWhitelist.contains(event.getName())) {
            event.setCanceled(true);
        }
    }
}
