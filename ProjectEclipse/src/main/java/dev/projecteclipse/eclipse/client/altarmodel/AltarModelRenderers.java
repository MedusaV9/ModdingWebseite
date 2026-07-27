package dev.projecteclipse.eclipse.client.altarmodel;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.EclipseBlockEntities;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;

/**
 * Registers the {@link AltarModelRenderer} for the altar block entity (F-076) — the
 * {@code client.entity.door.DoorRenderers} pattern, minus the guard: the altar BE type
 * is a plain always-bound registration in {@code registry.EclipseBlockEntities}.
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class AltarModelRenderers {
    private AltarModelRenderers() {}

    @SubscribeEvent
    static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        event.registerBlockEntityRenderer(EclipseBlockEntities.ALTAR.get(),
                context -> new AltarModelRenderer());
    }
}
