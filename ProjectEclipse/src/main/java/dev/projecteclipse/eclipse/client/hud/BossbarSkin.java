package dev.projecteclipse.eclipse.client.hud;

import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;
import java.util.UUID;

import javax.annotation.Nullable;

import com.mojang.blaze3d.systems.RenderSystem;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.cutscene.client.CameraDirector;
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
 * Bossbar v3 ({@code docs/plans_v3/P3_ui.md} §3.5): the surgical
 * {@link CustomizeGuiOverlayEvent.BossEventProgress} approach is kept — a bar is "ours" when
 * its UUID was tagged by an {@link S2CBossbarStylePayload} (primary match) or, as a safety
 * net for v1 revive-ritual bars, when its name's translation key starts with
 * {@code ritual.eclipse.}. Every unmatched bar renders 100% vanilla — the event is not
 * cancelled.
 *
 * <p><b>v3 juice</b> (all {@code reducedFx}-gated, applies to all three themes and both
 * {@code bossbarStyle} variants):</p>
 * <ul>
 *   <li><b>Entrance/exit state machine</b>: first sighting of a bar UUID → 8-tick drop-in
 *       (y −6→0, alpha 0→1, fill wipes L→R). Tracked bars that stop rendering → 6-tick
 *       fade-out ghost drawn from a {@link RenderGuiEvent.Post} pass (the bar no longer
 *       fires events, so the ghost is redrawn from cached geometry). A bar re-seen after
 *       &gt; {@value #REENTER_MILLIS} ms without events replays the entrance.</li>
 *   <li><b>Animated fill</b>: a 4-frame sheet {@code fill_anim.png} (512x128, 8 ticks/frame,
 *       P2 asset) replaces the single tinted fill when present; the committed procedural
 *       fallback is the current fill plus a second scroll pass at 0.5x speed.</li>
 *   <li><b>Damage flash + micro-shake</b>: a progress DROP &gt; {@value #DAMAGE_DROP_THRESHOLD}
 *       flashes the fill white for ~3 ticks and shakes the frame ±2px; a trailing "damage
 *       ghost" segment lingers behind the lerped fill and drains after a short hold.
 *       Progress RISES keep the v2 soft leading-edge glow flash.</li>
 *   <li><b>Phase notches</b>: NOTCHED_6/10/12/20 overlays draw a thin tick at every notch
 *       fraction (v2 hardcoded NOTCHED_6 at thirds).</li>
 *   <li><b>Styles</b>: {@code bossbarStyle=ORNATE} keeps the themed 512x64 frames;
 *       {@code SLIM} renders a frameless rounded Quiet-Eclipse strip from pure fills.
 *       {@code showBossbarSkin=false} still falls back to the minimal 4px strip — a revive
 *       countdown is NEVER fully hidden.</li>
 *   <li><b>Name band</b> (§2 typography): the name line moved from above the bar into the
 *       fill band (subtle scrim, {@code DIM} → {@code TEXT} flash on change) so stacked
 *       bars read tighter; the vanilla 19px increment is kept (v2 reserved +10 for the
 *       floating name line).</li>
 *   <li><b>Breathing</b>: while a {@code boss}-themed bar is on screen its outer frame
 *       hairline breathes (sin, 3 s).</li>
 * </ul>
 *
 * <p>Server-driven telegraphs survive: {@code boss}-themed bars tint fill/glow toward the
 * vanilla {@link BossEvent.BossBarColor} (the Ferryman's WHITE/PURPLE/RED phase swaps) and
 * the minimal strip is colored by bar color too. Under F1 ({@code hideGui}) the handler
 * keeps the {@link BarState} lerp warm but draws nothing and does not cancel the event.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class BossbarSkin {
    private static final ResourceLocation FILL = texture("fill");
    /** P2 asset (512x128, 4 frames of 512x32); probed live, procedural fallback until it lands. */
    private static final ResourceLocation FILL_ANIM = texture("fill_anim");
    private static final ResourceLocation SCROLL = texture("scroll");
    private static final ResourceLocation GLOW = texture("glow");

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
    /** End-cap flash duration after a progress rise. */
    private static final long FLASH_MILLIS = 400L;
    /** The scroll overlay pattern repeats every this many logical px (256 texels at 2 tx/px). */
    private static final int SCROLL_PERIOD = 128;
    /** Untagged skinned-bar states are dropped after this long without rendering. */
    private static final long STATE_TTL_MILLIS = 120_000L;

    // --- v3 animation constants (§3.5) ---

    /** Entrance drop-in length (8 ticks). */
    private static final long ENTRANCE_MILLIS = 400L;
    /** Exit fade-out length (6 ticks). */
    private static final long EXIT_MILLIS = 300L;
    /** No event for this long ⇒ the bar left the screen and the exit ghost may start. */
    private static final long EXIT_GRACE_MILLIS = 250L;
    /** A bar re-seen after this long without events replays the entrance. */
    private static final long REENTER_MILLIS = 1_000L;
    /** Progress DROP beyond this triggers the damage flash/shake (0.5%). */
    private static final float DAMAGE_DROP_THRESHOLD = 0.005F;
    /** White damage-flash length (~3 ticks). */
    private static final long DAMAGE_FLASH_MILLIS = 150L;
    /** Micro-shake amplitude on damage (logical px). */
    private static final float SHAKE_PX = 2.0F;
    /** The damage ghost holds this long before draining toward the lerped fill. */
    private static final long GHOST_HOLD_MILLIS = 200L;
    /** Ghost drain per rendered frame once the hold elapsed. */
    private static final float GHOST_DRAIN_PER_FRAME = 0.01F;
    /** Name flashes DIM → TEXT for this long after the bar name changes. */
    private static final long NAME_FLASH_MILLIS = 600L;
    /** Boss-theme frame breathing period (3 s sine). */
    private static final float BREATHE_PERIOD_MILLIS = 3_000.0F;
    /** fill_anim sheet: 4 frames, 8 ticks (400 ms) each. */
    private static final long ANIM_FRAME_MILLIS = 400L;

    /** Per-skinned-bar client state, keyed by the {@code BossEvent} UUID. Client thread only. */
    private static final Map<UUID, BarState> SKINNED = new HashMap<>();

    /** Geometry observed this frame, so timer/announcement layers can stack below real bars. */
    private static long lastBarSeenMillis;
    /** Reset to the vanilla anchor every frame ({@link #onRenderGuiPre}); bars re-stack it. */
    private static int observedBarsBottom = 12;
    /** {@code fill_anim.png} probe: 0 = unknown (re-probe), 1 = present, 2 = absent. */
    private static int fillAnimProbe;

    private static final class BarState {
        String theme;
        float displayedProgress = -1.0F;
        float lastActualProgress = -1.0F;
        /** Trailing damage ghost: lags behind {@link #displayedProgress} after a drop. */
        float ghostProgress = -1.0F;
        long flashStartMillis;
        long damageStartMillis;
        long entranceStartMillis;
        long lastSeenMillis;
        long nameFlashStartMillis;
        long lastNameChangeMillis;
        /** Name-change detection: string compared only when the component REFERENCE changes. */
        @Nullable
        Component lastNameComponent;
        @Nullable
        String lastNameString;
        /** Cached geometry/telegraphs for the event-less exit-ghost redraw. */
        int lastX = Integer.MIN_VALUE;
        int lastY;
        @Nullable
        BossEvent.BossBarColor lastColor;
        @Nullable
        BossEvent.BossBarOverlay lastOverlay;

        BarState(String theme, long now) {
            this.theme = theme;
            this.lastSeenMillis = now;
            beginEntrance(now);
        }

        void beginEntrance(long now) {
            this.entranceStartMillis = EclipseClientConfig.reducedFx() ? 0L : now;
            this.displayedProgress = -1.0F;
            this.ghostProgress = -1.0F;
            this.lastActualProgress = -1.0F;
            this.damageStartMillis = 0L;
            this.flashStartMillis = 0L;
        }

        float entranceProgress(long now) {
            if (entranceStartMillis == 0L || EclipseClientConfig.reducedFx()) {
                return 1.0F;
            }
            return Mth.clamp((now - entranceStartMillis) / (float) ENTRANCE_MILLIS, 0.0F, 1.0F);
        }
    }

    private BossbarSkin() {}

    /** {@link S2CBossbarStylePayload} entry point: tags a server bar UUID with a skin theme. */
    public static void setTheme(UUID id, String theme) {
        BarState state = SKINNED.get(id);
        if (state == null) {
            SKINNED.put(id, new BarState(theme, Util.getMillis()));
        } else {
            state.theme = theme;
        }
    }

    /**
     * Y of the next free bossbar slot: below the last bar (or reserved overlay row) rendered
     * within the last ~250 ms, or the vanilla top anchor (12) when nothing is showing. Used
     * by the day-timer layer and the announcement sweep so they never overlap real bars.
     */
    public static int nextFreeBarY() {
        return Util.getMillis() - lastBarSeenMillis < 250L ? observedBarsBottom : 12;
    }

    /**
     * Reserves a row of the top-center overlay stack ({@code DayTimerLayer} calls this after
     * drawing, BEFORE the announcement layer renders — see the registration order in
     * {@code EclipseGuiLayers}) so later {@link #nextFreeBarY()} readers stack below it.
     */
    public static void reserveOverlayRow(int bottomY) {
        lastBarSeenMillis = Util.getMillis();
        observedBarsBottom = Math.max(observedBarsBottom, bottomY);
    }

    /**
     * Fresh stacking geometry at the top of every GUI frame: the old wall-clock reset
     * (25 ms without a bar event) never fires above 40 fps, so {@code observedBarsBottom}
     * stuck at its historical max until ALL bars vanished. The bar events below re-stack
     * it each frame before the timer/announcement layers read it.
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
            state = new BarState(fallbackTheme, now);
            SKINNED.put(bar.getId(), state);
        } else if (now - state.lastSeenMillis > REENTER_MILLIS) {
            // The bar left the screen long enough ago that the exit ghost finished — replay
            // the entrance (boss re-entered range, countdown re-armed, cutscene ended, ...).
            state.beginEntrance(now);
        }
        state.lastSeenMillis = now;

        // Name change detection without per-frame string building: getString() runs only
        // when the server actually swapped the name component (countdowns: ~1/s). Names
        // that tick faster than every 3 s (the day countdown's "Next phase: 2h 14m") are
        // ticker-style — they stay DIM instead of strobing the DIM→TEXT flash every second.
        Component name = bar.getName();
        if (name != state.lastNameComponent) {
            state.lastNameComponent = name;
            String nameString = name.getString();
            if (!nameString.equals(state.lastNameString)) {
                if (state.lastNameString != null) {
                    state.nameFlashStartMillis =
                            now - state.lastNameChangeMillis > 3_000L ? now : 0L;
                }
                state.lastNameChangeMillis = now;
                state.lastNameString = nameString;
            }
        }

        float actual = Mth.clamp(bar.getProgress(), 0.0F, 1.0F);
        if (state.lastActualProgress >= 0.0F) {
            float delta = actual - state.lastActualProgress;
            if (delta < -DAMAGE_DROP_THRESHOLD) {
                // Damage: white flash + shake; the ghost keeps the pre-drop level visible.
                state.damageStartMillis = now;
                state.ghostProgress = Math.max(state.ghostProgress, state.displayedProgress);
            } else if (delta > 0.001F) {
                // Rise: v2's soft leading-edge glow flash.
                state.flashStartMillis = now;
            }
        }
        state.lastActualProgress = actual;
        if (state.displayedProgress < 0.0F) {
            state.displayedProgress = actual;
        } else {
            state.displayedProgress += Mth.clamp(actual - state.displayedProgress, -LERP_PER_FRAME, LERP_PER_FRAME);
        }
        // Trailing damage ghost: hold briefly, then drain toward the lerped fill.
        if (state.ghostProgress > state.displayedProgress) {
            if (now - state.damageStartMillis > GHOST_HOLD_MILLIS) {
                state.ghostProgress = Math.max(state.displayedProgress, state.ghostProgress - GHOST_DRAIN_PER_FRAME);
            }
        } else {
            state.ghostProgress = state.displayedProgress;
        }
        state.lastColor = bar.getColor();
        state.lastOverlay = bar.getOverlay();

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
            state.lastX = Integer.MIN_VALUE; // no exit ghost in minimal mode
            drawMinimalStrip(guiGraphics, event.getX(), event.getY(), state.theme, state.displayedProgress,
                    bar.getColor());
            observedBarsBottom = Math.max(observedBarsBottom, event.getY() + event.getIncrement());
            return;
        }

        state.lastX = event.getX();
        state.lastY = event.getY();
        // v2 reserved +10 for the floating name line; v3 draws the name inside the fill band
        // (§3.5 "stacked bars read tighter"), so the vanilla 19px increment is kept as-is.
        float flash = state.flashStartMillis == 0L ? 0.0F
                : Mth.clamp(1.0F - (now - state.flashStartMillis) / (float) FLASH_MILLIS, 0.0F, 1.0F);
        drawLiveBar(guiGraphics, event.getX(), event.getY(), state, bar.getName(),
                0.35F + 0.65F * flash, 1.0F, bar.getColor(), bar.getOverlay(), now);
        observedBarsBottom = Math.max(observedBarsBottom, event.getY() + event.getIncrement());
    }

    /** Live (event-driven) bar body: entrance pose, damage shake, then the shared renderer. */
    private static void drawLiveBar(GuiGraphics guiGraphics, int x, int y, BarState state,
            Component name, float glowAlpha, float alpha,
            @Nullable BossEvent.BossBarColor barColor, @Nullable BossEvent.BossBarOverlay overlay, long now) {
        boolean reduced = EclipseClientConfig.reducedFx();
        float entrance = state.entranceProgress(now);
        float damageFlash = reduced || state.damageStartMillis == 0L ? 0.0F
                : Mth.clamp(1.0F - (now - state.damageStartMillis) / (float) DAMAGE_FLASH_MILLIS, 0.0F, 1.0F);
        if (!reduced && damageFlash > 0.0F) {
            // Deterministic micro-shake: two incommensurate sines, decaying with the flash.
            x += Math.round(Mth.sin(now * 0.09F) * SHAKE_PX * damageFlash);
            y += Math.round(Mth.cos(now * 0.13F) * SHAKE_PX * 0.5F * damageFlash);
        }
        float nameFlash = state.nameFlashStartMillis == 0L ? 0.0F
                : Mth.clamp(1.0F - (now - state.nameFlashStartMillis) / (float) NAME_FLASH_MILLIS, 0.0F, 1.0F);
        drawBar(guiGraphics, x, y, state.theme, state.displayedProgress, state.ghostProgress,
                glowAlpha, name, alpha, barColor, overlay, entrance, damageFlash, nameFlash, now);
    }

    /**
     * Exit state machine: tracked bars that stopped firing events within the last
     * {@value #EXIT_MILLIS} ms (after a {@value #EXIT_GRACE_MILLIS} ms grace so low fps never
     * false-triggers) are redrawn from cached geometry as a fading, slightly rising ghost.
     * Skipped under F1, cutscene HUD suppression, the minimal-strip fallback and
     * {@code reducedFx} (exit snaps).
     */
    @SubscribeEvent
    static void onRenderGuiPost(RenderGuiEvent.Post event) {
        if (SKINNED.isEmpty() || EclipseClientConfig.reducedFx() || !EclipseClientConfig.showBossbarSkin()) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null || minecraft.options.hideGui || CameraDirector.isHudSuppressed()) {
            return;
        }
        long now = Util.getMillis();
        for (BarState state : SKINNED.values()) {
            if (state.lastX == Integer.MIN_VALUE || state.displayedProgress < 0.0F) {
                continue;
            }
            long age = now - state.lastSeenMillis;
            if (age < EXIT_GRACE_MILLIS || age > EXIT_GRACE_MILLIS + EXIT_MILLIS) {
                continue;
            }
            float fade = 1.0F - (age - EXIT_GRACE_MILLIS) / (float) EXIT_MILLIS;
            int rise = Math.round(4.0F * (1.0F - fade));
            drawBar(event.getGuiGraphics(), state.lastX, state.lastY - rise, state.theme,
                    state.displayedProgress, state.displayedProgress, 0.0F, state.lastNameComponent,
                    0.9F * fade * fade, state.lastColor, state.lastOverlay, 1.0F, 0.0F, 0.0F, now);
        }
    }

    /**
     * Shared skinned-bar body, also used by {@link AnnouncementOverlay}'s client-local sweep:
     * track, lerped fill, scrolling energy overlay, chrome (ORNATE frame / SLIM strip),
     * leading-edge glow and the in-band name line. {@code alpha} scales the whole bar (the
     * announcement sweep's fade-out); real bars pass {@code 1}. Sweeps have no backing
     * {@code BossEvent}, so this variant carries no color/overlay telegraphs.
     */
    public static void drawThemedBar(GuiGraphics guiGraphics, int x, int y, String theme,
            float progress, float glowAlpha, Component name, float alpha) {
        drawThemedBar(guiGraphics, x, y, theme, progress, glowAlpha, name, alpha, null, null);
    }

    /**
     * Full skinned-bar body for callers without a tracked {@link BarState}: no entrance,
     * shake or damage state — {@code barColor}/{@code overlay} keep the vanilla telegraphs
     * (phase-color tint, notch overlays). Both may be {@code null} (announcement sweeps).
     */
    public static void drawThemedBar(GuiGraphics guiGraphics, int x, int y, String theme,
            float progress, float glowAlpha, Component name, float alpha,
            @Nullable BossEvent.BossBarColor barColor, @Nullable BossEvent.BossBarOverlay overlay) {
        drawBar(guiGraphics, x, y, theme, progress, progress, glowAlpha, name, alpha, barColor, overlay,
                1.0F, 0.0F, 1.0F, Util.getMillis());
    }

    /**
     * The one master renderer behind every skinned look. {@code entrance} 0..1 drives the
     * drop-in (y offset, alpha ramp, L→R fill wipe), {@code damageFlash} 0..1 whitens the
     * fill, {@code nameFlash} 0..1 lerps the name {@code DIM → TEXT}. {@code ghostProgress}
     * ≥ {@code progress} draws the trailing damage segment between the two.
     */
    private static void drawBar(GuiGraphics guiGraphics, int x, int y, String theme,
            float progress, float ghostProgress, float glowAlpha, @Nullable Component name, float alpha,
            @Nullable BossEvent.BossBarColor barColor, @Nullable BossEvent.BossBarOverlay overlay,
            float entrance, float damageFlash, float nameFlash, long now) {
        float ease = easeOutCubic(entrance);
        y += Math.round(-6.0F * (1.0F - ease));
        alpha = Mth.clamp(alpha, 0.0F, 1.0F) * ease;
        if (alpha < 0.02F) {
            return;
        }
        boolean slim = EclipseClientConfig.bossbarStyle() == EclipseClientConfig.BossbarStyle.SLIM;
        int fillY = y + FILL_OFFSET_Y;
        // Entrance wipe: the fill sweeps L→R while the chrome fades in.
        float wiped = Mth.clamp(progress, 0.0F, 1.0F) * ease;
        float wipedGhost = Mth.clamp(Math.max(ghostProgress, progress), 0.0F, 1.0F) * ease;
        int fillWidth = Math.round(FILL_WIDTH * wiped);
        int ghostWidth = Math.round(FILL_WIDTH * wipedGhost);

        // Phase-color tint: boss-themed bars follow the server's bar color (WHITE = no tint);
        // the damage flash lerps the tint toward pure white.
        boolean bossTheme = S2CBossbarStylePayload.THEME_BOSS.equals(theme);
        int tint = bossTheme && barColor != null ? barColorRgb(barColor) : 0xFFFFFF;
        float tintRed = Mth.lerp(damageFlash, ((tint >> 16) & 0xFF) / 255.0F, 1.0F);
        float tintGreen = Mth.lerp(damageFlash, ((tint >> 8) & 0xFF) / 255.0F, 1.0F);
        float tintBlue = Mth.lerp(damageFlash, (tint & 0xFF) / 255.0F, 1.0F);

        RenderSystem.enableBlend();
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        if (slim) {
            drawSlimBody(guiGraphics, x, y, fillY, theme, fillWidth, ghostWidth, tint, damageFlash,
                    alpha, bossTheme, now);
        } else {
            drawOrnateBody(guiGraphics, x, y, fillY, theme, fillWidth, ghostWidth,
                    tintRed, tintGreen, tintBlue, damageFlash, alpha, bossTheme, now);
        }
        // Phase notches: a thin dark tick at every notch fraction of the fill window.
        int notches = notchCount(overlay);
        if (notches > 1) {
            guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F); // fill() colors carry their own alpha
            int notchColor = ((int) (0.85F * alpha * 255.0F) << 24) | 0x140A24;
            for (int notch = 1; notch < notches; notch++) {
                int markX = x + Math.round(FILL_WIDTH * notch / (float) notches);
                guiGraphics.fill(markX, fillY, markX + 1, fillY + FILL_HEIGHT, notchColor);
            }
        }
        // Leading-edge glow (flashes via glowAlpha on progress rises), phase/damage-tinted.
        float edgeGlow = Math.max(glowAlpha, damageFlash);
        if (fillWidth > 0 && edgeGlow > 0.02F) {
            guiGraphics.setColor(tintRed, tintGreen, tintBlue, Mth.clamp(edgeGlow, 0.0F, 1.0F) * alpha);
            int glowSize = slim ? 10 : 14;
            guiGraphics.blit(GLOW, x + fillWidth - glowSize / 2, fillY + FILL_HEIGHT / 2 - glowSize / 2,
                    glowSize, glowSize, 0.0F, 0.0F, 64, 64, 64, 64);
        }
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.disableBlend();

        drawNameBand(guiGraphics, x, fillY, name, alpha, nameFlash);
    }

    /** ORNATE body: textured track/fill/scroll, damage ghost, themed frame, boss breathing. */
    private static void drawOrnateBody(GuiGraphics guiGraphics, int x, int y, int fillY, String theme,
            int fillWidth, int ghostWidth, float tintRed, float tintGreen, float tintBlue,
            float damageFlash, float alpha, boolean bossTheme, long now) {
        // Empty track: the fill strip darkened to a faint violet bed.
        guiGraphics.setColor(0.28F, 0.22F, 0.36F, 0.85F * alpha);
        guiGraphics.blit(FILL, x, fillY, FILL_WIDTH, FILL_HEIGHT, 0.0F, 0.0F, 512, 32, 512, 32);
        if (fillWidth > 0) {
            guiGraphics.setColor(tintRed, tintGreen, tintBlue, alpha);
            if (!EclipseClientConfig.reducedFx() && fillAnimPresent()) {
                // 4-frame animated sheet: 512x128, one 512x32 frame every 8 ticks.
                int frame = (int) ((now / ANIM_FRAME_MILLIS) % 4L);
                guiGraphics.blit(FILL_ANIM, x, fillY, fillWidth, FILL_HEIGHT, 0.0F, frame * 32.0F,
                        Math.round(512.0F * fillWidth / FILL_WIDTH), 32, 512, 128);
                drawScrollOverlay(guiGraphics, x, fillY, fillWidth, 12L);
            } else {
                guiGraphics.blit(FILL, x, fillY, fillWidth, FILL_HEIGHT, 0.0F, 0.0F,
                        Math.round(512.0F * fillWidth / FILL_WIDTH), 32, 512, 32);
                drawScrollOverlay(guiGraphics, x, fillY, fillWidth, 12L);
                if (!EclipseClientConfig.reducedFx()) {
                    // Procedural fill_anim fallback: second energy pass at half speed.
                    guiGraphics.setColor(tintRed, tintGreen, tintBlue, 0.45F * alpha);
                    drawScrollOverlay(guiGraphics, x, fillY, fillWidth, 24L);
                }
            }
        }
        // fill()-based passes below carry their own alpha — reset the shader tint first.
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        drawGhostSegment(guiGraphics, x, fillY, fillWidth, ghostWidth, alpha);
        if (damageFlash > 0.0F && fillWidth > 0) {
            guiGraphics.fill(x, fillY, x + fillWidth, fillY + FILL_HEIGHT,
                    ((int) (0.55F * damageFlash * alpha * 255.0F) << 24) | 0xFFFFFF);
        }
        // Themed frame on top of the fill.
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
        guiGraphics.blit(frameTexture(theme), x + FRAME_OFFSET_X, y + FRAME_OFFSET_Y,
                FRAME_WIDTH, FRAME_HEIGHT, 0.0F, 0.0F, 512, 64, 512, 64);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        if (bossTheme && !EclipseClientConfig.reducedFx()) {
            float breathe = 0.22F + 0.16F * Mth.sin(now * (Mth.TWO_PI / BREATHE_PERIOD_MILLIS));
            drawFrameOutline(guiGraphics, x + FRAME_OFFSET_X - 1, y + FRAME_OFFSET_Y - 1,
                    FRAME_WIDTH + 2, FRAME_HEIGHT + 2,
                    ((int) (breathe * alpha * 255.0F) << 24) | (EclipseUiTheme.DANGER & 0xFFFFFF));
        }
    }

    /** SLIM body (§3.5): frameless rounded Quiet-Eclipse strip rendered from pure fills. */
    private static void drawSlimBody(GuiGraphics guiGraphics, int x, int y, int fillY, String theme,
            int fillWidth, int ghostWidth, int bossTint, float damageFlash, float alpha,
            boolean bossTheme, long now) {
        int accent = bossTheme ? bossTint : switch (theme) {
            case S2CBossbarStylePayload.THEME_GOAL -> 0x9AF0E0;
            case S2CBossbarStylePayload.THEME_BOSS -> EclipseUiTheme.DANGER & 0xFFFFFF;
            default -> EclipseUiTheme.ACCENT & 0xFFFFFF;
        };
        int fillRgb = lerpRgb(accent, 0xFFFFFF, damageFlash);
        int bedColor = ((int) (0.88F * alpha * 255.0F) << 24) | 0x140A24;
        // Rounded bed (1px cut corners) + hairline outline that breathes on boss bars.
        fillRounded(guiGraphics, x, fillY, FILL_WIDTH, FILL_HEIGHT, bedColor);
        float outlineAlpha = alpha;
        int outlineRgb = EclipseUiTheme.HAIRLINE & 0xFFFFFF;
        if (bossTheme && !EclipseClientConfig.reducedFx()) {
            outlineAlpha = alpha * (0.55F + 0.45F * (0.5F + 0.5F * Mth.sin(now * (Mth.TWO_PI / BREATHE_PERIOD_MILLIS))));
            outlineRgb = lerpRgb(outlineRgb, accent, 0.6F);
        }
        drawFrameOutline(guiGraphics, x - 1, fillY - 1, FILL_WIDTH + 2, FILL_HEIGHT + 2,
                ((int) (outlineAlpha * 255.0F) << 24) | outlineRgb);
        if (fillWidth > 0) {
            fillRounded(guiGraphics, x, fillY, fillWidth, FILL_HEIGHT,
                    ((int) (alpha * 255.0F) << 24) | fillRgb);
            // Scroll energy on top of the flat fill (kept subtle for the quiet look).
            guiGraphics.setColor(1.0F, 1.0F, 1.0F, 0.5F * alpha);
            drawScrollOverlay(guiGraphics, x, fillY, fillWidth, 12L);
            if (!EclipseClientConfig.reducedFx()) {
                guiGraphics.setColor(1.0F, 1.0F, 1.0F, 0.25F * alpha);
                drawScrollOverlay(guiGraphics, x, fillY, fillWidth, 24L);
            }
            guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        }
        drawGhostSegment(guiGraphics, x, fillY, fillWidth, ghostWidth, alpha);
        if (damageFlash > 0.0F && fillWidth > 0) {
            guiGraphics.fill(x, fillY, x + fillWidth, fillY + FILL_HEIGHT,
                    ((int) (0.55F * damageFlash * alpha * 255.0F) << 24) | 0xFFFFFF);
        }
    }

    /** Trailing damage ghost: pale segment between the lerped fill edge and the pre-drop level. */
    private static void drawGhostSegment(GuiGraphics guiGraphics, int x, int fillY,
            int fillWidth, int ghostWidth, float alpha) {
        if (ghostWidth > fillWidth) {
            guiGraphics.fill(x + fillWidth, fillY, x + ghostWidth, fillY + FILL_HEIGHT,
                    ((int) (0.45F * alpha * 255.0F) << 24) | (EclipseUiTheme.DANGER & 0xFFFFFF));
        }
    }

    /** In-band name line (§3.5): subtle scrim + centered text, DIM → TEXT flash on change. */
    private static void drawNameBand(GuiGraphics guiGraphics, int x, int fillY,
            @Nullable Component name, float alpha, float nameFlash) {
        int alphaByte = (int) (alpha * 255.0F);
        if (name == null || alphaByte < 8) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();
        int nameWidth = minecraft.font.width(name);
        int centerX = x + FILL_WIDTH / 2;
        int textX = centerX - nameWidth / 2;
        int textY = fillY - 1;
        // Scrim keeps the line readable over the animated fill at guiScale 2/3.
        guiGraphics.fill(textX - 3, textY - 1, textX + nameWidth + 3, textY + 9,
                ((int) (0.4F * alpha * 255.0F) << 24));
        int rgb = lerpRgb(EclipseUiTheme.DIM & 0xFFFFFF, EclipseUiTheme.TEXT & 0xFFFFFF, nameFlash);
        guiGraphics.drawString(minecraft.font, name, textX, textY, (alphaByte << 24) | rgb);
    }

    /** Scrolling energy streaks clipped to the filled width; segments avoid UV wrap-around. */
    private static void drawScrollOverlay(GuiGraphics guiGraphics, int x, int fillY, int fillWidth,
            long millisPerPx) {
        // 2 texels per logical px -> the 256px texture repeats every SCROLL_PERIOD logical px.
        int scroll = (int) ((Util.getMillis() / millisPerPx) % SCROLL_PERIOD);
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

    /** 1px rectangle outline from four fills (breathing frame glow, SLIM hairline). */
    private static void drawFrameOutline(GuiGraphics guiGraphics, int x, int y, int width, int height,
            int color) {
        guiGraphics.fill(x, y, x + width, y + 1, color);
        guiGraphics.fill(x, y + height - 1, x + width, y + height, color);
        guiGraphics.fill(x, y + 1, x + 1, y + height - 1, color);
        guiGraphics.fill(x + width - 1, y + 1, x + width, y + height - 1, color);
    }

    /** Filled rect with 1px cut corners — the SLIM "rounded" strip primitive. */
    private static void fillRounded(GuiGraphics guiGraphics, int x, int y, int width, int height,
            int color) {
        if (width <= 2) {
            guiGraphics.fill(x, y + 1, x + width, y + height - 1, color);
            return;
        }
        guiGraphics.fill(x + 1, y, x + width - 1, y + height, color);
        guiGraphics.fill(x, y + 1, x + 1, y + height - 1, color);
        guiGraphics.fill(x + width - 1, y + 1, x + width, y + height - 1, color);
    }

    /** §3.5 generalized phase ticks: notch count per vanilla overlay (0 = plain progress). */
    private static int notchCount(@Nullable BossEvent.BossBarOverlay overlay) {
        if (overlay == null) {
            return 0;
        }
        return switch (overlay) {
            case NOTCHED_6 -> 6;
            case NOTCHED_10 -> 10;
            case NOTCHED_12 -> 12;
            case NOTCHED_20 -> 20;
            default -> 0;
        };
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

    /** Component-wise RGB lerp (no alpha). */
    private static int lerpRgb(int from, int to, float t) {
        t = Mth.clamp(t, 0.0F, 1.0F);
        int red = (int) Mth.lerp(t, (from >> 16) & 0xFF, (to >> 16) & 0xFF);
        int green = (int) Mth.lerp(t, (from >> 8) & 0xFF, (to >> 8) & 0xFF);
        int blue = (int) Mth.lerp(t, from & 0xFF, to & 0xFF);
        return (red << 16) | (green << 8) | blue;
    }

    private static float easeOutCubic(float t) {
        float inv = 1.0F - Mth.clamp(t, 0.0F, 1.0F);
        return 1.0F - inv * inv * inv;
    }

    /** Live probe for the P2 {@code fill_anim.png} sheet; re-probed every ~5 s (see tick). */
    private static boolean fillAnimPresent() {
        if (fillAnimProbe == 0) {
            fillAnimProbe = Minecraft.getInstance().getResourceManager().getResource(FILL_ANIM).isPresent()
                    ? 1 : 2;
        }
        return fillAnimProbe == 1;
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
        if (Minecraft.getInstance().player == null || Minecraft.getInstance().player.tickCount % 100 != 0) {
            return;
        }
        fillAnimProbe = 0; // re-probe the P2 sheet every ~5 s (picks up resource reloads)
        if (SKINNED.isEmpty()) {
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
