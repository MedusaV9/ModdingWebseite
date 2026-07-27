package dev.projecteclipse.eclipse.woah.mansiondome;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.MobCategory;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityAttributeCreationEvent;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;

/**
 * WOAH-01 entity registry — this feature's OWN {@code DeferredRegister} per the house
 * no-shared-file rule (the {@code FinaleEntities} pattern): {@code EclipseEntities} is
 * never touched. {@link #register(IEventBus)} is wired from the WOAH-01 anchor in
 * {@code woah.WoahFeatures}; until it lands the attribute listener no-ops via
 * {@link DeferredHolder#isBound()}.
 *
 * <p>No spawn egg, no natural spawning — the emitter is placed exclusively by
 * {@link MansionDomeService#arm}. {@link MobCategory#MISC} keeps it out of the vanilla
 * spawn census.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class MansionDomeEntities {
    public static final DeferredRegister<EntityType<?>> ENTITIES =
            DeferredRegister.create(Registries.ENTITY_TYPE, EclipseMod.MOD_ID);

    /**
     * The roof device (§3.3): ~2.45 blocks of rings + core + antenna. Health is a
     * formality — real durability is the synced hit counter driven by
     * {@code MansionDomeState.hitsRemaining}.
     */
    public static final DeferredHolder<EntityType<?>, EntityType<DomeEmitterEntity>> GLITCH_EMITTER =
            ENTITIES.register("glitch_emitter",
                    () -> EntityType.Builder.of(DomeEmitterEntity::new, MobCategory.MISC)
                            .sized(1.4F, 2.6F)
                            .eyeHeight(1.8F)
                            .clientTrackingRange(10)
                            .fireImmune()
                            .build("glitch_emitter"));

    private MansionDomeEntities() {}

    /** Wiring hook for the {@code WoahFeatures} WOAH-01 anchor (one line). */
    public static void register(IEventBus modEventBus) {
        ENTITIES.register(modEventBus);
    }

    @SubscribeEvent
    static void onEntityAttributeCreation(EntityAttributeCreationEvent event) {
        if (!GLITCH_EMITTER.isBound()) {
            EclipseMod.LOGGER.warn("MansionDomeEntities registrar not wired yet — glitch_emitter "
                    + "dormant (add MansionDomeEntities.register(modEventBus) under the WOAH-01 anchor)");
            return;
        }
        event.put(GLITCH_EMITTER.get(), Mob.createMobAttributes()
                .add(Attributes.MAX_HEALTH, 100.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.0D)
                .add(Attributes.KNOCKBACK_RESISTANCE, 1.0D)
                .add(Attributes.FOLLOW_RANGE, 16.0D)
                .build());
    }
}
