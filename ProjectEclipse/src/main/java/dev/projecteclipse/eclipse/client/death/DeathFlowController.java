package dev.projecteclipse.eclipse.client.death;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.death.DeathFlowPayloads;
import dev.projecteclipse.eclipse.network.death.DeathFlowPayloads.S2CDeathStatePayload;
import dev.projecteclipse.eclipse.network.death.DeathFlowPayloads.S2CRevivedPayload;
import dev.projecteclipse.eclipse.veilfx.TransitionFx;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.screens.ReceivingLevelScreen;
import net.minecraft.network.chat.Component;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.ScreenEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Client state machine of the death/ship-respawn flow (P3 §3.7, WB-DEATH): mirrors the
 * server phases carried by {@link S2CDeathStatePayload} — death → ship wake → door open →
 * fade home — and drives everything the server cannot: the {@link TransitionFx}
 * portal-enter/exit envelopes around the two dimension hops, the action-bar door prompts
 * ("Die Tür öffnet sich …"), the sneak-to-skip input during the door phase, the
 * suppression of the vanilla {@link ReceivingLevelScreen} while a flow hop hides behind
 * the black, and the handoff to {@link GhostHeartsLayer} on {@link S2CRevivedPayload}.
 *
 * <p>Installs the {@link DeathFlowPayloads} client consumers from static init — this class
 * is an {@code @EventBusSubscriber(Dist.CLIENT)}, so it is class-loaded during client mod
 * construction, before any payload can arrive (the {@code GrowthPayloads} seam pattern).</p>
 *
 * <p><b>Kill-switch:</b> all client theater (fades, prompts, screen suppression — and, via
 * {@link DeathScreenSwap}, the custom screen itself) respects the {@code customDeathScreen}
 * config; phase state is still tracked while it is off so flipping the toggle mid-session
 * behaves. The ghost HUD ({@link GhostHeartsLayer}) is deliberately NOT tied to the
 * toggle — it conveys the gameplay-relevant ghost state.</p>
 *
 * <p><b>Fail-safes:</b> phases auto-clear {@value #PHASE_STALE_MILLIS} ms after the last
 * server update (the server's own hard caps fire long before); everything resets on
 * logout; screen suppression is bounded by {@value #SUPPRESS_WINDOW_MILLIS} ms windows,
 * so a lost {@code PHASE_CLEAR} can never suppress loading screens forever.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class DeathFlowController {
    /** Client-side dead-man switch: no flow payload for this long → clear local theater. */
    private static final long PHASE_STALE_MILLIS = 30_000L;
    /** How long after a hop-adjacent phase the vanilla level-loading screen stays suppressed. */
    private static final long SUPPRESS_WINDOW_MILLIS = 4_000L;
    /** Action-bar prompts are re-pushed on this cadence while a ship phase is live. */
    private static final int PROMPT_REFRESH_TICKS = 30;
    /** …but only for this long per phase (a ghost's SHIP_WAKE never advances — no nagging). */
    private static final int PROMPT_REFRESH_WINDOW_TICKS = 160;
    /** The door-open prompt switches from "opens" to the walk hint after this many ticks. */
    private static final int DOOR_PROMPT_SWITCH_TICKS = 40;
    /** Sneak-skip is armed this many ticks into the door phase (no accidental instant skip). */
    private static final int SKIP_ARM_TICKS = 10;

    private static int phase = DeathFlowPayloads.PHASE_CLEAR;
    private static boolean ghost;
    private static long phaseSetMillis;
    private static int phaseTicks;
    private static boolean skipSent;

    // Last PHASE_DEATH data for the death screen (fallback: ClientStateCache.lives).
    private static boolean deathStateValid;
    private static int deathHearts;
    private static boolean deathGhost;
    private static int deathLostHeartIndex = -1;
    private static String deathCauseKey = "generic";
    private static int deathHoldTicks;

    /** End of the current ReceivingLevelScreen suppression window (0 = none). */
    private static long suppressUntilMillis;

    static {
        DeathFlowPayloads.setClientDeathStateHandler(DeathFlowController::handleDeathState);
        DeathFlowPayloads.setClientRevivedHandler(DeathFlowController::handleRevived);
    }

    private DeathFlowController() {}

    // ------------------------------------------------------------------ payload intake

    private static void handleDeathState(S2CDeathStatePayload payload) {
        int previous = phase;
        phase = payload.phase();
        ghost = payload.ghost();
        phaseSetMillis = System.currentTimeMillis();
        phaseTicks = 0;
        skipSent = false;

        switch (payload.phase()) {
            case DeathFlowPayloads.PHASE_DEATH -> {
                deathStateValid = true;
                deathHearts = payload.heartsRemaining();
                deathGhost = payload.ghost();
                deathLostHeartIndex = payload.lostHeartIndex();
                deathCauseKey = payload.causeKey();
                deathHoldTicks = payload.holdTicks();
            }
            case DeathFlowPayloads.PHASE_SHIP_WAKE -> {
                if (theaterOn()) {
                    // Release the black from the respawn click (a no-op glitch tail if the
                    // enter side never ran — instant-respawn gamerule, relog resume, ghosts).
                    TransitionFx.playPortalExit(24);
                    prompt(payload.ghost() ? "message.eclipse.death.door_closed"
                            : "message.eclipse.death.ship_wake");
                }
                armSuppression();
            }
            case DeathFlowPayloads.PHASE_DOOR_OPEN -> {
                if (theaterOn()) {
                    prompt("message.eclipse.death.door_opening");
                }
            }
            case DeathFlowPayloads.PHASE_RETURNING -> {
                if (theaterOn()) {
                    TransitionFx.playPortalEnter(12);
                }
                armSuppression();
            }
            case DeathFlowPayloads.PHASE_CLEAR -> {
                deathStateValid = false;
                if (theaterOn() && previous == DeathFlowPayloads.PHASE_RETURNING) {
                    TransitionFx.playPortalExit(24);
                    armSuppression();
                }
            }
            default -> { }
        }
    }

    private static void handleRevived(S2CRevivedPayload payload) {
        GhostHeartsLayer.beginReviveBurst(payload.heartsRestored());
        if (theaterOn()) {
            prompt("message.eclipse.death.revived");
        }
    }

    // ------------------------------------------------------------------ screen seam

    /**
     * Called by {@link EclipseDeathScreen} the moment the respawn button fires: fades to
     * black over the vanilla respawn + ship teleport and opens the loading-screen
     * suppression window ({@code PHASE_SHIP_WAKE} releases the fade; its stale failsafe
     * would release it too).
     */
    static void noteRespawnClicked() {
        PacketDistributor.sendToServer(
                new DeathFlowPayloads.C2SRespawnReadyPayload(DeathFlowPayloads.ACTION_SCREEN_READY));
        if (theaterOn()) {
            TransitionFx.playPortalEnter(12);
        }
        armSuppression();
    }

    /** Death-screen data accessors (payload truth with {@link ClientStateCache} fallback). */
    static boolean hasDeathState() {
        return deathStateValid;
    }

    static int deathHearts() {
        return deathStateValid ? deathHearts : Math.max(0, ClientStateCache.lives);
    }

    static boolean deathGhost() {
        return deathStateValid ? deathGhost : ClientStateCache.lives <= 0;
    }

    static int deathLostHeartIndex() {
        return deathStateValid ? deathLostHeartIndex : Math.max(0, ClientStateCache.lives);
    }

    static String deathCauseKey() {
        return deathStateValid ? deathCauseKey : "generic";
    }

    static int deathHoldTicks() {
        return deathStateValid ? deathHoldTicks
                : dev.projecteclipse.eclipse.lives.DeathFlowHooks.HOLD_TICKS_NORMAL;
    }

    // ------------------------------------------------------------------ tick / events

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null || minecraft.player == null || phase == DeathFlowPayloads.PHASE_CLEAR) {
            return;
        }
        if (System.currentTimeMillis() - phaseSetMillis > PHASE_STALE_MILLIS) {
            // Server went quiet (should be impossible — its hard caps fire at 8-12 s).
            phase = DeathFlowPayloads.PHASE_CLEAR;
            deathStateValid = false;
            return;
        }
        if (minecraft.isPaused()) {
            return;
        }
        phaseTicks++;
        if (!theaterOn()) {
            return;
        }

        if (phase == DeathFlowPayloads.PHASE_SHIP_WAKE && phaseTicks % PROMPT_REFRESH_TICKS == 0) {
            prompt(ghost ? "message.eclipse.death.door_closed" : "message.eclipse.death.ship_wake");
        } else if (phase == DeathFlowPayloads.PHASE_DOOR_OPEN) {
            if (phaseTicks % PROMPT_REFRESH_TICKS == 0) {
                prompt(phaseTicks < DOOR_PROMPT_SWITCH_TICKS
                        ? "message.eclipse.death.door_opening"
                        : "message.eclipse.death.door_walk");
            }
            if (!skipSent && !ghost && phaseTicks > SKIP_ARM_TICKS
                    && minecraft.player.isShiftKeyDown()) {
                skipSent = true;
                PacketDistributor.sendToServer(new DeathFlowPayloads.C2SRespawnReadyPayload(
                        DeathFlowPayloads.ACTION_DOOR_SKIP));
            }
        }
    }

    /**
     * Suppresses the vanilla "receiving level" screen while a flow hop is hiding behind
     * the {@link TransitionFx} black (§3.7 "no vanilla screens"). Bounded by the
     * suppression window, exact-class-checked, and inert while the kill-switch is off.
     * The exact-class check matters: {@code LoadingScreenSwap}'s custom loading screen
     * EXTENDS {@link ReceivingLevelScreen}, so an {@code instanceof} here could cancel
     * the replacement screen that was just installed (blank-screen race, eval LOW).
     */
    @SubscribeEvent
    static void onScreenOpening(ScreenEvent.Opening event) {
        if (!theaterOn() || System.currentTimeMillis() >= suppressUntilMillis) {
            return;
        }
        if (event.getNewScreen() != null
                && event.getNewScreen().getClass() == ReceivingLevelScreen.class) {
            event.setCanceled(true);
        }
    }

    /** A flow can never leak into the next session. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        phase = DeathFlowPayloads.PHASE_CLEAR;
        ghost = false;
        phaseTicks = 0;
        skipSent = false;
        deathStateValid = false;
        suppressUntilMillis = 0L;
    }

    // ------------------------------------------------------------------ helpers

    private static boolean theaterOn() {
        return EclipseClientConfig.customDeathScreen();
    }

    private static void armSuppression() {
        suppressUntilMillis = System.currentTimeMillis() + SUPPRESS_WINDOW_MILLIS;
    }

    /** Action-bar line (anonymity-safe, self-fading — no new HUD layer needed). */
    private static void prompt(String key) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.player != null) {
            Component text = EclipseLang.tr(key);
            minecraft.gui.setOverlayMessage(text, false);
        }
    }
}
