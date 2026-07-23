package dev.projecteclipse.eclipse.client.hud;

import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;
import java.util.UUID;

import javax.annotation.Nullable;

import com.mojang.blaze3d.systems.RenderSystem;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.S2CBossbarStylePayload;
import net.minecraft.Util;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.LerpingBossEvent;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.contents.TranslatableContents;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.BossEvent;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.CustomizeGuiOverlayEvent;
import net.neoforged.neoforge.client.event.RenderGuiEvent;

/**
 * Surgical bossbar skinning ({@code docs/ideas/03_ui_ux.md} §D): subscribes to the per-bar
 * {@link CustomizeGuiOverlayEvent.BossEventProgress} (game bus, cancellable) and replaces the
 * rendering of OUR bars only. A bar is "ours" when its UUID was tagged by an
 * {@link S2CBossbarStylePayload} (primary match) or, as a safety net for the v1 revive
 * ritual, when its name's translation key starts with {@code ritual.eclipse.} (theme
 * {@code goal}). Every unmatched bar renders 100% vanilla — the event is not cancelled.
 *
 * <p>Skinned rendering: themed 512x64 frame blitted at 192x15 logical px around a 182x7
 * fill window, a lerped fill (the displayed progress approaches the real progress at
 * {@value #LERP_PER_FRAME}/frame), a scrolling energy overlay (UV offset from
 * {@link Util#getMillis()}) and an end-cap glow that flashes on progress changes.
 * {@code setIncrement(getIncrement() + 10)} reserves the taller frame's space. With
 * {@code showBossbarSkin=false} a minimal 4px strip renders instead — a revive countdown is
 * NEVER fully hidden.</p>
 *
 * <p>Server-driven telegraphs survive the reskin: {@code boss}-themed bars tint their fill
 * and leading-edge glow toward the vanilla {@link BossEvent.BossBarColor} (the
 * Ferryman's WHITE/PURPLE/RED phase colors), a NOTCHED_6 overlay draws thin phase ticks at
 * the 1/3 and 2/3 marks of the fill window (the Herald's phase breaks), and the minimal
 * strip is colored by bar color too. Under F1 ({@code hideGui}) the handler keeps the
 * {@link BarState} lerp warm but draws nothing and does not cancel the event.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class BossbarSkin {
    private static final ResourceLocation FILL =
            texture("fill");
    private static final ResourceLocation SCROLL =
            texture("scroll");
    private static final ResourceLocation GLOW =
            texture("glow");

    /** Frame blit rect relative to the vanilla bar origin (x, y). */
    private static final int FRAME_OFFSET_X = -5;
    private static final int FRAME_OFFSET_Y = -5;
    private static final int FRAME_WIDTH = 192;
    private static final int FRAME_HEIGHT = 15;
    /** Fill window relative to the vanilla bar origin (matches the frame textures). */
    private static final int FILL_OFFSET_Y = -1;
    private static final int FILL_WIDTH = 182;
    private static final int FILL_HEIGHT = 7;
    /** Displayed progress approaches the real progress this much per rendered frame. */
    private static final float LERP_PER_FRAME = 0.05F;
    /** End-cap flash duration after a progress change. */
    private static final long FLASH_MILLIS = 400L;
    /** The scroll overlay pattern repeats every this many logical px (256 texels at 2 tx/px). */
    private static final int SCROLL_PERIOD = 128;
    /** Untagged skinned-bar states are dropped after this long without rendering. */
    private static final long STATE_TTL_MILLIS = 120_000L;

    /** Per-skinned-bar client state, keyed by the {@code BossEvent} UUID. Client thread only. */
    private static final Map<UUID, BarState> SKINNED = new HashMap<>();

    /** Geometry observed this frame, so the announcement sweep can stack below real bars. */
    private static long lastBarSeenMillis;
    /** Reset to the vanilla anchor every frame ({@link #onRenderGuiPre}); bars re-stack it. */
    private static int observedBarsBottom = 12;

    private static final class BarState {
        String theme;
        float displayedProgress = -1.0F;
        float lastActualProgress = -1.0F;
        long flashStartMillis;
        long lastSeenMillis;

        BarState(String theme) {
            this.theme = theme;
            this.lastSeenMillis = Util.getMillis();
        }
    }

    private BossbarSkin() {}

    /** {@link S2CBossbarStylePayload} entry point: tags a server bar UUID with a skin theme. */
    public static void setTheme(UUID id, String theme) {
        BarState state = SKINNED.get(id);
        if (state == null) {
            SKINNED.put(id, new BarState(theme));
        } else {
            state.theme = theme;
        }
    }

    /**
     * Y of the next free bossbar slot: below the last bar rendered within the last ~250 ms,
     * or the vanilla top anchor (12) when no bars are showing. Used by the announcement
     * sweep so it never overlaps real bars.
     */
    public static int nextFreeBarY() {
        return Util.getMillis() - lastBarSeenMillis < 250L ? observedBarsBottom : 12;
    }

    /**
     * Fresh stacking geometry at the top of every GUI frame: the old wall-clock reset
     * (25 ms without a bar event) never fires above 40 fps, so {@code observedBarsBottom}
     * stuck at its historical max until ALL bars vanished. The bar events below re-stack
     * it each frame before the announcement layer reads it.
     */
    @SubscribeEvent
    static void onRenderGuiPre(RenderGuiEvent.Pre event) {
        observedBarsBottom = 12;
    }

    @SubscribeEvent
    static void onBossEventProgress(CustomizeGuiOverlayEvent.BossEventProgress event) {
        long now = Util.getMillis();
        // Track stacking geometry for ALL bars (vanilla ones included) before any matching.
        lastBarSeenMillis = now;

        LerpingBossEvent bar = event.getBossEvent();
        BarState state = SKINNED.get(bar.getId());
        if (state == null) {
            String fallbackTheme = fallbackTheme(bar.getName());
            if (fallbackTheme == null) {
                observedBarsBottom = Math.max(observedBarsBottom, event.getY() + event.getIncrement());
                return; // not ours — vanilla renders untouched
            }
            state = new BarState(fallbackTheme);
            SKINNED.put(bar.getId(), state);
        }
        state.lastSeenMillis = now;

        float actual = Mth.clamp(bar.getProgress(), 0.0F, 1.0F);
        if (state.lastActualProgress >= 0.0F && Math.abs(actual - state.lastActualProgress) > 0.001F) {
            state.flashStartMillis = now;
        }
        state.lastActualProgress = actual;
        if (state.displayedProgress < 0.0F) {
            state.displayedProgress = actual;
        } else {
            state.displayedProgress += Mth.clamp(actual - state.displayedProgress, -LERP_PER_FRAME, LERP_PER_FRAME);
        }

        if (Minecraft.getInstance().options.hideGui) {
            // F1: the BarState above stays warm so displayedProgress doesn't jump when the
            // HUD returns, but nothing is drawn and the event is left alone — the vanilla
            // bar is hidden anyway, so there is nothing to cancel.
            observedBarsBottom = Math.max(observedBarsBottom, event.getY() + event.getIncrement());
            return;
        }

        event.setCanceled(true);
        GuiGraphics guiGraphics = event.getGuiGraphics();
        if (!EclipseClientConfig.showBossbarSkin()) {
            // Minimal 4px strip: countdowns (revive ritual!) must never disappear entirely.
            drawMinimalStrip(guiGraphics, event.getX(), event.getY(), state.theme, state.displayedProgress,
                    bar.getColor());
            observedBarsBottom = Math.max(observedBarsBottom, event.getY() + event.getIncrement());
            return;
        }

        event.setIncrement(event.getIncrement() + 10);
        float flash = state.flashStartMillis == 0L ? 0.0F
                : Mth.clamp(1.0F - (now - state.flashStartMillis) / (float) FLASH_MILLIS, 0.0F, 1.0F);
        drawThemedBar(guiGraphics, event.getX(), event.getY(), state.theme, state.displayedProgress,
                0.35F + 0.65F * flash, bar.getName(), 1.0F, bar.getColor(), bar.getOverlay());
        observedBarsBottom = Math.max(observedBarsBottom, event.getY() + event.getIncrement());
    }

    /**
     * Shared skinned-bar body, also used by {@link AnnouncementOverlay}'s client-local sweep:
     * dark track, lerped fill, scrolling energy overlay, themed frame, leading-edge glow and
     * (when given) the centered name line above the frame. {@code alpha} scales the whole
     * bar (the announcement sweep's fade-out); real bars pass {@code 1}. Sweeps have no
     * backing {@code BossEvent}, so this variant carries no color/overlay telegraphs.
     */
    public static void drawThemedBar(GuiGraphics guiGraphics, int x, int y, String theme,
            float progress, float glowAlpha, Component name, float alpha) {
        drawThemedBar(guiGraphics, x, y, theme, progress, glowAlpha, name, alpha, null, null);
    }

    /**
     * Full skinned-bar body for real server bars: {@code barColor}/{@code overlay} restore
     * the telegraphs the skin used to swallow. For the {@code boss} theme the fill and
     * leading-edge glow tint toward the vanilla bar color (WHITE/PURPLE/RED phase swaps),
     * and a NOTCHED_6 overlay draws thin phase ticks at the 1/3 and 2/3 marks of the fill
     * window (the Herald's phase breaks). Both may be {@code null} (announcement sweeps).
     */
    public static void drawThemedBar(GuiGraphics guiGraphics, int x, int y, String theme,
            float progress, float glowAlpha, Component name, float alpha,
            @Nullable BossEvent.BossBarColor barColor, @Nullable BossEvent.BossBarOverlay overlay) {
        alpha = Mth.clamp(alpha, 0.0F, 1.0F);
        if (alpha < 0.02F) {
            return;
        }
        int fillY = y + FILL_OFFSET_Y;
        int fillWidth = Math.round(FILL_WIDTH * Mth.clamp(progress, 0.0F, 1.0F));

        // Phase-color tint: boss-themed bars follow the server's bar color (WHITE = no tint).
        boolean bossTheme = S2CBossbarStylePayload.THEME_BOSS.equals(theme);
        int tint = bossTheme && barColor != null ? barColorRgb(barColor) : 0xFFFFFF;
        float tintRed = ((tint >> 16) & 0xFF) / 255.0F;
        float tintGreen = ((tint >> 8) & 0xFF) / 255.0F;
        float tintBlue = (tint & 0xFF) / 255.0F;

        RenderSystem.enableBlend();
        // Empty track: the fill strip darkened to a faint violet bed.
        guiGraphics.setColor(0.28F, 0.22F, 0.36F, 0.85F * alpha);
        guiGraphics.blit(FILL, x, fillY, FILL_WIDTH, FILL_HEIGHT, 0.0F, 0.0F, 512, 32, 512, 32);
        // Lerped fill (the scroll overlay inherits the tint for a coherent energy hue).
        if (fillWidth > 0) {
            guiGraphics.setColor(tintRed, tintGreen, tintBlue, alpha);
            guiGraphics.blit(FILL, x, fillY, fillWidth, FILL_HEIGHT, 0.0F, 0.0F,
                    Math.round(512.0F * fillWidth / FILL_WIDTH), 32, 512, 32);
            drawScrollOverlay(guiGraphics, x, fillY, fillWidth);
        }
        // Herald phase notches: thin dark ticks where the phases break (2/3 and 1/3 health).
        if (bossTheme && overlay == BossEvent.BossBarOverlay.NOTCHED_6) {
            guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F); // fill() colors below carry their own alpha
            int notchColor = ((int) (0.85F * alpha * 255.0F) << 24) | 0x140A24;
            for (int third = 1; third <= 2; third++) {
                int markX = x + Math.round(FILL_WIDTH * third / 3.0F);
                guiGraphics.fill(markX, fillY, markX + 1, fillY + FILL_HEIGHT, notchColor);
            }
        }
        // Themed frame on top of the fill.
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
        guiGraphics.blit(frameTexture(theme), x + FRAME_OFFSET_X, y + FRAME_OFFSET_Y,
                FRAME_WIDTH, FRAME_HEIGHT, 0.0F, 0.0F, 512, 64, 512, 64);
        // Leading-edge glow (flashes via glowAlpha on progress changes), phase-tinted too.
        if (fillWidth > 0 && glowAlpha > 0.02F) {
            guiGraphics.setColor(tintRed, tintGreen, tintBlue, Mth.clamp(glowAlpha, 0.0F, 1.0F) * alpha);
            guiGraphics.blit(GLOW, x + fillWidth - 7, fillY - 4, 14, 14, 0.0F, 0.0F, 64, 64, 64, 64);
        }
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.disableBlend();

        int alphaByte = (int) (alpha * 255.0F);
        if (name != null && alphaByte >= 8) {
            Minecraft minecraft = Minecraft.getInstance();
            int textX = guiGraphics.guiWidth() / 2 - minecraft.font.width(name) / 2;
            guiGraphics.drawString(minecraft.font, name, textX, y - 12, (alphaByte << 24) | 0xFFFFFF);
        }
    }

    /** Scrolling energy streaks clipped to the filled width; segments avoid UV wrap-around. */
    private static void drawScrollOverlay(GuiGraphics guiGraphics, int x, int fillY, int fillWidth) {
        // 2 texels per logical px -> the 256px texture repeats every SCROLL_PERIOD logical px.
        int scroll = (int) ((Util.getMillis() / 12L) % SCROLL_PERIOD);
        int drawn = 0;
        while (drawn < fillWidth) {
            int phase = (scroll + drawn) % SCROLL_PERIOD;
            int segment = Math.min(SCROLL_PERIOD - phase, fillWidth - drawn);
            guiGraphics.blit(SCROLL, x + drawn, fillY, segment, FILL_HEIGHT,
                    phase * 2.0F, 0.0F, segment * 2, 32, 256, 32);
            drawn += segment;
        }
    }

    /**
     * The {@code showBossbarSkin=false} fallback: 4px track + progress strip, no text. The
     * strip takes the server bar's color when known (phase telegraphs must survive even the
     * minimal look); the fixed theme accent is only the no-color fallback.
     */
    private static void drawMinimalStrip(GuiGraphics guiGraphics, int x, int y, String theme, float progress,
            @Nullable BossEvent.BossBarColor barColor) {
        int accent = barColor != null ? 0xFF000000 | barColorRgb(barColor) : switch (theme) {
            case S2CBossbarStylePayload.THEME_GOAL -> 0xFF9AF0E0;
            case S2CBossbarStylePayload.THEME_BOSS -> 0xFFE86078;
            default -> 0xFFC8B4E8;
        };
        guiGraphics.fill(x, y, x + FILL_WIDTH, y + 4, 0xB0140A24);
        int width = Math.round(FILL_WIDTH * Mth.clamp(progress, 0.0F, 1.0F));
        if (width > 0) {
            guiGraphics.fill(x, y, x + width, y + 4, accent);
        }
    }

    /** Vanilla bossbar palette → RGB, for the fill/glow tint and the minimal strip. */
    private static int barColorRgb(BossEvent.BossBarColor color) {
        return switch (color) {
            case PINK -> 0xFF73A5;
            case BLUE -> 0x4FC3FF;
            case RED -> 0xFF4A4A;
            case GREEN -> 0x58E877;
            case YELLOW -> 0xFFD447;
            case PURPLE -> 0xB44CFF;
            case WHITE -> 0xFFFFFF;
        };
    }

    /** Translation-key safety net for v1 bars that predate the style payload (revive ritual). */
    private static String fallbackTheme(Component name) {
        if (name.getContents() instanceof TranslatableContents translatable
                && translatable.getKey().startsWith("ritual.eclipse.")) {
            return S2CBossbarStylePayload.THEME_GOAL;
        }
        return null;
    }

    static ResourceLocation frameTexture(String theme) {
        return switch (theme) {
            case S2CBossbarStylePayload.THEME_GOAL -> texture("goal_frame");
            case S2CBossbarStylePayload.THEME_BOSS -> texture("boss_frame");
            default -> texture("day_frame");
        };
    }

    private static ResourceLocation texture(String name) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/bossbar/" + name + ".png");
    }

    /** Prunes stale bar states (bar removed server-side) and clears everything on disconnect. */
    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        if (Minecraft.getInstance().level == null) {
            if (!SKINNED.isEmpty()) {
                SKINNED.clear();
            }
            return;
        }
        if (SKINNED.isEmpty() || Minecraft.getInstance().player == null
                || Minecraft.getInstance().player.tickCount % 100 != 0) {
            return;
        }
        long now = Util.getMillis();
        for (Iterator<BarState> iterator = SKINNED.values().iterator(); iterator.hasNext();) {
            BarState state = iterator.next();
            if (now - state.lastSeenMillis > STATE_TTL_MILLIS) {
                iterator.remove();
            }
        }
    }
}
