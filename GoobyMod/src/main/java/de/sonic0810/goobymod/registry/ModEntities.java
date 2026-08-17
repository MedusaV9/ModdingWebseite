package de.sonic0810.goobymod.registry;

import de.sonic0810.goobymod.GoobyConfig;
import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.entity.CouchSeatEntity;
import de.sonic0810.goobymod.entity.GoobyEntity;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.MobCategory;
import net.minecraft.world.entity.SpawnPlacementTypes;
import net.minecraft.world.entity.animal.Animal;
import net.minecraft.world.level.levelgen.Heightmap;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityAttributeCreationEvent;
import net.neoforged.neoforge.event.entity.RegisterSpawnPlacementsEvent;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;

@EventBusSubscriber(modid = GoobyMod.MODID)
public final class ModEntities {
    public static final DeferredRegister<EntityType<?>> ENTITY_TYPES =
            DeferredRegister.create(Registries.ENTITY_TYPE, GoobyMod.MODID);

    public static final DeferredHolder<EntityType<?>, EntityType<GoobyEntity>> GOOBY =
            ENTITY_TYPES.register("gooby", () -> EntityType.Builder.of(GoobyEntity::new, MobCategory.CREATURE)
                    .sized(1.1F, 1.4F)
                    .eyeHeight(1.05F)
                    .clientTrackingRange(10)
                    .build("gooby"));

    /**
     * Unsichtbarer Couch-Sitzmarker: nie gespeichert, nie summonbar — nach
     * einem Reload steht der Spieler einfach auf, verwaiste Marker gibt es nicht.
     */
    public static final DeferredHolder<EntityType<?>, EntityType<CouchSeatEntity>> COUCH_SEAT =
            ENTITY_TYPES.register("couch_seat",
                    () -> EntityType.Builder.<CouchSeatEntity>of(CouchSeatEntity::new, MobCategory.MISC)
                            .sized(0.25F, 0.25F)
                            .noSave()
                            .noSummon()
                            .clientTrackingRange(8)
                            .updateInterval(20)
                            .build("couch_seat"));

    @SubscribeEvent
    public static void registerAttributes(EntityAttributeCreationEvent event) {
        event.put(GOOBY.get(), GoobyEntity.createAttributes().build());
    }

    @SubscribeEvent
    public static void registerSpawnPlacements(RegisterSpawnPlacementsEvent event) {
        event.register(GOOBY.get(), SpawnPlacementTypes.ON_GROUND,
                Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
                (type, level, spawnType, pos, random) -> GoobyConfig.wildSpawns()
                        && Animal.checkAnimalSpawnRules(type, level, spawnType, pos, random),
                RegisterSpawnPlacementsEvent.Operation.REPLACE);
    }

    public static void register(IEventBus bus) {
        ENTITY_TYPES.register(bus);
    }

    private ModEntities() {
    }
}
