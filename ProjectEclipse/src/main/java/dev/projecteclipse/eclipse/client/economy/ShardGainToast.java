package dev.projecteclipse.eclipse.client.economy;

import java.util.ArrayDeque;
import java.util.concurrent.ConcurrentLinkedQueue;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.economy.ShardPayloads;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RegisterGuiLayersEvent;
import net.neoforged.neoforge.client.gui.VanillaGuiLayers;

/**
 * D14 personal shard-gain toast ("+2 Umbrasplitter") — the {@code SkillProcToast} pattern:
 * {@code S2CShardGainPayload} drives a hotbar mini line that fades in with a 3px rise,
 * holds ~2s and fades out; gains queue (cap {@value #QUEUE_LIMIT}, oldest dropped) so a
 * quest-spree never overlaps. Renders one lane ABOVE the skill-proc toast so a proc and a
 * shard gain landing the same tick never stack. Never chat (anonymity law); the payload
 * only fires for grants that did not already play the {@code RewardMaterializeOverlay}.
 *
 * <p>Self-registered GUI layer (the {@code SkillProcToast.Registrar} pattern —
 * {@code EclipseGuiLayers} stays untouched); F1-hidden with the rest of the GUI.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ShardGainToast {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "shard_gain_toast");

    /** One lane above {@code SkillProcToast}'s materializing offset (70) — never stacks. */
    private static final int BOTTOM_OFFSET = 82;
    private static final int IN_TICKS = 5;
    private static final int HOLD_TICKS = 36;
    private static final int OUT_TICKS = 8;
    private static final int TOTAL_TICKS = IN_TICKS + HOLD_TICKS + OUT_TICKS;
    private static final int RISE_PX = 3;
    private static final int QUEUE_LIMIT = 4;

    private record Gain(int delta, int newBalance) {}

    /** Network thread hands off here; drained on the client tick thread. */
    private static final ConcurrentLinkedQueue<Gain> INCOMING = new ConcurrentLinkedQueue<>();
    // Client tick thread only.
    private static final ArrayDeque<Gain> QUEUE = new ArrayDeque<>();
    @Nullable
    private static Gain active;
    private static int ticks;

    private ShardGainToast() {}

    /** Mod-bus layer registration (nested, {@code SkillProcToast.Registrar} pattern). */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class Registrar {
        private Registrar() {}

        @SubscribeEvent
        static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
            event.registerAbove(VanillaGuiLayers.BOSS_OVERLAY, LAYER_ID, ShardGainToast::render);
        }
    }

    /** Payload entry point ({@code ShardPayloads.handleShardGain}). */
    public static void enqueue(ShardPayloads.S2CShardGainPayload payload) {
        if (payload.delta() > 0) {
            INCOMING.add(new Gain(payload.delta(), payload.newBalance()));
        }
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            INCOMING.clear();
            QUEUE.clear();
            active = null;
            return;
        }
        Gain incoming;
        while ((incoming = INCOMING.poll()) != null) {
            if (QUEUE.size() >= QUEUE_LIMIT) {
                QUEUE.pollFirst(); // oldest toast is the least interesting one
            }
            QUEUE.addLast(incoming);
        }
        if (minecraft.isPaused()) {
            return; // freeze the active toast; the queue stays intact
        }
        if (active != null && ++ticks > TOTAL_TICKS) {
            active = null;
        }
        if (active == null && !QUEUE.isEmpty()) {
            active = QUEUE.pollFirst();
            ticks = 0;
        }
    }

    /** GUI layer body (self-registered above the boss overlay). */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        Gain gain = active;
        if (gain == null || minecraft.options.hideGui) {
            return;
        }
        float t = ticks + deltaTracker.getGameTimeDeltaPartialTick(true);
        boolean reduced = EclipseClientConfig.reducedFx();

        float alpha;
        if (t < IN_TICKS) {
            alpha = reduced ? 1.0F : easeOutCubic(t / IN_TICKS);
        } else if (t <= IN_TICKS + HOLD_TICKS) {
            alpha = 1.0F;
        } else {
            alpha = 1.0F - easeOutCubic((t - IN_TICKS - HOLD_TICKS) / OUT_TICKS);
        }
        alpha = Mth.clamp(alpha, 0.0F, 1.0F);
        if (alpha <= 0.04F) {
            return; // fill() alpha-floor guard AND skips the invisible first frame
        }
        int rise = reduced ? 0 : Math.round((1.0F - easeOutCubic(Math.min(1.0F, t / IN_TICKS))) * RISE_PX);

        Font font = minecraft.font;
        String diamond = "◆ ";
        String body = toastText(gain);
        int diamondWidth = font.width(diamond);
        int width = diamondWidth + font.width(body);
        int x = (guiGraphics.guiWidth() - width) / 2;
        int y = guiGraphics.guiHeight() - BOTTOM_OFFSET + rise;

        // Quiet backdrop pill so the line reads over bright terrain (no hard panel).
        guiGraphics.fill(x - 5, y - 3, x + width + 5, y + font.lineHeight + 2,
                EclipseUiTheme.withAlpha(EclipseUiTheme.PANEL, alpha * 0.7F));
        guiGraphics.drawString(font, diamond, x, y, EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha));
        guiGraphics.drawString(font, body, x + diamondWidth, y,
                EclipseUiTheme.withAlpha(EclipseUiTheme.TEXT, alpha));
    }

    /** Toast body: "+2 Umbrasplitter (12 gesamt)" — degrades to the item name pre-langmerge. */
    private static String toastText(Gain gain) {
        if (EclipseLang.hasKey("gui.eclipse.shards.gain_toast")) {
            return EclipseLang.trString("gui.eclipse.shards.gain_toast", gain.delta(), gain.newBalance());
        }
        return "+" + gain.delta() + " " + EclipseLang.trString("item.eclipse.umbral_shard")
                + " (" + gain.newBalance() + ")";
    }

    private static float easeOutCubic(float t) {
        float inv = 1.0F - Mth.clamp(t, 0.0F, 1.0F);
        return 1.0F - inv * inv * inv;
    }
}
