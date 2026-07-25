package dev.projecteclipse.eclipse.veilfx;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * PH-CORE's {@link PhotonFxRegistry} row registrar — and the REFERENCE PATTERN for content
 * workers: copy this class (own name, own rows), keep the {@code Dist.CLIENT} MOD-bus
 * subscriber shape, and pair every row with (a) a {@code FxCues.CUE_*} constant (server
 * side) and (b) the {@code assets/eclipse/fx/<id>.fx} asset (author it with
 * {@code tools/photon/fxlib.py} or Photon's in-game editor).
 *
 * <p>The two rows below are the shipped smoke tests for the whole lane
 * ({@code tools/photon/fxlib.py templates} generates their assets):</p>
 * <ul>
 *   <li>{@code CUE_TEMPLATE_BURST} — REPLACE row with a Quasar fallback: Photon plays
 *       {@code eclipse:template_burst}; photon-less clients (or any bridge refusal) get the
 *       {@code eclipse:unlock_burst} Quasar emitter instead. Fire it with
 *       {@code /dev photon test} or {@code FxPayloads.sendFxEvent(level,
 *       FxCues.CUE_TEMPLATE_BURST, pos, 0, 0, range)}.</li>
 *   <li>{@code CUE_TEMPLATE_LOOP} — loop row (WINDOWED-only law, INTEGRATION.md §4):
 *       payload-firing it is a warned no-op; client windows drive it via
 *       {@code PhotonFxRegistry.ensureLoop/releaseLoop}.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public final class PhotonFxRows {
    private PhotonFxRows() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_TEMPLATE_BURST,
                fx("template_burst"),
                fx("unlock_burst"),
                FxBudget.Channel.BURST,
                PhotonFxRegistry.Mode.REPLACE,
                false));
        PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
                FxCues.CUE_TEMPLATE_LOOP,
                fx("template_loop"),
                null,
                FxBudget.Channel.AMBIENT,
                PhotonFxRegistry.Mode.LAYER,
                true));
    }

    private static ResourceLocation fx(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
