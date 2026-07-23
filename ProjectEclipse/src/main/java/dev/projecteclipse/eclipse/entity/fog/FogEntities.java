package dev.projecteclipse.eclipse.entity.fog;

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
 * Entity registry for the W7 half of the fog-storm family — this family's OWN
 * {@code DeferredRegister} per the P6 no-shared-file rule
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §1.6): {@code EclipseEntities} is never
 * touched, and W8's Fog Colossus registers in its own {@code FogEliteEntities}.
 * {@link #register(IEventBus)} needs one wiring line in the {@code EclipseMod}
 * constructor — listed in {@code docs/plans_v3/wiring/P6-W7_wiring.md} for the
 * integrator. Until that line lands, every listener here (and the client renderer
 * registration) no-ops via {@link DeferredHolder#isBound()}, so the build and both run
 * configs stay green either way.
 *
 * <p>Sizes are frozen in plan §2.3/§6: fog_revenant MONSTER 0.7×2.2, storm_hound MONSTER
 * 0.9×1.1, both {@code clientTrackingRange(10)}. No spawn eggs (house rule: event mod,
 * admins use {@code /summon}); natural population is P6-W6's spawn rules, so the spawn
 * placements registered here only matter for dungeon spawners and any future biome
 * hooks — standard on-ground monster rules (light-gated, MOTION_BLOCKING_NO_LEAVES).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class FogEntities {
    public static final DeferredRegister<EntityType<?>> ENTITIES =
            DeferredRegister.create(Registries.ENTITY_TYPE, EclipseMod.MOD_ID);

    /**
     * Fog Revenant — tall hovering wraith of the fog storms (spec §2.3: 30 HP, dmg 5,
     * speed 0.26, r=5 blind burst on a 240–320 t cooldown).
     */
    public static final DeferredHolder<EntityType<?>, EntityType<FogRevenantEntity>> FOG_REVENANT =
            ENTITIES.register("fog_revenant",
                    () -> EntityType.Builder.of(FogRevenantEntity::new, MobCategory.MONSTER)
                            .sized(0.7F, 2.2F)
                            .eyeHeight(1.9F)
                            .clientTrackingRange(10)
                            .build("fog_revenant"));

    /**
     * Storm Hound — charged lunge pack hunter (spec §2.3: 24 HP, dmg 4, speed 0.34,
     * telegraphed 12-block dash, packs of 2–3 via W6).
     */
    public static final DeferredHolder<EntityType<?>, EntityType<StormHoundEntity>> STORM_HOUND =
            ENTITIES.register("storm_hound",
                    () -> EntityType.Builder.of(StormHoundEntity::new, MobCategory.MONSTER)
                            .sized(0.9F, 1.1F)
                            .eyeHeight(0.8F)
                            .clientTrackingRange(10)
                            .build("storm_hound"));

    private FogEntities() {}

    /** Wiring hook for the {@code EclipseMod} constructor (integrator-applied). */
    public static void register(IEventBus modEventBus) {
        ENTITIES.register(modEventBus);
    }

    @SubscribeEvent
    static void onEntityAttributeCreation(EntityAttributeCreationEvent event) {
        if (!FOG_REVENANT.isBound() || !STORM_HOUND.isBound()) {
            EclipseMod.LOGGER.warn("FogEntities registrar not wired yet — fog_revenant/storm_hound "
                    + "dormant (apply docs/plans_v3/wiring/P6-W7_wiring.md)");
            return;
        }
        event.put(FOG_REVENANT.get(), FogRevenantEntity.createAttributes().build());
        event.put(STORM_HOUND.get(), StormHoundEntity.createAttributes().build());
    }

    @SubscribeEvent
    static void onRegisterSpawnPlacements(RegisterSpawnPlacementsEvent event) {
        if (!FOG_REVENANT.isBound() || !STORM_HOUND.isBound()) {
            return; // Registrar not wired yet (warning already logged by the attribute hook).
        }
        event.register(FOG_REVENANT.get(), SpawnPlacementTypes.ON_GROUND,
                Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, Monster::checkMonsterSpawnRules,
                RegisterSpawnPlacementsEvent.Operation.REPLACE);
        event.register(STORM_HOUND.get(), SpawnPlacementTypes.ON_GROUND,
                Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, Monster::checkMonsterSpawnRules,
                RegisterSpawnPlacementsEvent.Operation.REPLACE);
    }
}
