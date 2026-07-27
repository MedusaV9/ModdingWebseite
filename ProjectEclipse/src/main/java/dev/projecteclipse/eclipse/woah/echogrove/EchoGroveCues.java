package dev.projecteclipse.eclipse.woah.echogrove;

import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.resources.ResourceLocation;

/**
 * WOAH-05 Echo-Grove FX cue ids (plan §4.2) — minted through {@link FxCues#cue}
 * so they live in the shared {@code eclipse:fx/cue/…} namespace WITHOUT touching
 * the shared {@code FxCues} file (the {@code woah.resonance.ResonanceCues} pattern).
 * Client rows consuming these register in {@code client.echo.EchoPhotonFxRows}.
 */
public final class EchoGroveCues {
    /**
     * The memory flood (plan §3.5): one-shot per flood at the memory-tree center,
     * range 256. {@code a} = hold ticks (160 normal, 600 finale), {@code b} = 1 for
     * the warmer afterglow variant (post-finale). The client row's custom leg starts
     * {@code echo_flood_bloom.fx}, schedules {@code echo_ash_fall.fx} for the decay
     * beat and latches the grade warmth + music-box motif in {@code EchoGroveFx}.
     */
    public static final ResourceLocation CUE_ECHO_FLOOD = FxCues.cue("woah_echo_flood");

    /** Finale blossom rain over the memory tree (600t one-shot, plan §7.3). */
    public static final ResourceLocation CUE_ECHO_BLOOM_RAIN = FxCues.cue("woah_echo_bloom_rain");

    /**
     * Whisper wisp on orb interaction (ENTITY lane — rides the clicked orb;
     * sent per interaction with the 3 s per-orb cooldown, plan §3.6).
     */
    public static final ResourceLocation CUE_ECHO_WHISPER = FxCues.cue("woah_echo_whisper");

    /** Lost-orb collect implosion (20t one-shot at the orb position, plan §3.6). */
    public static final ResourceLocation CUE_ECHO_ORB_COLLECT = FxCues.cue("woah_echo_orb_collect");

    private EchoGroveCues() {}
}
