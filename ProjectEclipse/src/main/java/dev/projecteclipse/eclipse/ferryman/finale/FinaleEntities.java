package dev.projecteclipse.eclipse.ferryman.finale;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.MobCategory;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.entity.Mob;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityAttributeCreationEvent;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;

/**
 * Entity registry for the FERRYMAN2 finale family — this family's OWN
 * {@code DeferredRegister} per the house no-shared-file rule ({@code AmbientEntities}
 * pattern): {@code EclipseEntities} is never touched. {@link #register(IEventBus)}
 * needs one wiring line in the {@code EclipseMod} constructor; until it lands every
 * listener here (and the client renderer registration) no-ops via
 * {@link DeferredHolder#isBound()}.
 *
 * <p>No spawn eggs, no natural spawning (house rule) — the gate and key are placed by
 * {@link PortalFormation}/{@link FinaleSequence}, the wisps by the gate breach and the
 * Ferryman's Geisterbeschwörung. All three are {@link MobCategory#MISC} (PLAN-B B5:
 * self-capped event mobs stay out of the vanilla spawn census).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class FinaleEntities {
    public static final DeferredRegister<EntityType<?>> ENTITIES =
            DeferredRegister.create(Registries.ENTITY_TYPE, EclipseMod.MOD_ID);

    /**
     * The finale portal gate (F-045): a ~12-block GeckoLib arch standing over the water
     * off the center island. Pure scenery-with-state: invulnerable, immobile, persisted
     * (the monument stays after the crossing). Hitbox spans the closed door leaves only
     * (the frame is wider than any sane hitbox; displays/FX carry the rest visually).
     */
    public static final DeferredHolder<EntityType<?>, EntityType<PortalGateEntity>> PORTAL_GATE =
            ENTITIES.register("portal_gate",
                    () -> EntityType.Builder.of(PortalGateEntity::new, MobCategory.MISC)
                            .sized(5.0F, 12.0F)
                            .eyeHeight(6.0F)
                            .clientTrackingRange(12)
                            .fireImmune()
                            .build("portal_gate"));

    /**
     * The giant finale key (F-045b): ~3 blocks, hovering over the altar from the moment
     * the gate stands. Right-click OR walk-in starts the key sequence; invulnerable,
     * persisted until consumed by the flight.
     */
    public static final DeferredHolder<EntityType<?>, EntityType<PortalKeyEntity>> PORTAL_KEY =
            ENTITIES.register("portal_key",
                    () -> EntityType.Builder.of(PortalKeyEntity::new, MobCategory.MISC)
                            .sized(1.1F, 3.2F)
                            .eyeHeight(2.4F)
                            .clientTrackingRange(10)
                            .fireImmune()
                            .build("portal_key"));

    /**
     * The violet soul wisp (F-045b breach ghosts / F-046b Geisterbeschwörung): a small
     * vex-like shade with a hard lifespan, never saved to disk (despawn guarantee), no
     * collision physics (phases through the deck like the vex it apes).
     */
    public static final DeferredHolder<EntityType<?>, EntityType<SoulWispEntity>> SOUL_WISP =
            ENTITIES.register("soul_wisp",
                    () -> EntityType.Builder.of(SoulWispEntity::new, MobCategory.MISC)
                            .sized(0.6F, 1.0F)
                            .eyeHeight(0.7F)
                            .clientTrackingRange(10)
                            .fireImmune()
                            .build("soul_wisp"));

    private FinaleEntities() {}

    /** Wiring hook for the {@code EclipseMod} constructor (one line). */
    public static void register(IEventBus modEventBus) {
        ENTITIES.register(modEventBus);
    }

    @SubscribeEvent
    static void onEntityAttributeCreation(EntityAttributeCreationEvent event) {
        if (!PORTAL_GATE.isBound()) {
            EclipseMod.LOGGER.warn("FinaleEntities registrar not wired yet — portal_gate/"
                    + "portal_key/soul_wisp dormant (add FinaleEntities.register(modEventBus))");
            return;
        }
        // Health values on the two props are irrelevant (mechanically invulnerable).
        event.put(PORTAL_GATE.get(), Mob.createMobAttributes()
                .add(Attributes.MAX_HEALTH, 200.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.0D)
                .add(Attributes.KNOCKBACK_RESISTANCE, 1.0D)
                .add(Attributes.FOLLOW_RANGE, 16.0D)
                .build());
        event.put(PORTAL_KEY.get(), Mob.createMobAttributes()
                .add(Attributes.MAX_HEALTH, 40.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.0D)
                .add(Attributes.KNOCKBACK_RESISTANCE, 1.0D)
                .add(Attributes.FOLLOW_RANGE, 16.0D)
                .build());
        event.put(SOUL_WISP.get(), Monster.createMonsterAttributes()
                .add(Attributes.MAX_HEALTH, SoulWispEntity.MAX_HEALTH)
                .add(Attributes.ATTACK_DAMAGE, SoulWispEntity.CONTACT_DAMAGE)
                .add(Attributes.MOVEMENT_SPEED, 0.3D)
                .add(Attributes.FOLLOW_RANGE, 32.0D)
                .build());
    }
}
