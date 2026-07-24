package dev.projecteclipse.eclipse.client.economy;

import java.util.concurrent.ConcurrentLinkedQueue;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.hud.BottomToastQueue;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.network.economy.ShardPayloads;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * D14 personal shard-gain toast ("+2 Umbrasplitter"): {@code S2CShardGainPayload} drives a
 * one-line "◆ +2 …" pill in the shared bottom lane. Since EVAL-DOPA-F #5 the pill lives in
 * {@link BottomToastQueue} (single renderer, stacked slots, FIFO) — a shard gain landing
 * during a collection tier card now takes the slot above it instead of rendering through
 * it. This class only adapts the payload: network-thread handoff, then a
 * {@link BottomToastQueue.Toast} with the pill text/drawing. Never chat (anonymity law);
 * the payload only fires for grants that did not already play the
 * {@code RewardMaterializeOverlay}.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ShardGainToast {
    /** Hold length of the one-line pill (the shared queue adds fade in/out around it). */
    private static final int HOLD_TICKS = 36;

    private record Gain(int delta, int newBalance) implements BottomToastQueue.Toast {
        @Override
        public int holdTicks() {
            return HOLD_TICKS;
        }

        @Override
        public void draw(GuiGraphics guiGraphics, Font font, int centerX, int y, float alpha) {
            String diamond = "◆ ";
            String body = toastText(this);
            int diamondWidth = font.width(diamond);
            int width = diamondWidth + font.width(body);
            int x = centerX - width / 2;
            // Quiet backdrop pill so the line reads over bright terrain (no hard panel).
            guiGraphics.fill(x - 5, y - 3, x + width + 5, y + font.lineHeight + 2,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.PANEL, alpha * 0.7F));
            guiGraphics.drawString(font, diamond, x, y,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha));
            guiGraphics.drawString(font, body, x + diamondWidth, y,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
        }
    }

    /** Network thread hands off here; drained onto the shared queue on the client tick. */
    private static final ConcurrentLinkedQueue<Gain> INCOMING = new ConcurrentLinkedQueue<>();

    private ShardGainToast() {}

    /** Payload entry point ({@code ShardPayloads.handleShardGain}). */
    public static void enqueue(ShardPayloads.S2CShardGainPayload payload) {
        if (payload.delta() > 0) {
            INCOMING.add(new Gain(payload.delta(), payload.newBalance()));
        }
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        if (Minecraft.getInstance().level == null) {
            INCOMING.clear();
            return;
        }
        Gain incoming;
        while ((incoming = INCOMING.poll()) != null) {
            BottomToastQueue.enqueue(incoming);
        }
    }

    /** Toast body: "+2 Umbrasplitter (12 gesamt)" — degrades to the item name pre-langmerge. */
    private static String toastText(Gain gain) {
        if (EclipseLang.hasKey("gui.eclipse.shards.gain_toast")) {
            return EclipseLang.trString("gui.eclipse.shards.gain_toast", gain.delta(), gain.newBalance());
        }
        return "+" + gain.delta() + " " + EclipseLang.trString("item.eclipse.umbral_shard")
                + " (" + gain.newBalance() + ")";
    }
}
