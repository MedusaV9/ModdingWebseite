package dev.projecteclipse.eclipse.entity.dungeon;

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
 * Entity registry for the dungeon family (P6-W10) — this family's OWN
 * {@code DeferredRegister} per the P6 no-shared-file rule
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §1.6). {@link #register(IEventBus)}
 * needs one wiring line in the {@code EclipseMod} constructor — listed in
 * {@code docs/plans_v3/wiring/P6-W910_wiring.md} for the integrator. Until that line
 * lands, every listener here (and the client renderer registration) no-ops via
 * {@link DeferredHolder#isBound()}, so the build and both run configs stay green.
 *
 * <p>No spawn eggs (house rule) and no natural spawning — cultists come out of the
 * config-driven dungeon spawners ({@code DungeonSpawners}, unknown ids fall back to
 * vanilla mobs until this registrar is wired) and from the Rift Warden's phase-2 summon;
 * testing goes through {@code /summon eclipse:eclipse_cultist}.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DungeonEntities {
    public static final DeferredRegister<EntityType<?>> ENTITIES =
            DeferredRegister.create(Registries.ENTITY_TYPE, EclipseMod.MOD_ID);

    /**
     * Eclipse Cultist — robed dungeon caster (frozen §6 id; MONSTER, 0.6×1.9, tracking
     * range 10 per the §2.3 sheet). Spawner-friendly: normal despawning, no persistence.
     */
    public static final DeferredHolder<EntityType<?>, EntityType<EclipseCultistEntity>> ECLIPSE_CULTIST =
            ENTITIES.register("eclipse_cultist",
                    () -> EntityType.Builder.of(EclipseCultistEntity::new, MobCategory.MONSTER)
                            .sized(0.6F, 1.9F)
                            .eyeHeight(1.6F)
                            .clientTrackingRange(10)
                            .build("eclipse_cultist"));

    /**
     * Shadow Bolt — the cultist's (and Rift Warden's) purple seeker projectile (frozen §6
     * id). MISC, tiny box, high update rate like vanilla fireballs.
     */
    public static final DeferredHolder<EntityType<?>, EntityType<ShadowBoltProjectile>> SHADOW_BOLT =
            ENTITIES.register("shadow_bolt",
                    () -> EntityType.Builder.<ShadowBoltProjectile>of(ShadowBoltProjectile::new, MobCategory.MISC)
                            .sized(0.35F, 0.35F)
                            .clientTrackingRange(8)
                            .updateInterval(2)
                            .build("shadow_bolt"));

    private DungeonEntities() {}

    /** Wiring hook for the {@code EclipseMod} constructor (integrator-applied). */
    public static void register(IEventBus modEventBus) {
        ENTITIES.register(modEventBus);
    }

    @SubscribeEvent
    static void onEntityAttributeCreation(EntityAttributeCreationEvent event) {
        if (!ECLIPSE_CULTIST.isBound()) {
            EclipseMod.LOGGER.warn("DungeonEntities registrar not wired yet — eclipse_cultist/"
                    + "shadow_bolt dormant (apply docs/plans_v3/wiring/P6-W910_wiring.md)");
            return;
        }
        event.put(ECLIPSE_CULTIST.get(), EclipseCultistEntity.createAttributes().build());
    }
}
