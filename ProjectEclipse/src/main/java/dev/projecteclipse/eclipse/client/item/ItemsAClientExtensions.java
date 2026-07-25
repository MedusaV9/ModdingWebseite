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
 * Client MOD-bus wiring for the ITEMS-A GeckoLib items (arm artifact, heart extractor),
 * self-registering — the {@code WandClientExtensions} pattern with no shared-file edits:
 * {@link RegisterClientExtensionsEvent} hangs each {@code GeoItemRenderer} onto its item
 * via {@link IClientItemExtensions#getCustomRenderer()} (both item models are
 * {@code builtin/entity}, so vanilla routes every perspective there, GUI included).
 * Renderers are created lazily ON first use so no GeckoLib model loading happens before
 * resource managers exist.
 *
 * <p>No {@code isBound()} guard needed here: unlike the wiring-doc-gated
 * {@code WandItems}, {@code EclipseItems.register} is a core line in
 * {@code EclipseMod}'s constructor — the holders are always bound by the time the
 * client-extensions event fires.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ItemsAClientExtensions {
    private ItemsAClientExtensions() {}

    @SubscribeEvent
    static void onRegisterClientExtensions(RegisterClientExtensionsEvent event) {
        register(event, EclipseItems.ARM_ARTIFACT.get(), ArmArtifactRenderer::new);
        register(event, EclipseItems.HEART_EXTRACTOR.get(), HeartExtractorRenderer::new);
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
