package de.sonic0810.goobymod.client;

import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.registry.ModBlockEntities;
import de.sonic0810.goobymod.registry.ModEntities;
import de.sonic0810.goobymod.registry.ModItems;
import de.sonic0810.goobymod.registry.ModMenus;
import de.sonic0810.goobymod.registry.ModParticles;
import net.minecraft.world.item.component.DyedItemColor;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;
import net.neoforged.neoforge.client.event.RegisterColorHandlersEvent;
import net.neoforged.neoforge.client.event.RegisterParticleProvidersEvent;
import net.neoforged.neoforge.client.event.RegisterMenuScreensEvent;

@EventBusSubscriber(modid = GoobyMod.MODID, value = Dist.CLIENT)
public final class ClientSetup {

    @SubscribeEvent
    public static void registerRenderers(EntityRenderersEvent.RegisterRenderers event) {
        event.registerEntityRenderer(ModEntities.GOOBY.get(), GoobyRenderer::new);
        event.registerBlockEntityRenderer(ModBlockEntities.RABBIT_HUTCH.get(), RabbitHutchRenderer::new);
    }

    @SubscribeEvent
    public static void registerParticles(RegisterParticleProvidersEvent event) {
        event.registerSpriteSet(ModParticles.ZZZ.get(), ZzzParticle.Provider::new);
        event.registerSpriteSet(ModParticles.HEART_GOLD.get(), HeartGoldParticle.Provider::new);
        event.registerSpriteSet(ModParticles.PAW_PRINT.get(), PawPrintParticle.Provider::new);
    }

    @SubscribeEvent
    public static void registerScreens(RegisterMenuScreensEvent event) {
        event.register(ModMenus.GOOBY_SATCHEL.get(), GoobySatchelScreen::new);
    }

    @SubscribeEvent
    public static void registerItemColors(RegisterColorHandlersEvent.Item event) {
        event.register((stack, tintIndex) -> tintIndex == 0
                        ? DyedItemColor.getOrDefault(stack, 0xB8325E) : 0xFFFFFFFF,
                ModItems.GOOBY_SCARF.get());
    }

    private ClientSetup() {
    }
}
