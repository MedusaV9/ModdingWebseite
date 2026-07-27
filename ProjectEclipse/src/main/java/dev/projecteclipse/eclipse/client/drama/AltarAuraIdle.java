package dev.projecteclipse.eclipse.client.drama;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.cutscene.client.CameraDirector;
import dev.projecteclipse.eclipse.veilfx.AltarAura2FxRows;
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
 * pattern) for the {@code veilfx.AltarAuraFxRows} (V1, dais-scale) and
 * {@code veilfx.AltarAura2FxRows} (V2, island-scale) loop rows. Each row is its own
 * hysteresis window so the boundary never flickers; all key off the client-synced
 * {@link FxAnchors#ALTAR_CENTER} anchor and {@link ClientStateCache#altarLevel}:
 *
 * <ul>
 *   <li><b>Stage 1+</b> — {@code altar_aura_motes} (rising motes + ground-fog ring)
 *       and the island-edge {@code altar_aura_rim_*} ring, near band
 *       {@value #NEAR_MATERIALIZE_DIST}/{@value #NEAR_RELEASE_DIST}.</li>
 *   <li><b>Stage 2+</b> — {@code altar_aura_glyphs} (rune-spark orbit + ground pulse),
 *       {@code altar_aura_spiral_*} (streams converging rim → crown, near band) and
 *       {@code altar_aura_pillar} (the soft light column — the FAR tell, band
 *       {@value #FAR_MATERIALIZE_DIST}/{@value #FAR_RELEASE_DIST}).</li>
 *   <li><b>Stage 4+</b> — {@code altar_aura_bands} (counter-orbiting light bands +
 *       energy arcs, near band). The L5 corona ribbons stay {@link AltarCoronaIdle}'s
 *       job — the two controllers deliberately never share a row.</li>
 * </ul>
 *
 * <p><b>F-075 V2 tier swap:</b> the rim and spiral families carry {@code minLevel} AND
 * {@code maxLevel} (rim lo 1–2 / mid 3–4 / hi 5; spiral lo 2–3 / hi 4+), so exactly ONE
 * rim and ONE spiral executor is ever live. Outgrowing a tier releases it gracefully
 * (fade) while the next tier blooms; a stage DROP (admin reset) releases instantly.</p>
 *
 * <p><b>Stage-up bloom beat:</b> the controller tracks the last seen stage — when it
 * RISES, every newly-eligible closed window waits {@value #STAGE_BLOOM_DELAY_TICKS} t
 * before its first spawn, so the new layer blooms right after the
 * {@code altar_aura_powerup} ring wave (fired by {@code AltarCeremonyFx}) has swept the
 * island instead of popping at t 0. Tracking the synced stage here (instead of a
 * ceremony callback) also covers {@code /eclipse altar set} and avoids any payload
 * ordering race.</p>
 *
 * <p><b>LOD / budgets:</b> near-field aura loops exist only under
 * {@value #NEAR_RELEASE_DIST} blocks; the far tell is ONE beam + ≤ 10 motes. Worst case
 * (L5, standing on the island) this holds 6 aura executors (motes, glyphs, bands,
 * rim_hi, spiral_hi, pillar) + the corona = 7 of {@code PhotonBridge.MAX_LIVE_EXECUTORS}.
 * Idle cost while far: one distance check per row per tick. Everything releases on
 * {@code reducedFx} / cutscene camera ({@link CameraDirector#isActive()}) / anchor loss /
 * stage drop / dimension change / logout; refused spawns retry every
 * {@value #RETRY_TICKS} t. Photon-less clients keep the shipped Quasar idle stack
 * untouched (the rows carry no Quasar leg — see {@code AltarAuraFxRows}).</p>
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
    /**
     * F-075 V2: first-spawn delay of newly stage-eligible windows after a stage RISE —
     * the {@code altar_aura_powerup} wave (~1.2 s altar → rim) lands first, then the
     * new layer fades in.
     */
    private static final int STAGE_BLOOM_DELAY_TICKS = 45;
    /**
     * V2 island-scale rows anchor at the ISLAND TOP (the altar block sits
     * {@code AltarSanctumBuilder.ALTAR_ABOVE_GROUND} = 4 above the surface); their
     * emitter shapes are authored surface-relative.
     */
    private static final double ISLAND_TOP_OFFSET = -4.0D;

    /** One independent hysteresis window per loop row. */
    private static final class Window {
        final ResourceLocation cue;
        final int minLevel;
        /** Last stage this tier serves — above it the next tier takes over (V2 swap). */
        final int maxLevel;
        final double materializeSq;
        final double releaseSq;
        /** Loop anchor height above the {@code ALTAR_CENTER} anchor (blocks). */
        final double yOffset;
        boolean open;
        int retryCountdown;

        Window(ResourceLocation cue, int minLevel, int maxLevel, double materialize,
                double release, double yOffset) {
            this.cue = cue;
            this.minLevel = minLevel;
            this.maxLevel = maxLevel;
            this.materializeSq = materialize * materialize;
            this.releaseSq = release * release;
            this.yOffset = yOffset;
        }
    }

    private static final Window[] WINDOWS = {
        // Stage 1: the whisper — motes ring + floor fog (asset offsets are floor-relative).
        new Window(AltarAuraFxRows.CUE_ALTAR_AURA_MOTES, 1, Integer.MAX_VALUE,
                NEAR_MATERIALIZE_DIST, NEAR_RELEASE_DIST, -0.5D),
        // Stage 2: living script around the crown + the ground pulse.
        new Window(AltarAuraFxRows.CUE_ALTAR_AURA_GLYPHS, 2, Integer.MAX_VALUE,
                NEAR_MATERIALIZE_DIST, NEAR_RELEASE_DIST, 1.2D),
        // Stage 2: the far tell — one soft column, readable across the disc.
        new Window(AltarAuraFxRows.CUE_ALTAR_AURA_PILLAR, 2, Integer.MAX_VALUE,
                FAR_MATERIALIZE_DIST, FAR_RELEASE_DIST, 1.5D),
        // Stage 4: the high-stage crown — orbit bands + energy arcs.
        new Window(AltarAuraFxRows.CUE_ALTAR_AURA_BANDS, 4, Integer.MAX_VALUE,
                NEAR_MATERIALIZE_DIST, NEAR_RELEASE_DIST, 1.5D),
        // F-075 V2 rim ring tiers (island-edge read; exactly one live at a time).
        new Window(AltarAura2FxRows.CUE_ALTAR_AURA_RIM_LO, 1, 2,
                NEAR_MATERIALIZE_DIST, NEAR_RELEASE_DIST, ISLAND_TOP_OFFSET),
        new Window(AltarAura2FxRows.CUE_ALTAR_AURA_RIM_MID, 3, 4,
                NEAR_MATERIALIZE_DIST, NEAR_RELEASE_DIST, ISLAND_TOP_OFFSET),
        new Window(AltarAura2FxRows.CUE_ALTAR_AURA_RIM_HI, 5, Integer.MAX_VALUE,
                NEAR_MATERIALIZE_DIST, NEAR_RELEASE_DIST, ISLAND_TOP_OFFSET),
        // F-075 V2 spiral stream tiers (rim → crown convergence).
        new Window(AltarAura2FxRows.CUE_ALTAR_AURA_SPIRAL_LO, 2, 3,
                NEAR_MATERIALIZE_DIST, NEAR_RELEASE_DIST, ISLAND_TOP_OFFSET),
        new Window(AltarAura2FxRows.CUE_ALTAR_AURA_SPIRAL_HI, 4, Integer.MAX_VALUE,
                NEAR_MATERIALIZE_DIST, NEAR_RELEASE_DIST, ISLAND_TOP_OFFSET),
    };

    /** Last stage seen by the tick loop; −1 = unobserved (login/world change). */
    private static int lastStage = -1;

    private AltarAuraIdle() {}

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null || level.dimension() != Level.OVERWORLD
                || EclipseClientConfig.reducedFx()) {
            closeAll(false);
            lastStage = -1;
            return;
        }
        // Cutscene cameras own the frame (and the executor budget): release gracefully,
        // re-materialize once the director hands control back.
        if (CameraDirector.isActive()) {
            closeAll(true);
            return;
        }
        Vec3 anchor = FxAnchors.get(FxAnchors.ALTAR_CENTER);
        if (anchor == null) {
            closeAll(false);
            return;
        }
        int stage = Math.min(Math.max(ClientStateCache.altarLevel, 0), 5);
        if (lastStage >= 0 && stage > lastStage) {
            // Stage rose: newly-eligible closed windows wait for the power-up wave.
            for (Window window : WINDOWS) {
                if (!window.open && window.minLevel > lastStage && window.minLevel <= stage) {
                    window.retryCountdown = STAGE_BLOOM_DELAY_TICKS;
                }
            }
        }
        lastStage = stage;
        double distSq = minecraft.gameRenderer.getMainCamera().getPosition().distanceToSqr(anchor);
        boolean paused = minecraft.isPaused();
        for (Window window : WINDOWS) {
            if (stage < window.minLevel) {
                close(window, false); // stage gate (admin resets drop instantly, no fade)
                continue;
            }
            if (stage > window.maxLevel) {
                close(window, true); // tier outgrown: graceful fade under the next tier
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
        lastStage = -1;
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
