package dev.projecteclipse.eclipse.entity.ambient;

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
 * Entity registry for the ambience family (P6-W1) — this family's OWN
 * {@code DeferredRegister} per the P6 no-shared-file rule
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §1.6): {@code EclipseEntities} is never
 * touched. {@link #register(IEventBus)} needs one wiring line in the {@code EclipseMod}
 * constructor — listed in {@code docs/plans_v3/wiring/P6-W1_wiring.md} for the
 * integrator. Until that line lands, every listener here (and the client renderer
 * registration) no-ops via {@link DeferredHolder#isBound()}, so the build and both run
 * configs stay green either way.
 *
 * <p>No spawn egg on purpose (house rule: event mod, admins use {@code /summon}), and no
 * natural spawning — P6-W6's spawn rules maintain the limbo lane population.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class AmbientEntities {
    public static final DeferredRegister<EntityType<?>> ENTITIES =
            DeferredRegister.create(Registries.ENTITY_TYPE, EclipseMod.MOD_ID);

    /**
     * Drift Lantern — limbo sea ambience wisp and the GeckoLib pipeline pilot (spec §2.3:
     * CREATURE, 0.6×1.1, tracking range 10). Fire-immune flavor: it IS a soul flame.
     */
    public static final DeferredHolder<EntityType<?>, EntityType<DriftLanternEntity>> DRIFT_LANTERN =
            ENTITIES.register("drift_lantern",
                    () -> EntityType.Builder.of(DriftLanternEntity::new, MobCategory.CREATURE)
                            .sized(0.6F, 1.1F)
                            .eyeHeight(0.75F)
                            .clientTrackingRange(10)
                            .fireImmune()
                            .build("drift_lantern"));

    private AmbientEntities() {}

    /** Wiring hook for the {@code EclipseMod} constructor (integrator-applied). */
    public static void register(IEventBus modEventBus) {
        ENTITIES.register(modEventBus);
    }

    @SubscribeEvent
    static void onEntityAttributeCreation(EntityAttributeCreationEvent event) {
        if (!DRIFT_LANTERN.isBound()) {
            EclipseMod.LOGGER.warn("AmbientEntities registrar not wired yet — drift_lantern "
                    + "dormant (apply docs/plans_v3/wiring/P6-W1_wiring.md)");
            return;
        }
        event.put(DRIFT_LANTERN.get(), DriftLanternEntity.createAttributes().build());
    }
}
