package dev.projecteclipse.eclipse.veilfx;

import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import foundry.veil.api.client.render.VeilRenderSystem;

/**
 * Global FX budgets (P2 §3.1/§3.5, FROZEN API). Every Quasar emitter spawn and every dynamic
 * FX light goes through this — the §3.5 numbers are acceptance criteria:
 * <ul>
 *   <li>Emitters: ≤ {@value #GLOBAL_PER_WINDOW} spawns/s globally; the SEQUENCE channel may
 *       burst to {@value #SEQUENCE_BURST_PER_WINDOW}/s for ≤ 3 s during cutscenes; live
 *       Quasar particles ≤ {@value #MAX_LIVE_PARTICLES}.</li>
 *   <li>Lights: ≤ {@value #MAX_LIGHTS} concurrent FX point lights.</li>
 *   <li>{@code reducedFx} halves every rate; tier 0 disables the AMBIENT channel.</li>
 * </ul>
 *
 * <p>Budgets are tracked in 20-tick windows against {@link EclipseFxState#clientTicks()}
 * (no allocations, no iteration — plain int counters). Client-side only; calls are made from
 * the client tick/render threads.</p>
 */
public final class FxBudget {
    public enum Channel { AMBIENT, BURST, SEQUENCE, STORM }

    /** Global spawns per 20-tick window (≈ per second) outside SEQUENCE bursts. */
    private static final int GLOBAL_PER_WINDOW = 30;
    /** SEQUENCE burst ceiling per window; sustainable for ≤ 3 consecutive windows. */
    private static final int SEQUENCE_BURST_PER_WINDOW = 60;
    /** SEQUENCE spend allowed across the previous 3 windows before the burst is revoked. */
    private static final int SEQUENCE_BURST_HISTORY_CAP = 180;
    /** Per-channel caps per window at full quality (global cap still binds). */
    private static final int AMBIENT_PER_WINDOW = 12;
    private static final int BURST_PER_WINDOW = 15;
    private static final int STORM_PER_WINDOW = 12;
    private static final int MAX_LIVE_PARTICLES = 1500;
    private static final int MAX_LIGHTS = 16;

    private static int windowIndex = Integer.MIN_VALUE;
    private static int ambientCount;
    private static int burstCount;
    private static int stormCount;
    private static int sequenceCount;
    private static int totalCount;
    /** SEQUENCE spend of the last three completed windows (burst hysteresis). */
    private static int seqHist0;
    private static int seqHist1;
    private static int seqHist2;

    private static int lightsHeld;

    /** Live-particle probe cache (asking Veil once per window is plenty). */
    private static int liveParticlesCached;
    private static int liveParticlesWindow = Integer.MIN_VALUE;

    private FxBudget() {}

    /**
     * Requests one emitter spawn on the given channel. Enforces per-channel spawns/sec, the
     * global cap and the live-particle cap. Refusals are silent by design — callers simply
     * skip the spawn (never fall back to vanilla particle floods).
     */
    public static boolean tryEmitter(Channel c) {
        int tier = qualityTier();
        if (tier <= 0 && c == Channel.AMBIENT) {
            return false;
        }
        rollWindow();
        int scaleShift = tier >= 2 ? 0 : 1; // reducedFx halves every rate
        if (liveParticles() >= (MAX_LIVE_PARTICLES >> scaleShift)) {
            return false;
        }
        int globalCap = GLOBAL_PER_WINDOW >> scaleShift;
        switch (c) {
            case AMBIENT -> {
                if (ambientCount >= (AMBIENT_PER_WINDOW >> scaleShift) || totalCount >= globalCap) {
                    return false;
                }
                ambientCount++;
            }
            case BURST -> {
                if (burstCount >= (BURST_PER_WINDOW >> scaleShift) || totalCount >= globalCap) {
                    return false;
                }
                burstCount++;
            }
            case STORM -> {
                if (stormCount >= (STORM_PER_WINDOW >> scaleShift) || totalCount >= globalCap) {
                    return false;
                }
                stormCount++;
            }
            case SEQUENCE -> {
                boolean burstAllowed = (seqHist0 + seqHist1 + seqHist2) < (SEQUENCE_BURST_HISTORY_CAP >> scaleShift);
                int cap = (burstAllowed ? SEQUENCE_BURST_PER_WINDOW : GLOBAL_PER_WINDOW) >> scaleShift;
                if (sequenceCount >= cap || totalCount >= cap) {
                    return false;
                }
                sequenceCount++;
            }
        }
        totalCount++;
        return true;
    }

    /**
     * Claims one of the {@value #MAX_LIGHTS} concurrent FX point-light slots (half at
     * reduced quality). New requests are refused while the pool is exhausted; callers keep
     * their previous light or skip it. Pair every {@code true} with {@link #releaseLight()}.
     */
    public static boolean tryLight() {
        int cap = qualityTier() >= 2 ? MAX_LIGHTS : MAX_LIGHTS / 2;
        if (lightsHeld >= cap) {
            return false;
        }
        lightsHeld++;
        return true;
    }

    /** Returns a light slot claimed with {@link #tryLight()}. */
    public static void releaseLight() {
        if (lightsHeld > 0) {
            lightsHeld--;
        }
    }

    /**
     * 2 = full, 1 = reducedFx, 0 = minimal. Derived from {@code EclipseClientConfig}:
     * {@code reducedFx} alone gives tier 1; {@code reducedFx} with {@code veilPostFx}
     * disabled reads as "give me the minimum" → tier 0 (AMBIENT off, hard caps).
     */
    public static int qualityTier() {
        if (!EclipseClientConfig.reducedFx()) {
            return 2;
        }
        return EclipseClientConfig.veilPostFx() ? 1 : 0;
    }

    /** Currently held FX light slots (dev/QA introspection). */
    public static int lightsHeld() {
        return lightsHeld;
    }

    private static void rollWindow() {
        int now = EclipseFxState.clientTicks() / 20;
        if (now != windowIndex) {
            // Skipped windows (lag spikes, menus) simply zero the history slots they cover.
            seqHist2 = windowIndex == now - 1 ? seqHist1 : 0;
            seqHist1 = windowIndex == now - 1 ? seqHist0 : 0;
            seqHist0 = windowIndex == now - 1 ? sequenceCount : 0;
            windowIndex = now;
            ambientCount = 0;
            burstCount = 0;
            stormCount = 0;
            sequenceCount = 0;
            totalCount = 0;
        }
    }

    private static int liveParticles() {
        if (liveParticlesWindow != windowIndex) {
            liveParticlesWindow = windowIndex;
            try {
                liveParticlesCached = VeilRenderSystem.renderer().getParticleManager().getParticleCount();
            } catch (Throwable t) {
                liveParticlesCached = 0; // Veil unavailable — the spawn will fail safely downstream
            }
        }
        return liveParticlesCached;
    }
}
