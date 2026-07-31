package dev.projecteclipse.eclipse.veilfx;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * F-056/F-058 {@link PhotonFxRegistry} row registrar — the credits finale-rework cues,
 * plus the F-102 "Himmel-Kontraktion / Eclipse-Verschwinden" pair. Assets are authored
 * programmatically by {@code tools/photon/credits2_fx.py} and
 * {@code tools/photon/credits5_fx.py} (fxlib) into {@code assets/eclipse/fx/*.fx};
 * re-run the scripts instead of hand-editing the gzip-NBT. Server senders live in
 * {@code ritual.CreditsShatterAct} / {@code ritual.CreditsBlackHoleAct} /
 * {@code ritual.CreditsSequence} (the F-102 cues).
 *
 * <p>All rows are Photon-only garnish (Quasar leg {@code null} — legal for NEW cues,
 * the {@code CUE_LANDMARK_ECHO} precedent): the moments already read fully through the
 * block displays, the sky override and the sustained fades on photon-less clients.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class CreditsFinaleFxRows {

    /** F-102 sky-contraction veil: inward streak trails + haze pouring into the hole. */
    public static final ResourceLocation CUE_CREDITS5_SKYDRAIN = FxCues.cue("credits5_skydrain");
    /** F-102 eclipse last-light seal: one dim flare + exhaling halo as it winks out. */
    public static final ResourceLocation CUE_CREDITS5_LASTLIGHT = FxCues.cue("credits5_lastlight");

    private CreditsFinaleFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        // F-058 — island-shatter collapse veil: a slow dark dust updraft + violet ember
        // motes + one soft shock ring over the breaking island (~460t one-shot, fired
        // once at the break beat).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_CREDITS_COLLAPSE,
                fx("credits_collapse"),
                null,
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // F-056 — the black-hole maw: rotating accretion swirls + infalling particle
        // streams + a photon-ring rim glow (~340t one-shot, re-fired by the act on a
        // 300t cadence — the kneel-corona sustain law: re-sends inside the runtime are
        // silent dedup no-ops, the seam never gaps).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_BLACK_HOLE,
                fx("black_hole_maw"),
                null,
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // F-102 — sky-contraction veil: long inward streak trails + a whisper haze
        // pouring off the far dome into the hole (~150t one-shot, re-fired by
        // CreditsSequence every 150t across reveal+560..+1220 — back-to-back fires
        // seam under the maw's sustain law; the display half is the act's sky-drain
        // streams on the same window).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_CREDITS5_SKYDRAIN,
                fx("credits5_skydrain"),
                null,
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.LAYER,
                false));
        // F-102 — the eclipse's LAST LIGHT: one dim center flare + a thin exhaling
        // halo + final embers (~120t one-shot, fired ONCE at reveal+1270, sealing the
        // eclipse-fade beat 30t before the dark melt).
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                CUE_CREDITS5_LASTLIGHT,
                fx("credits5_lastlight"),
                null,
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.LAYER,
                false));
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
