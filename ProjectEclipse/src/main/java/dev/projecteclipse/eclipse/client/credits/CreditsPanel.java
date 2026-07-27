package dev.projecteclipse.eclipse.client.credits;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.network.credits.CreditsPayloads;
import dev.projecteclipse.eclipse.network.credits.CreditsPayloads.S2CCreditsRollPayload;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RenderGuiEvent;

/**
 * Right-side credits text scroll (IDEAS-backrooms_finale §B4): a panel on the right third
 * of the screen (x 68%→96%) whose lines scroll bottom→top across the whole beach+black span
 * of the credits sequence, 0.9 scale, {@link EclipseUiTheme#TEXT} body with
 * {@link EclipseUiTheme#DIM} section headers, behind a soft 110-alpha left-edge gradient so
 * the text reads over the sunrise.
 *
 * <p><b>Content is lang-keyed</b> (langdrop protocol, de/en parity):
 * {@code eclipse.credits.roll.1}, {@code .2}, … are read until the first missing key at
 * roll start. A line value starting with {@code #} renders as a DIM section header with
 * extra leading space; everything else is a body line. Resolved once per roll (a mid-roll
 * {@code /lang} switch applies on the next roll).</p>
 *
 * <p>Renders from {@link RenderGuiEvent.Post} like {@code BossIntroOverlay}, so the
 * cutscene letterbox's GUI-layer suppression can never eat it; only F1 hides it. The scroll
 * clock is client-tick based and the whole panel clears on logout or when the configured
 * duration elapses.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class CreditsPanel {
    /** Hard cap on roll lines (defensive bound for the lang scan). */
    private static final int MAX_LINES = 200;
    private static final float SCALE = 0.9F;
    /** Extra leading gap above a {@code #} header line (unscaled px). */
    private static final int HEADER_GAP = 10;
    /** Panel horizontal bounds as fractions of the screen width. */
    private static final float PANEL_LEFT = 0.68F;
    private static final float PANEL_RIGHT = 0.96F;
    /**
     * FXTEAM CUT-CREDITS: the panel stays invisible for 3 s after the roll payload (the
     * sunrise gets the frame to itself first), then fades in over {@value #FADE_IN_TICKS}t.
     * The scroll clock starts AFTER the delay, so no lines are skipped. Shortened rolls
     * (mid-run rejoins send as little as 40t) drop the delay so the text is never lost.
     */
    private static final int FADE_IN_DELAY_TICKS = 60;
    private static final int FADE_IN_TICKS = 20;

    // --- FIN-6 "Made by Sonic0810" hold ---
    /** Lang key of the persistent maker card (langdrop finale2; literal fallback below). */
    private static final String MADE_BY_KEY = "eclipse.credits.end.madeby";
    /**
     * Merge-window fallback: the key ships via the langdrop protocol, and the maker card
     * must survive a pre-merge build — the name is identical in every locale anyway.
     */
    private static final String MADE_BY_FALLBACK = "Made by Sonic0810";
    private static final int MADE_BY_FADE_IN_TICKS = 30;
    private static final int MADE_BY_FADE_OUT_TICKS = 30;
    /** Watchdog: the hold self-clears if the server's stop payload never arrives. */
    private static final int MADE_BY_MAX_HOLD_TICKS = 1600;
    private static final float MADE_BY_SCALE = 1.4F;

    static {
        CreditsPayloads.setClientRollHandler(CreditsPanel::handle);
    }

    private record Line(String text, boolean header) {}

    /** Client thread only. */
    private static List<Line> lines = List.of();
    private static int durationTicks;
    /** Ticks since roll start; -1 = idle. */
    private static int ticks = -1;
    /** Ticks since the stop payload started the maker-card fade-out; -1 = not fading. */
    private static int fadeOutTicks = -1;

    private CreditsPanel() {}

    private static void handle(S2CCreditsRollPayload payload) {
        if (payload.durationTicks() <= 0) {
            // FIN-6: the roll's stop also hands HUD + FOV back to gameplay, and a live
            // maker card leaves gently instead of popping off a black screen.
            CreditsClient.onRollStopped();
            if (ticks > durationTicks && ticks >= 0) {
                fadeOutTicks = 0;
            } else {
                clear();
            }
            return;
        }
        lines = resolveLines();
        durationTicks = payload.durationTicks();
        ticks = 0;
        fadeOutTicks = -1;
        EclipseMod.LOGGER.info("Credits roll started: {} line(s) over {}t", lines.size(), durationTicks);
    }

    private static List<Line> resolveLines() {
        List<Line> resolved = new ArrayList<>();
        for (int i = 1; i <= MAX_LINES; i++) {
            String key = "eclipse.credits.roll." + i;
            if (!EclipseLang.hasKey(key)) {
                break;
            }
            String text = EclipseLang.trString(key);
            boolean header = text.startsWith("#");
            resolved.add(new Line(header ? text.substring(1).strip() : text, header));
        }
        return resolved;
    }

    private static void clear() {
        lines = List.of();
        ticks = -1;
        fadeOutTicks = -1;
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            if (ticks >= 0) {
                clear();
            }
            return;
        }
        if (ticks < 0 || minecraft.isPaused()) {
            return;
        }
        // FIN-6: the scroll's end no longer clears the panel — it hands over to the
        // centered maker card, which holds until the server's stop payload (watchdogged).
        if (++ticks > durationTicks + MADE_BY_MAX_HOLD_TICKS) {
            clear();
            return;
        }
        if (fadeOutTicks >= 0 && ++fadeOutTicks > MADE_BY_FADE_OUT_TICKS) {
            clear();
        }
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        clear();
    }

    @SubscribeEvent
    static void onRenderGui(RenderGuiEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (ticks < 0 || lines.isEmpty() || minecraft.level == null || minecraft.options.hideGui) {
            return;
        }
        GuiGraphics guiGraphics = event.getGuiGraphics();
        DeltaTracker deltaTracker = event.getPartialTick();
        // Depth-lift over the caption layer's fade fill (see TitleCardLayer.POST_OVERLAY_Z:
        // layers write depth at z≈5-6k, Post handlers draw at z=0 and get clipped) — the
        // roll and the maker card both ride credits fades by design.
        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(0.0F, 0.0F, TitleCardLayer.POST_OVERLAY_Z);
        try {
            renderPanel(guiGraphics, minecraft, deltaTracker);
        } finally {
            guiGraphics.pose().popPose();
        }
    }

    private static void renderPanel(GuiGraphics guiGraphics, Minecraft minecraft,
            DeltaTracker deltaTracker) {
        float partial = minecraft.isPaused() ? 0.0F : deltaTracker.getGameTimeDeltaPartialTick(false);
        float age = ticks + partial;
        if (age > durationTicks) {
            // FIN-6: the scroll is done — the centered maker card takes over and stays
            // while the rest of the credits (and the world behind them) disappears.
            renderMadeBy(guiGraphics, minecraft.font, age, partial);
            return;
        }
        // Sunrise-first delay: hold invisible, fade in, and run the scroll on the
        // remaining span. Rolls too short to afford the delay (rejoins) skip it.
        int delay = durationTicks > FADE_IN_DELAY_TICKS + 2 * FADE_IN_TICKS ? FADE_IN_DELAY_TICKS : 0;
        float alpha = Mth.clamp((age - delay) / FADE_IN_TICKS, 0.0F, 1.0F);
        if (alpha <= 0.03F) {
            return;
        }
        float progress = Mth.clamp((age - delay) / (durationTicks - delay), 0.0F, 1.0F);

        int width = guiGraphics.guiWidth();
        int height = guiGraphics.guiHeight();
        Font font = minecraft.font;
        int left = Math.round(width * PANEL_LEFT);
        int right = Math.round(width * PANEL_RIGHT);

        // Total scaled block height (headers carry extra leading space).
        int lineHeight = font.lineHeight + 3;
        float blockHeight = 0.0F;
        for (Line line : lines) {
            blockHeight += (line.header() ? HEADER_GAP + lineHeight : lineHeight) * SCALE;
        }
        // Bottom→top: the block enters at the bottom edge and fully exits over the top.
        float travel = height + blockHeight;
        float top = height - progress * travel;

        // Soft 110-alpha scrim behind the text so the sunrise never washes it out; the left
        // edge is feathered in 3 steps (GuiGraphics has no horizontal gradient helper).
        // The whole panel (scrim + text) rides the fade-in alpha.
        guiGraphics.fill(left - 12, 0, left - 8, height, Math.round(28 * alpha) << 24);
        guiGraphics.fill(left - 8, 0, left - 4, height, Math.round(56 * alpha) << 24);
        guiGraphics.fill(left - 4, 0, left, height, Math.round(84 * alpha) << 24);
        guiGraphics.fill(left, 0, right + 6, height, Math.round(110 * alpha) << 24);

        int textAlpha = Mth.clamp(Math.round(alpha * 255.0F), 0, 255);
        if (textAlpha < 8) {
            return; // drawString treats ~0 alpha as opaque
        }
        float y = top;
        for (Line line : lines) {
            if (line.header()) {
                y += HEADER_GAP * SCALE;
            }
            float lineTop = y;
            y += lineHeight * SCALE;
            if (lineTop > height || y < 0.0F || line.text().isEmpty()) {
                continue;
            }
            guiGraphics.pose().pushPose();
            guiGraphics.pose().translate(left + 6, lineTop, 0.0F);
            guiGraphics.pose().scale(SCALE, SCALE, 1.0F);
            int rgb = (line.header() ? EclipseUiTheme.DIM : EclipseUiTheme.TEXT) & 0xFFFFFF;
            guiGraphics.drawString(font, line.text(), 0, 0, (textAlpha << 24) | rgb, true);
            guiGraphics.pose().popPose();
        }
    }

    /**
     * FIN-6 maker card: dead-center "Made by Sonic0810", fading in as the last roll lines
     * exit and holding — through the eclipse burst, the whiteout and the black — until the
     * server's stop payload fades it out. A soft dark backing band keeps it readable over
     * the ever-brighter burst (white text on the white peak would vanish).
     */
    private static void renderMadeBy(GuiGraphics guiGraphics, Font font, float age, float partial) {
        float in = Mth.clamp((age - durationTicks) / MADE_BY_FADE_IN_TICKS, 0.0F, 1.0F);
        float out = fadeOutTicks < 0 ? 1.0F
                : Mth.clamp(1.0F - (fadeOutTicks + partial) / MADE_BY_FADE_OUT_TICKS, 0.0F, 1.0F);
        float alpha = Math.min(in, out);
        int textAlpha = Mth.clamp(Math.round(alpha * 255.0F), 0, 255);
        if (textAlpha < 8) {
            return;
        }
        String text = EclipseLang.hasKey(MADE_BY_KEY)
                ? EclipseLang.trString(MADE_BY_KEY) : MADE_BY_FALLBACK;
        int width = guiGraphics.guiWidth();
        int centerY = guiGraphics.guiHeight() / 2;
        int halfWidth = Math.round(font.width(text) * MADE_BY_SCALE / 2.0F) + 16;
        int halfHeight = Math.round(font.lineHeight * MADE_BY_SCALE / 2.0F) + 8;
        int band = Math.round(90.0F * alpha) << 24;
        guiGraphics.fill(width / 2 - halfWidth, centerY - halfHeight,
                width / 2 + halfWidth, centerY + halfHeight, band);
        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(width / 2.0F - font.width(text) * MADE_BY_SCALE / 2.0F,
                centerY - font.lineHeight * MADE_BY_SCALE / 2.0F, 0.0F);
        guiGraphics.pose().scale(MADE_BY_SCALE, MADE_BY_SCALE, 1.0F);
        guiGraphics.drawString(font, text, 0, 0,
                (textAlpha << 24) | (EclipseUiTheme.TEXT & 0xFFFFFF), true);
        guiGraphics.pose().popPose();
    }
}
