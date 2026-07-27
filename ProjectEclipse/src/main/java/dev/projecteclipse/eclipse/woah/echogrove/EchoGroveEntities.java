package dev.projecteclipse.eclipse.woah.echogrove;

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
 * WOAH-05 entity registry (plan §3.1) — deliberately its OWN deferred register
 * (NOT {@code ghosts/GhostEntities}, which is another worker's file), bootstrapped
 * from the WOAH-05 anchor in {@code woah/WoahFeatures.register}.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EchoGroveEntities {
    public static final DeferredRegister<EntityType<?>> ENTITIES =
            DeferredRegister.create(Registries.ENTITY_TYPE, EclipseMod.MOD_ID);

    /** Scene-actor ghost (adults + children via the CHILD flag; renderer scales). */
    public static final DeferredHolder<EntityType<?>, EntityType<EchoGhostEntity>> ECHO_GHOST =
            ENTITIES.register(EchoGhostEntity.ENTITY_ID,
                    () -> EntityType.Builder.of(EchoGhostEntity::new, MobCategory.MISC)
                            .sized(0.6F, 1.8F)
                            .clientTrackingRange(10)
                            .updateInterval(2)
                            .build(EchoGhostEntity.ENTITY_ID));

    /** The dog of {@code dog_fetch} (Wolf subclass — WolfModel is bound to Wolf). */
    public static final DeferredHolder<EntityType<?>, EntityType<EchoGhostWolfEntity>> ECHO_GHOST_WOLF =
            ENTITIES.register(EchoGhostWolfEntity.ENTITY_ID,
                    () -> EntityType.Builder.of(EchoGhostWolfEntity::new, MobCategory.MISC)
                            .sized(0.6F, 0.85F)
                            .clientTrackingRange(10)
                            .updateInterval(2)
                            .build(EchoGhostWolfEntity.ENTITY_ID));

    /** Interactable memory orbs (persistent, plan §3.6). */
    public static final DeferredHolder<EntityType<?>, EntityType<MemoryOrbEntity>> MEMORY_ORB =
            ENTITIES.register(MemoryOrbEntity.ENTITY_ID,
                    () -> EntityType.Builder.of(MemoryOrbEntity::new, MobCategory.MISC)
                            .sized(0.5F, 0.5F)
                            .clientTrackingRange(10)
                            .updateInterval(20)
                            .build(MemoryOrbEntity.ENTITY_ID));

    private EchoGroveEntities() {}

    public static void register(IEventBus modEventBus) {
        ENTITIES.register(modEventBus);
    }

    @SubscribeEvent
    static void onEntityAttributeCreation(EntityAttributeCreationEvent event) {
        if (ECHO_GHOST.isBound()) {
            event.put(ECHO_GHOST.get(), EchoGhostEntity.createAttributes().build());
        }
        if (ECHO_GHOST_WOLF.isBound()) {
            event.put(ECHO_GHOST_WOLF.get(), EchoGhostWolfEntity.createEchoAttributes().build());
        }
        if (MEMORY_ORB.isBound()) {
            event.put(MEMORY_ORB.get(), MemoryOrbEntity.createAttributes().build());
        }
    }
}
