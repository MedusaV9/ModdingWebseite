package dev.projecteclipse.eclipse.client.credits;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.cutscene.client.CameraDirector;
import dev.projecteclipse.eclipse.music.MusicCues;
import dev.projecteclipse.eclipse.network.credits.CreditsPayloads;
import dev.projecteclipse.eclipse.network.credits.CreditsPayloads.S2CCreditsBeginPayload;
import dev.projecteclipse.eclipse.network.credits.CreditsPayloads.S2CCreditsClosePayload;
import dev.projecteclipse.eclipse.network.credits.CreditsPayloads.S2CCreditsFovPayload;
import dev.projecteclipse.eclipse.ritual.CreditsConfig;
import net.minecraft.util.Mth;
import net.minecraft.client.Minecraft;
import net.minecraft.client.resources.sounds.SimpleSoundInstance;
import net.minecraft.sounds.SoundEvents;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Client brain of the C15 final credits sequence: latches the per-run nonce from
 * {@link S2CCreditsBeginPayload} and executes the guarded self-close of
 * {@link S2CCreditsClosePayload} (IDEAS-backrooms_finale §B3).
 *
 * <p><b>Close guards — ALL client-side, ALL mandatory:</b></p>
 * <ol>
 *   <li>nonce match — a client that never received this run's begin payload (joined late,
 *       different server, restarted mid-credits) ignores the close;</li>
 *   <li>never with {@link Minecraft#hasSingleplayerServer()} (singleplayer/LAN dev worlds
 *       must not shut themselves down);</li>
 *   <li>{@link CreditsConfig#allowFinaleClose()} kill-switch (rehearsals).</li>
 * </ol>
 *
 * <p>The stop itself goes through {@code minecraft.execute(minecraft::stop)} — the graceful
 * title-screen-Quit path (saves options, stops sounds, destroys the window), guaranteed on
 * the render thread. Everything resets on logout so a credits state can never leak into the
 * next session.</p>
 *
 * <p><b>FXTEAM CUT-CREDITS close choreography</b>: the moment the close is scheduled the
 * {@code day_final} channel starts its 40t crossfade-out ({@code MusicCues.stop()} —
 * {@code MusicManager.FADE_TICKS} equals the close delay, so the music reaches silence
 * exactly as the window dies instead of hard-cutting mid-phrase), and the final second of
 * pure black carries two faint warden-heartbeat thumps ({@value #HEARTBEAT_FIRST_AT}t /
 * {@value #HEARTBEAT_SECOND_AT}t before stop; gated by the {@code heartbeatSound}
 * accessibility toggle).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class CreditsClient {
    /** Countdown values (ticks before stop) of the two finale heartbeat thumps. */
    private static final int HEARTBEAT_FIRST_AT = 20;
    private static final int HEARTBEAT_SECOND_AT = 12;
    static {
        // Payload consumer seam (BossIntroOverlay pattern): installed on client class-load,
        // so CreditsPayloads itself never references client classes.
        CreditsPayloads.setClientBeginHandler(CreditsClient::handleBegin);
        CreditsPayloads.setClientCloseHandler(CreditsClient::handleClose);
        CreditsPayloads.setClientFovHandler(CreditsClient::handleFov);
    }

    /** The latched credits-run nonce; 0 = no run seen this session. Client thread only. */
    private static int nonce;
    /** Ticks until {@code Minecraft.stop()}; -1 = no close scheduled. Client thread only. */
    private static int closeCountdown = -1;

    // --- FIN-6 eclipse-explosion zoom (per-tick ramp of the director's external FOV) ---
    /** Current external FOV multiplier (1 = neutral). Client thread only. */
    private static float fovScale = 1.0F;
    private static float fovFrom = 1.0F;
    private static float fovTarget = 1.0F;
    private static int fovRampTicks;
    private static int fovRampElapsed;

    private CreditsClient() {}

    /** The current run's nonce (0 = none) — read by the sibling credits overlays. */
    static int nonce() {
        return nonce;
    }

    private static void handleBegin(S2CCreditsBeginPayload payload) {
        nonce = payload.nonce();
        closeCountdown = -1;
        // FIN-6: the whole finale is HUD-free (sidebar, hotbar, day timer). Cleared on
        // logout, on the roll's stop payload, and by the close itself.
        CameraDirector.setExternalHudSuppressed(true);
        EclipseMod.LOGGER.info("Credits sequence began (nonce {})", payload.nonce());
    }

    /** FIN-6: begins a linear ramp of the external FOV multiplier toward the payload target. */
    private static void handleFov(S2CCreditsFovPayload payload) {
        fovFrom = fovScale;
        fovTarget = Mth.clamp(payload.targetScale(), 0.2F, 2.0F);
        fovRampTicks = Math.max(0, payload.rampTicks());
        fovRampElapsed = 0;
        if (fovRampTicks == 0) {
            fovScale = fovTarget;
            CameraDirector.setExternalFovScale(fovScale);
        }
    }

    /**
     * Called by {@code CreditsPanel} when the roll's stop payload lands (the rehearsal /
     * integrated-server end path, which never closes the client): the HUD and FOV are
     * handed back to gameplay.
     */
    static void onRollStopped() {
        CameraDirector.setExternalHudSuppressed(false);
        resetFov();
    }

    private static void resetFov() {
        fovScale = 1.0F;
        fovFrom = 1.0F;
        fovTarget = 1.0F;
        fovRampTicks = 0;
        fovRampElapsed = 0;
        CameraDirector.setExternalFovScale(1.0F);
    }

    private static void handleClose(S2CCreditsClosePayload payload) {
        Minecraft minecraft = Minecraft.getInstance();
        if (nonce == 0 || payload.nonce() != nonce) {
            EclipseMod.LOGGER.info("Credits close ignored: nonce mismatch (got {}, have {})",
                    payload.nonce(), nonce);
            return;
        }
        if (minecraft.hasSingleplayerServer()) {
            EclipseMod.LOGGER.info("Credits close ignored: singleplayer/LAN host");
            return;
        }
        if (!CreditsConfig.allowFinaleClose()) {
            EclipseMod.LOGGER.info("Credits close ignored: allowFinaleClose=false");
            return;
        }
        closeCountdown = Math.max(1, payload.delayTicks());
        // Music-synced fade-out: the finale channel crossfades to silence over the same
        // 40t the countdown runs, so Minecraft.stop() never hard-cuts day_final.
        MusicCues.stop();
        EclipseMod.LOGGER.info("Credits close scheduled in {} ticks (music fading out)", closeCountdown);
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        // FIN-6 zoom ramp: eased per-tick step toward the target multiplier.
        if (fovRampElapsed < fovRampTicks) {
            fovRampElapsed++;
            float linear = fovRampElapsed / (float) fovRampTicks;
            float eased = linear * linear * (3.0F - 2.0F * linear);
            fovScale = Mth.lerp(eased, fovFrom, fovTarget);
            CameraDirector.setExternalFovScale(fovScale);
        }
        if (closeCountdown < 0) {
            return;
        }
        if (--closeCountdown == 0) {
            closeCountdown = -1;
            Minecraft minecraft = Minecraft.getInstance();
            EclipseMod.LOGGER.info("Credits finale: closing the client (Minecraft.stop())");
            minecraft.execute(minecraft::stop);
            return;
        }
        // Two faint heartbeat thumps under the last second of pure black (the ECLIPSE
        // card is gone by now — CreditsSequence trimmed it to end ~20t before the stop).
        if ((closeCountdown == HEARTBEAT_FIRST_AT || closeCountdown == HEARTBEAT_SECOND_AT)
                && EclipseClientConfig.heartbeatSound()) {
            Minecraft.getInstance().getSoundManager().play(SimpleSoundInstance.forUI(
                    SoundEvents.WARDEN_HEARTBEAT,
                    closeCountdown == HEARTBEAT_FIRST_AT ? 0.7F : 0.62F,
                    closeCountdown == HEARTBEAT_FIRST_AT ? 0.4F : 0.3F));
        }
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        nonce = 0;
        closeCountdown = -1;
        CameraDirector.setExternalHudSuppressed(false);
        resetFov();
    }
}
