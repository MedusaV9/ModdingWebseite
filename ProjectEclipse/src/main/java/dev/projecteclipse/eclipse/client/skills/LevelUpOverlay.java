package dev.projecteclipse.eclipse.client.skills;

import java.util.ArrayDeque;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.GlitchText;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.cutscene.client.CameraDirector;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import net.minecraft.Util;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RegisterGuiLayersEvent;

/**
 * Client-local level-up celebration (WB-SKILLS): a center-screen "LEVEL 12" glyph that
 * glitches in and out in the purple accent palette — characters resolve left-to-right out
 * of {@link GlitchText} noise over {@value #GLITCH_IN_TICKS}t, hold with a soft breathing
 * glow and an expanding hairline underline, then dissolve back — plus one
 * {@code ui.level_up} sting and a small {@code eclipse:unlock_burst} Quasar flourish at
 * the player's feet ({@code spawnOrFallback}: vanilla END_ROD/PORTAL burst when Veil is
 * unavailable, {@code reducedFx}-gated like the announcement unlock burst).
 *
 * <p><b>Self only, server truth:</b> level-ups are detected by polling the synced
 * {@code ClientStateCache.skillLevel} (only ever the local player's state). The first sync
 * of a session seeds silently (login is not a celebration); multi-level jumps enqueue
 * every intermediate level and play back one after another while they fit the queue
 * (capped at {@value #QUEUE_LIMIT}); a jump wider than the remaining room coalesces to
 * the first + final level, always keeping the newest. A HUD overlay, NEVER a screen:
 * input is never blocked. Gated on {@code levelUpCelebrations}; F1 hides the glyph
 * (ticking continues so it doesn't pop back after F1); cutscene HUD suppression both
 * cancels the layer (LetterboxLayer hook) and defers queued playback until the flight
 * ends. {@code reducedFx} plays a calm fade-only variant with no scramble/jitter.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class LevelUpOverlay {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "skill_level_up");
    private static final ResourceLocation FLOURISH_EMITTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "unlock_burst");

    private static final int GLITCH_IN_TICKS = 8;
    private static final int HOLD_TICKS = 26;
    private static final int GLITCH_OUT_TICKS = 8;
    private static final int TOTAL_TICKS = GLITCH_IN_TICKS + HOLD_TICKS + GLITCH_OUT_TICKS;
    /** Quiet gap between queued celebrations so back-to-back levels stay readable. */
    private static final int GAP_TICKS = 8;
    private static final int QUEUE_LIMIT = 8;
    private static final float SCALE = 2.0F;

    // Client tick thread only.
    private static final ArrayDeque<Integer> QUEUE = new ArrayDeque<>();
    private static int lastSeenLevel = -1;
    /** Ticks into the active celebration; {@code -1} = idle. */
    private static int ticks = -1;
    private static int celebratedLevel;

    private LevelUpOverlay() {}

    /** Mod-bus layer registration (nested, {@code SkillKeybind.Registrar} pattern). */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class Registrar {
        private Registrar() {}

        @SubscribeEvent
        static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
            event.registerAboveAll(LAYER_ID, LevelUpOverlay::render);
        }
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            QUEUE.clear();
            lastSeenLevel = -1;
            ticks = -1;
            return;
        }
        if (minecraft.isPaused()) {
            return;
        }

        int level = ClientStateCache.skillLevel;
        if (lastSeenLevel < 0) {
            lastSeenLevel = level; // login sync seed — never celebrate the join
        } else if (level > lastSeenLevel) {
            if (EclipseClientConfig.levelUpCelebrations()) {
                int first = lastSeenLevel + 1;
                if (level - lastSeenLevel <= QUEUE_LIMIT - QUEUE.size()) {
                    for (int reached = first; reached <= level; reached++) {
                        QUEUE.addLast(reached);
                    }
                } else {
                    // M-6: a jump wider than the remaining queue room used to pollLast()
                    // itself into an arbitrary subset (2..8 then 20). Coalesce instead:
                    // celebrate the first newly reached level and the final one; the
                    // oldest pending entries yield so the NEWEST level always plays.
                    while (QUEUE.size() > QUEUE_LIMIT - 2) {
                        QUEUE.pollFirst();
                    }
                    if (first < level) {
                        QUEUE.addLast(first);
                    }
                    QUEUE.addLast(level);
                }
            }
            lastSeenLevel = level;
        } else if (level < lastSeenLevel) {
            lastSeenLevel = level; // admin xp set downward — no theater
        }

        if (!EclipseClientConfig.levelUpCelebrations()) {
            QUEUE.clear(); // toggled off mid-queue: drop pending celebrations
        }

        if (ticks >= 0 && ++ticks > TOTAL_TICKS + GAP_TICKS) {
            ticks = -1;
        }
        // Cutscene flights defer playback (the layer render is cancelled anyway).
        if (ticks < 0 && !QUEUE.isEmpty() && !CameraDirector.isHudSuppressed()) {
            start(QUEUE.pollFirst());
        }
    }

    private static void start(int level) {
        celebratedLevel = level;
        ticks = 0;
        UiSounds.levelUp();
        LocalPlayer player = Minecraft.getInstance().player;
        if (player != null && !EclipseClientConfig.reducedFx()) {
            QuasarSpawner.spawnOrFallback(FLOURISH_EMITTER, player.position());
        }
    }

    /** GUI layer body (self-registered above all; letterbox suppression cancels it). */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        if (ticks < 0 || ticks > TOTAL_TICKS || minecraft.options.hideGui) {
            return;
        }
        float t = ticks + deltaTracker.getGameTimeDeltaPartialTick(true);
        String text = EclipseLang.trString("gui.eclipse.skills.level_glyph", celebratedLevel);
        boolean reduced = EclipseClientConfig.reducedFx();

        float alpha;
        if (t < GLITCH_IN_TICKS) {
            alpha = easeOutCubic(t / GLITCH_IN_TICKS);
        } else if (t <= GLITCH_IN_TICKS + HOLD_TICKS) {
            alpha = 1.0F;
        } else {
            alpha = 1.0F - easeOutCubic((t - GLITCH_IN_TICKS - HOLD_TICKS) / GLITCH_OUT_TICKS);
        }
        alpha = Mth.clamp(alpha, 0.0F, 1.0F);
        if (alpha <= 0.01F) {
            return;
        }

        // Character resolve: in-phase reveals left->right, out-phase dissolves right->left.
        String shown = text;
        if (!reduced) {
            int length = text.length();
            int resolved = length;
            if (t < GLITCH_IN_TICKS) {
                resolved = Math.round(t / GLITCH_IN_TICKS * length);
            } else if (t > GLITCH_IN_TICKS + HOLD_TICKS) {
                resolved = Math.round((1.0F - (t - GLITCH_IN_TICKS - HOLD_TICKS) / GLITCH_OUT_TICKS) * length);
            }
            resolved = Mth.clamp(resolved, 0, length);
            if (resolved < length) {
                shown = text.substring(0, resolved)
                        + GlitchText.scramble(length - resolved, celebratedLevel);
            }
        }

        Font font = minecraft.font;
        float centerX = guiGraphics.guiWidth() / 2.0F;
        float centerY = guiGraphics.guiHeight() / 3.0F;
        boolean glitchPhase = !reduced && (t < GLITCH_IN_TICKS || t > GLITCH_IN_TICKS + HOLD_TICKS);

        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(centerX, centerY, 0.0F);
        guiGraphics.pose().scale(SCALE, SCALE, 1.0F);
        int halfWidth = font.width(shown) / 2;

        if (glitchPhase) {
            // Chromatic ghosts: deep-purple copies jittering ±1px around the main glyph.
            long roll = Util.getMillis() / 100L + celebratedLevel;
            int jitter = (int) (roll % 3L) - 1;
            int ghost = EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT_DEEP, alpha * 0.6F);
            guiGraphics.drawString(font, shown, -halfWidth - 1 + jitter, -font.lineHeight / 2, ghost, false);
            guiGraphics.drawString(font, shown, -halfWidth + 1 - jitter, -font.lineHeight / 2, ghost, false);
        } else {
            // Steady state: a quiet deep-purple drop shadow keeps the glyph readable.
            guiGraphics.drawString(font, shown, -halfWidth + 1, -font.lineHeight / 2 + 1,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT_DEEP, alpha * 0.8F), false);
        }

        // Hold-phase breathing: the accent lifts toward white on a slow sine.
        float breath = !reduced && t >= GLITCH_IN_TICKS && t <= GLITCH_IN_TICKS + HOLD_TICKS
                ? (Mth.sin((t - GLITCH_IN_TICKS) * 0.35F) + 1.0F) * 0.5F * 0.25F : 0.0F;
        int main = EclipseUiTheme.withAlpha(lerpColor(EclipseUiTheme.ACCENT, 0xFFFFFFFF, breath), alpha);
        guiGraphics.drawString(font, shown, -halfWidth, -font.lineHeight / 2, main, false);

        // Expanding hairline underline during the hold (§2.3 quiet flourish).
        if (t >= GLITCH_IN_TICKS) {
            float spread = Mth.clamp((t - GLITCH_IN_TICKS) / 6.0F, 0.0F, 1.0F);
            int lineHalf = Math.round(easeOutCubic(spread) * (halfWidth + 6));
            int lineY = font.lineHeight / 2 + 3;
            guiGraphics.fill(-lineHalf, lineY, lineHalf, lineY + 1,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT_DEEP, alpha * 0.9F));
        }
        guiGraphics.pose().popPose();
    }

    private static float easeOutCubic(float t) {
        float inv = 1.0F - Mth.clamp(t, 0.0F, 1.0F);
        return 1.0F - inv * inv * inv;
    }

    /** RGB lerp toward {@code to}, alpha forced opaque (alpha is applied by the caller). */
    private static int lerpColor(int from, int to, float t) {
        float clamped = Mth.clamp(t, 0.0F, 1.0F);
        int r = Math.round(Mth.lerp(clamped, (from >>> 16) & 0xFF, (to >>> 16) & 0xFF));
        int g = Math.round(Mth.lerp(clamped, (from >>> 8) & 0xFF, (to >>> 8) & 0xFF));
        int b = Math.round(Mth.lerp(clamped, from & 0xFF, to & 0xFF));
        return 0xFF000000 | (r << 16) | (g << 8) | b;
    }
}
