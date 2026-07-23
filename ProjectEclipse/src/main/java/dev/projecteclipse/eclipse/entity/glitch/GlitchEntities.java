package dev.projecteclipse.eclipse.entity.glitch;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.MobCategory;
import net.minecraft.world.entity.SpawnPlacementTypes;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.level.levelgen.Heightmap;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityAttributeCreationEvent;
import net.neoforged.neoforge.event.entity.RegisterSpawnPlacementsEvent;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;

/**
 * Entity registry for the GLITCHED family — this family's OWN {@code DeferredRegister}
 * per the P6 no-shared-file rule ({@code docs/plans_v3/P6_mobs_models_builds.md} §1.6):
 * the shared {@code EclipseEntities} stays frozen. {@link #register(IEventBus)} needs
 * one wiring line in the {@code EclipseMod} constructor — listed in
 * {@code docs/plans_v3/wiring/P6-W8_wiring.md}. Until that line lands every listener
 * here (and {@code client/entity/glitch/GlitchRenderers}) no-ops via
 * {@link DeferredHolder#isBound()}, so both run configs stay green either way.
 *
 * <p>The three ids are FROZEN and already load-bearing elsewhere:
 * {@code glitch/GlitchConfig.DEFAULT_ENTITY_IDS} spawns exactly these, and
 * {@code data/eclipse/tags/entity_type/glitched.json} keys the shared
 * {@code glitch_shard} drop hook off them. Sizes per §2.3: husk humanoid 0.6×1.9,
 * hound = stalker proportions 0.9×1.2, tick shard-mite 0.6×0.5. No spawn eggs (house
 * rule: event mod, admins use {@code /summon}); natural population is
 * {@code GlitchSpawnService} (fresh-ring sampling), so the spawn placements here only
 * matter for dungeon spawners — standard on-ground monster rules.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class GlitchEntities {
    public static final DeferredRegister<EntityType<?>> ENTITIES =
            DeferredRegister.create(Registries.ENTITY_TYPE, EclipseMod.MOD_ID);

    /** Glitched Husk — humanoid shambler with the unseen speed burst (30 HP / 5 / 0.27). */
    public static final DeferredHolder<EntityType<?>, EntityType<GlitchedHuskEntity>> GLITCHED_HUSK =
            ENTITIES.register("glitched_husk",
                    () -> EntityType.Builder.of(GlitchedHuskEntity::new, MobCategory.MONSTER)
                            .sized(0.6F, 1.9F)
                            .eyeHeight(1.66F)
                            .clientTrackingRange(10)
                            .build("glitched_husk"));

    /** Glitched Hound — fast blink-stutter quadruped (24 HP / 4 / 0.35). */
    public static final DeferredHolder<EntityType<?>, EntityType<GlitchedHoundEntity>> GLITCHED_HOUND =
            ENTITIES.register("glitched_hound",
                    () -> EntityType.Builder.of(GlitchedHoundEntity::new, MobCategory.MONSTER)
                            .sized(0.9F, 1.2F)
                            .eyeHeight(0.85F)
                            .clientTrackingRange(10)
                            .build("glitched_hound"));

    /** Glitched Tick — latching shard-mite, spawns in threes (12 HP / 3 / 0.42). */
    public static final DeferredHolder<EntityType<?>, EntityType<GlitchedTickEntity>> GLITCHED_TICK =
            ENTITIES.register("glitched_tick",
                    () -> EntityType.Builder.of(GlitchedTickEntity::new, MobCategory.MONSTER)
                            .sized(0.6F, 0.5F)
                            .eyeHeight(0.35F)
                            .clientTrackingRange(10)
                            .build("glitched_tick"));

    private GlitchEntities() {}

    /** Wiring hook for the {@code EclipseMod} constructor (integrator-applied). */
    public static void register(IEventBus modEventBus) {
        ENTITIES.register(modEventBus);
    }

    @SubscribeEvent
    static void onEntityAttributeCreation(EntityAttributeCreationEvent event) {
        if (!GLITCHED_HUSK.isBound() || !GLITCHED_HOUND.isBound() || !GLITCHED_TICK.isBound()) {
            EclipseMod.LOGGER.warn("GlitchEntities registrar not wired yet — glitched mobs "
                    + "dormant (apply docs/plans_v3/wiring/P6-W8_wiring.md)");
            return;
        }
        event.put(GLITCHED_HUSK.get(), GlitchedHuskEntity.createAttributes().build());
        event.put(GLITCHED_HOUND.get(), GlitchedHoundEntity.createAttributes().build());
        event.put(GLITCHED_TICK.get(), GlitchedTickEntity.createAttributes().build());
    }

    @SubscribeEvent
    static void onRegisterSpawnPlacements(RegisterSpawnPlacementsEvent event) {
        if (!GLITCHED_HUSK.isBound() || !GLITCHED_HOUND.isBound() || !GLITCHED_TICK.isBound()) {
            return; // Registrar not wired yet (warning already logged by the attribute hook).
        }
        event.register(GLITCHED_HUSK.get(), SpawnPlacementTypes.ON_GROUND,
                Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, Monster::checkMonsterSpawnRules,
                RegisterSpawnPlacementsEvent.Operation.REPLACE);
        event.register(GLITCHED_HOUND.get(), SpawnPlacementTypes.ON_GROUND,
                Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, Monster::checkMonsterSpawnRules,
                RegisterSpawnPlacementsEvent.Operation.REPLACE);
        event.register(GLITCHED_TICK.get(), SpawnPlacementTypes.ON_GROUND,
                Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, Monster::checkMonsterSpawnRules,
                RegisterSpawnPlacementsEvent.Operation.REPLACE);
    }
}
