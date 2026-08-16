package de.sonic0810.goobymod.client;

import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.entity.GoobyWardrobe;
import de.sonic0810.goobymod.registry.ModItems;
import net.minecraft.world.item.component.DyedItemColor;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RegisterColorHandlersEvent;

/**
 * Item-Tint fuer das faerbbare Abenteuer-Halstuch (Explorer-Outfit v5.4).
 * Bewusst eine eigene Subscriber-Klasse: {@code ClientSetup} bleibt
 * unangetastet; mehrere Listener desselben Events sind problemlos.
 */
@EventBusSubscriber(modid = GoobyMod.MODID, value = Dist.CLIENT)
public final class ExplorerOutfitClient {

    @SubscribeEvent
    public static void registerItemColors(RegisterColorHandlersEvent.Item event) {
        event.register((stack, tintIndex) -> tintIndex == 0
                        ? DyedItemColor.getOrDefault(stack, GoobyWardrobe.DEFAULT_BANDANA_COLOR)
                        : 0xFFFFFFFF,
                ModItems.ADVENTURE_BANDANA.get());
    }

    private ExplorerOutfitClient() {
    }
}
