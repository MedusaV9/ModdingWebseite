package dev.projecteclipse.eclipse.veilfx;

import dev.projecteclipse.eclipse.EclipseMod;
import foundry.veil.api.client.render.post.PostPipeline;
import net.minecraft.client.Minecraft;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Client API for the glitch → fade-to-black → fade-in screen transition (P2 R13, FROZEN):
 * <ul>
 *   <li>{@link #playPortalEnter(int)} — glitch ramps up, then the screen fades to black
 *       over {@code ticks} and <b>stays black</b> until {@link #playPortalExit(int)} (the
 *       dimension change happens behind the black; P5's portal flow calls
 *       {@code playPortalEnter(18)} / {@code playPortalExit(24)}).</li>
 *   <li>{@link #playPortalExit(int)} — releases the fade over {@code ticks} with a glitch
 *       tail-off.</li>
 *   <li>{@link #setLoadingPulse(float)} — P3's dimension-change screen drives a slow
 *       world-side glitch breathing while "receiving level" (0 disables; refresh at least
 *       every {@value #LOADING_STALE_TICKS} ticks or the pulse expires defensively).</li>
 * </ul>
 *
 * <p>The visual is the {@code eclipse:rift_glitch} post pipeline (TRANSITION priority,
 * registered here; uniforms frozen in §3.3: {@code GlitchAmount}, {@code FadeAmount},
 * {@code Time}). {@code GlitchAmount} is the max of three sources: the transition envelope,
 * the loading pulse, and short {@link #glitchPulse(float, int)} pops (rift open/close —
 * {@code RiftFx} feeds these; W9's storm reveal may call it too, R14's "rift_glitch pulse
 * 0.4"). The pipeline renders the WORLD-side effect only — GUI-side visuals during loading
 * are P3's ({@code they render GUI; our pipeline supplies the world-side glitch}, R13c).</p>
 *
 * <p><b>Iris caveat:</b> like every Veil post pipeline this is hard-gated off while an Iris
 * shaderpack is active or {@code veilPostFx} is disabled ({@code VeilPostController}'s
 * global gate). The transition state still runs; P3's GUI screen is the visible fallback
 * for the black hold in that configuration (§7 risk 1).</p>
 *
 * <p><b>Fail-safes:</b> the black hold auto-releases after {@value #HOLD_MAX_TICKS} ticks
 * (~60 s) if {@code playPortalExit} never arrives (crashed teleport, dropped packet), and
 * everything resets on logout — a stuck black screen is impossible by construction. The
 * frozen {@code EclipseFxState.startTransitionGlitch/transitionGlitch/transitionFade}
 * blackboard is mirrored on every enter/exit so siblings polling that surface see the
 * transition; this class's own richer curves (separate glitch/fade shapes) feed the
 * pipeline.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class TransitionFx {
    /** Pipeline id (§3.3 FROZEN): {@code eclipse:rift_glitch}, TRANSITION priority. */
    public static final ResourceLocation RIFT_GLITCH_POST =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "rift_glitch");

    /** Max black-hold before the fail-safe auto-exit (P3's own screen watchdog is 90 s — ours fires first). */
    private static final int HOLD_MAX_TICKS = 1200;
    /** Fail-safe / mirror release length. */
    private static final int AUTO_EXIT_TICKS = 40;
    /** Enter/exit lengths are clamped to sane bounds (P5 sends 18/24). */
    private static final int MAX_PHASE_TICKS = 200;
    /** Loading pulse expires when not refreshed for this long (defensive against a dead screen). */
    private static final int LOADING_STALE_TICKS = 100;
    /** Glitch settles to this simmer while holding black (invisible behind the fade, keeps uniforms sane). */
    private static final float HOLD_GLITCH_FLOOR = 0.25F;
    /** Fraction of the enter phase after which the glitch is fully up (fade completes at 1.0). */
    private static final float ENTER_GLITCH_PORTION = 0.6F;
    private static final float ENTER_FADE_START = 0.35F;
    /** Exit glitch spike peak ("fade→0 with glitch tail-off"). */
    private static final float EXIT_GLITCH_PEAK = 0.8F;

    private enum Phase { NONE, ENTER, HOLD, EXIT }

    private static Phase phase = Phase.NONE;
    private static int phaseStart;
    private static int enterTicks = 18;
    private static int exitTicks = 24;
    /** Fade level captured when the exit began (1 from HOLD; current value mid-ENTER; 0 from NONE). */
    private static float exitFadeFrom;

    // --- short glitch pops (rift open/close, storm reveal) ---
    private static float pulseAmp;
    private static int pulseStart = Integer.MIN_VALUE;
    private static int pulseDecay = 1;

    // --- loading pulse (P3's screen) ---
    private static float loadingPulse;
    private static int loadingSetTick = Integer.MIN_VALUE;

    static {
        // Feature-owned pipeline row (P2 §3.1 pattern): this class is an event subscriber,
        // so it loads on client startup and the row exists before the first tick.
        VeilPostController.register(new VeilPostController.PipelineSpec(
                RIFT_GLITCH_POST, VeilPostController.PipelinePriority.TRANSITION,
                TransitionFx::wantPipeline, TransitionFx::feedPipeline));
    }

    private TransitionFx() {}

    // ------------------------------------------------------------------ frozen API (R13)

    /**
     * Glitch up, then fade to black over {@code ticks}; the screen STAYS black afterwards
     * until {@link #playPortalExit(int)} (fail-safe release after {@value #HOLD_MAX_TICKS}
     * ticks). Safe to call again mid-transition — the envelope restarts.
     */
    public static void playPortalEnter(int ticks) {
        enterTicks = Mth.clamp(ticks, 1, MAX_PHASE_TICKS);
        phase = Phase.ENTER;
        phaseStart = EclipseFxState.clientTicks();
        // Mirror onto the frozen blackboard for siblings polling EclipseFxState.
        EclipseFxState.startTransitionGlitch(enterTicks, HOLD_MAX_TICKS, AUTO_EXIT_TICKS);
    }

    /**
     * Releases the fade over {@code ticks} with a glitch tail-off. Called at the destination
     * once the dimension change is done. From an idle state this degrades to a pure glitch
     * tail (no black flash) — safe if the enter side was reset by a relog.
     */
    public static void playPortalExit(int ticks) {
        exitTicks = Mth.clamp(ticks, 1, MAX_PHASE_TICKS);
        exitFadeFrom = envelopeFade(0.0F);
        phase = Phase.EXIT;
        phaseStart = EclipseFxState.clientTicks();
        EclipseFxState.startTransitionGlitch(0, 0, exitTicks);
    }

    /**
     * P3's replacement loading screen drives a slow world-side glitch breathing while
     * "receiving level": {@code p01} in [0,1] scales it (0 = off). Refresh at least every
     * {@value #LOADING_STALE_TICKS} ticks (per-frame is fine); set 0 when the screen closes.
     */
    public static void setLoadingPulse(float p01) {
        loadingPulse = Mth.clamp(p01, 0.0F, 1.0F);
        loadingSetTick = EclipseFxState.clientTicks();
    }

    // ------------------------------------------------------------------ additive helpers

    /**
     * Short screen-glitch pop (no fade): {@code amplitude} clamps to [0,1] and decays
     * quadratically over {@code decayTicks}. A weaker pop never replaces a stronger live
     * one. Used by {@code RiftFx} on open/close (≤ 0.5 per R11) and available to W9's
     * storm reveal ({@code glitchPulse(0.4F, 20)} matches R14's "rift_glitch pulse 0.4").
     */
    public static void glitchPulse(float amplitude, int decayTicks) {
        amplitude = Mth.clamp(amplitude, 0.0F, 1.0F);
        if (amplitude <= pulseValue(0.0F)) {
            return;
        }
        pulseAmp = amplitude;
        pulseStart = EclipseFxState.clientTicks();
        pulseDecay = Math.max(1, decayTicks);
    }

    // ------------------------------------------------------------------ curves

    /** Transition-envelope glitch 0..1 (enter ramp → hold simmer → exit spike/tail). */
    private static float envelopeGlitch(float partialTick) {
        float t = elapsed(partialTick);
        return switch (phase) {
            case NONE -> 0.0F;
            case ENTER -> smooth01(Math.min(1.0F, t / (enterTicks * ENTER_GLITCH_PORTION)));
            case HOLD -> HOLD_GLITCH_FLOOR + (1.0F - HOLD_GLITCH_FLOOR) * square(1.0F - Math.min(1.0F, t / 20.0F));
            case EXIT -> {
                float s = Math.min(1.0F, t / exitTicks);
                yield EXIT_GLITCH_PEAK * (s < 0.25F ? s / 0.25F : 1.0F - (s - 0.25F) / 0.75F);
            }
        };
    }

    /** Transition-envelope fade-to-black 0..1 (0 = clear, 1 = fully black). */
    private static float envelopeFade(float partialTick) {
        float t = elapsed(partialTick);
        return switch (phase) {
            case NONE -> 0.0F;
            case ENTER -> smooth01((t / enterTicks - ENTER_FADE_START) / (1.0F - ENTER_FADE_START));
            case HOLD -> 1.0F;
            case EXIT -> exitFadeFrom * (1.0F - smooth01(t / exitTicks));
        };
    }

    private static float pulseValue(float partialTick) {
        if (pulseStart == Integer.MIN_VALUE) {
            return 0.0F;
        }
        float t = EclipseFxState.clientTicks() + partialTick - pulseStart;
        if (t >= pulseDecay) {
            return 0.0F;
        }
        return pulseAmp * square(1.0F - t / pulseDecay);
    }

    /** Loading-pulse glitch contribution: gentle 2 s breathing scaled by the driven value. */
    private static float loadingValue(float partialTick) {
        if (loadingPulse <= 0.0F || loadingSetTick == Integer.MIN_VALUE) {
            return 0.0F;
        }
        float now = EclipseFxState.clientTicks() + partialTick;
        if (now - loadingSetTick > LOADING_STALE_TICKS) {
            return 0.0F;
        }
        return loadingPulse * (0.12F + 0.08F * Mth.sin(Mth.TWO_PI * now / 40.0F));
    }

    // ------------------------------------------------------------------ pipeline row

    private static boolean wantPipeline() {
        return phase != Phase.NONE || pulseValue(1.0F) > 0.004F || loadingValue(1.0F) > 0.004F;
    }

    private static void feedPipeline(PostPipeline pipeline) {
        float partialTick = Minecraft.getInstance().getTimer().getGameTimeDeltaPartialTick(false);
        float glitch = Math.max(envelopeGlitch(partialTick),
                Math.max(pulseValue(partialTick), loadingValue(partialTick)));
        pipeline.getUniform("GlitchAmount").setFloat(Mth.clamp(glitch, 0.0F, 1.0F));
        pipeline.getUniform("FadeAmount").setFloat(Mth.clamp(envelopeFade(partialTick), 0.0F, 1.0F));
        // Wall-clock time: the artifact pattern keeps animating even when client ticks
        // stall during a dimension change (exactly when this pipeline matters most).
        pipeline.getUniform("Time").setFloat((System.currentTimeMillis() % 100_000L) / 1000.0F);
    }

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        if (phase == Phase.NONE) {
            return;
        }
        int t = EclipseFxState.clientTicks() - phaseStart;
        switch (phase) {
            case ENTER -> {
                if (t >= enterTicks) {
                    phase = Phase.HOLD;
                    phaseStart = EclipseFxState.clientTicks();
                }
            }
            case HOLD -> {
                if (t >= HOLD_MAX_TICKS) {
                    EclipseMod.LOGGER.warn("TransitionFx hold exceeded {} ticks without playPortalExit; auto-releasing",
                            HOLD_MAX_TICKS);
                    playPortalExit(AUTO_EXIT_TICKS);
                }
            }
            case EXIT -> {
                if (t >= exitTicks) {
                    phase = Phase.NONE;
                }
            }
            default -> { }
        }
    }

    /** Disconnect reset — a transition can never leak into the next session. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        phase = Phase.NONE;
        pulseAmp = 0.0F;
        pulseStart = Integer.MIN_VALUE;
        loadingPulse = 0.0F;
        loadingSetTick = Integer.MIN_VALUE;
    }

    private static float elapsed(float partialTick) {
        return EclipseFxState.clientTicks() + partialTick - phaseStart;
    }

    private static float smooth01(float x) {
        x = Mth.clamp(x, 0.0F, 1.0F);
        return x * x * (3.0F - 2.0F * x);
    }

    private static float square(float x) {
        return x * x;
    }
}
