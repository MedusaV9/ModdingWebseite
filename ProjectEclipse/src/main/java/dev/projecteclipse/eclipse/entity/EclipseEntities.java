package dev.projecteclipse.eclipse.entity;

import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.boss.HeraldEntity;
import dev.projecteclipse.eclipse.entity.boss.HeraldShardProjectile;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.MobCategory;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.monster.Monster;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.event.entity.EntityAttributeCreationEvent;
import net.neoforged.neoforge.registries.DeferredRegister;

/**
 * Entity type registry for the v2 custom mobs ({@code docs/ideas/04_content.md} §1).
 * Attributes are supplied through {@link EntityAttributeCreationEvent}; client layer
 * definitions and renderers live in {@code client.entity.EclipseEntityRenderers}.
 *
 * <p>None of these mobs use natural (biome) spawning — {@link EclipseSpawner} places them
 * server-side keyed off the event day and the night-event state, and the Deckhand crew is
 * seeded once by {@code limbo.GhostShipBuilder}. No spawn eggs are registered on purpose
 * (event mod: admins use {@code /summon}).</p>
 */
public final class EclipseEntities {
    public static final DeferredRegister<EntityType<?>> ENTITIES =
            DeferredRegister.create(Registries.ENTITY_TYPE, EclipseMod.MOD_ID);

    /** Doppelganger event hunter (Pale Nights only); player-sized so the mimicry holds up. */
    public static final Supplier<EntityType<TheOtherEntity>> THE_OTHER = ENTITIES.register("the_other",
            () -> EntityType.Builder.of(TheOtherEntity::new, MobCategory.MONSTER)
                    .sized(0.6F, 1.8F)
                    .eyeHeight(1.62F)
                    .clientTrackingRange(10)
                    .build("the_other"));

    /** Ambient watcher; never attacks, vanishes when stared at, unkillable. */
    public static final Supplier<EntityType<GazerEntity>> GAZER = ENTITIES.register("gazer",
            () -> EntityType.Builder.of(GazerEntity::new, MobCategory.CREATURE)
                    .sized(0.8F, 2.1F)
                    .eyeHeight(1.6F)
                    .clientTrackingRange(10)
                    .fireImmune()
                    .build("gazer"));

    /** Night pack hunter (day 5+, packs doubled on Umbral Nights). */
    public static final Supplier<EntityType<UmbralStalkerEntity>> UMBRAL_STALKER = ENTITIES.register("umbral_stalker",
            () -> EntityType.Builder.of(UmbralStalkerEntity::new, MobCategory.MONSTER)
                    .sized(0.9F, 1.2F)
                    .eyeHeight(0.85F)
                    .clientTrackingRange(10)
                    .build("umbral_stalker"));

    /** Mute rowing crew of the limbo ghost ship; invulnerable ambience. */
    public static final Supplier<EntityType<DeckhandEntity>> DECKHAND = ENTITIES.register("deckhand",
            () -> EntityType.Builder.of(DeckhandEntity::new, MobCategory.CREATURE)
                    .sized(0.7F, 1.6F)
                    .eyeHeight(1.3F)
                    .clientTrackingRange(10)
                    .build("deckhand"));

    /** Fullbright wisp orbiting the sanctum altar (one per altar level). */
    public static final Supplier<EntityType<SunmoteEntity>> SUNMOTE = ENTITIES.register("sunmote",
            () -> EntityType.Builder.of(SunmoteEntity::new, MobCategory.CREATURE)
                    .sized(0.4F, 0.4F)
                    .eyeHeight(0.2F)
                    .clientTrackingRange(10)
                    .fireImmune()
                    .build("sunmote"));

    /**
     * Day-7 boss (W11, spec §2.1). Summoned only by the Herald's Lure ritual or
     * {@code /eclipse boss herald summon} — never spawned naturally. The hitbox spans the
     * floating core (center 2.5 blocks above feet) down through the tentacle chains.
     */
    public static final Supplier<EntityType<HeraldEntity>> HERALD = ENTITIES.register("herald",
            () -> EntityType.Builder.of(HeraldEntity::new, MobCategory.MONSTER)
                    .sized(2.2F, 3.2F)
                    .eyeHeight(2.5F)
                    .clientTrackingRange(10)
                    .fireImmune()
                    .build("herald"));

    /** Homing corona shard fired by the Herald's volley; shootable down mid-air. */
    public static final Supplier<EntityType<HeraldShardProjectile>> HERALD_SHARD = ENTITIES.register("herald_shard",
            () -> EntityType.Builder.<HeraldShardProjectile>of(HeraldShardProjectile::new, MobCategory.MISC)
                    .sized(0.4F, 0.4F)
                    .clientTrackingRange(8)
                    .updateInterval(10)
                    .fireImmune()
                    .build("herald_shard"));

    private EclipseEntities() {}

    public static void register(IEventBus modEventBus) {
        ENTITIES.register(modEventBus);
        modEventBus.addListener(EclipseEntities::onEntityAttributeCreation);
    }

    private static void onEntityAttributeCreation(EntityAttributeCreationEvent event) {
        // The Other walks at player pace via goal speed modifiers over a zombie-like base.
        event.put(THE_OTHER.get(), Monster.createMonsterAttributes()
                .add(Attributes.MAX_HEALTH, 20.0D)
                .add(Attributes.ATTACK_DAMAGE, 3.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.3D)
                .add(Attributes.FOLLOW_RANGE, 48.0D)
                .build());
        // Gazer never moves under its own power (relocation is teleport-only).
        event.put(GAZER.get(), Mob.createMobAttributes()
                .add(Attributes.MAX_HEALTH, 6.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.0D)
                .add(Attributes.FOLLOW_RANGE, 48.0D)
                .build());
        // Spec §1.3: 20 HP, 4 dmg, speed 0.32, follow 40.
        event.put(UMBRAL_STALKER.get(), Monster.createMonsterAttributes()
                .add(Attributes.MAX_HEALTH, 20.0D)
                .add(Attributes.ATTACK_DAMAGE, 4.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.32D)
                .add(Attributes.FOLLOW_RANGE, 40.0D)
                .build());
        event.put(DECKHAND.get(), Mob.createMobAttributes()
                .add(Attributes.MAX_HEALTH, 20.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.0D)
                .add(Attributes.FOLLOW_RANGE, 48.0D)
                .build());
        event.put(SUNMOTE.get(), Mob.createMobAttributes()
                .add(Attributes.MAX_HEALTH, 2.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.0D)
                .add(Attributes.FOLLOW_RANGE, 16.0D)
                .build());
        // Spec §2.1: 300 HP base (player-count scaling adjusts MAX_HEALTH at summon time),
        // gaze deals 8 via ATTACK_DAMAGE, immovable (knockback() is a no-op too).
        event.put(HERALD.get(), Monster.createMonsterAttributes()
                .add(Attributes.MAX_HEALTH, HeraldEntity.BASE_MAX_HEALTH)
                .add(Attributes.ATTACK_DAMAGE, 8.0D)
                .add(Attributes.MOVEMENT_SPEED, 0.3D)
                .add(Attributes.FOLLOW_RANGE, 64.0D)
                .add(Attributes.KNOCKBACK_RESISTANCE, 1.0D)
                .add(Attributes.ARMOR, 4.0D)
                .build());
    }
}
