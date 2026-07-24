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
 * Entity registry for the W8 half of the fog-storm family — the storm ELITE tier. Own
 * {@code DeferredRegister} per the P6 no-shared-file rule
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §1.6/§3-W8): W7's {@code FogEntities}
 * (revenant + storm hound) is a sibling file in this package and is never touched;
 * the shared {@code EclipseEntities} stays frozen. {@link #register(IEventBus)} needs
 * one wiring line in the {@code EclipseMod} constructor — listed in
 * {@code docs/plans_v3/wiring/P6-W8_wiring.md}. Until that line lands every listener
 * here (and the client registration in {@code FogEliteRenderers}) no-ops via
 * {@link DeferredHolder#isBound()}, so both run configs stay green either way.
 *
 * <p>Size is frozen in plan §2.3/§6: fog_colossus MONSTER 1.6×3.4,
 * {@code clientTrackingRange(10)}. No spawn egg (house rule: event mod, admins use
 * {@code /summon}); natural population is P6-W6's storm spawn rules (1 per storm, day
 * ≥ 9), so the spawn placement registered here only matters for dungeon spawners and
 * future hooks — standard on-ground monster rules.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class FogEliteEntities {
    public static final DeferredRegister<EntityType<?>> ENTITIES =
            DeferredRegister.create(Registries.ENTITY_TYPE, EclipseMod.MOD_ID);

    /**
     * Fog Colossus — rare heavy elite of the fog storms (spec §2.3: 80 HP, dmg 10,
     * speed 0.22, KB resist 1.0, r=6 ground slam on a 200 t cooldown).
     */
    public static final DeferredHolder<EntityType<?>, EntityType<FogColossusEntity>> FOG_COLOSSUS =
            ENTITIES.register("fog_colossus",
                    () -> EntityType.Builder.of(FogColossusEntity::new, MobCategory.MONSTER)
                            .sized(1.6F, 3.4F)
                            .eyeHeight(2.8F)
                            .clientTrackingRange(10)
                            .build("fog_colossus"));

    private FogEliteEntities() {}

    /** Wiring hook for the {@code EclipseMod} constructor (integrator-applied). */
    public static void register(IEventBus modEventBus) {
        ENTITIES.register(modEventBus);
    }

    @SubscribeEvent
    static void onEntityAttributeCreation(EntityAttributeCreationEvent event) {
        if (!FOG_COLOSSUS.isBound()) {
            EclipseMod.LOGGER.warn("FogEliteEntities registrar not wired yet — fog_colossus "
                    + "dormant (apply docs/plans_v3/wiring/P6-W8_wiring.md)");
            return;
        }
        event.put(FOG_COLOSSUS.get(), FogColossusEntity.createAttributes().build());
    }

    @SubscribeEvent
    static void onRegisterSpawnPlacements(RegisterSpawnPlacementsEvent event) {
        if (!FOG_COLOSSUS.isBound()) {
            return; // Registrar not wired yet (warning already logged by the attribute hook).
        }
        event.register(FOG_COLOSSUS.get(), SpawnPlacementTypes.ON_GROUND,
                Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, Monster::checkMonsterSpawnRules,
                RegisterSpawnPlacementsEvent.Operation.REPLACE);
    }
}
