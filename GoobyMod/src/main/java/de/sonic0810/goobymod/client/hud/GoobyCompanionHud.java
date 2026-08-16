package de.sonic0810.goobymod.client.hud;

import de.sonic0810.goobymod.GoobyClientConfig;
import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.client.fx.GoobyClientFx;
import de.sonic0810.goobymod.entity.GoobyEntity;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.screens.ChatScreen;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RenderGuiEvent;

/**
 * Compact companion card for the nearest own tamed Gooby: name, mood glyph,
 * whistle command, plus health and satisfaction bars — all values are already
 * synchronized entity data, so no extra networking is needed. The card fades
 * in/out via {@link GoobyClientFx} (auto-fade after inactivity) and hides
 * behind screens, the debug overlay and F1. Presentation (metrics, colors,
 * clamping, drawing) lives in {@link CompanionCardRenderer}, shared with the
 * config screen preview.
 */
@EventBusSubscriber(modid = GoobyMod.MODID, value = Dist.CLIENT)
public final class GoobyCompanionHud {

    /** LOW priority keeps the card above the screen-effect vignette. */
    @SubscribeEvent(priority = EventPriority.LOW)
    public static void onRenderGui(RenderGuiEvent.Post event) {
        if (!GoobyClientConfig.showCompanionHud()) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.player == null || minecraft.level == null || minecraft.options.hideGui
                || minecraft.getDebugOverlay().showDebugScreen()) {
            return;
        }
        if (minecraft.screen != null && !(minecraft.screen instanceof ChatScreen)) {
            return;
        }
        GoobyEntity gooby = GoobyClientFx.trackedGooby();
        if (gooby == null) {
            return;
        }
        float partialTick = event.getPartialTick().getGameTimeDeltaPartialTick(true);
        float alpha = GoobyClientFx.hudAlpha(partialTick);
        if (alpha < 0.05F) {
            return;
        }
        renderCard(event.getGuiGraphics(), minecraft, gooby, alpha);
    }

    private static void renderCard(GuiGraphics graphics, Minecraft minecraft, GoobyEntity gooby,
            float alpha) {
        int x = CompanionCardRenderer.clampOffsetX(GoobyClientConfig.companionHudOffsetX(),
                graphics.guiWidth());
        int y = CompanionCardRenderer.clampOffsetY(GoobyClientConfig.companionHudOffsetY(),
                graphics.guiHeight());
        CompanionCardRenderer.CardData data = new CompanionCardRenderer.CardData(
                gooby.getName().getString(),
                gooby.getMood(),
                gooby.getCommandMode(),
                Mth.clamp(gooby.getHealth() / gooby.getMaxHealth(), 0.0F, 1.0F),
                Mth.clamp(gooby.getSatisfaction() / (float) GoobyEntity.MAX_SATISFACTION, 0.0F, 1.0F),
                gooby.isAlerting());
        CompanionCardRenderer.renderCard(graphics, minecraft.font, data, x, y, alpha);
    }

    private GoobyCompanionHud() {
    }
}
