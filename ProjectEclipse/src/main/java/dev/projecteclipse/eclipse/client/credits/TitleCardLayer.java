package dev.projecteclipse.eclipse.client.credits;

import java.util.ArrayDeque;
import java.util.concurrent.ThreadLocalRandom;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.GlitchText;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.credits.CreditsPayloads;
import dev.projecteclipse.eclipse.network.credits.CreditsPayloads.S2CCreditsTitlePayload;
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
 * Full-screen credits title card (C15 / IDEAS-backrooms_finale §B1 t=470): the
 * {@code BossIntroOverlay} decode recipe — the title arrives as {@link GlitchText#scramble}
 * noise and locks in one real character every {@value #TICKS_PER_CHAR}t — restyled from the
 * DANGER boss language into a gold/credits variant (warm {@value #GOLD} hairlines and lock
 * flash on a deeper scrim band). Deliberately its OWN layer, not a caption: the doomsday
 * card needs the auto-fitting 2x+ typography and the decode; {@code CaptionRenderer}'s
 * TITLE style stays untouched for the deadpan correction card.
 *
 * <p>FXTEAM CUT-CREDITS decode polish: each character lands GOLD the tick it locks and
 * cools to TEXT over {@value #CHAR_FLASH_TICKS}t (a per-letter resolve wave), and the
 * full-lock timerZero boom carries one {@value #BASS_FLASH_TICKS}-tick low-alpha white
 * flash frame across the screen.</p>
 *
 * <p>Long titles auto-shrink so the card can never clip: the scale drops from 2.0 until the
 * whole line fits inside 92% of the screen width. Renders from {@link RenderGuiEvent.Post}
 * (survives the letterbox GUI suppression; only F1 hides it). {@code reducedFx} keeps
 * {@link GlitchText}'s calm static, stops the hairline breathing exactly like the boss
 * card, and drops the bass flash frame (the per-letter resolve is color-only and stays).
 * No {@code CenterStageArbiter} claim: during the finale every other center-stage
 * system (day cards, level-ups, roulette) is long past.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class TitleCardLayer {
    private static final int TICKS_PER_CHAR = 2;
    /** Pure-noise flare before the first character locks. */
    private static final int PRE_TICKS = 10;
    private static final int FADE_TICKS = 20;
    private static final int QUEUE_LIMIT = 3;
    /** GOLD→TEXT flash length right after the title locks completely. */
    private static final int LOCK_FLASH_TICKS = 12;
    /** FXTEAM CUT-CREDITS per-letter resolve: each char lands GOLD and cools over this. */
    private static final int CHAR_FLASH_TICKS = 5;
    /** Bass-sync flash frame riding the full-lock timerZero boom (skipped by reducedFx). */
    private static final int BASS_FLASH_TICKS = 2;
    private static final float BASS_FLASH_ALPHA = 0.22F;
    private static final int BAND_PAD_TOP = 14;
    private static final int BAND_PAD_BOTTOM = 12;
    /** Warm credits gold (the DANGER slot of the boss card's palette). */
    private static final int GOLD = 0xFFE9C46A;

    static {
        CreditsPayloads.setClientTitleHandler(TitleCardLayer::handle);
    }

    /** Client thread only. */
    private static final ArrayDeque<S2CCreditsTitlePayload> QUEUE = new ArrayDeque<>();

    private static String title = "";
    private static int holdTicks;
    private static int glitchSalt;
    /** Ticks since the active card started; {@code -1} = no card running. */
    private static int ticks = -1;
    private static boolean lockSoundPlayed;

    private TitleCardLayer() {}

    private static void handle(S2CCreditsTitlePayload payload) {
        if (QUEUE.size() < QUEUE_LIMIT) {
            QUEUE.add(payload);
        }
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            QUEUE.clear();
            ticks = -1;
            return;
        }
        if (minecraft.isPaused()) {
            return;
        }
        if (ticks < 0 && !QUEUE.isEmpty()) {
            start(QUEUE.poll());
        }
        if (ticks < 0) {
            return;
        }
        ticks++;
        int decodeEnd = decodeEndTick();
        if (ticks <= decodeEnd) {
            int locked = lockedChars(ticks);
            if (locked > 0 && locked % 2 == 0 && locked != lockedChars(ticks - 1)) {
                UiSounds.typewriter(0.7F + 0.6F * locked / Math.max(1, title.length()));
            }
            if (!lockSoundPlayed && locked >= title.length()) {
                lockSoundPlayed = true;
                UiSounds.timerZero(); // the glitch-boom as the title snaps true
            }
        }
        if (ticks > decodeEnd + holdTicks + FADE_TICKS) {
            ticks = -1;
        }
    }

    private static void start(S2CCreditsTitlePayload payload) {
        title = EclipseLang.tr(payload.titleKey()).getString();
        holdTicks = Math.max(20, payload.holdTicks());
        glitchSalt = ThreadLocalRandom.current().nextInt();
        ticks = 0;
        lockSoundPlayed = false;
        UiSounds.error(); // arrival glitch burst
        EclipseMod.LOGGER.info("Credits title card: '{}' (hold {}t)", title, holdTicks);
    }

    private static int decodeEndTick() {
        return PRE_TICKS + title.length() * TICKS_PER_CHAR;
    }

    private static int lockedChars(int atTick) {
        return Mth.clamp((atTick - PRE_TICKS) / TICKS_PER_CHAR, 0, title.length());
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        QUEUE.clear();
        ticks = -1;
    }

    @SubscribeEvent
    static void onRenderGui(RenderGuiEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (ticks < 0 || minecraft.level == null || minecraft.options.hideGui || title.isEmpty()) {
            return;
        }
        GuiGraphics guiGraphics = event.getGuiGraphics();
        DeltaTracker deltaTracker = event.getPartialTick();
        float t = ticks + deltaTracker.getGameTimeDeltaPartialTick(true);
        int decodeEnd = decodeEndTick();
        float alpha = t <= decodeEnd + holdTicks ? 1.0F
                : Mth.clamp(1.0F - (t - decodeEnd - holdTicks) / FADE_TICKS, 0.0F, 1.0F);
        if (alpha < 0.03F) {
            return;
        }
        Font font = minecraft.font;
        int width = guiGraphics.guiWidth();
        int centerX = width / 2;
        int cardCenterY = Math.round(guiGraphics.guiHeight() * 0.38F);
        boolean reduced = EclipseClientConfig.reducedFx();

        // Auto-fit: shrink from 2.0 until the full title fits inside 92% of the width.
        float scale = 2.0F;
        int titleWidth = font.width(title);
        while (scale > 0.8F && titleWidth * scale > width * 0.92F) {
            scale -= 0.1F;
        }
        int scaledHalfHeight = Math.round(font.lineHeight * scale / 2.0F);

        // --- cinematic band: full-width scrim + breathing GOLD hairlines ---
        int bandTop = cardCenterY - scaledHalfHeight - BAND_PAD_TOP;
        int bandBottom = cardCenterY + scaledHalfHeight + BAND_PAD_BOTTOM;
        guiGraphics.fill(0, bandTop, width, bandBottom,
                EclipseUiTheme.withAlpha(EclipseUiTheme.VEIL, alpha));
        float breathe = reduced ? 0.6F
                : 0.45F + 0.35F * Mth.sin((float) (System.currentTimeMillis() % 100_000L) * 0.0021F);
        int hairline = EclipseUiTheme.withAlpha(GOLD, alpha * breathe);
        guiGraphics.fill(0, bandTop, width, bandTop + 1, hairline);
        guiGraphics.fill(0, bandBottom - 1, width, bandBottom, hairline);

        // --- title, GlitchText decode-in with the per-letter gold resolve ---
        int locked = lockedChars(ticks);
        String noiseTail = buildNoiseTail(locked);
        float lockFlash = locked < title.length() ? 0.0F
                : Mth.clamp(1.0F - (t - decodeEnd) / LOCK_FLASH_TICKS, 0.0F, 1.0F);
        int alphaByte = Mth.clamp((int) (alpha * 255.0F), 8, 255);

        var pose = guiGraphics.pose();
        pose.pushPose();
        pose.translate(centerX - titleWidth * scale / 2.0F, cardCenterY - scaledHalfHeight, 0.0F);
        pose.scale(scale, scale, 1.0F);
        // Per-letter glitch resolve (FXTEAM CUT-CREDITS): every char lands GOLD the tick
        // it locks and cools to TEXT over CHAR_FLASH_TICKS, so the decode reads as a wave
        // of individual resolutions instead of one block recolor. The whole-string lock
        // flash still rides on top (max() below) for the final snap.
        int x = 0;
        for (int i = 0; i < locked; i++) {
            String glyph = String.valueOf(title.charAt(i));
            float charFlash = Mth.clamp(
                    1.0F - (t - (PRE_TICKS + (i + 1) * TICKS_PER_CHAR)) / CHAR_FLASH_TICKS, 0.0F, 1.0F);
            int rgb = lerpRgb(EclipseUiTheme.TEXT & 0xFFFFFF, GOLD & 0xFFFFFF,
                    Math.max(charFlash, lockFlash));
            guiGraphics.drawString(font, glyph, x, 0, (alphaByte << 24) | rgb);
            x += font.width(glyph);
        }
        if (!noiseTail.isEmpty()) {
            guiGraphics.drawString(font, noiseTail, x, 0,
                    (Mth.clamp((int) (alpha * 210.0F), 8, 255) << 24) | (GOLD & 0xFFFFFF));
        }
        pose.popPose();

        // One bass-sync flash frame as the title snaps true (the timerZero boom): a
        // 2-tick low-alpha white pop over the whole frame. reducedFx drops it entirely
        // (single-frame flashes are exactly what that toggle is for).
        if (!reduced && t >= decodeEnd && locked >= title.length()) {
            float flashFrame = 1.0F - (t - decodeEnd) / BASS_FLASH_TICKS;
            if (flashFrame > 0.0F) {
                guiGraphics.fill(0, 0, width, guiGraphics.guiHeight(),
                        EclipseUiTheme.withAlpha(0xFFFFFFFF, BASS_FLASH_ALPHA * flashFrame * alpha));
            }
        }
    }

    /**
     * Noise for the not-yet-locked tail ({@code BossIntroOverlay} recipe): scramble re-rolls
     * every few ticks ({@code reducedFx} → {@link GlitchText}'s calm static), real spaces
     * stay spaces so the title's word shape reads through the corruption.
     */
    private static String buildNoiseTail(int locked) {
        int tail = title.length() - locked;
        if (tail <= 0) {
            return "";
        }
        String noise = GlitchText.scramble(tail, glitchSalt);
        StringBuilder builder = new StringBuilder(tail);
        for (int i = 0; i < tail; i++) {
            builder.append(title.charAt(locked + i) == ' ' ? ' ' : noise.charAt(i));
        }
        return builder.toString();
    }

    /** Component-wise RGB lerp (no alpha). */
    private static int lerpRgb(int from, int to, float t) {
        t = Mth.clamp(t, 0.0F, 1.0F);
        int red = (int) Mth.lerp(t, (from >> 16) & 0xFF, (to >> 16) & 0xFF);
        int green = (int) Mth.lerp(t, (from >> 8) & 0xFF, (to >> 8) & 0xFF);
        int blue = (int) Mth.lerp(t, from & 0xFF, to & 0xFF);
        return (red << 16) | (green << 8) | blue;
    }
}
