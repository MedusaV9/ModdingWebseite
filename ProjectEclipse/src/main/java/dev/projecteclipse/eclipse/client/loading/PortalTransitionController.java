package dev.projecteclipse.eclipse.client.loading;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.network.gate.GatePayloads;
import dev.projecteclipse.eclipse.network.gate.S2CPortalFxPayload;
import dev.projecteclipse.eclipse.veilfx.TransitionFx;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.screens.LevelLoadingScreen;
import net.minecraft.client.gui.screens.ReceivingLevelScreen;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RenderGuiEvent;
import net.neoforged.neoforge.client.event.ScreenEvent;

/**
 * Full-screen GUI choreography for portal / dimension hops (P3 §3.11 "portal glitch
 * transition"), driven by {@link S2CPortalFxPayload} (sent right before the server-side
 * teleport — xbox event entry/exit via {@code XboxTransitionBridge}, future P6/P2 senders):
 *
 * <pre>ENTER → glitch slabs ramp (0.5 s) → fade to black (0.25 s) → HOLD black while the
 * dimension changes (the {@link EclipseLoadingScreen} shows its pure-black variant)
 * → level received → fade in from black (0.75 s) with a glitch tail.</pre>
 *
 * <p>This is the GUI-side of the P2 R13 transition chain: {@link TransitionFx#playPortalEnter}
 * / {@link TransitionFx#playPortalExit} are mirrored for the world-side {@code rift_glitch}
 * post pipeline, but that pipeline is hard-gated off under Iris/{@code veilPostFx=false} —
 * THIS overlay is the always-on visible fallback (§3.11, §7 risk 1). Rendering hooks:
 * {@link RenderGuiEvent.Post} (fires even under F1 — a mid-teleport fade must never vanish;
 * documented §3.13 exemption: transitions are cover, not clutter) plus
 * {@link ScreenEvent.Render.Post} for frames where a screen (loading, chat, …) is up. All
 * phase math is wall-clock so the animation cannot freeze while client ticks stall during
 * the dimension swap; state also advances from the render hooks for the same reason.</p>
 *
 * <p><b>Fail-safes (never traps, never blocks input):</b> the overlay is not a screen and
 * captures nothing; the black hold self-releases when the loading screen closes with a level
 * present, when no loading screen ever appears within {@code holdTicks} + grace (aborted
 * teleport), and unconditionally at the 90 s cap; everything resets on logout.
 * {@code reducedFx} drops the glitch slabs and keeps the plain fades.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class PortalTransitionController {
    private static final long GLITCH_MILLIS = 500L;
    private static final long FADE_OUT_MILLIS = 250L;
    private static final long FADE_IN_MILLIS = 750L;
    /** Outer watchdog (§3.11: "any missed phase times out — 90s cap"); TransitionFx's own is 60 s. */
    private static final long HOLD_CAP_MILLIS = 90_000L;
    /** Extra wait beyond the payload's holdTicks before the "no loading screen" release. */
    private static final long NO_SCREEN_GRACE_MILLIS = 2_000L;
    /** Frozen P5 flow values for the mirrored world-side pipeline (P2-W8 wiring). */
    private static final int FX_ENTER_TICKS = 18;
    private static final int FX_EXIT_TICKS = 24;
    /** Glitch slab pattern re-rolls every 45 ms (GlitchText's wall-clock bucket technique). */
    private static final long SLAB_ROLL_MILLIS = 45L;
    private static final int MAX_SLABS = 14;

    private enum Phase { IDLE, GLITCH, FADE_OUT, HOLD, FADE_IN }

    private static Phase phase = Phase.IDLE;
    private static long phaseStartMillis;
    private static long holdCoverMillis = 1_500L;
    private static String styleId = "";
    private static boolean sawLoadingScreen;
    /** Black level captured when the fade-in began (1 from HOLD, partial from earlier phases). */
    private static float fadeInFrom = 1.0F;

    /** Reused slab roll source, re-seeded per frame (render thread only). */
    private static final RandomSource SLAB_RANDOM = RandomSource.create();

    static {
        // Payload consumer seam (GrowthPayloads pattern): installed on client class-load, so
        // GatePayloads itself never references client classes.
        GatePayloads.setClientPortalFxHandler(PortalTransitionController::onPayload);
    }

    private PortalTransitionController() {}

    // ------------------------------------------------------------------ payload entry

    /** Runs on the client main thread (payload handler). */
    public static void onPayload(S2CPortalFxPayload payload) {
        switch (payload.phase()) {
            case ENTER -> begin(payload);
            case HOLD -> {
                if (phase == Phase.HOLD) {
                    phaseStartMillis = now(); // extend an active hold
                } else if (phase == Phase.IDLE || phase == Phase.FADE_IN) {
                    begin(payload);
                }
            }
            case EXIT -> {
                if (phase != Phase.IDLE) {
                    beginFadeIn();
                }
            }
        }
    }

    private static void begin(S2CPortalFxPayload payload) {
        styleId = payload.styleId();
        holdCoverMillis = Mth.clamp(payload.holdTicks(), 0, 600) * 50L;
        sawLoadingScreen = false;
        enterPhase(Phase.GLITCH);
        TransitionFx.playPortalEnter(FX_ENTER_TICKS);
        EclipseMod.LOGGER.debug("Portal transition started (style {}, hold {} ms)", styleId, holdCoverMillis);
    }

    // ------------------------------------------------------------------ queries

    /** Whether the choreography is running (the loading screen switches to its black variant). */
    public static boolean active() {
        return phase != Phase.IDLE;
    }

    // ------------------------------------------------------------------ state machine

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        advance();
    }

    /** Wall-clock driven; called from tick AND render so stalled ticks cannot freeze a phase. */
    private static void advance() {
        if (phase == Phase.IDLE) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();
        boolean loadingUp = isLoadingScreen(minecraft.screen);
        if (loadingUp) {
            sawLoadingScreen = true;
        }
        long t = now() - phaseStartMillis;
        switch (phase) {
            case GLITCH -> {
                if (t >= GLITCH_MILLIS) {
                    enterPhase(Phase.FADE_OUT);
                }
            }
            case FADE_OUT -> {
                if (t >= FADE_OUT_MILLIS) {
                    enterPhase(Phase.HOLD);
                }
            }
            case HOLD -> {
                boolean levelReady = minecraft.level != null && !loadingUp;
                if (t >= HOLD_CAP_MILLIS) {
                    EclipseMod.LOGGER.warn("Portal transition hold exceeded {} ms; force-releasing",
                            HOLD_CAP_MILLIS);
                    beginFadeIn();
                } else if (sawLoadingScreen && levelReady) {
                    beginFadeIn(); // destination received: the loading screen closed onto a level
                } else if (!sawLoadingScreen && levelReady && t >= holdCoverMillis + NO_SCREEN_GRACE_MILLIS) {
                    beginFadeIn(); // teleport finished without any loading screen (same-dim / instant)
                }
            }
            case FADE_IN -> {
                if (t >= FADE_IN_MILLIS) {
                    phase = Phase.IDLE;
                }
            }
            default -> { }
        }
    }

    private static void beginFadeIn() {
        fadeInFrom = blackLevel();
        enterPhase(Phase.FADE_IN);
        TransitionFx.playPortalExit(FX_EXIT_TICKS);
    }

    private static void enterPhase(Phase next) {
        phase = next;
        phaseStartMillis = now();
    }

    /** Disconnect reset — a transition can never leak into the next session. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        phase = Phase.IDLE;
        sawLoadingScreen = false;
    }

    // ------------------------------------------------------------------ rendering

    /** World-visible frames (no screen up); fires even under F1 by design (transition = cover). */
    @SubscribeEvent
    static void onRenderGui(RenderGuiEvent.Post event) {
        if (phase == Phase.IDLE || Minecraft.getInstance().screen != null) {
            return; // screen frames are covered by onScreenRender (avoid double-blending)
        }
        advance();
        renderOverlay(event.getGuiGraphics());
    }

    /** On top of any open screen — including {@link EclipseLoadingScreen}'s black variant. */
    @SubscribeEvent
    static void onScreenRender(ScreenEvent.Render.Post event) {
        if (phase == Phase.IDLE) {
            return;
        }
        advance();
        renderOverlay(event.getGuiGraphics());
    }

    private static void renderOverlay(GuiGraphics guiGraphics) {
        int width = guiGraphics.guiWidth();
        int height = guiGraphics.guiHeight();
        float black = blackLevel();
        float glitch = glitchLevel();
        if (glitch > 0.02F && !EclipseClientConfig.reducedFx()) {
            renderGlitchSlabs(guiGraphics, width, height, glitch);
        }
        if (black > 0.01F) {
            guiGraphics.fill(0, 0, width, height, EclipseUiTheme.withAlpha(0xFF000000, black));
        }
    }

    /** GlitchText-style horizontal displacement slabs, deterministic per 45 ms bucket. */
    private static void renderGlitchSlabs(GuiGraphics guiGraphics, int width, int height, float strength) {
        SLAB_RANDOM.setSeed(System.currentTimeMillis() / SLAB_ROLL_MILLIS);
        int count = Math.max(2, Math.round(strength * MAX_SLABS));
        for (int i = 0; i < count; i++) {
            int slabHeight = 1 + SLAB_RANDOM.nextInt(Math.max(2, height / 48));
            int y = SLAB_RANDOM.nextInt(Math.max(1, height - slabHeight));
            int shift = SLAB_RANDOM.nextInt(width / 8 + 1) - width / 16;
            int color = switch (SLAB_RANDOM.nextInt(4)) {
                case 0 -> EclipseUiTheme.ACCENT;
                case 1 -> EclipseUiTheme.ACCENT_DEEP;
                case 2 -> 0xFFEDE7F8;
                default -> 0xFF06030F;
            };
            float alpha = strength * (0.10F + SLAB_RANDOM.nextFloat() * 0.22F);
            guiGraphics.fill(shift, y, shift + width, y + slabHeight,
                    EclipseUiTheme.withAlpha(color, alpha));
        }
    }

    // ------------------------------------------------------------------ curves

    /** Current black cover 0..1. */
    private static float blackLevel() {
        long t = now() - phaseStartMillis;
        return switch (phase) {
            case IDLE, GLITCH -> 0.0F;
            case FADE_OUT -> smooth01((float) t / FADE_OUT_MILLIS);
            case HOLD -> 1.0F;
            case FADE_IN -> fadeInFrom * (1.0F - smooth01((float) t / FADE_IN_MILLIS));
        };
    }

    /** Current glitch strength 0..1. */
    private static float glitchLevel() {
        long t = now() - phaseStartMillis;
        return switch (phase) {
            case IDLE -> 0.0F;
            case GLITCH -> smooth01((float) t / GLITCH_MILLIS);
            case FADE_OUT -> 1.0F;
            case HOLD -> 0.25F; // faint remnant on the black hold (mirrors TransitionFx's simmer)
            case FADE_IN -> {
                float s = Mth.clamp((float) t / FADE_IN_MILLIS, 0.0F, 1.0F);
                yield 0.8F * (1.0F - s);
            }
        };
    }

    private static boolean isLoadingScreen(Screen screen) {
        // EclipseLoadingScreen extends ReceivingLevelScreen, so the first check covers it too.
        return screen instanceof ReceivingLevelScreen || screen instanceof LevelLoadingScreen;
    }

    private static long now() {
        return System.currentTimeMillis();
    }

    private static float smooth01(float x) {
        x = Mth.clamp(x, 0.0F, 1.0F);
        return x * x * (3.0F - 2.0F * x);
    }
}
