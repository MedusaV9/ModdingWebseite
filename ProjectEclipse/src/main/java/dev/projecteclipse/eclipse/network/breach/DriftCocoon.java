package dev.projecteclipse.eclipse.network.breach;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.veilfx.AtmospherePhotonFxRows;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import dev.projecteclipse.eclipse.veilfx.QuasarSpawner;
import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * NEWFX-D2 — <b>Drift Cocoon</b> (PLAN-NEWFX §2): while the nether-breach glitch-drift
 * carries the LOCAL player, a loose cocoon of glitch-embers and stretched light-threads
 * wraps the faller, stuttering sideways on the drift's frame-skip beats — falling through
 * the world's seams, not through air.
 *
 * <p><b>Seam:</b> {@link BreachClientFx#handle} — every {@code DRIFT_DOWN}/{@code
 * DRIFT_UP} payload (capture AND each dimension seam re-pulse) opens/refreshes the
 * window; {@code DRIFT_END}, a dimension change/respawn ({@code Clone} — the seam
 * teleport replaces the player entity, so the next payload re-opens on the new one),
 * logout, or the {@value #WINDOW_TIMEOUT_TICKS}-tick lost-packet failsafe closes it.</p>
 *
 * <p><b>Tech (plan row):</b> entity-attached WINDOWED loop on the local player —
 * {@code Mode.REPLACE} semantics run directly through the bridge because registry rows
 * are position-anchored (see {@link AtmospherePhotonFxRows}): the Photon cocoon
 * ({@code eclipse:breach_drift_cocoon}, {@link PhotonBridge#ensureAttachedFx}) is
 * preferred; the Quasar orbit stand-in ({@link QuasarSpawner#ensureAttached}) runs only
 * while the Photon leg is down. The server's REVERSE_PORTAL ring + ash streaks
 * ({@code BreachTransferService.ambientTick}) remain the untouched photon-less floor.
 * <b>Budget:</b> AMBIENT (stand-in leg; charged only when a NEW emitter spawns).
 * <b>reducedFx:</b> the window never opens — and force-releases if the toggle flips
 * mid-transit (loop law, INTEGRATION.md §4).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class DriftCocoon {
    /**
     * Lost-DRIFT_END failsafe (ticks). The longest legal ride is the descent chain
     * (~10–20 s per plan); the server re-pulses each seam, refreshing this window, so
     * a healthy transit never hits the timeout.
     */
    static final int WINDOW_TIMEOUT_TICKS = 20 * 30;

    /** Remaining window ticks; {@code <= 0} = closed. */
    private static int windowTicks;

    private DriftCocoon() {}

    /** DRIFT_DOWN/DRIFT_UP consumer ({@link BreachClientFx}): opens/refreshes the window. */
    static void open() {
        if (EclipseClientConfig.reducedFx()) {
            return; // plan row: the window never opens under reducedFx
        }
        windowTicks = WINDOW_TIMEOUT_TICKS;
    }

    /** DRIFT_END consumer ({@link BreachClientFx}): graceful release (threads snap out). */
    static void close() {
        release(true);
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        if (windowTicks <= 0) {
            return;
        }
        LocalPlayer player = Minecraft.getInstance().player;
        if (player == null || EclipseClientConfig.reducedFx()) {
            release(false); // level gone / toggle flipped mid-ride: hard release
            return;
        }
        windowTicks--;
        if (windowTicks == 0) {
            EclipseMod.LOGGER.debug("DriftCocoon: window timeout (missed DRIFT_END?)");
            release(true);
            return;
        }
        // REPLACE semantics, re-ensured on the tick cadence (both calls are cheap
        // early-outs while their leg is healthy; budget charges only on NEW spawns).
        boolean photonLive = PhotonBridge.ensureAttachedFx(
                AtmospherePhotonFxRows.FX_BREACH_DRIFT_COCOON, player,
                PhotonBridge.AUTO_ROTATE_NONE, null);
        if (photonLive) {
            QuasarSpawner.removeAttached(
                    AtmospherePhotonFxRows.QUASAR_DRIFT_COCOON_ORBIT, player);
        } else {
            QuasarSpawner.ensureAttached(
                    AtmospherePhotonFxRows.QUASAR_DRIFT_COCOON_ORBIT, player,
                    FxBudget.Channel.AMBIENT);
        }
    }

    /**
     * Dimension change / respawn: the old player entity (and everything riding it) is
     * gone — drop the dead handles, but KEEP the window. The server sends each seam's
     * DRIFT payload BEFORE the teleport ({@code BreachTransferService.sendDriftPhase}
     * precedes {@code teleportTo}), so a hard close here would land AFTER that packet's
     * refresh and kill the cocoon for the whole nether stretch. The next tick re-ensures
     * both legs on the replacement entity; non-drift dimension changes never have an
     * open window, and an aborted ride is closed by DRIFT_END ({@code releaseStaleDrift}
     * covers death/tp) or the timeout failsafe.
     */
    @SubscribeEvent
    static void onClone(ClientPlayerNetworkEvent.Clone event) {
        LocalPlayer oldPlayer = event.getOldPlayer();
        if (oldPlayer != null) {
            PhotonBridge.stopAttachedFx(AtmospherePhotonFxRows.FX_BREACH_DRIFT_COCOON,
                    oldPlayer, true);
            QuasarSpawner.removeAttached(
                    AtmospherePhotonFxRows.QUASAR_DRIFT_COCOON_ORBIT, oldPlayer);
        }
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        release(false);
    }

    private static void release(boolean graceful) {
        windowTicks = 0;
        LocalPlayer player = Minecraft.getInstance().player;
        if (player != null) {
            PhotonBridge.stopAttachedFx(AtmospherePhotonFxRows.FX_BREACH_DRIFT_COCOON,
                    player, !graceful);
            QuasarSpawner.removeAttached(
                    AtmospherePhotonFxRows.QUASAR_DRIFT_COCOON_ORBIT, player);
        }
    }
}
