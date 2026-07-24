package dev.projecteclipse.eclipse.client.wand;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.wand.WandItems;
import net.minecraft.client.renderer.BlockEntityWithoutLevelRenderer;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RegisterGuiLayersEvent;
import net.neoforged.neoforge.client.extensions.common.IClientItemExtensions;
import net.neoforged.neoforge.client.extensions.common.RegisterClientExtensionsEvent;
import net.neoforged.neoforge.client.gui.VanillaGuiLayers;

/**
 * Client MOD-bus wiring for the wand, self-registering (no shared-file edits):
 *
 * <ul>
 *   <li>{@link RegisterClientExtensionsEvent}: hangs the GeckoLib
 *       {@link EclipseWandRenderer} onto the item via
 *       {@link IClientItemExtensions#getCustomRenderer()} (the frozen P6 convention
 *       adapted for items — the item model is {@code builtin/entity}, so vanilla routes
 *       every perspective to this renderer). The renderer is created lazily ON the event
 *       so no GeckoLib model loading happens before resource managers exist.</li>
 *   <li>{@link RegisterGuiLayersEvent}: adds the {@link WandChargeHud} charge pips right
 *       above the hotbar. Deliberately NOT added to the cutscene HUD whitelist
 *       ({@code EclipseGuiLayers} owns it) — cutscene suppression SHOULD hide it.</li>
 * </ul>
 *
 * <p>Both registrations no-op when the {@code WandItems} registrar is not wired yet
 * (unbound holder) — the mod must never crash from a half-applied wiring doc.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class WandClientExtensions {
    private WandClientExtensions() {}

    @SubscribeEvent
    static void onRegisterClientExtensions(RegisterClientExtensionsEvent event) {
        if (!WandItems.ECLIPSE_WAND.isBound()) {
            EclipseMod.LOGGER.warn("WandItems registrar not wired yet — eclipse_wand renderer "
                    + "dormant (apply docs/plans_v3/wiring/W4-WAND_wiring.md)");
            return;
        }
        event.registerItem(new IClientItemExtensions() {
            private EclipseWandRenderer renderer;

            @Override
            public BlockEntityWithoutLevelRenderer getCustomRenderer() {
                if (renderer == null) {
                    renderer = new EclipseWandRenderer();
                }
                return renderer;
            }
        }, WandItems.ECLIPSE_WAND.get());
    }

    @SubscribeEvent
    static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
        if (!WandItems.ECLIPSE_WAND.isBound()) {
            return;
        }
        event.registerAbove(VanillaGuiLayers.HOTBAR, WandChargeHud.LAYER_ID, WandChargeHud::render);
    }
}
