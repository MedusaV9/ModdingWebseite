package dev.projecteclipse.eclipse.cutscene.client;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.ChatFormatting;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.resources.sounds.SimpleSoundInstance;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Cinematic captions + fullscreen fades (P2 R12; frozen payload entry points
 * {@link #enqueue} / {@link #fade}, called by {@code network.fx.FxPayloads} and the camera
 * director's {@code caption}/{@code fade} path events). This replaces the old
 * "subtitles as announcements" route whose text was silently cancelled by the cutscene HUD
 * suppression (P2 §1.7): the caption layer ({@link #LAYER_ID}, registered above the
 * letterbox by {@code client.EclipseGuiLayers}) is on the letterbox whitelist, so captions
 * are immune to suppression by construction — and they work outside cutscenes too.
 *
 * <p><b>Styles</b> ({@link S2CCaptionPayload} constants):</p>
 * <ul>
 *   <li>{@code SUBTITLE} — lower third, resting just above the letterbox bar (or where the
 *       bar would be): 0.9-scale wrapped text over a soft 140-alpha black gradient band,
 *       4-tick fade in/out, typewriter reveal at {@value #SUBTITLE_CHARS_PER_TICK}
 *       chars/tick with a {@code ui.caption_tick} blip every 2nd character (gated by the
 *       {@code uiSounds} config).</li>
 *   <li>{@code TITLE} — screen center, 2.0 scale, letter-spaced track-in: the glyphs start
 *       8 px apart and slide together while fading in over {@value #TITLE_IN_TICKS} ticks,
 *       backed by a soft violet under-glow.</li>
 *   <li>{@code WHISPER} — small italic line at 60% alpha with a ±0.5 px value-noise jitter
 *       (the Other's voice).</li>
 * </ul>
 *
 * <p><b>Fade</b>: one fullscreen color envelope (rise {@code inTicks} → hold → release
 * {@code outTicks}, any ARGB). Drawn below the caption text so titles stay readable over
 * flashes/fades (intro v3's white→violet burst, expansion's cut-to-black). A new fade
 * replaces the current one. Captions queue (cap {@value #QUEUE_LIMIT}); a stop/disconnect
 * clears everything.</p>
 *
 * <p>Timing is client-tick based (+ partial tick), so captions and fades freeze with the
 * pause screen exactly like the rest of the HUD.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class CaptionRenderer {
    /** Frozen layer id (P2 §6.2) — P3 overlays coordinate against this, never duplicate it. */
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "cutscene_captions");

    private static final int QUEUE_LIMIT = 8;
    private static final int SUBTITLE_CHARS_PER_TICK = 2;
    private static final int SUBTITLE_FADE_TICKS = 4;
    private static final int TITLE_IN_TICKS = 20;
    private static final int TITLE_OUT_TICKS = 15;
    private static final int WHISPER_FADE_TICKS = 6;
    /** Widest subtitle line in GUI px before wrapping (readability cap at GUI scale 2). */
    private static final int SUBTITLE_MAX_WIDTH = 320;
    /** Fraction of the screen height the subtitle block sits above even without letterbox bars. */
    private static final float LOWER_THIRD_FRACTION = 0.12F;

    private record Caption(String langKey, int durationTicks, int style) {}

    /** Client thread only. */
    private static final ArrayDeque<Caption> QUEUE = new ArrayDeque<>();
    @Nullable
    private static Caption active;
    private static int activeStartTick;
    /** Last typewriter char count a tick blip played for (subtitle style). */
    private static int lastBlippedChars;

    /** Shared caption clock (client ticks; freezes while paused). */
    private static int ticks;

    // --- fade envelope ---
    private static int fadeStartTick = Integer.MIN_VALUE;
    private static int fadeIn;
    private static int fadeHold;
    private static int fadeOut;
    private static int fadeArgb = 0xFF000000;

    private CaptionRenderer() {}

    // ------------------------------------------------------------------ frozen entry points

    /**
     * Queues a caption ({@code S2CCaptionPayload} handler + camera-director path events).
     * {@code style} per {@link S2CCaptionPayload} constants; non-positive durations fall
     * back to a per-style default.
     */
    public static void enqueue(String langKey, int durationTicks, int style) {
        if (langKey == null || langKey.isEmpty()) {
            return;
        }
        int clampedStyle = Mth.clamp(style, S2CCaptionPayload.STYLE_SUBTITLE, S2CCaptionPayload.STYLE_WHISPER);
        int duration = durationTicks > 0 ? durationTicks : switch (clampedStyle) {
            case S2CCaptionPayload.STYLE_TITLE -> 90;
            case S2CCaptionPayload.STYLE_WHISPER -> 70;
            default -> 80;
        };
        if (QUEUE.size() < QUEUE_LIMIT) {
            QUEUE.add(new Caption(langKey, duration, clampedStyle));
        }
    }

    /**
     * Starts (or replaces) the fullscreen fade envelope ({@code S2CScreenFadePayload}
     * handler): alpha rises over {@code inTicks}, holds {@code holdTicks}, releases over
     * {@code outTicks}. {@code argb}'s alpha is the peak opacity.
     */
    public static void fade(int inTicks, int holdTicks, int outTicks, int argb) {
        fadeStartTick = ticks;
        fadeIn = Math.max(0, inTicks);
        fadeHold = Math.max(0, holdTicks);
        fadeOut = Math.max(0, outTicks);
        fadeArgb = argb;
    }

    /** Clears everything (disconnect / server stop sentinel paths). */
    public static void clear() {
        QUEUE.clear();
        active = null;
        fadeStartTick = Integer.MIN_VALUE;
    }

    // ------------------------------------------------------------------ tick

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            if (active != null || !QUEUE.isEmpty() || fadeStartTick != Integer.MIN_VALUE) {
                clear();
            }
            return;
        }
        if (minecraft.isPaused()) {
            return; // captions + fades freeze with the game
        }
        ticks++;
        Caption current = active;
        if (current != null && ticks - activeStartTick >= current.durationTicks()) {
            active = null;
            current = null;
        }
        if (current == null && !QUEUE.isEmpty()) {
            active = QUEUE.poll();
            activeStartTick = ticks;
            lastBlippedChars = 0;
        }
        tickTypewriterSound(minecraft);
    }

    /** A soft {@code ui.caption_tick} every 2nd revealed subtitle character ({@code uiSounds}-gated). */
    private static void tickTypewriterSound(Minecraft minecraft) {
        Caption current = active;
        if (current == null || current.style() != S2CCaptionPayload.STYLE_SUBTITLE
                || !EclipseClientConfig.uiSounds()) {
            return;
        }
        String text = Component.translatable(current.langKey()).getString();
        int revealed = Math.min(text.length(), (ticks - activeStartTick) * SUBTITLE_CHARS_PER_TICK);
        if (revealed / 2 > lastBlippedChars / 2 && revealed < text.length()) {
            minecraft.getSoundManager().play(SimpleSoundInstance.forUI(
                    EclipseSounds.UI_CAPTION_TICK.get(), 0.92F + 0.16F * (float) Math.random(), 0.35F));
        }
        lastBlippedChars = revealed;
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        clear();
    }

    // ------------------------------------------------------------------ render

    /** {@code LayeredDraw.Layer} body — registered above the letterbox by {@code EclipseGuiLayers}. */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        float partial = Minecraft.getInstance().isPaused() ? 0.0F
                : deltaTracker.getGameTimeDeltaPartialTick(false);
        renderFade(guiGraphics, partial);
        Caption current = active;
        if (current == null) {
            return;
        }
        float age = ticks + partial - activeStartTick;
        switch (current.style()) {
            case S2CCaptionPayload.STYLE_TITLE -> renderTitle(guiGraphics, current, age);
            case S2CCaptionPayload.STYLE_WHISPER -> renderWhisper(guiGraphics, current, age);
            default -> renderSubtitle(guiGraphics, current, age);
        }
    }

    // --- fade ---

    private static void renderFade(GuiGraphics guiGraphics, float partial) {
        float envelope = fadeEnvelope(partial);
        if (envelope <= 0.0F) {
            return;
        }
        int peakAlpha = (fadeArgb >>> 24) & 0xFF;
        int alpha = Mth.clamp(Math.round(peakAlpha * envelope), 0, 255);
        if (alpha <= 0) {
            return;
        }
        guiGraphics.fill(0, 0, guiGraphics.guiWidth(), guiGraphics.guiHeight(),
                (alpha << 24) | (fadeArgb & 0x00FFFFFF));
    }

    /** Smoothed in→hold→out envelope in [0,1]; self-clears when finished. */
    private static float fadeEnvelope(float partial) {
        if (fadeStartTick == Integer.MIN_VALUE) {
            return 0.0F;
        }
        float t = ticks + partial - fadeStartTick;
        if (t < fadeIn) {
            return smooth(fadeIn <= 0 ? 1.0F : t / fadeIn);
        }
        t -= fadeIn;
        if (t < fadeHold) {
            return 1.0F;
        }
        t -= fadeHold;
        if (t < fadeOut) {
            return smooth(1.0F - t / fadeOut);
        }
        fadeStartTick = Integer.MIN_VALUE;
        return 0.0F;
    }

    // --- subtitle ---

    private static void renderSubtitle(GuiGraphics guiGraphics, Caption caption, float age) {
        float alpha = inOutAlpha(age, caption.durationTicks(), SUBTITLE_FADE_TICKS, SUBTITLE_FADE_TICKS);
        if (alpha <= 0.03F) {
            return;
        }
        Font font = Minecraft.getInstance().font;
        String full = Component.translatable(caption.langKey()).getString();
        int revealed = Math.min(full.length(), (int) (age * SUBTITLE_CHARS_PER_TICK));
        List<String> lines = wrap(font, full, SUBTITLE_MAX_WIDTH);
        if (lines.isEmpty()) {
            return;
        }

        int width = guiGraphics.guiWidth();
        int height = guiGraphics.guiHeight();
        float scale = 0.9F;
        int lineHeight = font.lineHeight + 3;
        int blockHeight = Math.round(lines.size() * lineHeight * scale);
        int blockWidth = 0;
        for (String line : lines) {
            blockWidth = Math.max(blockWidth, Math.round(font.width(line) * scale));
        }
        // Rest just above the letterbox bar; without bars, hold the same lower-third line.
        int barTop = height - Math.max(LetterboxLayer.barPx(height), Math.round(height * LOWER_THIRD_FRACTION));
        int bottom = barTop - 8;
        int top = bottom - blockHeight;
        int centerX = width / 2;

        // 140-alpha black gradient band behind the text (soft top/bottom bleed).
        int bandAlpha = Math.round(140.0F * alpha);
        int bandHalf = blockWidth / 2 + 18;
        int band = bandAlpha << 24;
        guiGraphics.fillGradient(centerX - bandHalf, top - 10, centerX + bandHalf, top - 2, 0, band);
        guiGraphics.fill(centerX - bandHalf, top - 2, centerX + bandHalf, bottom + 2, band);
        guiGraphics.fillGradient(centerX - bandHalf, bottom + 2, centerX + bandHalf, bottom + 10, band, 0);

        int textAlpha = Mth.clamp(Math.round(alpha * 255.0F), 0, 255);
        if (textAlpha < 8) {
            return; // drawString treats ~0 alpha as opaque
        }
        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(centerX, top, 0.0F);
        guiGraphics.pose().scale(scale, scale, 1.0F);
        int consumed = 0;
        int y = 0;
        for (String line : lines) {
            int lineRevealed = Mth.clamp(revealed - consumed, 0, line.length());
            consumed += line.length() + 1; // +1: the space the wrap consumed at the break
            if (lineRevealed > 0) {
                String shown = line.substring(0, lineRevealed);
                // Center on the FULL line width so text doesn't slide while typing.
                guiGraphics.drawString(font, shown, -font.width(line) / 2, y,
                        (textAlpha << 24) | 0xF4EFFF, true);
            }
            y += lineHeight;
        }
        guiGraphics.pose().popPose();
    }

    // --- title ---

    private static void renderTitle(GuiGraphics guiGraphics, Caption caption, float age) {
        float in = Mth.clamp(age / TITLE_IN_TICKS, 0.0F, 1.0F);
        float inEased = 1.0F - (1.0F - in) * (1.0F - in) * (1.0F - in); // ease-out cubic
        float alpha = inOutAlpha(age, caption.durationTicks(), TITLE_IN_TICKS, TITLE_OUT_TICKS);
        int textAlpha = Mth.clamp(Math.round(alpha * 255.0F), 0, 255);
        if (textAlpha < 8) {
            return;
        }
        Font font = Minecraft.getInstance().font;
        String text = Component.translatable(caption.langKey()).getString();
        if (text.isEmpty()) {
            return;
        }
        float scale = 2.0F;
        // Track-in: glyphs start 8 px apart (unscaled) and slide together as the title fades in.
        float spacing = Mth.lerp(inEased, 8.0F, 1.0F);
        float totalWidth = -spacing;
        for (int i = 0; i < text.length(); i++) {
            totalWidth += font.width(String.valueOf(text.charAt(i))) + spacing;
        }

        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(guiGraphics.guiWidth() / 2.0F, guiGraphics.guiHeight() * 0.38F, 0.0F);
        guiGraphics.pose().scale(scale, scale, 1.0F);
        float x = -totalWidth / 2.0F;
        int glowAlpha = Mth.clamp(Math.round(alpha * 110.0F), 0, 255);
        for (int i = 0; i < text.length(); i++) {
            String glyph = String.valueOf(text.charAt(i));
            int glyphX = Math.round(x);
            if (glowAlpha >= 8) {
                // Soft violet under-glow: one offset ghost pass below the white glyph.
                guiGraphics.drawString(font, glyph, glyphX + 1, 1, (glowAlpha << 24) | 0x8A63D2, false);
            }
            guiGraphics.drawString(font, glyph, glyphX, 0, (textAlpha << 24) | 0xFFFFFF, false);
            x += font.width(glyph) + spacing;
        }
        guiGraphics.pose().popPose();
    }

    // --- whisper ---

    private static void renderWhisper(GuiGraphics guiGraphics, Caption caption, float age) {
        float alpha = 0.6F * inOutAlpha(age, caption.durationTicks(), WHISPER_FADE_TICKS, WHISPER_FADE_TICKS);
        int textAlpha = Mth.clamp(Math.round(alpha * 255.0F), 0, 255);
        if (textAlpha < 8) {
            return;
        }
        Font font = Minecraft.getInstance().font;
        Component text = Component.translatable(caption.langKey()).withStyle(ChatFormatting.ITALIC);
        // ±0.5 px value-noise jitter — unsettling, but readable.
        float jitterX = (noise(age * 1.7F, 11) - 0.5F);
        float jitterY = (noise(age * 1.7F, 37) - 0.5F);

        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(guiGraphics.guiWidth() / 2.0F + jitterX,
                guiGraphics.guiHeight() * 0.60F + jitterY, 0.0F);
        guiGraphics.pose().scale(0.85F, 0.85F, 1.0F);
        guiGraphics.drawString(font, text, -font.width(text) / 2, 0,
                (textAlpha << 24) | 0xCFC4E8, false);
        guiGraphics.pose().popPose();
    }

    // ------------------------------------------------------------------ helpers

    /** Fade-in/out alpha over a caption's lifetime. */
    private static float inOutAlpha(float age, int duration, int inTicks, int outTicks) {
        float in = inTicks <= 0 ? 1.0F : Mth.clamp(age / inTicks, 0.0F, 1.0F);
        float out = outTicks <= 0 ? 1.0F
                : Mth.clamp((duration - age) / outTicks, 0.0F, 1.0F);
        return Math.min(in, out);
    }

    /** Greedy word wrap on the plain string (typewriter needs raw char indices). */
    private static List<String> wrap(Font font, String text, int maxWidth) {
        List<String> lines = new ArrayList<>(3);
        StringBuilder line = new StringBuilder();
        for (String word : text.split(" ")) {
            String candidate = line.isEmpty() ? word : line + " " + word;
            if (!line.isEmpty() && font.width(candidate) > maxWidth) {
                lines.add(line.toString());
                line = new StringBuilder(word);
            } else {
                line = new StringBuilder(candidate);
            }
        }
        if (!line.isEmpty()) {
            lines.add(line.toString());
        }
        return lines;
    }

    /** Smooth 1-D value noise in [0, 1]. */
    private static float noise(float x, int seed) {
        int cell = Mth.floor(x);
        float f = x - cell;
        float s = f * f * (3.0F - 2.0F * f);
        return Mth.lerp(s, hash(cell, seed), hash(cell + 1, seed));
    }

    private static float hash(int i, int seed) {
        int h = i * 374761393 + seed * 668265263;
        h = (h ^ (h >>> 13)) * 1274126177;
        return ((h ^ (h >>> 16)) & 0x7FFFFFFF) / (float) 0x7FFFFFFF;
    }

    private static float smooth(float x) {
        x = Mth.clamp(x, 0.0F, 1.0F);
        return x * x * (3.0F - 2.0F * x);
    }
}
