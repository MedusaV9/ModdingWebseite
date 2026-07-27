package dev.projecteclipse.eclipse.woah.chronostasis;

import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.resources.ResourceLocation;

/**
 * WOAH-03 logical FX cue ids, minted via the frozen {@link FxCues#cue(String)} helper
 * (parallel-worker law: constants live HERE, the shared {@code FxCues} file stays
 * untouched). Both cues travel the position lane ({@code FxPayloads.sendFxEvent}) and
 * resolve client-side through the rows registered by
 * {@code woah.chronostasis.client.ChronoStasisFxRows}.
 */
public final class ChronoCues {
    /**
     * Time-jolt pulse ({@code eclipse:fx/cue/woah_chrono_jolt}). Sender:
     * {@code ChronoStasisService.beginJolt} (pos = sphere center, a = joltCount 1..5,
     * b = 0, range 96) and the DISCHARGE tower-impact reuse (pos = impact,
     * <b>a = 2 semantics collide is avoided by using a = -1 for impacts</b> — see below).
     *
     * <p>Payload contract: {@code a >= 0} = a real time-jolt (client arms the 60 t jolt
     * window: tick-sound pause, scene shimmer); {@code a < 0} = dust-puff variant for
     * tower-debris impacts during DISCHARGE (scaled-down spawn, no jolt window).</p>
     */
    public static final ResourceLocation CUE_CHRONO_JOLT = FxCues.cue("woah_chrono_jolt");

    /**
     * Discharge burst ({@code eclipse:fx/cue/woah_chrono_discharge}). Sender:
     * {@code ChronoStasisService} at DISCHARGE t=30 (pos = blast center, a = 1, b = 0,
     * range 128). The client row arms the 230 t discharge/rewind window (grade white
     * kick, frozen-rain release, tick-sound mute) and layers the Photon shockwave.
     */
    public static final ResourceLocation CUE_CHRONO_DISCHARGE = FxCues.cue("woah_chrono_discharge");

    private ChronoCues() {}
}
