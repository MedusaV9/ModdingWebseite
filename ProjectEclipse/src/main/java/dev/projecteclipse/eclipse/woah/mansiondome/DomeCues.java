package dev.projecteclipse.eclipse.woah.mansiondome;

import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.resources.ResourceLocation;

/**
 * WOAH-01 logical FX cue ids, minted via the frozen {@link FxCues#cue(String)} helper
 * (parallel-worker law: constants live HERE, the shared {@code FxCues} file stays
 * untouched). Rows are registered client-side by
 * {@code woah.mansiondome.client.MansionDomeFxRows}.
 */
public final class DomeCues {
    /**
     * Emitter hit sparks + 1-frame glitch still ({@code eclipse:fx/cue/woah_dome_device_hit}).
     * Position lane at the device; {@code a} = {@code hitsRemaining / 8f} (the more broken,
     * the more sparks), {@code b} = 0 normal hit / 1 the final hit. Sender:
     * {@link MansionDomeService#onDeviceHit} and the t0 destruction beat.
     */
    public static final ResourceLocation CUE_DOME_DEVICE_HIT = FxCues.cue("woah_dome_device_hit");

    /**
     * Shell-shatter burst ({@code eclipse:fx/cue/woah_dome_shatter_burst}). Position lane at
     * the shell centre; {@code a} = shellRadius in blocks (client scales the shock ring —
     * asset authored at radius {@value #SHATTER_AUTHORED_RADIUS}, the
     * {@code CUE_STRUCTURE_SLAM} executor-scale pattern). Sender: the t30 destruction beat.
     */
    public static final ResourceLocation CUE_DOME_SHATTER_BURST = FxCues.cue("woah_dome_shatter_burst");

    /**
     * Device idle glimmer loop ({@code eclipse:fx/cue/woah_dome_device_idle}) —
     * <b>WINDOWED-only</b> (never payload-fired): core motes + ring arcs, driven by the
     * 48-block window controller in {@code MansionDomeClient}.
     */
    public static final ResourceLocation CUE_DOME_DEVICE_IDLE = FxCues.cue("woah_dome_device_idle");

    /**
     * Beam-base updraft loop ({@code eclipse:fx/cue/woah_dome_beam_base}) —
     * <b>WINDOWED-only</b>: motes sucked up into the sky beam, same window controller.
     */
    public static final ResourceLocation CUE_DOME_BEAM_BASE = FxCues.cue("woah_dome_beam_base");

    /** Radius (blocks) the shatter ring asset is authored at ({@code a / this} = scale). */
    public static final float SHATTER_AUTHORED_RADIUS = 8.0F;

    private DomeCues() {}
}
