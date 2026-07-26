package dev.projecteclipse.eclipse.client.hud;

import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;
import java.util.UUID;

import javax.annotation.Nullable;

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
 * <p><b>Everything is drawn procedurally</b> (A11, "komische Glitch Texturen"). The bar used
 * to blit 512x64 ornament sheets down to 192x15; GUI textures sample with {@code GL_NEAREST}
 * and no mipmaps, so that 4.27x minification point-sampled every ~4th texel row of dense
 * filigree and produced the speckled, AI-artefact-looking mush players reported. There is no
 * texture sampling left in this class at all — track, fill, edges, ticks and the leading-edge
 * glow are {@code fill}/{@code fillGradient} rectangles, which are resolution-exact at every
 * GUI scale. All geometry is centred on {@code guiGraphics.guiWidth() / 2}.</p>
 *
 * <p><b>v3 juice</b> (all {@code reducedFx}-gated, applies to all themes and both
 * {@code bossbarStyle} variants):</p>
 * <ul>
 *   <li><b>Entrance/exit state machine</b>: first sighting of a bar UUID → 8-tick slide-in
 *       ({@value #SLIDE_PX}px up into place, alpha 0→1, fill wipes L→R). Tracked bars that
 *       stop rendering → 6-tick fade-out ghost drawn from a {@link RenderGuiEvent.Post} pass
 *       (the bar no longer fires events, so the ghost is redrawn from cached geometry). Both
 *       travel DOWNWARD-to-up / down-and-out so the name line never clips off the top of the
 *       screen. A bar re-seen after &gt; {@value #REENTER_MILLIS} ms without events replays
 *       the entrance.</li>
 *   <li><b>Fill dressing</b>: a vertical {@link BarPalette} gradient with a 1px accent top
 *       highlight and 1px bottom shade, plus a single 1px highlight column scanning the
 *       filled width.</li>
 *   <li><b>Damage flash + micro-shake</b>: a progress DROP &gt; {@value #DAMAGE_DROP_THRESHOLD}
 *       flashes the fill white for ~3 ticks and shakes the frame ±1px (A10 halved the v3
 *       amplitude); a trailing "damage ghost" segment lingers behind the lerped fill and
 *       drains after a short hold. Progress RISES keep the v2 soft leading-edge glow
 *       flash.</li>
 *   <li><b>Phase notches</b>: NOTCHED_6/10/12/20 overlays draw a thin tick at every notch
 *       fraction (v2 hardcoded NOTCHED_6 at thirds).</li>
 *   <li><b>Styles</b>: {@code bossbarStyle=ORNATE} adds the 1px outer/inner edge pair and
 *       small end-cap ticks; {@code SLIM} drops the ticks for a frameless rounded strip.
 *       {@code showBossbarSkin=false} still falls back to the minimal 4px strip — a revive
 *       countdown is NEVER fully hidden.</li>
 *   <li><b>Name line</b> (§2 typography): centred {@value #NAME_OFFSET_Y}px above the bar
 *       with a text shadow ({@code DIM} → {@code TEXT} flash on change), matching the
 *       vanilla name position so the vanilla 19px row increment stays correct.</li>
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
    /** Bar width, matching the vanilla bossbar (the row is centred on {@code guiWidth/2}). */
    private static final int BAR_WIDTH = 182;
    /** Bar band height; the vanilla 19px row increment leaves room for the name line above. */
    private static final int BAR_HEIGHT = 7;
    /** Baseline gap between the name line and the top of the bar (vanilla draws at y−9). */
    private static final int NAME_OFFSET_Y = 10;
    /** Entrance/exit travel: the bar slides UP into place, never off the top of the screen. */
    private static final int SLIDE_PX = 5;
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
    /** Leading-edge glow: accent columns trailing back from the fill head. */
    private static final int GLOW_FALLOFF_PX = 5;
    /** A10 cap: at most this many skinned bars render; the rest collapse to "+N more". */
    private static final int MAX_VISIBLE_BARS = 2;
    /** Height reserved for the overflow counter row in the top stack. */
    private static final int OVERFLOW_ROW_HEIGHT = 10;

    // --- Themes -------------------------------------------------------------------------
    // day/goal/boss arrive over the wire (S2CBossbarStylePayload); the three below are
    // CLIENT-LOCAL refinements picked by AnnouncementOverlay off the announcement's title
    // key, so "Der Altar steigt auf", "Siegel gebrochen" and "Die Welt wächst" each read in
    // their own colour instead of sharing one generic goal skin. Unknown themes fall back
    // to the goal palette, so a future server-side theme string can never render blank.

    /** Altar milestone announcements — gold. */
    public static final String THEME_ALTAR = "altar";
    /** Unlock ("Siegel gebrochen") announcements — violet. */
    public static final String THEME_SEAL = "seal";
    /** World-expansion ("Die Welt wächst") announcements — teal. */
    public static final String THEME_WORLD = "world";

    /**
     * Per-theme colours. {@code fillTop}/{@code fillBottom} are the vertical fill gradient,
     * {@code accent} the bright hairline/tick/leading-edge colour. All plain RGB — the alpha
     * is applied per draw call so a bar can fade as a whole.
     */
    private record BarPalette(int fillTop, int fillBottom, int accent) {}

    private static final BarPalette PALETTE_ALTAR = new BarPalette(0xD4A017, 0x8A6A10, 0xF6DC8A);
    private static final BarPalette PALETTE_SEAL = new BarPalette(0xA45CFF, 0x5C2E99, 0xD8B8FF);
    private static final BarPalette PALETTE_WORLD = new BarPalette(0x3FD9C4, 0x14776C, 0x9CF4E7);
    private static final BarPalette PALETTE_BOSS = new BarPalette(0xE8455C, 0x7A1426, 0xFFA3B0);
    private static final BarPalette PALETTE_GOAL = new BarPalette(0xB98CFF, 0x5B3AA6, 0xE2CDFF);
    private static final BarPalette PALETTE_DAY = new BarPalette(0x9A8FB8, 0x413364, 0xD8CFF0);

    /** 1px outer edge — near-black, seats the bar on bright sky and pale terrain alike. */
    private static final int EDGE_OUTER = 0x05030A;
    /** Empty-track gradient (dark Eclipse violet). */
    private static final int TRACK_TOP = 0x1A1230;
    private static final int TRACK_BOTTOM = 0x0B0718;

    /** Per-skinned-bar client state, keyed by the {@code BossEvent} UUID. Client thread only. */
    private static final Map<UUID, BarState> SKINNED = new HashMap<>();

    /** Geometry observed this frame, so the announcement sweep can stack below real bars. */
    private static long lastBarSeenMillis;
    /** Reset to the vanilla anchor every frame ({@link #onRenderGuiPre}); bars re-stack it. */
    private static int observedBarsBottom = 12;
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
        boolean lastDrawn;
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
            state.lastDrawn = false; // a cap-hidden bar leaves no exit ghost
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
            state.lastDrawn = false; // no exit ghost in minimal mode
            drawMinimalStrip(guiGraphics, event.getY(), state.theme, state.displayedProgress,
                    bar.getColor());
            observedBarsBottom = Math.max(observedBarsBottom, event.getY() + event.getIncrement());
            return;
        }

        state.lastDrawn = true;
        state.lastY = event.getY();
        // The name sits above the bar exactly where vanilla puts it, so the vanilla 19px
        // increment stays correct and stacked bars keep their spacing.
        float flash = state.flashStartMillis == 0L ? 0.0F
                : Mth.clamp(1.0F - (now - state.flashStartMillis) / (float) FLASH_MILLIS, 0.0F, 1.0F);
        drawLiveBar(guiGraphics, event.getY(), state, bar.getName(),
                0.35F + 0.65F * flash, 1.0F, bar.getColor(), bar.getOverlay(), now);
        observedBarsBottom = Math.max(observedBarsBottom, event.getY() + event.getIncrement());
    }

    /** Live (event-driven) bar body: entrance pose, damage shake, then the shared renderer. */
    private static void drawLiveBar(GuiGraphics guiGraphics, int y, BarState state,
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
        int shakeX = 0;
        if (!reduced && damageFlash > 0.0F) {
            // Deterministic micro-shake: two incommensurate sines, decaying with the flash.
            shakeX = Math.round(Mth.sin(now * 0.09F) * SHAKE_PX * damageFlash);
            y += Math.round(Mth.cos(now * 0.13F) * SHAKE_PX * 0.5F * damageFlash);
        }
        float nameFlash = state.nameFlashStartMillis == 0L ? 0.0F
                : Mth.clamp(1.0F - (now - state.nameFlashStartMillis) / (float) NAME_FLASH_MILLIS, 0.0F, 1.0F);
        drawBar(guiGraphics, shakeX, y, state.theme, state.displayedProgress, state.ghostProgress,
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
            if (!state.lastDrawn || state.displayedProgress < 0.0F) {
                continue;
            }
            long age = now - state.lastSeenMillis;
            if (age < EXIT_GRACE_MILLIS || age > EXIT_GRACE_MILLIS + EXIT_MILLIS) {
                continue;
            }
            float fade = 1.0F - (age - EXIT_GRACE_MILLIS) / (float) EXIT_MILLIS;
            // Sinks out (mirror of the slide-in) — rising would clip the name line off-screen
            // for the topmost row, whose name already sits at y = 2.
            int sink = Math.round(SLIDE_PX * (1.0F - fade));
            drawBar(event.getGuiGraphics(), 0, state.lastY + sink, state.theme,
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
    public static void drawThemedBar(GuiGraphics guiGraphics, int y, String theme,
            float progress, float glowAlpha, Component name, float alpha) {
        drawThemedBar(guiGraphics, y, theme, progress, glowAlpha, name, alpha, null, null);
    }

    /**
     * Full skinned-bar body for callers without a tracked {@link BarState}: no entrance,
     * shake or damage state — {@code barColor}/{@code overlay} keep the vanilla telegraphs
     * (phase-color tint, notch overlays). Both may be {@code null} (announcement sweeps).
     */
    public static void drawThemedBar(GuiGraphics guiGraphics, int y, String theme,
            float progress, float glowAlpha, Component name, float alpha,
            @Nullable BossEvent.BossBarColor barColor, @Nullable BossEvent.BossBarOverlay overlay) {
        drawBar(guiGraphics, 0, y, theme, progress, progress, glowAlpha, name, alpha, barColor, overlay,
                1.0F, 0.0F, 0.0F, 1.0F, Util.getMillis());
    }

    /**
     * The one master renderer behind every skinned look — pure {@code fill} /
     * {@code fillGradient} rectangles, no texture sampling at all (see the class javadoc for
     * why). The bar is always centred on {@code guiGraphics.guiWidth() / 2}, so the layout is
     * identical at every GUI scale; {@code shakeX} only carries the damage micro-shake.
     * {@code entrance} 0..1 drives the slide-in (y offset, alpha ramp, L→R fill wipe),
     * {@code damageFlash} 0..1 whitens the fill, {@code damageGlow} 0..1 drives the A10
     * post-hit edge glow, {@code nameFlash} 0..1 lerps the name {@code DIM → TEXT}.
     * {@code ghostProgress} ≥ {@code progress} draws the trailing damage segment between the two.
     */
    private static void drawBar(GuiGraphics guiGraphics, int shakeX, int y, String theme,
            float progress, float ghostProgress, float glowAlpha, @Nullable Component name, float alpha,
            @Nullable BossEvent.BossBarColor barColor, @Nullable BossEvent.BossBarOverlay overlay,
            float entrance, float damageFlash, float damageGlow, float nameFlash, long now) {
        float ease = easeOutCubic(entrance);
        y += Math.round(SLIDE_PX * (1.0F - ease));
        alpha = Mth.clamp(alpha, 0.0F, 1.0F) * ease;
        if (alpha < 0.02F) {
            return;
        }
        boolean slim = EclipseClientConfig.bossbarStyle() == EclipseClientConfig.BossbarStyle.SLIM;
        int barX = guiGraphics.guiWidth() / 2 - BAR_WIDTH / 2 + shakeX;
        int bottom = y + BAR_HEIGHT;

        // Phase telegraphs survive: a boss-themed bar follows the server's BossBarColor
        // (the Ferryman's WHITE/PURPLE/RED phase swaps); everything else uses its theme.
        boolean bossTheme = S2CBossbarStylePayload.THEME_BOSS.equals(theme);
        BarPalette palette = palette(theme, bossTheme ? barColor : null);
        int accent = palette.accent();
        int fillTop = lerpRgb(palette.fillTop(), 0xFFFFFF, damageFlash);
        int fillBottom = lerpRgb(palette.fillBottom(), 0xFFFFFF, damageFlash);

        // Entrance wipe: the fill sweeps L→R while the chrome fades in.
        float wiped = Mth.clamp(progress, 0.0F, 1.0F) * ease;
        float wipedGhost = Mth.clamp(Math.max(ghostProgress, progress), 0.0F, 1.0F) * ease;
        int fillWidth = Math.round(BAR_WIDTH * wiped);
        int ghostWidth = Math.round(BAR_WIDTH * wipedGhost);

        // 1px outer dark edge: seats the bar on bright sky as well as on dark caves.
        drawFrameOutline(guiGraphics, barX - 1, y - 1, BAR_WIDTH + 2, BAR_HEIGHT + 2,
                argb(EDGE_OUTER, 0.90F * alpha));
        // Empty track, then the fill — both vertical gradients.
        if (slim) {
            gradientRounded(guiGraphics, barX, y, BAR_WIDTH, BAR_HEIGHT,
                    argb(TRACK_TOP, 0.88F * alpha), argb(TRACK_BOTTOM, 0.88F * alpha));
        } else {
            guiGraphics.fillGradient(barX, y, barX + BAR_WIDTH, bottom,
                    argb(TRACK_TOP, 0.85F * alpha), argb(TRACK_BOTTOM, 0.85F * alpha));
        }
        if (fillWidth > 0) {
            if (slim) {
                gradientRounded(guiGraphics, barX, y, fillWidth, BAR_HEIGHT,
                        argb(fillTop, alpha), argb(fillBottom, alpha));
            } else {
                guiGraphics.fillGradient(barX, y, barX + fillWidth, bottom,
                        argb(fillTop, alpha), argb(fillBottom, alpha));
            }
            drawFillDressing(guiGraphics, barX, y, fillWidth, accent, alpha, now);
        }
        drawGhostSegment(guiGraphics, barX, y, fillWidth, ghostWidth, alpha);
        if (damageFlash > 0.0F && fillWidth > 0) {
            guiGraphics.fill(barX, y, barX + fillWidth, bottom,
                    argb(0xFFFFFF, 0.55F * damageFlash * alpha));
        }
        // Phase notches: a thin dark tick at every notch fraction, inset so it does not
        // fight the inner edge drawn below.
        int notches = notchCount(overlay);
        if (notches > 1) {
            int notchColor = argb(EDGE_OUTER, 0.80F * alpha);
            for (int notch = 1; notch < notches; notch++) {
                int markX = barX + Math.round(BAR_WIDTH * notch / (float) notches);
                guiGraphics.fill(markX, y + 1, markX + 1, bottom - 1, notchColor);
            }
        }
        // 1px inner light edge, tinted by the theme — an EMPTY bar still reads as
        // altar/seal/world/boss instead of a generic grey slot. A10: only a boss bar's edge
        // brightens, and only for ~1 s after a real hit (no idle breathing).
        float edgeAlpha = 0.34F + 0.40F * (bossTheme ? damageGlow : 0.0F);
        drawFrameOutline(guiGraphics, barX, y, BAR_WIDTH, BAR_HEIGHT, argb(accent, edgeAlpha * alpha));
        if (!slim) {
            drawEndTicks(guiGraphics, barX, y, accent, alpha);
        }
        drawLeadingEdge(guiGraphics, barX, y, fillWidth, accent,
                Math.max(glowAlpha, damageFlash), alpha);
        drawName(guiGraphics, y, name, alpha, nameFlash);
    }

    /**
     * Fill dressing: a 1px accent top highlight and 1px bottom shade that keep the gradient
     * dimensional, plus a single 1px highlight column scanning the filled width every
     * {@value #SCAN_PERIOD_MILLIS} ms. {@code reducedFx} keeps the edges, drops the scan.
     */
    private static void drawFillDressing(GuiGraphics guiGraphics, int barX, int y, int fillWidth,
            int accent, float alpha, long now) {
        if (fillWidth <= 0) {
            return;
        }
        int bottom = y + BAR_HEIGHT;
        guiGraphics.fill(barX, y, barX + fillWidth, y + 1, argb(accent, 0.45F * alpha));
        guiGraphics.fill(barX, bottom - 1, barX + fillWidth, bottom, argb(0x0A0512, 0.35F * alpha));
        if (EclipseClientConfig.reducedFx()) {
            return;
        }
        int scanX = barX + (int) (now % SCAN_PERIOD_MILLIS * BAR_WIDTH / SCAN_PERIOD_MILLIS);
        if (scanX < barX + fillWidth) {
            guiGraphics.fill(scanX, y, scanX + 1, bottom, argb(0xFFFFFF, 0.18F * alpha));
        }
    }

    /** Trailing damage ghost: pale segment between the lerped fill edge and the pre-drop level. */
    private static void drawGhostSegment(GuiGraphics guiGraphics, int barX, int y,
            int fillWidth, int ghostWidth, float alpha) {
        if (ghostWidth > fillWidth) {
            guiGraphics.fill(barX + fillWidth, y, barX + ghostWidth, y + BAR_HEIGHT,
                    argb(EclipseUiTheme.DANGER & 0xFFFFFF, 0.45F * alpha));
        }
    }

    /** Small accent end-cap ticks, {@code 2px} clear of the frame (ORNATE only). */
    private static void drawEndTicks(GuiGraphics guiGraphics, int barX, int y, int accent, float alpha) {
        int color = argb(accent, 0.55F * alpha);
        guiGraphics.fill(barX - 3, y, barX - 2, y + BAR_HEIGHT, color);
        guiGraphics.fill(barX + BAR_WIDTH + 2, y, barX + BAR_WIDTH + 3, y + BAR_HEIGHT, color);
    }

    /**
     * Procedural leading-edge glow, replacing the old {@code glow.png} blit: a bright 1px head
     * column at the fill edge plus a short accent falloff trailing back into the fill.
     */
    private static void drawLeadingEdge(GuiGraphics guiGraphics, int barX, int y, int fillWidth,
            int accent, float intensity, float alpha) {
        if (fillWidth <= 0 || intensity < 0.02F) {
            return;
        }
        intensity = Mth.clamp(intensity, 0.0F, 1.0F);
        int headX = barX + fillWidth - 1;
        for (int back = 1; back <= GLOW_FALLOFF_PX; back++) {
            int columnX = headX - back;
            if (columnX < barX) {
                break;
            }
            float falloff = 1.0F - back / (float) (GLOW_FALLOFF_PX + 1);
            guiGraphics.fill(columnX, y, columnX + 1, y + BAR_HEIGHT,
                    argb(accent, 0.45F * intensity * falloff * alpha));
        }
        guiGraphics.fill(headX, y, headX + 1, y + BAR_HEIGHT, argb(0xFFFFFF, 0.85F * intensity * alpha));
    }

    /**
     * Centred name line {@value #NAME_OFFSET_Y}px above the bar — the vanilla name position,
     * drawn with a text shadow and flashing {@code DIM → TEXT} when the name changes.
     */
    private static void drawName(GuiGraphics guiGraphics, int y, @Nullable Component name,
            float alpha, float nameFlash) {
        int alphaByte = (int) (alpha * 255.0F);
        if (name == null || alphaByte < 8) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();
        int textX = guiGraphics.guiWidth() / 2 - minecraft.font.width(name) / 2;
        int rgb = lerpRgb(EclipseUiTheme.DIM & 0xFFFFFF, EclipseUiTheme.TEXT & 0xFFFFFF, nameFlash);
        guiGraphics.drawString(minecraft.font, name, textX, y - NAME_OFFSET_Y,
                (alphaByte << 24) | rgb, true);
    }

    /**
     * The {@code showBossbarSkin=false} fallback: 4px track + progress strip, no text. The
     * strip takes the server bar's color when known (phase telegraphs must survive even the
     * minimal look); the theme's fill color is only the no-color fallback.
     */
    private static void drawMinimalStrip(GuiGraphics guiGraphics, int y, String theme, float progress,
            @Nullable BossEvent.BossBarColor barColor) {
        int barX = guiGraphics.guiWidth() / 2 - BAR_WIDTH / 2;
        int accent = barColor != null ? barColorRgb(barColor) : palette(theme, null).fillTop();
        guiGraphics.fill(barX, y, barX + BAR_WIDTH, y + 4, 0xB0140A24);
        int width = Math.round(BAR_WIDTH * Mth.clamp(progress, 0.0F, 1.0F));
        if (width > 0) {
            guiGraphics.fill(barX, y, barX + width, y + 4, 0xFF000000 | accent);
        }
    }

    /** 1px rectangle outline from four fills (outer dark edge, inner accent edge). */
    private static void drawFrameOutline(GuiGraphics guiGraphics, int x, int y, int width, int height,
            int color) {
        guiGraphics.fill(x, y, x + width, y + 1, color);
        guiGraphics.fill(x, y + height - 1, x + width, y + height, color);
        guiGraphics.fill(x, y + 1, x + 1, y + height - 1, color);
        guiGraphics.fill(x + width - 1, y + 1, x + width, y + height - 1, color);
    }

    /** Vertical gradient with 1px cut corners — the SLIM "rounded" strip primitive. */
    private static void gradientRounded(GuiGraphics guiGraphics, int x, int y, int width, int height,
            int top, int bottom) {
        if (width <= 2) {
            guiGraphics.fillGradient(x, y + 1, x + width, y + height - 1, top, bottom);
            return;
        }
        guiGraphics.fillGradient(x + 1, y, x + width - 1, y + height, top, bottom);
        guiGraphics.fillGradient(x, y + 1, x + 1, y + height - 1, top, bottom);
        guiGraphics.fillGradient(x + width - 1, y + 1, x + width, y + height - 1, top, bottom);
    }

    /**
     * Theme → colours. A {@code boss}-themed bar carrying a server-set
     * {@link BossEvent.BossBarColor} follows that colour instead, so the Ferryman's
     * WHITE/PURPLE/RED phase telegraphs survive; {@code WHITE} means "no telegraph" and keeps
     * the red boss palette. Unknown themes fall back to the goal palette — a future
     * server-side theme string can never render as a blank bar.
     */
    private static BarPalette palette(String theme, @Nullable BossEvent.BossBarColor barColor) {
        if (barColor != null && barColor != BossEvent.BossBarColor.WHITE) {
            int rgb = barColorRgb(barColor);
            return new BarPalette(rgb, scaleRgb(rgb, 0.42F), lerpRgb(rgb, 0xFFFFFF, 0.55F));
        }
        return switch (theme) {
            case THEME_ALTAR -> PALETTE_ALTAR;
            case THEME_SEAL -> PALETTE_SEAL;
            case THEME_WORLD -> PALETTE_WORLD;
            case S2CBossbarStylePayload.THEME_BOSS -> PALETTE_BOSS;
            case S2CBossbarStylePayload.THEME_DAY -> PALETTE_DAY;
            default -> PALETTE_GOAL;
        };
    }

    /** RGB + float alpha → packed ARGB for {@code fill}/{@code fillGradient}. */
    private static int argb(int rgb, float alpha) {
        return (Mth.clamp((int) (alpha * 255.0F + 0.5F), 0, 255) << 24) | (rgb & 0xFFFFFF);
    }

    /** Scales an RGB triple — the gradient foot of a bar-colour telegraph. */
    private static int scaleRgb(int rgb, float factor) {
        int red = Mth.clamp((int) (((rgb >> 16) & 0xFF) * factor), 0, 255);
        int green = Mth.clamp((int) (((rgb >> 8) & 0xFF) * factor), 0, 255);
        int blue = Mth.clamp((int) ((rgb & 0xFF) * factor), 0, 255);
        return (red << 16) | (green << 8) | blue;
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

    /** Translation-key safety net for v1 bars that predate the style payload (revive ritual). */
    private static String fallbackTheme(Component name) {
        if (name.getContents() instanceof TranslatableContents translatable
                && translatable.getKey().startsWith("ritual.eclipse.")) {
            return S2CBossbarStylePayload.THEME_GOAL;
        }
        return null;
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
