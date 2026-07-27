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
    /** FIN-6 gentle end cards: slow silent fade-in/out instead of the glitch decode. */
    private static final int GENTLE_IN_TICKS = 50;
    private static final int GENTLE_OUT_TICKS = 50;
    // --- F-072 V3 finale style (the "Minecraft Eclipse" closer over the black hole) ---
    /** Materialize window: the last letter finishes its ramp inside this. */
    private static final int FINALE_IN_TICKS = 120;
    private static final int FINALE_OUT_TICKS = 80;
    /** Per-letter stagger / per-letter alpha+rise ramp (ticks). */
    private static final int FINALE_LETTER_STAGGER = 4;
    private static final int FINALE_LETTER_RAMP = 34;
    /** Kerning breath: extra tracking px (GUI units at scale 1) easing in, then a slow residual sine. */
    private static final float FINALE_TRACK_START = 2.8F;
    private static final float FINALE_TRACK_BREATH = 0.3F;
    /** Chromatic fringe: starting split px, settling to 0 over this window. */
    private static final float FINALE_FRINGE_PX = 1.6F;
    private static final int FINALE_FRINGE_SETTLE = 130;
    /** Dust motes converging into each letter as it materializes. */
    private static final int FINALE_MOTES_PER_LETTER = 3;

    static {
        CreditsPayloads.setClientTitleHandler(TitleCardLayer::handle);
    }

    /** Client thread only. */
    private static final ArrayDeque<S2CCreditsTitlePayload> QUEUE = new ArrayDeque<>();

    private static String title = "";
    private static int holdTicks;
    private static int glitchSalt;
    /** Card style ({@link S2CCreditsTitlePayload#STYLE_DECODE} / GENTLE / FINALE). */
    private static int style;
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
        if (style == S2CCreditsTitlePayload.STYLE_GENTLE) {
            if (ticks > GENTLE_IN_TICKS + holdTicks + GENTLE_OUT_TICKS) {
                ticks = -1;
            }
            return;
        }
        if (style == S2CCreditsTitlePayload.STYLE_FINALE) {
            if (ticks > FINALE_IN_TICKS + holdTicks + FINALE_OUT_TICKS) {
                ticks = -1;
            }
            return;
        }
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
        style = payload.style();
        ticks = 0;
        lockSoundPlayed = false;
        if (style == S2CCreditsTitlePayload.STYLE_DECODE) {
            UiSounds.error(); // arrival glitch burst — the soft end cards stay silent
        }
        EclipseMod.LOGGER.info("Credits title card: '{}' (hold {}t, style {})", title, holdTicks, style);
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

    /**
     * Z-lift for every draw of this card ({@code RenderGuiEvent.Post} renders at pose
     * z=0, but GUI LAYERS stack upward — {@code GuiLayerManager} translates
     * {@code +200} per layer and the caption layer's fullscreen fade fill WRITES
     * DEPTH at its layer z, so an unlifted card is depth-clipped BEHIND the credits
     * black and invisible). The lift MUST NOT be a constant: the caption layer's z is
     * {@code 200 * registrationIndex} and grows with every layer any mod registers —
     * a stale constant (the old 9000) ended up BELOW the fade fill (measured z=12400
     * with 66 layers) and depth-killed every end card. NeoForge sizes the GUI
     * projection as {@code farPlane = 11000 + max(10000*(1+screens), 200*layerCount)}
     * with the near clip at pose z {@code farPlane - 11000}, so {@code farPlane -
     * 11100} is always above every registered layer (max draw z
     * {@code 200*(layerCount-1)}) and 100 units inside the clip. Shared with
     * {@link CreditsPanel}.
     */
    static float postOverlayZ() {
        return net.neoforged.neoforge.client.ClientHooks.getGuiFarPlane() - 11_100.0F;
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
        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(0.0F, 0.0F, postOverlayZ());
        try {
            renderCard(guiGraphics, minecraft, t);
        } finally {
            guiGraphics.pose().popPose();
        }
    }

    private static void renderCard(GuiGraphics guiGraphics, Minecraft minecraft, float t) {
        if (style == S2CCreditsTitlePayload.STYLE_GENTLE) {
            renderGentle(guiGraphics, t);
            return;
        }
        if (style == S2CCreditsTitlePayload.STYLE_FINALE) {
            renderFinale(guiGraphics, t);
            return;
        }
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
     * FIN-6 gentle end card: a slow, silent fade-in / hold / fade-out of the auto-fitted
     * title between two static gold hairlines — the post-eclipse black-screen language
     * ("Minecraft Eclipse kommt zurück in…"), no glitch, no flashes, no scrim band (the
     * screen behind it is already pure black).
     */
    private static void renderGentle(GuiGraphics guiGraphics, float t) {
        float in = Mth.clamp(t / GENTLE_IN_TICKS, 0.0F, 1.0F);
        float out = Mth.clamp((GENTLE_IN_TICKS + holdTicks + GENTLE_OUT_TICKS - t)
                / GENTLE_OUT_TICKS, 0.0F, 1.0F);
        float alpha = Math.min(in * in * (3.0F - 2.0F * in), out * out * (3.0F - 2.0F * out));
        int textAlpha = Mth.clamp(Math.round(alpha * 255.0F), 0, 255);
        if (textAlpha < 8) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();
        Font font = minecraft.font;
        int width = guiGraphics.guiWidth();
        int centerX = width / 2;
        int cardCenterY = Math.round(guiGraphics.guiHeight() * 0.44F);
        float scale = 2.0F;
        int titleWidth = font.width(title);
        while (scale > 0.8F && titleWidth * scale > width * 0.92F) {
            scale -= 0.1F;
        }
        int scaledHalfHeight = Math.round(font.lineHeight * scale / 2.0F);
        int hairline = EclipseUiTheme.withAlpha(GOLD, alpha * 0.55F);
        int bandTop = cardCenterY - scaledHalfHeight - BAND_PAD_TOP;
        int bandBottom = cardCenterY + scaledHalfHeight + BAND_PAD_BOTTOM;
        guiGraphics.fill(0, bandTop, width, bandTop + 1, hairline);
        guiGraphics.fill(0, bandBottom - 1, width, bandBottom, hairline);
        var pose = guiGraphics.pose();
        pose.pushPose();
        pose.translate(centerX - titleWidth * scale / 2.0F, cardCenterY - scaledHalfHeight, 0.0F);
        pose.scale(scale, scale, 1.0F);
        guiGraphics.drawString(font, title, 0, 0,
                (textAlpha << 24) | (EclipseUiTheme.TEXT & 0xFFFFFF), false);
        pose.popPose();
    }

    /**
     * F-072 V3 finale card ("Minecraft Eclipse" over the eaten world): every letter
     * MATERIALIZES on its own staggered ramp — rising ~4 px into place while
     * {@value #FINALE_MOTES_PER_LETTER} dust motes converge onto it and burn out — the
     * hole "releasing" the title letter by letter. The tracking starts
     * {@value #FINALE_TRACK_START} px wide and breathes IN as the line settles (then
     * keeps a barely-visible ±{@value #FINALE_TRACK_BREATH} px residual breath), and a
     * chromatic fringe (red/blue ghost passes) starts at {@value #FINALE_FRINGE_PX} px
     * and CALMS to zero over {@value #FINALE_FRINGE_SETTLE}t — the card arrives
     * agitated and comes to rest. The fade-out at the end sinks it back into the held
     * black. Silent by design (the victory theme carries the moment); {@code reducedFx}
     * drops the motes and the fringe but keeps the stagger and the kerning ease.
     */
    private static void renderFinale(GuiGraphics guiGraphics, float t) {
        float out = Mth.clamp((FINALE_IN_TICKS + holdTicks + FINALE_OUT_TICKS - t)
                / FINALE_OUT_TICKS, 0.0F, 1.0F);
        float outEase = out * out * (3.0F - 2.0F * out);
        if (outEase < 0.02F) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();
        Font font = minecraft.font;
        boolean reduced = EclipseClientConfig.reducedFx();
        int width = guiGraphics.guiWidth();
        int centerX = width / 2;
        int cardCenterY = Math.round(guiGraphics.guiHeight() * 0.44F);
        int length = title.length();

        // Whole-line settle 0..1 (drives tracking + fringe; letters have own ramps).
        float settle = Mth.clamp(t / FINALE_IN_TICKS, 0.0F, 1.0F);
        settle = settle * settle * (3.0F - 2.0F * settle);
        // Kerning: wide at birth, breathing in; a slow residual sine keeps it alive.
        float track = FINALE_TRACK_START * (1.0F - settle)
                + (settle >= 1.0F ? FINALE_TRACK_BREATH * Mth.sin((t - FINALE_IN_TICKS) * 0.03F)
                        : 0.0F);
        // Auto-fit against the WIDEST layout (birth tracking) so nothing ever clips.
        int titleWidth = font.width(title);
        float maxLineWidth = titleWidth + (length - 1) * FINALE_TRACK_START;
        float scale = 2.0F;
        while (scale > 0.8F && maxLineWidth * scale > width * 0.92F) {
            scale -= 0.1F;
        }
        float lineWidth = titleWidth + (length - 1) * track;
        int scaledHalfHeight = Math.round(font.lineHeight * scale / 2.0F);

        // Chromatic fringe amplitude (px, GUI space at scale 1), calming to rest.
        float fringe = reduced ? 0.0F
                : FINALE_FRINGE_PX * Mth.clamp(1.0F - t / FINALE_FRINGE_SETTLE, 0.0F, 1.0F);

        var pose = guiGraphics.pose();
        pose.pushPose();
        pose.translate(centerX - lineWidth * scale / 2.0F, cardCenterY - scaledHalfHeight, 0.0F);
        pose.scale(scale, scale, 1.0F);
        float x = 0.0F;
        for (int i = 0; i < length; i++) {
            String glyph = String.valueOf(title.charAt(i));
            int glyphWidth = font.width(glyph);
            float birth = Mth.clamp((t - i * FINALE_LETTER_STAGGER) / FINALE_LETTER_RAMP,
                    0.0F, 1.0F);
            float birthEase = birth * birth * (3.0F - 2.0F * birth);
            float alpha = birthEase * outEase;
            if (alpha > 0.015F) {
                float rise = (1.0F - birthEase) * (1.0F - birthEase) * 4.0F;
                int alphaByte = Mth.clamp(Math.round(alpha * 255.0F), 0, 255);
                // Settling chroma: red/blue ghost passes, strongest while the letter is
                // young, gone once the fringe clock rests.
                float letterFringe = fringe * (0.35F + 0.65F * (1.0F - birthEase));
                if (letterFringe > 0.05F) {
                    int ghostAlpha = Mth.clamp(Math.round(alpha * 90.0F), 0, 255);
                    drawGlyph(guiGraphics, font, glyph, x - letterFringe, rise,
                            (ghostAlpha << 24) | 0xFF5A66);
                    drawGlyph(guiGraphics, font, glyph, x + letterFringe, rise,
                            (ghostAlpha << 24) | 0x6699FF);
                }
                drawGlyph(guiGraphics, font, glyph, x, rise,
                        (alphaByte << 24) | (EclipseUiTheme.TEXT & 0xFFFFFF));
                // Converging dust: motes spiral in from a hashed ring and burn out as
                // the letter locks (alpha peaks mid-materialize, zero at both ends).
                if (!reduced && birthEase < 1.0F) {
                    float dustAlpha = birthEase * (1.0F - birthEase) * 4.0F * outEase;
                    int dustByte = Mth.clamp(Math.round(dustAlpha * 150.0F), 0, 255);
                    if (dustByte > 6) {
                        for (int m = 0; m < FINALE_MOTES_PER_LETTER; m++) {
                            float angle = (i * 2.4F + m * 2.1F) + (1.0F - birthEase) * 1.7F;
                            float reach = (7.0F + 5.0F * hash(i * 7 + m, 3))
                                    * (1.0F - birthEase);
                            float mx = x + glyphWidth / 2.0F + Mth.cos(angle) * reach;
                            float my = font.lineHeight / 2.0F + rise
                                    + Mth.sin(angle) * reach * 0.7F;
                            guiGraphics.fill(Math.round(mx), Math.round(my),
                                    Math.round(mx) + 1, Math.round(my) + 1,
                                    (dustByte << 24) | (GOLD & 0xFFFFFF));
                        }
                    }
                }
            }
            x += glyphWidth + track;
        }
        pose.popPose();

        // The gold hairlines only arrive once the line has settled — a quiet frame.
        if (settle >= 1.0F) {
            float lineIn = Mth.clamp((t - FINALE_IN_TICKS) / 40.0F, 0.0F, 1.0F);
            int hairline = EclipseUiTheme.withAlpha(GOLD, outEase * 0.45F * lineIn);
            int bandTop = cardCenterY - scaledHalfHeight - BAND_PAD_TOP;
            int bandBottom = cardCenterY + scaledHalfHeight + BAND_PAD_BOTTOM;
            guiGraphics.fill(0, bandTop, width, bandTop + 1, hairline);
            guiGraphics.fill(0, bandBottom - 1, width, bandBottom, hairline);
        }
    }

    /** One glyph at a float offset inside the already-scaled finale pose. */
    private static void drawGlyph(GuiGraphics guiGraphics, Font font, String glyph,
            float x, float y, int argb) {
        var pose = guiGraphics.pose();
        pose.pushPose();
        pose.translate(x, y, 0.0F);
        guiGraphics.drawString(font, glyph, 0, 0, argb, false);
        pose.popPose();
    }

    /** Tiny deterministic hash in [0, 1) (the CreditsSequence mixer, local copy). */
    private static float hash(int index, int salt) {
        int h = index * 374761393 + salt * 668265263;
        h = (h ^ (h >>> 13)) * 1274126177;
        return ((h ^ (h >>> 16)) & 0x7FFFFFFF) / (float) 0x80000000L;
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
