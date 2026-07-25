package dev.projecteclipse.eclipse.client.drama;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.veilfx.FxAnchors;
import dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * PH-ALTAR (IDEAS-world.md #9) — the permanent "you finished the altar" tell: three lazy
 * gold-violet Photon ara ribbons ({@code eclipse:altar_corona_idle}) orbiting the altar
 * crown, only at altar level {@value #CORONA_MIN_LEVEL}, only up close. This is the
 * WINDOWED-loop controller mandated by INTEGRATION.md §4 (the {@code SanctumLightfall}
 * window pattern beside {@link AltarIdleMotes}): a materialize/release hysteresis band
 * ({@value #MATERIALIZE_DIST}/{@value #RELEASE_DIST}) so the boundary never flickers,
 * a {@value #RETRY_TICKS}-tick retry cadence for refused spawns, and unconditional
 * release on {@code reducedFx} / anchor loss / level drop / dimension change / logout.
 *
 * <p>Gates: overworld + NOT {@code reducedFx} + {@link FxAnchors#ALTAR_CENTER} synced +
 * {@code ClientStateCache.altarLevel >= }{@value #CORONA_MIN_LEVEL} (both login-resynced)
 * + camera inside the band. The L5 gate means at most ONE such loop exists per world,
 * endgame only. The loop leg is spawned at {@code anchor + [0, }{@value #CROWN_ABOVE_ANCHOR}{@code , 0]}
 * (above {@code AltarVeilSky}'s crown read) through the
 * {@code FxCues.CUE_ALTAR_CORONA_IDLE} registry row (registered by
 * {@code veilfx/AltarPhotonFxRows}) — {@code PhotonFxRegistry.ensureLoop} is idempotent
 * and re-spawns pruned legs; {@code releaseLoop(graceful)} fades the ribbons out.</p>
 *
 * <p><b>Fallback / budgets:</b> the row has no Quasar leg by design — the shipped idle
 * stack ({@link AltarIdleMotes}, {@code SanctumLightfall}, {@code AltarVeilSky}) is the
 * photon-less L5 read and keeps running unchanged (Mode.LAYER). Photon absent / missing
 * asset / {@code reducedFx} / bridge budget refusal ⇒ silent no-op, bit-identical to
 * today. Loop cost while open: 3 carriers + 3 ara ribbons + ≤ 30 dust motes, one
 * executor against {@code PhotonBridge.MAX_LIVE_EXECUTORS}. Idle cost while far:
 * one distance check per tick.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class AltarCoronaIdle {
    /** The corona is the finished-altar tell — endgame only. */
    private static final int CORONA_MIN_LEVEL = 5;
    /** Window materializes within this camera distance (blocks)… */
    private static final double MATERIALIZE_DIST = 48.0D;
    /** …and releases only beyond this one (hysteresis — no boundary thrash). */
    private static final double RELEASE_DIST = 60.0D;
    private static final double MATERIALIZE_DIST_SQ = MATERIALIZE_DIST * MATERIALIZE_DIST;
    private static final double RELEASE_DIST_SQ = RELEASE_DIST * RELEASE_DIST;
    /** Crown height above the {@code ALTAR_CENTER} anchor (above AltarVeilSky's crown). */
    private static final double CROWN_ABOVE_ANCHOR = 3.2D;
    /** Refused-spawn retry cadence (ticks) — the SanctumLightfall cadence. */
    private static final int RETRY_TICKS = 40;

    /** Whether the window is currently open (drives the hysteresis band). */
    private static boolean open;
    private static int retryCountdown;

    private AltarCoronaIdle() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null || level.dimension() != Level.OVERWORLD
                || EclipseClientConfig.reducedFx()) {
            close(false);
            return;
        }
        Vec3 anchor = FxAnchors.get(FxAnchors.ALTAR_CENTER);
        if (anchor == null || ClientStateCache.altarLevel < CORONA_MIN_LEVEL) {
            close(false);
            return;
        }
        double distSq = minecraft.gameRenderer.getMainCamera().getPosition().distanceToSqr(anchor);
        if (distSq > (open ? RELEASE_DIST_SQ : MATERIALIZE_DIST_SQ)) {
            close(true); // walked away: graceful fade, not a pop
            return;
        }
        if (minecraft.isPaused()) {
            return; // keep the window, freeze the cadence
        }
        open = true;
        if (--retryCountdown > 0) {
            return;
        }
        boolean live = PhotonFxRegistry.ensureLoop(FxCues.CUE_ALTAR_CORONA_IDLE,
                anchor.add(0.0D, CROWN_ABOVE_ANCHOR, 0.0D));
        // Healthy leg: re-ensure every tick (idempotent prune + re-spawn of pruned legs).
        // Refused (photon absent / missing asset / executor budget): back off RETRY_TICKS.
        retryCountdown = live ? 1 : RETRY_TICKS;
    }

    /** Disconnect reset (QuasarSpawner.DisconnectReset pattern; registry releases too). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        close(false);
    }

    private static void close(boolean graceful) {
        if (open) {
            PhotonFxRegistry.releaseLoop(FxCues.CUE_ALTAR_CORONA_IDLE, graceful);
        }
        open = false;
        retryCountdown = 0;
    }
}
