package dev.projecteclipse.eclipse.veilfx;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * F-072 V3 {@link PhotonFxRegistry} row registrar — the credits V3 polish cues (the
 * {@link CreditsFinaleFxRows} sibling; cue ids via {@link FxCues#cue} so the shared
 * {@code FxCues} class stays untouched). Assets are authored programmatically by
 * {@code tools/photon/credits3_fx.py} (fxlib) into {@code assets/eclipse/fx/*.fx};
 * re-run the script instead of hand-editing the gzip-NBT. Both senders live in
 * {@code ritual.CreditsSequence}.
 *
 * <p>Both rows are Photon-only garnish (Quasar leg {@code null} — legal for NEW cues,
 * the {@code CUE_LANDMARK_ECHO} precedent): the pre-crack beat already reads through
 * the tremor shake + crack sounds, and the space shot through the sky override + post
 * pass on photon-less clients.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class CreditsFinale3FxRows {

    /** V3 pre-crack veil: seams glow + dust trickles ~50t before the island breaks. */
    public static final ResourceLocation CUE_CREDITS3_PRECRACK = FxCues.cue("credits3_precrack");
    /** V3 space atmosphere: far nebula swaths + rare shooting stars around the maw. */
    public static final ResourceLocation CUE_CREDITS3_NEBULA = FxCues.cue("credits3_nebula");

    private CreditsFinale3FxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // F-072 V3 — pre-crack veil ("Vorriss"): pulsing crack-line glow hugging the
        // island surface + fine dust sinking off the underside + two seam pops (~70t
        // one-shot, fired once at T_SHATTER_PRECRACK — 50t before the break beat; its
        // build-up gradient peaks exactly as credits_collapse lands).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_CREDITS3_PRECRACK,
                fx("credits3_precrack"),
                null,
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // F-072 V3 — nebula garnish for the black-hole tele shot: huge whisper-alpha
        // swaths on a 55–80-block shell + four subtle shooting-star streaks per window
        // (~340t one-shot, re-fired with the maw on its 300t cadence — the kneel-corona
        // sustain law keeps the seam gapless; re-sends dedup silently).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_CREDITS3_NEBULA,
                fx("credits3_nebula"),
                null,
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.LAYER,
                false));
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
