package dev.projecteclipse.eclipse.client.drama;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.veilfx.AltarAuraFxRows;
import dev.projecteclipse.eclipse.veilfx.FxAnchors;
import dev.projecteclipse.eclipse.veilfx.PhotonFxRegistry;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * F-075 — the permanent, ALTAR-LEVEL-scaled aura of the sanctum island: the WINDOWED
 * loop controller (INTEGRATION.md §4, the {@link AltarCoronaIdle}/{@code SanctumLightfall}
 * pattern) for the four {@code veilfx.AltarAuraFxRows} loop rows. Each row is its own
 * hysteresis window so the boundary never flickers; all four key off the client-synced
 * {@link FxAnchors#ALTAR_CENTER} anchor and {@link ClientStateCache#altarLevel}:
 *
 * <ul>
 *   <li><b>Stage 1+</b> — {@code altar_aura_motes} (rising motes + ground-fog ring),
 *       near band {@value #NEAR_MATERIALIZE_DIST}/{@value #NEAR_RELEASE_DIST}.</li>
 *   <li><b>Stage 2+</b> — {@code altar_aura_glyphs} (rune-spark orbit + ground pulse,
 *       near band) and {@code altar_aura_pillar} (the soft light column — the FAR tell,
 *       band {@value #FAR_MATERIALIZE_DIST}/{@value #FAR_RELEASE_DIST}).</li>
 *   <li><b>Stage 4+</b> — {@code altar_aura_bands} (counter-orbiting light bands +
 *       energy arcs, near band). The L5 corona ribbons stay {@link AltarCoronaIdle}'s
 *       job — the two controllers deliberately never share a row.</li>
 * </ul>
 *
 * <p><b>LOD / budgets:</b> near-field aura loops exist only under
 * {@value #NEAR_RELEASE_DIST} blocks; the far tell is ONE beam + ≤ 10 motes. Worst case
 * (L5, standing on the island) this holds 4 aura executors + the corona = 5 of
 * {@code PhotonBridge.MAX_LIVE_EXECUTORS}. Idle cost while far: one distance check per
 * row per tick. Everything releases on {@code reducedFx} / anchor loss / stage drop /
 * dimension change / logout; refused spawns retry every {@value #RETRY_TICKS} t.
 * Photon-less clients keep the shipped Quasar idle stack untouched (the rows carry no
 * Quasar leg — see {@code AltarAuraFxRows}).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class AltarAuraIdle {
    /** Near-field aura loops materialize within this camera distance (blocks)… */
    private static final double NEAR_MATERIALIZE_DIST = 88.0D;
    /** …and release only beyond this one (hysteresis — the F-075 "&lt; 96" LOD law). */
    private static final double NEAR_RELEASE_DIST = 96.0D;
    /** The far light-column tell materializes within this distance… */
    private static final double FAR_MATERIALIZE_DIST = 200.0D;
    /** …and releases beyond this one. */
    private static final double FAR_RELEASE_DIST = 220.0D;
    /** Refused-spawn retry cadence (ticks) — the SanctumLightfall cadence. */
    private static final int RETRY_TICKS = 40;

    /** One independent hysteresis window per loop row. */
    private static final class Window {
        final ResourceLocation cue;
        final int minLevel;
        final double materializeSq;
        final double releaseSq;
        /** Loop anchor height above the {@code ALTAR_CENTER} anchor (blocks). */
        final double yOffset;
        boolean open;
        int retryCountdown;

        Window(ResourceLocation cue, int minLevel, double materialize, double release,
                double yOffset) {
            this.cue = cue;
            this.minLevel = minLevel;
            this.materializeSq = materialize * materialize;
            this.releaseSq = release * release;
            this.yOffset = yOffset;
        }
    }

    private static final Window[] WINDOWS = {
        // Stage 1: the whisper — motes ring + floor fog (asset offsets are floor-relative).
        new Window(AltarAuraFxRows.CUE_ALTAR_AURA_MOTES, 1,
                NEAR_MATERIALIZE_DIST, NEAR_RELEASE_DIST, -0.5D),
        // Stage 2: living script around the crown + the ground pulse.
        new Window(AltarAuraFxRows.CUE_ALTAR_AURA_GLYPHS, 2,
                NEAR_MATERIALIZE_DIST, NEAR_RELEASE_DIST, 1.2D),
        // Stage 2: the far tell — one soft column, readable across the disc.
        new Window(AltarAuraFxRows.CUE_ALTAR_AURA_PILLAR, 2,
                FAR_MATERIALIZE_DIST, FAR_RELEASE_DIST, 1.5D),
        // Stage 4: the high-stage crown — orbit bands + energy arcs.
        new Window(AltarAuraFxRows.CUE_ALTAR_AURA_BANDS, 4,
                NEAR_MATERIALIZE_DIST, NEAR_RELEASE_DIST, 1.5D),
    };

    private AltarAuraIdle() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null || level.dimension() != Level.OVERWORLD
                || EclipseClientConfig.reducedFx()) {
            closeAll(false);
            return;
        }
        Vec3 anchor = FxAnchors.get(FxAnchors.ALTAR_CENTER);
        if (anchor == null) {
            closeAll(false);
            return;
        }
        int stage = Math.min(Math.max(ClientStateCache.altarLevel, 0), 5);
        double distSq = minecraft.gameRenderer.getMainCamera().getPosition().distanceToSqr(anchor);
        boolean paused = minecraft.isPaused();
        for (Window window : WINDOWS) {
            if (stage < window.minLevel) {
                close(window, false); // stage gate (admin resets drop instantly, no fade)
                continue;
            }
            if (distSq > (window.open ? window.releaseSq : window.materializeSq)) {
                close(window, true); // walked away: graceful fade, not a pop
                continue;
            }
            if (paused) {
                continue; // keep the window, freeze the cadence
            }
            window.open = true;
            if (--window.retryCountdown > 0) {
                continue;
            }
            boolean live = PhotonFxRegistry.ensureLoop(window.cue,
                    anchor.add(0.0D, window.yOffset, 0.0D));
            // Healthy leg: re-ensure every tick (idempotent prune + re-spawn).
            // Refused (photon absent / missing asset / executor budget): back off.
            window.retryCountdown = live ? 1 : RETRY_TICKS;
        }
    }

    /** Disconnect reset (QuasarSpawner.DisconnectReset pattern; registry releases too). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        closeAll(false);
    }

    private static void close(Window window, boolean graceful) {
        if (window.open) {
            PhotonFxRegistry.releaseLoop(window.cue, graceful);
        }
        window.open = false;
        window.retryCountdown = 0;
    }

    private static void closeAll(boolean graceful) {
        for (Window window : WINDOWS) {
            close(window, graceful);
        }
    }
}
