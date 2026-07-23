package dev.projecteclipse.eclipse.entity.pale;

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
 * Entity registry for the pale-garden family (P6-W9) — this family's OWN
 * {@code DeferredRegister} per the P6 no-shared-file rule
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §1.6). {@link #register(IEventBus)}
 * needs one wiring line in the {@code EclipseMod} constructor — listed in
 * {@code docs/plans_v3/wiring/P6-W910_wiring.md} for the integrator. Until that line
 * lands, every listener here (and the client renderer registration) no-ops via
 * {@link DeferredHolder#isBound()}, so the build and both run configs stay green.
 *
 * <p>No spawn egg (house rule) and no natural spawning — P6-W6's spawn rules gate the
 * sentinel on {@code SpawnGates.PALE_GARDEN} (default FALSE until P1 lands the biome);
 * testing goes through {@code /summon eclipse:pale_sentinel}.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class PaleEntities {
    public static final DeferredRegister<EntityType<?>> ENTITIES =
            DeferredRegister.create(Registries.ENTITY_TYPE, EclipseMod.MOD_ID);

    /**
     * Pale Sentinel — the 2.4-block gaunt tree-revenant of the Pale Garden (frozen §6 id;
     * MONSTER, 0.8×2.4, tracking range 10 per the §2.3 sheet).
     */
    public static final DeferredHolder<EntityType<?>, EntityType<PaleSentinelEntity>> PALE_SENTINEL =
            ENTITIES.register("pale_sentinel",
                    () -> EntityType.Builder.of(PaleSentinelEntity::new, MobCategory.MONSTER)
                            .sized(0.8F, 2.4F)
                            .eyeHeight(2.1F)
                            .clientTrackingRange(10)
                            .build("pale_sentinel"));

    private PaleEntities() {}

    /** Wiring hook for the {@code EclipseMod} constructor (integrator-applied). */
    public static void register(IEventBus modEventBus) {
        ENTITIES.register(modEventBus);
    }

    @SubscribeEvent
    static void onEntityAttributeCreation(EntityAttributeCreationEvent event) {
        if (!PALE_SENTINEL.isBound()) {
            EclipseMod.LOGGER.warn("PaleEntities registrar not wired yet — pale_sentinel "
                    + "dormant (apply docs/plans_v3/wiring/P6-W910_wiring.md)");
            return;
        }
        event.put(PALE_SENTINEL.get(), PaleSentinelEntity.createAttributes().build());
    }
}
