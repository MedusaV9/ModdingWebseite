package dev.projecteclipse.eclipse.client;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import net.minecraft.client.renderer.item.CompassItemPropertyFunction;
import net.minecraft.client.renderer.item.ItemProperties;
import net.minecraft.core.component.DataComponents;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.item.component.LodestoneTracker;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * Client-side entry point shell for Project: Eclipse.
 * Static methods annotated with {@link SubscribeEvent} are auto-registered on the client only.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class EclipseClient {
    private EclipseClient() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        event.enqueueWork(EclipseClient::registerCompassAngles);
        EclipseMod.LOGGER.info("Project: Eclipse client setup");
    }

    /**
     * W13 economy compasses: both read the {@code minecraft:lodestone_tracker} component
     * that their server-side {@code inventoryTick} refreshes, driving the same {@code angle}
     * item property vanilla compasses use (needle frame overrides in the item models).
     * ItemProperties' backing map is not thread-safe — registered via {@code enqueueWork}.
     */
    private static void registerCompassAngles() {
        // One function instance per item: CompassItemPropertyFunction keeps per-instance
        // wobble state, exactly like vanilla's separate compass/recovery-compass functions.
        CompassItemPropertyFunction.CompassTarget lodestoneTarget = (level, stack, entity) -> {
            LodestoneTracker tracker = stack.get(DataComponents.LODESTONE_TRACKER);
            return tracker != null ? tracker.target().orElse(null) : null;
        };
        ItemProperties.register(EclipseItems.COMPASS_OF_WATCHER.get(),
                ResourceLocation.withDefaultNamespace("angle"), new CompassItemPropertyFunction(lodestoneTarget));
        ItemProperties.register(EclipseItems.GRAVE_DOWSER.get(),
                ResourceLocation.withDefaultNamespace("angle"), new CompassItemPropertyFunction(lodestoneTarget));
    }
}
