package dev.projecteclipse.eclipse.veilfx;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * F-056/F-058 {@link PhotonFxRegistry} row registrar — the credits finale-rework cues.
 * Assets are authored programmatically by {@code tools/photon/credits2_fx.py} (fxlib)
 * into {@code assets/eclipse/fx/*.fx}; re-run the script instead of hand-editing the
 * gzip-NBT. Server senders live in {@code ritual.CreditsShatterAct} /
 * {@code ritual.CreditsBlackHoleAct}.
 *
 * <p>Both rows are Photon-only garnish (Quasar leg {@code null} — legal for NEW cues,
 * the {@code CUE_LANDMARK_ECHO} precedent): the moments already read fully through the
 * block displays, the sky override and the sustained fades on photon-less clients.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class CreditsFinaleFxRows {

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
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
