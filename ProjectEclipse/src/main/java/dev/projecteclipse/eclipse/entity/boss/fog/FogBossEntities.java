package dev.projecteclipse.eclipse.entity.boss.fog;

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
 * Entity registry for the Fog Tyrant boss family (P6-W11) — this family's OWN
 * {@code DeferredRegister} per the P6 no-shared-file rule
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §1.6/§3-W11): W7's {@code FogEntities}
 * and W8's {@code FogEliteEntities} are sibling registrars in {@code entity/fog} and are
 * never touched. {@link #register(IEventBus)} needs one wiring line in the
 * {@code EclipseMod} constructor — listed in
 * {@code docs/plans_v3/wiring/WB-TYRANT_wiring.md}. Until that line lands, every
 * listener here (and the client registration in {@code FogBossRenderers}) no-ops via
 * {@link DeferredHolder#isBound()}, so both run configs stay green either way.
 *
 * <p>Size is frozen in plan §2.3/§6: fog_tyrant MONSTER 2.4×4.2, fire-immune,
 * {@code clientTrackingRange(10)}. No spawn egg, no natural spawning, not a dungeon
 * spawner mob: P1 marks the strongest storm's lair via {@link FogBankMarker#markLair}
 * (or calls {@link FogTyrantEntity#summonAt} directly); admins use
 * {@code /summon eclipse:fog_tyrant}.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class FogBossEntities {
    public static final DeferredRegister<EntityType<?>> ENTITIES =
            DeferredRegister.create(Registries.ENTITY_TYPE, EclipseMod.MOD_ID);

    /**
     * The Fog Tyrant — crowned apex of a mature fog storm (spec §2.4: 350 HP scaled,
     * dmg 9, speed 0.2, fire-immune, three-phase scripted fight).
     */
    public static final DeferredHolder<EntityType<?>, EntityType<FogTyrantEntity>> FOG_TYRANT =
            ENTITIES.register("fog_tyrant",
                    () -> EntityType.Builder.of(FogTyrantEntity::new, MobCategory.MONSTER)
                            .sized(2.4F, 4.2F)
                            .eyeHeight(3.0F)
                            .clientTrackingRange(10)
                            .fireImmune()
                            .build("fog_tyrant"));

    private FogBossEntities() {}

    /** Wiring hook for the {@code EclipseMod} constructor (integrator-applied). */
    public static void register(IEventBus modEventBus) {
        ENTITIES.register(modEventBus);
    }

    @SubscribeEvent
    static void onEntityAttributeCreation(EntityAttributeCreationEvent event) {
        if (!FOG_TYRANT.isBound()) {
            EclipseMod.LOGGER.warn("FogBossEntities registrar not wired yet — fog_tyrant "
                    + "dormant (apply docs/plans_v3/wiring/WB-TYRANT_wiring.md)");
            return;
        }
        event.put(FOG_TYRANT.get(), FogTyrantEntity.createAttributes().build());
    }
}
