package dev.projecteclipse.eclipse.ghosts;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.MobCategory;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityAttributeCreationEvent;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;

/**
 * P4-B9 entity registry for logout ghosts — separate from {@code EclipseEntities} per matrix.
 * Wiring: {@code GhostEntities.register(modEventBus)} in {@code EclipseMod} (see wiring doc).
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class GhostEntities {
    public static final DeferredRegister<EntityType<?>> ENTITIES =
            DeferredRegister.create(Registries.ENTITY_TYPE, EclipseMod.MOD_ID);

    /** Frozen id {@code eclipse:logout_ghost} for P6-W12 renderer contract. */
    public static final DeferredHolder<EntityType<?>, EntityType<LogoutGhostEntity>> LOGOUT_GHOST =
            ENTITIES.register(LogoutGhostEntity.ENTITY_ID,
                    () -> EntityType.Builder.of(LogoutGhostEntity::new, MobCategory.MISC)
                            .sized(0.6F, 1.8F)
                            .clientTrackingRange(10)
                            .updateInterval(20)
                            .build(LogoutGhostEntity.ENTITY_ID));

    private GhostEntities() {}

    public static void register(IEventBus modEventBus) {
        ENTITIES.register(modEventBus);
    }

    @SubscribeEvent
    static void onEntityAttributeCreation(EntityAttributeCreationEvent event) {
        if (!LOGOUT_GHOST.isBound()) {
            return;
        }
        event.put(LOGOUT_GHOST.get(), LogoutGhostEntity.createAttributes().build());
    }
}
