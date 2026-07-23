package dev.projecteclipse.eclipse.entity.boss.rift;

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
 * Entity registry for the Rift Warden boss family (P6-W10) — this family's OWN
 * {@code DeferredRegister} per the P6 no-shared-file rule
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §1.6). {@link #register(IEventBus)}
 * needs one wiring line in the {@code EclipseMod} constructor — listed in
 * {@code docs/plans_v3/wiring/P6-W910_wiring.md} for the integrator. Until that line
 * lands, every listener here (and the client renderer registration) no-ops via
 * {@link DeferredHolder#isBound()}, so the build and both run configs stay green.
 *
 * <p>No spawn egg, no natural spawning, not a dungeon-spawner mob: P1's Collapsed Vault
 * boss room places the warden through {@link RiftWardenEntity#summonAt} (or any
 * {@code /summon eclipse:rift_warden} — the fight self-pins its arena).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class RiftEntities {
    public static final DeferredRegister<EntityType<?>> ENTITIES =
            DeferredRegister.create(Registries.ENTITY_TYPE, EclipseMod.MOD_ID);

    /**
     * The Rift Warden — vertically-split obsidian knight, Collapsed Vault mini-boss
     * (frozen §6 id; MONSTER, 1.1×3.0, tracking range 10 per the §2.3 table).
     */
    public static final DeferredHolder<EntityType<?>, EntityType<RiftWardenEntity>> RIFT_WARDEN =
            ENTITIES.register("rift_warden",
                    () -> EntityType.Builder.of(RiftWardenEntity::new, MobCategory.MONSTER)
                            .sized(1.1F, 3.0F)
                            .eyeHeight(2.6F)
                            .clientTrackingRange(10)
                            .fireImmune()
                            .build("rift_warden"));

    private RiftEntities() {}

    /** Wiring hook for the {@code EclipseMod} constructor (integrator-applied). */
    public static void register(IEventBus modEventBus) {
        ENTITIES.register(modEventBus);
    }

    @SubscribeEvent
    static void onEntityAttributeCreation(EntityAttributeCreationEvent event) {
        if (!RIFT_WARDEN.isBound()) {
            EclipseMod.LOGGER.warn("RiftEntities registrar not wired yet — rift_warden "
                    + "dormant (apply docs/plans_v3/wiring/P6-W910_wiring.md)");
            return;
        }
        event.put(RIFT_WARDEN.get(), RiftWardenEntity.createAttributes().build());
    }
}
