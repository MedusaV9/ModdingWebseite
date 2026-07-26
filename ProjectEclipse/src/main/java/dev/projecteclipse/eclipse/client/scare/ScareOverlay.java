package dev.projecteclipse.eclipse.client.scare;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;

/**
 * HUD layer of the Scare framework (F-064): draws the visual beats of the running
 * {@link ScareDirector} script — overlay textures ({@code textures/scare/*.png}), glitching
 * text lines, single decaying flashes and blackout covers. Registered by
 * {@code EclipseGuiLayers} above the letterbox and under {@code CaptionRenderer} (the
 * {@code JumpscareOverlay} slot — captions stay readable over a face).
 *
 * <p>Pure function of {@code (script, time, seed)}: no state lives here, every jitter and
 * character scramble derives from {@link ScareDirector#noise} — one cue seed, one look.
 * Draw order is overlays → text → flash → blackout, so a blackout is always a full cover
 * (the backrooms clip hides its teleport under it).</p>
 *
 * <p><b>reducedFx</b>: overlays and flashes collapse into one soft dark vignette pulse
 * (≤ {@value #VIGNETTE_PEAK_ALPHA} alpha, the §A4 photosensitivity cap) driven by the same
 * envelopes; text renders without scramble jitter; blackouts stay (covers, not FX).</p>
 */
public final class ScareOverlay {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "scare_overlay");

    /** All scare textures are authored square at this size ({@code tools/scare/gen_overlays.py}). */
    private static final int TEXTURE_SIZE = 512;
    /** reducedFx vignette pulse peak (the §A4 25% cap). */
    private static final float VIGNETTE_PEAK_ALPHA = 0.25F;
    /** Glyph pool for glitch-text character scrambles (block/box noise, no letters). */
    private static final char[] GLITCH_GLYPHS =
            "█▓▒░#@%&$?!<>/\\|+*~^".toCharArray();

    private ScareOverlay() {}

    /** GUI-layer body (registered by {@code EclipseGuiLayers}). */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        ScareScript script = ScareDirector.active();
        if (script == null) {
            return;
        }
        float t = ScareDirector.time();
        if (t < 0.0F || t >= script.durationTicks()) {
            return;
        }
        int width = guiGraphics.guiWidth();
        int height = guiGraphics.guiHeight();
        boolean reduced = ScareDirector.reducedFx();

        if (reduced) {
            renderVignette(guiGraphics, width, height,
                    VIGNETTE_PEAK_ALPHA * reducedIntensity(script, t));
        } else {
            renderOverlays(guiGraphics, script, t, width, height);
        }
        renderTexts(guiGraphics, script, t, width, height, reduced);
        if (!reduced) {
            renderFlashes(guiGraphics, script, t, width, height);
        }
        renderBlackouts(guiGraphics, script, t, width, height);
    }

    // ------------------------------------------------------------------ overlays

    private static void renderOverlays(GuiGraphics guiGraphics, ScareScript script, float t,
            int width, int height) {
        int beatIndex = 0;
        for (ScareScript.Beat beat : script.beats()) {
            beatIndex++;
            if (!(beat instanceof ScareScript.Overlay overlay)) {
                continue;
            }
            float env = ScareScript.envelope(t, overlay.start(), overlay.end(),
                    overlay.fadeIn(), overlay.fadeOut());
            float alpha = overlay.maxAlpha() * env;
            if (alpha <= 0.01F) {
                continue;
            }
            // Seeded shudder, re-rolled every other tick (a slide, never a luminance strobe).
            long bucket = (long) (t * 2.0F);
            float jx = (ScareDirector.noise(beatIndex * 7919L, bucket) - 0.5F) * 2.0F * overlay.jitter();
            float jy = (ScareDirector.noise(beatIndex * 7919L + 1L, bucket) - 0.5F) * 2.0F * overlay.jitter();
            // Drift is authored in screen fractions per second → 1/20 per tick.
            float driftTicks = t - overlay.start();
            float cx = (overlay.cx() + overlay.driftX() * driftTicks / 20.0F) * width + jx;
            float cy = (overlay.cy() + overlay.driftY() * driftTicks / 20.0F) * height + jy;

            int rgb = overlay.rgb();
            guiGraphics.setColor(((rgb >> 16) & 0xFF) / 255.0F, ((rgb >> 8) & 0xFF) / 255.0F,
                    (rgb & 0xFF) / 255.0F, alpha);
            if (overlay.size() <= 0.0F) {
                // Fullscreen stretch (veils/washes); jitter shifts the whole sheet.
                guiGraphics.blit(texture(overlay.texture()), Math.round(jx), Math.round(jy),
                        width, height, 0.0F, 0.0F,
                        TEXTURE_SIZE, TEXTURE_SIZE, TEXTURE_SIZE, TEXTURE_SIZE);
            } else {
                int side = Math.round(height * overlay.size());
                guiGraphics.blit(texture(overlay.texture()), Math.round(cx - side / 2.0F),
                        Math.round(cy - side / 2.0F), side, side, 0.0F, 0.0F,
                        TEXTURE_SIZE, TEXTURE_SIZE, TEXTURE_SIZE, TEXTURE_SIZE);
            }
            guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        }
    }

    private static ResourceLocation texture(String name) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID,
                "textures/scare/" + name + ".png");
    }

    // ------------------------------------------------------------------ glitch text

    private static void renderTexts(GuiGraphics guiGraphics, ScareScript script, float t,
            int width, int height, boolean reduced) {
        Font font = Minecraft.getInstance().font;
        int beatIndex = 0;
        for (ScareScript.Beat beat : script.beats()) {
            beatIndex++;
            if (!(beat instanceof ScareScript.GlitchText text)) {
                continue;
            }
            float env = ScareScript.envelope(t, text.start(), text.end(),
                    text.fadeIn(), text.fadeOut());
            if (env <= 0.03F) {
                continue;
            }
            String line = EclipseLang.trString(text.key());
            long bucket = (long) (t * 2.0F);
            if (!reduced && text.glitch() > 0.0F) {
                line = scramble(line, beatIndex, bucket, text.glitch() * env);
            }
            float jitter = reduced ? 0.0F : 2.0F * text.glitch();
            float jx = (ScareDirector.noise(beatIndex * 104729L, bucket) - 0.5F) * 2.0F * jitter;
            float jy = (ScareDirector.noise(beatIndex * 104729L + 1L, bucket) - 0.5F) * 2.0F * jitter;

            int alpha = Mth.clamp(Math.round(env * 255.0F), 4, 255);
            int argb = (alpha << 24) | (text.rgb() & 0xFFFFFF);
            var pose = guiGraphics.pose();
            pose.pushPose();
            pose.translate(width / 2.0F + jx, height * text.cy() + jy, 0.0F);
            pose.scale(text.scale(), text.scale(), 1.0F);
            guiGraphics.drawString(font, line, -font.width(line) / 2,
                    -font.lineHeight / 2, argb, true);
            pose.popPose();
        }
    }

    /** Seeded per-character scramble: probability {@code chance} per char, per time bucket. */
    private static String scramble(String line, int beatIndex, long bucket, float chance) {
        char[] chars = line.toCharArray();
        for (int i = 0; i < chars.length; i++) {
            if (chars[i] == ' ') {
                continue;
            }
            float roll = ScareDirector.noise(beatIndex * 31L + i, bucket);
            if (roll < chance) {
                chars[i] = GLITCH_GLYPHS[(int) (ScareDirector.noise(beatIndex * 37L + i,
                        bucket + 977L) * GLITCH_GLYPHS.length)];
            }
        }
        return new String(chars);
    }

    // ------------------------------------------------------------------ flashes / blackouts

    private static void renderFlashes(GuiGraphics guiGraphics, ScareScript script, float t,
            int width, int height) {
        for (ScareScript.Beat beat : script.beats()) {
            if (!(beat instanceof ScareScript.Flash flash)) {
                continue;
            }
            float age = t - flash.at();
            if (age < 0.0F || age >= flash.duration()) {
                continue;
            }
            float alpha = flash.maxAlpha() * (1.0F - age / flash.duration());
            if (alpha > 0.01F) {
                guiGraphics.fill(0, 0, width, height, argb(alpha, flash.rgb()));
            }
        }
    }

    private static void renderBlackouts(GuiGraphics guiGraphics, ScareScript script, float t,
            int width, int height) {
        float alpha = 0.0F;
        for (ScareScript.Beat beat : script.beats()) {
            if (beat instanceof ScareScript.Blackout blackout) {
                alpha = Math.max(alpha, blackout.maxAlpha() * ScareScript.envelope(t,
                        blackout.start(), blackout.end(), blackout.fadeIn(), blackout.fadeOut()));
            }
        }
        if (alpha > 0.01F) {
            guiGraphics.fill(0, 0, width, height, argb(alpha, 0x000000));
        }
    }

    // ------------------------------------------------------------------ reducedFx vignette

    /** Combined overlay+flash intensity 0..1 driving the reducedFx vignette pulse. */
    private static float reducedIntensity(ScareScript script, float t) {
        float intensity = 0.0F;
        for (ScareScript.Beat beat : script.beats()) {
            if (beat instanceof ScareScript.Overlay overlay) {
                intensity = Math.max(intensity, overlay.maxAlpha() * ScareScript.envelope(t,
                        overlay.start(), overlay.end(), overlay.fadeIn(), overlay.fadeOut()));
            } else if (beat instanceof ScareScript.Flash flash) {
                float age = t - flash.at();
                if (age >= 0.0F && age < flash.duration()) {
                    intensity = Math.max(intensity,
                            flash.maxAlpha() * (1.0F - age / flash.duration()));
                }
            }
        }
        return Mth.clamp(intensity, 0.0F, 1.0F);
    }

    /** Soft dark edge wash — the whole reducedFx presentation (JumpscareOverlay pattern). */
    private static void renderVignette(GuiGraphics guiGraphics, int width, int height,
            float alpha) {
        if (alpha <= 0.01F) {
            return;
        }
        int band = Math.max(16, height / 4);
        int solid = argb(alpha, 0x0A0208);
        int clear = argb(0.0F, 0x0A0208);
        guiGraphics.fillGradient(0, 0, width, band, solid, clear);
        guiGraphics.fillGradient(0, height - band, width, height, clear, solid);
    }

    private static int argb(float alpha, int rgb) {
        return (Mth.floor(Mth.clamp(alpha, 0.0F, 1.0F) * 255.0F) << 24) | (rgb & 0xFFFFFF);
    }
}
