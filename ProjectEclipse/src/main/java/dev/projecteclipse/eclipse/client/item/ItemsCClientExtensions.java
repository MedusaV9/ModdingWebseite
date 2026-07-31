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
 * Client MOD-bus wiring for the POLISH3 hand-3D items (umbral blade, umbral pick,
 * Ferryman's Toll), self-registering — the {@code ItemsBClientExtensions} pattern with
 * no shared-file edits: {@link RegisterClientExtensionsEvent} hangs each
 * {@code GeoItemRenderer} onto its item via
 * {@link IClientItemExtensions#getCustomRenderer()}. Renderers are created lazily ON
 * first use so no GeckoLib model loading happens before resource managers exist.
 *
 * <p><b>Context split (the POLISH3 difference to ITEMS-A/B):</b> unlike the six
 * everywhere-3D hero items, these three items' models are
 * {@code neoforge:separate_transforms} models — only their {@code base} child is
 * {@code builtin/entity}, while the gui/ground/fixed perspectives bake the FINAL 2D
 * pixel icons. {@code ItemRenderer#render} checks {@code isCustomRenderer()} on the
 * model that {@code applyTransform} returned for the active
 * {@code ItemDisplayContext}, so this BEWLR only ever receives hand (and head)
 * contexts; GUI/ground/frame never leave the vanilla quad path. No context branch is
 * needed inside the renderers.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ItemsCClientExtensions {
    private ItemsCClientExtensions() {}

    @SubscribeEvent
    static void onRegisterClientExtensions(RegisterClientExtensionsEvent event) {
        register(event, EclipseItems.UMBRAL_BLADE.get(), UmbralBladeRenderer::new);
        register(event, EclipseItems.UMBRAL_PICK.get(), UmbralPickRenderer::new);
        register(event, EclipseItems.FERRYMAN_TOLL.get(), FerrymanTollRenderer::new);
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
