package dev.projecteclipse.eclipse.client.drama;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.hud.DayTimerCache;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.cutscene.client.CameraDirector;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.resources.sounds.SimpleSoundInstance;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RegisterGuiLayersEvent;
import net.neoforged.neoforge.client.gui.VanillaGuiLayers;

/**
 * "The Last Minute" pre-rollover hush (FIX-5, IDEAS-A #1). For the final
 * {@value #WINDOW_MILLIS}&nbsp;ms before every realtime day boundary the world holds its
 * breath, entirely client-side off the {@code S2CDayClockPayload} cache
 * ({@link DayTimerCache} — no new packets, no server timing changes):
 * <ul>
 *   <li><b>Audio duck</b>: the master listener gain eases down to
 *       {@code 1 − }{@value #DUCK_DEPTH} of the player's own master volume.
 *       {@code MusicManager} exposes no public volume API (its {@code CueSound} volume is
 *       owned exclusively by the crossfade), so the duck goes through
 *       {@code SoundManager.updateSourceVolume(MASTER, …)} — for MASTER that sets the
 *       engine's listener gain directly (verified against {@code SoundEngine
 *       .updateCategoryVolume}), ducking music and ambience together without touching any
 *       saved option. The pre-duck gain is re-derived from options every tick, so a user
 *       moving the volume slider mid-hush is respected, and it is restored the moment the
 *       hush ends (and on logout).</li>
 *   <li><b>HUD dim</b>: a full-screen black wash easing up to {@value #DIM_MAX_ALPHA}
 *       alpha via an own GUI layer (below the crosshair, like the mark vignette). Hidden
 *       under F1 and skipped entirely under {@code reducedFx}; deliberately NOT
 *       letterbox-whitelisted, so cutscene HUD suppression hides it.</li>
 *   <li><b>Heartbeat</b>: over the last {@value #HEARTBEAT_WINDOW_MILLIS}&nbsp;ms a quiet
 *       warden heartbeat accelerates from ~1&nbsp;Hz toward ~2.5&nbsp;Hz (the
 *       {@code HeartBurstOverlay} low-lives cue at pitch floor 0.5, kept quieter here).
 *       Gated by the same {@code heartbeatSound} + {@code reducedFx} opt-outs.</li>
 *   <li><b>Release</b>: at T-0 the target snaps to 0 and the envelope releases fast
 *       (~0.5&nbsp;s) — the server's day announcement lands out of the silence.
 *       {@code DayTimerCache} itself fires {@code ui.timer_zero}; nothing extra here.</li>
 * </ul>
 *
 * <p>Guards: inactive while the day clock is disarmed or paused, while a cutscene flight is
 * live ({@link CameraDirector#isActive()}), and while no level is loaded. Everything resets
 * on disconnect (the {@code QuasarSpawner.DisconnectReset} pattern).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class LastMinuteHush {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "last_minute_hush");

    /** Hush window before the boundary (IDEAS-A #1: the final 60 seconds). */
    private static final long WINDOW_MILLIS = 60_000L;
    /** Heartbeat ticks accelerate over the last 10 seconds. */
    private static final long HEARTBEAT_WINDOW_MILLIS = 10_000L;
    /** Master gain ducks by this fraction at full hush (0.45 → world at 55%). */
    private static final float DUCK_DEPTH = 0.45F;
    /** Full-screen dim cap — "a small 15% black fade", horror-calm, never blinding. */
    private static final float DIM_MAX_ALPHA = 0.15F;
    /** Envelope speeds (per-tick exponential approach): slow breath in, quick release. */
    private static final float ATTACK_RATE = 0.015F;
    private static final float RELEASE_RATE = 0.12F;
    /** Heartbeat cadence: every 20 ticks at T-10 s, accelerating to every 8 ticks at T-0. */
    private static final int HEARTBEAT_SLOW_TICKS = 20;
    private static final int HEARTBEAT_FAST_TICKS = 8;
    private static final float HEARTBEAT_VOLUME = 0.45F;

    /** Eased hush envelope 0..1 (drives duck and dim together). */
    private static float hush;
    /** Whether the listener gain currently differs from the player's own master volume. */
    private static boolean ducking;
    private static int heartbeatCountdown;

    private LastMinuteHush() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            reset(minecraft);
            return;
        }
        long remaining = hushRemainingMillis();
        float target = remaining > 0L ? 1.0F : 0.0F;
        hush += (target - hush) * (target > hush ? ATTACK_RATE : RELEASE_RATE);
        if (hush < 0.002F && target == 0.0F) {
            hush = 0.0F;
        }
        applyDuck(minecraft);
        tickHeartbeat(minecraft, remaining);
    }

    /** Disconnect reset — the listener gain must never stay ducked into the title screen. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        reset(Minecraft.getInstance());
    }

    /**
     * GUI-layer body: the slow black breath over the whole screen. F1-hidden, skipped under
     * {@code reducedFx} (the audio hush still plays — it is not a flashing effect).
     */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        if (hush <= 0.01F || EclipseClientConfig.reducedFx()) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.player == null || minecraft.options.hideGui) {
            return;
        }
        int alpha = Mth.floor(Mth.clamp(DIM_MAX_ALPHA * hush, 0.0F, 1.0F) * 255.0F);
        if (alpha <= 2) {
            return;
        }
        guiGraphics.fill(0, 0, guiGraphics.guiWidth(), guiGraphics.guiHeight(), alpha << 24);
    }

    // ------------------------------------------------------------------ internals

    /** Millis left inside the hush window, or 0 while the hush should not run. */
    private static long hushRemainingMillis() {
        if (CameraDirector.isActive() || !DayTimerCache.armed() || DayTimerCache.paused()) {
            return 0L;
        }
        long remaining = DayTimerCache.remainingMillis();
        return remaining > 0L && remaining <= WINDOW_MILLIS ? remaining : 0L;
    }

    /**
     * Applies (or releases) the master listener-gain duck. The base gain is re-read from
     * the player's own master volume option every tick; restoring simply writes that value
     * back, so no state can strand a wrong volume across sessions.
     */
    private static void applyDuck(Minecraft minecraft) {
        float master = minecraft.options.getSoundSourceVolume(SoundSource.MASTER);
        if (hush <= 0.0F) {
            if (ducking) {
                ducking = false;
                minecraft.getSoundManager().updateSourceVolume(SoundSource.MASTER, master);
            }
            return;
        }
        ducking = true;
        minecraft.getSoundManager().updateSourceVolume(SoundSource.MASTER,
                master * (1.0F - DUCK_DEPTH * hush));
    }

    /** Quiet warden heartbeat, accelerating over the last {@value #HEARTBEAT_WINDOW_MILLIS} ms. */
    private static void tickHeartbeat(Minecraft minecraft, long remaining) {
        if (remaining <= 0L || remaining > HEARTBEAT_WINDOW_MILLIS || hush < 0.5F
                || minecraft.isPaused()
                || EclipseClientConfig.reducedFx()
                || !EclipseClientConfig.heartbeatSound()) {
            return;
        }
        if (--heartbeatCountdown > 0) {
            return;
        }
        float closeness = 1.0F - remaining / (float) HEARTBEAT_WINDOW_MILLIS;
        heartbeatCountdown = Math.round(Mth.lerp(closeness,
                (float) HEARTBEAT_SLOW_TICKS, (float) HEARTBEAT_FAST_TICKS));
        // Pitch 0.5 is the engine's clamp floor (the HeartBurstOverlay dread heartbeat);
        // kept quieter than the low-lives cue so the two never fight.
        minecraft.getSoundManager().play(
                SimpleSoundInstance.forUI(SoundEvents.WARDEN_HEARTBEAT, 0.5F, HEARTBEAT_VOLUME));
    }

    private static void reset(Minecraft minecraft) {
        hush = 0.0F;
        heartbeatCountdown = 0;
        if (ducking) {
            ducking = false;
            minecraft.getSoundManager().updateSourceVolume(SoundSource.MASTER,
                    minecraft.options.getSoundSourceVolume(SoundSource.MASTER));
        }
    }

    /**
     * Own GUI-layer registration (mod-bus event in a nested class, the
     * {@code MusicConfig.SelfRegistrar} pattern) — no {@code EclipseGuiLayers} edit needed.
     * Below the crosshair like the mark vignette; deliberately NOT letterbox-whitelisted.
     */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    static final class LayerRegistrar {
        private LayerRegistrar() {}

        @SubscribeEvent
        static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
            event.registerBelow(VanillaGuiLayers.CROSSHAIR, LAYER_ID, LastMinuteHush::render);
        }
    }
}
