package dev.projecteclipse.eclipse.client.hud;

import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;
import java.util.UUID;

import javax.annotation.Nullable;

import com.mojang.blaze3d.systems.RenderSystem;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
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
 *       P2 asset) replaces the single tinted fill when present. A10 replaced the old
 *       scrolling color sweep with a quiet fill dressing: 1px top-highlight/bottom-shade
 *       edges plus a single 1px highlight column scanning the filled width.</li>
 *   <li><b>Damage flash + micro-shake</b>: a progress DROP &gt; {@value #DAMAGE_DROP_THRESHOLD}
 *       flashes the fill white for ~3 ticks and shakes the frame ±1px (A10 halved the v3
 *       amplitude); a trailing "damage ghost" segment lingers behind the lerped fill and
 *       drains after a short hold. Progress RISES keep the v2 soft leading-edge glow
 *       flash.</li>
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
 *   <li><b>Hit glow, not idle pulse (A10)</b>: the v3 3-second breathing hairline is gone —
 *       a {@code boss}-themed bar's outer hairline only glows for ~1 s after a real
 *       damage event, then rests. Premium, not noisy.</li>
 *   <li><b>Bar cap (A10, "zu viele bossbars")</b>: at most {@value #MAX_VISIBLE_BARS}
 *       skinned bars render at once; further skinned bars collapse into a single
 *       "+N more" overflow counter row directly under the visible stack (their
 *       {@link BarState} lerps stay warm so un-hiding never jumps). Unmatched vanilla
 *       bars are never hidden.</li>
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
    /** P2 asset (512x128, 4 frames of 512x32); probed live, plain fill until it lands. */
    private static final ResourceLocation FILL_ANIM = texture("fill_anim");
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
    /** ORNATE fill tuck: the fill slides this far under each end cap so no seam shows. */
    private static final int FILL_TUCK = 2;
    /**
     * A10 smoother fill lerp: the displayed progress approaches the real progress on a
     * time-based exponential with this time constant (settles in ~1 s, eases out instead
     * of the old constant-speed per-frame clamp — frame-rate independent).
     */
    private static final float FILL_LERP_TAU_MILLIS = 250.0F;
    /** End-cap flash duration after a progress rise. */
    private static final long FLASH_MILLIS = 400L;
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
    /** Micro-shake amplitude on damage (logical px; A10 halved the v3 ±2px). */
    private static final float SHAKE_PX = 1.0F;
    /** The damage ghost holds this long before draining toward the lerped fill. */
    private static final long GHOST_HOLD_MILLIS = 200L;
    /** Ghost drain per SECOND once the hold elapsed (time-based, ≈ the old 0.01/frame @60fps). */
    private static final float GHOST_DRAIN_PER_SECOND = 0.6F;
    /** Name flashes DIM → TEXT for this long after the bar name changes. */
    private static final long NAME_FLASH_MILLIS = 600L;
    /** A10 hit glow: the boss-theme hairline fades out over this long after a damage event. */
    private static final long DAMAGE_GLOW_MILLIS = 1_000L;
    /** A10 fill dressing: the 1px highlight column crosses the full bar width per period. */
    private static final long SCAN_PERIOD_MILLIS = 2_600L;
    /** fill_anim sheet: 4 frames, 8 ticks (400 ms) each. */
    private static final long ANIM_FRAME_MILLIS = 400L;
    /** A10 cap: at most this many skinned bars render; the rest collapse to "+N more". */
    private static final int MAX_VISIBLE_BARS = 2;
    /** Height reserved for the overflow counter row in the top stack. */
    private static final int OVERFLOW_ROW_HEIGHT = 10;

    /**
     * UIPOLISH bossbar-texture fix ("kaputte Bossbar-Textur"): the 512x64 frame sheets
     * carry BIG ornamental end caps whose art reaches well inside the naive 182px fill
     * window — the fill used to bleed through the semi-transparent caps, and stretching
     * the whole sheet 512x64 → 192x15 squashed the cap art ~1.6x wider than tall. Each
     * theme's measured cap widths (alpha audit of the fill band, tex rows 17..47) drive
     * two fixes in {@link #drawBar}/{@link #drawOrnateBody}: the caps blit at art aspect
     * (64 tex rows → {@value #FRAME_HEIGHT} px, only the plain middle rails stretch) and
     * the fill window insets between them (with a {@value #FILL_TUCK}px tuck under each
     * cap so no seam shows). SLIM and the minimal strip have no frame and keep the full
     * 182px window.
     */
    private record FrameMetrics(int capLeftTex, int capRightTex) {
        /** Left cap width on screen at art aspect. */
        int capLeftPx() {
            return Math.round(capLeftTex * (float) FRAME_HEIGHT / 64.0F);
        }

        /** Right cap width on screen at art aspect. */
        int capRightPx() {
            return Math.round(capRightTex * (float) FRAME_HEIGHT / 64.0F);
        }
    }

    private static final FrameMetrics GOAL_METRICS = new FrameMetrics(90, 90);
    private static final FrameMetrics BOSS_METRICS = new FrameMetrics(70, 70);
    private static final FrameMetrics DAY_METRICS = new FrameMetrics(118, 118);

    /** Per-skinned-bar client state, keyed by the {@code BossEvent} UUID. Client thread only. */
    private static final Map<UUID, BarState> SKINNED = new HashMap<>();

    /** Geometry observed this frame, so the announcement sweep can stack below real bars. */
    private static long lastBarSeenMillis;
    /** Reset to the vanilla anchor every frame ({@link #onRenderGuiPre}); bars re-stack it. */
    private static int observedBarsBottom = 12;
    /** {@code fill_anim.png} probe: 0 = unknown (re-probe), 1 = present, 2 = absent. */
    private static int fillAnimProbe;
    // --- A10 bar cap, per-frame (reset in onRenderGuiPre, drawn in onRenderGuiPost) ---
    /** Bar rows observed this frame (vanilla ones included — they occupy rows too). */
    private static int barsThisFrame;
    /** Skinned bars collapsed into the overflow counter this frame. */
    private static int hiddenThisFrame;
    /** Y of the overflow counter row (= the row the first hidden bar would have taken). */
    private static int overflowRowY;

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
        /** Last fill-lerp step (A10 time-based smoothing); 0 = fresh entrance. */
        long lastLerpMillis;
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
            this.lastLerpMillis = 0L;
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
     * Y of the next free bossbar slot: below the last bar (or the A10 overflow counter row)
     * rendered within the last ~250 ms, or the vanilla top anchor (12) when nothing is
     * showing. Used by the announcement sweep so it never overlaps real bars. (A7: the day
     * timer left the top stack for its slot above the hotbar — the old
     * {@code reserveOverlayRow} hand-shake is gone with it.)
     */
    public static int nextFreeBarY() {
        return Util.getMillis() - lastBarSeenMillis < 250L ? observedBarsBottom : 12;
    }

    /**
     * Fresh stacking geometry at the top of every GUI frame: the old wall-clock reset
     * (25 ms without a bar event) never fires above 40 fps, so {@code observedBarsBottom}
     * stuck at its historical max until ALL bars vanished. The bar events below re-stack
     * it each frame before the announcement layer reads it. Also resets the A10 bar-cap
     * counters (re-filled by this frame's bar events, drawn from {@link #onRenderGuiPost}).
     */
    @SubscribeEvent
    static void onRenderGuiPre(RenderGuiEvent.Pre event) {
        observedBarsBottom = 12;
        barsThisFrame = 0;
        hiddenThisFrame = 0;
        overflowRowY = 12;
    }

    @SubscribeEvent
    static void onBossEventProgress(CustomizeGuiOverlayEvent.BossEventProgress event) {
        long now = Util.getMillis();
        // Track stacking geometry for ALL bars (vanilla ones included) before any matching.
        lastBarSeenMillis = now;
        barsThisFrame++;

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
        // A10 smoother fill lerp: frame-time-based exponential ease-out toward the actual
        // progress (the old ±0.05/frame clamp moved at constant speed and sped up with fps).
        long stepMillis = state.lastLerpMillis == 0L ? 50L : Math.min(200L, now - state.lastLerpMillis);
        state.lastLerpMillis = now;
        if (state.displayedProgress < 0.0F) {
            state.displayedProgress = actual;
        } else {
            float catchUp = 1.0F - (float) Math.exp(-stepMillis / FILL_LERP_TAU_MILLIS);
            state.displayedProgress += (actual - state.displayedProgress) * catchUp;
        }
        // Trailing damage ghost: hold briefly, then drain toward the lerped fill.
        if (state.ghostProgress > state.displayedProgress) {
            if (now - state.damageStartMillis > GHOST_HOLD_MILLIS) {
                state.ghostProgress = Math.max(state.displayedProgress,
                        state.ghostProgress - GHOST_DRAIN_PER_SECOND * stepMillis / 1_000.0F);
            }
        } else {
            state.ghostProgress = state.displayedProgress;
        }
        state.lastColor = bar.getColor();
        state.lastOverlay = bar.getOverlay();

        // A10 bar cap ("zu viele bossbars"): rows beyond MAX_VISIBLE_BARS collapse into one
        // "+N more" counter row (drawn from onRenderGuiPost, after all bar events counted).
        // The bookkeeping above stays warm so an un-hidden bar resumes with a current fill.
        if (barsThisFrame > MAX_VISIBLE_BARS) {
            event.setCanceled(true);
            event.setIncrement(0); // hidden rows collapse — the stack stays compact
            if (hiddenThisFrame == 0) {
                overflowRowY = event.getY();
                // Reserve the counter row so the announcement sweep stacks below it.
                observedBarsBottom = Math.max(observedBarsBottom, event.getY() + OVERFLOW_ROW_HEIGHT);
            }
            hiddenThisFrame++;
            state.lastX = Integer.MIN_VALUE; // a cap-hidden bar leaves no exit ghost
            return;
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
        // A10: the frame hairline glows ONLY off damage events (no idle breathing) — a
        // slower ease-out than the white flash, so the hit reads without strobing.
        float damageGlow = reduced || state.damageStartMillis == 0L ? 0.0F
                : Mth.clamp(1.0F - (now - state.damageStartMillis) / (float) DAMAGE_GLOW_MILLIS, 0.0F, 1.0F);
        if (!reduced && damageFlash > 0.0F) {
            // Deterministic micro-shake: two incommensurate sines, decaying with the flash.
            x += Math.round(Mth.sin(now * 0.09F) * SHAKE_PX * damageFlash);
            y += Math.round(Mth.cos(now * 0.13F) * SHAKE_PX * 0.5F * damageFlash);
        }
        float nameFlash = state.nameFlashStartMillis == 0L ? 0.0F
                : Mth.clamp(1.0F - (now - state.nameFlashStartMillis) / (float) NAME_FLASH_MILLIS, 0.0F, 1.0F);
        drawBar(guiGraphics, x, y, state.theme, state.displayedProgress, state.ghostProgress,
                glowAlpha, name, alpha, barColor, overlay, entrance, damageFlash, damageGlow,
                nameFlash, now);
    }

    /**
     * Post pass, two jobs: (1) the A10 overflow counter row — "+N more" under the visible
     * stack whenever the bar cap collapsed rows this frame (drawn in every skin mode; the
     * bars are hidden regardless); (2) the exit state machine — tracked bars that stopped
     * firing events within the last {@value #EXIT_MILLIS} ms (after a
     * {@value #EXIT_GRACE_MILLIS} ms grace so low fps never false-triggers) are redrawn
     * from cached geometry as a fading, slightly rising ghost. Ghosts are skipped under
     * the minimal-strip fallback and {@code reducedFx} (exit snaps); everything is skipped
     * under F1 and cutscene HUD suppression.
     */
    @SubscribeEvent
    static void onRenderGuiPost(RenderGuiEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null || minecraft.options.hideGui || CameraDirector.isHudSuppressed()) {
            return;
        }
        if (hiddenThisFrame > 0) {
            drawOverflowRow(event.getGuiGraphics(), minecraft, hiddenThisFrame);
        }
        if (SKINNED.isEmpty() || EclipseClientConfig.reducedFx() || !EclipseClientConfig.showBossbarSkin()) {
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
                    0.9F * fade * fade, state.lastColor, state.lastOverlay, 1.0F, 0.0F, 0.0F, 0.0F, now);
        }
    }

    /** A10 overflow counter: a quiet DIM "+N more" line where the first hidden bar would sit. */
    private static void drawOverflowRow(GuiGraphics guiGraphics, Minecraft minecraft, int hidden) {
        Component label = EclipseLang.tr("gui.eclipse.bossbar.more", hidden);
        int width = minecraft.font.width(label);
        int x = (guiGraphics.guiWidth() - width) / 2;
        // Same subtle scrim treatment as the in-band name line, for guiScale-2/3 legibility.
        guiGraphics.fill(x - 3, overflowRowY - 1, x + width + 3, overflowRowY + 9, 0x66000000);
        guiGraphics.drawString(minecraft.font, label, x, overflowRowY, EclipseUiTheme.DIM);
    }

    /**
     * Shared skinned-bar body, also used by {@link AnnouncementOverlay}'s client-local sweep:
     * track, lerped fill, A10 fill dressing, chrome (ORNATE frame / SLIM strip),
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
                1.0F, 0.0F, 0.0F, 1.0F, Util.getMillis());
    }

    /**
     * The one master renderer behind every skinned look. {@code entrance} 0..1 drives the
     * drop-in (y offset, alpha ramp, L→R fill wipe), {@code damageFlash} 0..1 whitens the
     * fill, {@code damageGlow} 0..1 drives the A10 post-hit hairline glow (the only frame
     * "pulse" left), {@code nameFlash} 0..1 lerps the name {@code DIM → TEXT}.
     * {@code ghostProgress} ≥ {@code progress} draws the trailing damage segment between
     * the two.
     */
    private static void drawBar(GuiGraphics guiGraphics, int x, int y, String theme,
            float progress, float ghostProgress, float glowAlpha, @Nullable Component name, float alpha,
            @Nullable BossEvent.BossBarColor barColor, @Nullable BossEvent.BossBarOverlay overlay,
            float entrance, float damageFlash, float damageGlow, float nameFlash, long now) {
        float ease = easeOutCubic(entrance);
        y += Math.round(-6.0F * (1.0F - ease));
        alpha = Mth.clamp(alpha, 0.0F, 1.0F) * ease;
        if (alpha < 0.02F) {
            return;
        }
        boolean slim = EclipseClientConfig.bossbarStyle() == EclipseClientConfig.BossbarStyle.SLIM;
        int fillY = y + FILL_OFFSET_Y;
        // ORNATE fill window: inset between the frame's ornamental end caps (see
        // FrameMetrics) so the fill never bleeds through the cap art; SLIM keeps the
        // frameless full-width strip.
        int barX = x;
        int barWidth = FILL_WIDTH;
        if (!slim) {
            FrameMetrics metrics = frameMetrics(theme);
            barX = x + FRAME_OFFSET_X + metrics.capLeftPx() - FILL_TUCK;
            barWidth = FRAME_WIDTH - metrics.capLeftPx() - metrics.capRightPx() + 2 * FILL_TUCK;
        }
        // Entrance wipe: the fill sweeps L→R while the chrome fades in.
        float wiped = Mth.clamp(progress, 0.0F, 1.0F) * ease;
        float wipedGhost = Mth.clamp(Math.max(ghostProgress, progress), 0.0F, 1.0F) * ease;
        int fillWidth = Math.round(barWidth * wiped);
        int ghostWidth = Math.round(barWidth * wipedGhost);

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
                    damageGlow, alpha, bossTheme, now);
        } else {
            drawOrnateBody(guiGraphics, x, y, fillY, theme, barX, barWidth, fillWidth, ghostWidth,
                    tintRed, tintGreen, tintBlue, damageFlash, damageGlow, alpha, bossTheme, now);
        }
        // Phase notches: a thin dark tick at every notch fraction of the fill window.
        int notches = notchCount(overlay);
        if (notches > 1) {
            guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F); // fill() colors carry their own alpha
            int notchColor = ((int) (0.85F * alpha * 255.0F) << 24) | 0x140A24;
            for (int notch = 1; notch < notches; notch++) {
                int markX = barX + Math.round(barWidth * notch / (float) notches);
                guiGraphics.fill(markX, fillY, markX + 1, fillY + FILL_HEIGHT, notchColor);
            }
        }
        // Leading-edge glow (flashes via glowAlpha on progress rises), phase/damage-tinted.
        float edgeGlow = Math.max(glowAlpha, damageFlash);
        if (fillWidth > 0 && edgeGlow > 0.02F) {
            guiGraphics.setColor(tintRed, tintGreen, tintBlue, Mth.clamp(edgeGlow, 0.0F, 1.0F) * alpha);
            int glowSize = slim ? 10 : 14;
            guiGraphics.blit(GLOW, barX + fillWidth - glowSize / 2, fillY + FILL_HEIGHT / 2 - glowSize / 2,
                    glowSize, glowSize, 0.0F, 0.0F, 64, 64, 64, 64);
        }
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        RenderSystem.disableBlend();

        drawNameBand(guiGraphics, x, fillY, name, alpha, nameFlash);
    }

    /**
     * ORNATE body: textured track/fill inside the cap-inset window, quiet fill dressing,
     * damage ghost, themed frame. The frame blits in THREE slices (see {@link FrameMetrics}):
     * both end caps at art aspect, only the plain middle rails stretched between them —
     * the old single 512x64 → 192x15 stretch squashed the cap art into mush.
     */
    private static void drawOrnateBody(GuiGraphics guiGraphics, int x, int y, int fillY, String theme,
            int barX, int barWidth, int fillWidth, int ghostWidth,
            float tintRed, float tintGreen, float tintBlue,
            float damageFlash, float damageGlow, float alpha, boolean bossTheme, long now) {
        // Empty track: the fill strip darkened to a faint violet bed.
        guiGraphics.setColor(0.28F, 0.22F, 0.36F, 0.85F * alpha);
        guiGraphics.blit(FILL, barX, fillY, barWidth, FILL_HEIGHT, 0.0F, 0.0F, 512, 32, 512, 32);
        if (fillWidth > 0) {
            guiGraphics.setColor(tintRed, tintGreen, tintBlue, alpha);
            if (!EclipseClientConfig.reducedFx() && fillAnimPresent()) {
                // 4-frame animated sheet: 512x128, one 512x32 frame every 8 ticks.
                int frame = (int) ((now / ANIM_FRAME_MILLIS) % 4L);
                guiGraphics.blit(FILL_ANIM, barX, fillY, fillWidth, FILL_HEIGHT, 0.0F, frame * 32.0F,
                        Math.round(512.0F * fillWidth / barWidth), 32, 512, 128);
            } else {
                guiGraphics.blit(FILL, barX, fillY, fillWidth, FILL_HEIGHT, 0.0F, 0.0F,
                        Math.round(512.0F * fillWidth / barWidth), 32, 512, 32);
            }
        }
        // fill()-based passes below carry their own alpha — reset the shader tint first.
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        drawFillDressing(guiGraphics, barX, fillY, fillWidth, barWidth, alpha, now);
        drawGhostSegment(guiGraphics, barX, fillY, fillWidth, ghostWidth, alpha);
        if (damageFlash > 0.0F && fillWidth > 0) {
            guiGraphics.fill(barX, fillY, barX + fillWidth, fillY + FILL_HEIGHT,
                    ((int) (0.55F * damageFlash * alpha * 255.0F) << 24) | 0xFFFFFF);
        }
        // Themed frame on top of the fill: caps at art aspect, middle rails stretched.
        FrameMetrics metrics = frameMetrics(theme);
        ResourceLocation frame = frameTexture(theme);
        int frameX = x + FRAME_OFFSET_X;
        int frameY = y + FRAME_OFFSET_Y;
        int capLeft = metrics.capLeftPx();
        int capRight = metrics.capRightPx();
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
        guiGraphics.blit(frame, frameX, frameY, capLeft, FRAME_HEIGHT,
                0.0F, 0.0F, metrics.capLeftTex(), 64, 512, 64);
        guiGraphics.blit(frame, frameX + capLeft, frameY,
                FRAME_WIDTH - capLeft - capRight, FRAME_HEIGHT,
                metrics.capLeftTex(), 0.0F, 512 - metrics.capLeftTex() - metrics.capRightTex(), 64,
                512, 64);
        guiGraphics.blit(frame, frameX + FRAME_WIDTH - capRight, frameY, capRight, FRAME_HEIGHT,
                512 - metrics.capRightTex(), 0.0F, metrics.capRightTex(), 64, 512, 64);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        if (bossTheme && damageGlow > 0.0F && !EclipseClientConfig.reducedFx()) {
            // A10: no idle breathing — the outer hairline only glows after a hit, fading ~1 s.
            drawFrameOutline(guiGraphics, frameX - 1, frameY - 1,
                    FRAME_WIDTH + 2, FRAME_HEIGHT + 2,
                    ((int) (0.38F * damageGlow * alpha * 255.0F) << 24) | (EclipseUiTheme.DANGER & 0xFFFFFF));
        }
    }

    /** SLIM body (§3.5): frameless rounded Quiet-Eclipse strip rendered from pure fills. */
    private static void drawSlimBody(GuiGraphics guiGraphics, int x, int y, int fillY, String theme,
            int fillWidth, int ghostWidth, int bossTint, float damageFlash, float damageGlow,
            float alpha, boolean bossTheme, long now) {
        int accent = bossTheme ? bossTint : switch (theme) {
            case S2CBossbarStylePayload.THEME_GOAL -> 0x9AF0E0;
            case S2CBossbarStylePayload.THEME_BOSS -> EclipseUiTheme.DANGER & 0xFFFFFF;
            default -> EclipseUiTheme.ACCENT & 0xFFFFFF;
        };
        int fillRgb = lerpRgb(accent, 0xFFFFFF, damageFlash);
        int bedColor = ((int) (0.88F * alpha * 255.0F) << 24) | 0x140A24;
        // Rounded bed (1px cut corners) + the steady EclipseUiTheme panel hairline. A10:
        // the outline no longer breathes — it only warms toward the accent after a hit.
        fillRounded(guiGraphics, x, fillY, FILL_WIDTH, FILL_HEIGHT, bedColor);
        int outlineRgb = EclipseUiTheme.HAIRLINE & 0xFFFFFF;
        if (bossTheme && damageGlow > 0.0F && !EclipseClientConfig.reducedFx()) {
            outlineRgb = lerpRgb(outlineRgb, accent, 0.6F * damageGlow);
        }
        drawFrameOutline(guiGraphics, x - 1, fillY - 1, FILL_WIDTH + 2, FILL_HEIGHT + 2,
                ((int) (alpha * 255.0F) << 24) | outlineRgb);
        if (fillWidth > 0) {
            fillRounded(guiGraphics, x, fillY, fillWidth, FILL_HEIGHT,
                    ((int) (alpha * 255.0F) << 24) | fillRgb);
            drawFillDressing(guiGraphics, x, fillY, fillWidth, FILL_WIDTH, alpha, now);
        }
        drawGhostSegment(guiGraphics, x, fillY, fillWidth, ghostWidth, alpha);
        if (damageFlash > 0.0F && fillWidth > 0) {
            guiGraphics.fill(x, fillY, x + fillWidth, fillY + FILL_HEIGHT,
                    ((int) (0.55F * damageFlash * alpha * 255.0F) << 24) | 0xFFFFFF);
        }
    }

    /**
     * A10 fill dressing — replaces the v3 scrolling color sweep. Static edge treatment
     * (1px top highlight, 1px bottom shade — a quiet scanline read that keeps the fill
     * dimensional) plus a single 1px highlight column scanning the filled width every
     * {@value #SCAN_PERIOD_MILLIS} ms. {@code reducedFx} keeps the edges, drops the scan.
     * {@code barWidth} is the full fill-window width (the scan crosses it per period).
     */
    private static void drawFillDressing(GuiGraphics guiGraphics, int x, int fillY, int fillWidth,
            int barWidth, float alpha, long now) {
        if (fillWidth <= 0) {
            return;
        }
        guiGraphics.fill(x, fillY, x + fillWidth, fillY + 1,
                ((int) (0.14F * alpha * 255.0F) << 24) | 0xFFFFFF);
        guiGraphics.fill(x, fillY + FILL_HEIGHT - 1, x + fillWidth, fillY + FILL_HEIGHT,
                ((int) (0.30F * alpha * 255.0F) << 24) | 0x0A0512);
        if (EclipseClientConfig.reducedFx()) {
            return;
        }
        int scanX = x + (int) (now % SCAN_PERIOD_MILLIS * barWidth / SCAN_PERIOD_MILLIS);
        if (scanX < x + fillWidth) {
            guiGraphics.fill(scanX, fillY, scanX + 1, fillY + FILL_HEIGHT,
                    ((int) (0.22F * alpha * 255.0F) << 24) | 0xFFFFFF);
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

    /** Measured end-cap metrics of a theme's frame sheet (see {@link FrameMetrics}). */
    private static FrameMetrics frameMetrics(String theme) {
        return switch (theme) {
            case S2CBossbarStylePayload.THEME_GOAL -> GOAL_METRICS;
            case S2CBossbarStylePayload.THEME_BOSS -> BOSS_METRICS;
            default -> DAY_METRICS;
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
