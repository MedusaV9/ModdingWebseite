package dev.projecteclipse.eclipse.client.item;

import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import net.minecraft.client.renderer.BlockEntityWithoutLevelRenderer;
import net.minecraft.world.item.Item;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.extensions.common.IClientItemExtensions;
import net.neoforged.neoforge.client.extensions.common.RegisterClientExtensionsEvent;

/**
 * Client MOD-bus wiring for the ITEMS-B GeckoLib items (revive sigil, Herald's Lure,
 * Storm Heart), self-registering — the {@code WandClientExtensions} pattern with no
 * shared-file edits: {@link RegisterClientExtensionsEvent} hangs each
 * {@code GeoItemRenderer} onto its item via
 * {@link IClientItemExtensions#getCustomRenderer()}. Renderers are created lazily ON
 * first use so no GeckoLib model loading happens before resource managers exist.
 *
 * <p>No {@code isBound()} guard needed here: unlike the wiring-doc-gated
 * {@code WandItems}, {@code EclipseItems.register} is a core line in
 * {@code EclipseMod}'s constructor — the holders are always bound by the time the
 * client-extensions event fires.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ItemsBClientExtensions {
    private ItemsBClientExtensions() {}

    @SubscribeEvent
    static void onRegisterClientExtensions(RegisterClientExtensionsEvent event) {
        register(event, EclipseItems.REVIVE_SIGIL.get(), ReviveSigilRenderer::new);
        register(event, EclipseItems.HERALDS_LURE.get(), HeraldsLureRenderer::new);
        register(event, EclipseItems.STORM_HEART.get(), StormHeartRenderer::new);
    }

    private static void register(RegisterClientExtensionsEvent event, Item item,
            Supplier<? extends BlockEntityWithoutLevelRenderer> rendererFactory) {
        event.registerItem(new IClientItemExtensions() {
            private BlockEntityWithoutLevelRenderer renderer;

            @Override
            public BlockEntityWithoutLevelRenderer getCustomRenderer() {
                if (renderer == null) {
                    renderer = rendererFactory.get();
                }
                return renderer;
            }
        }, item);
    }
}
