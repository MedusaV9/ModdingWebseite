package dev.projecteclipse.eclipse.backrooms;

import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvent;
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
 * Registrar for the Backrooms event content — this package's OWN {@code DeferredRegister}s
 * per the P6 no-shared-file rule ({@code GlitchEntities} precedent): the shared
 * {@code EclipseEntities}/{@code EclipseSounds} stay frozen. {@link #register(IEventBus)}
 * needs the one wiring line in the {@code EclipseMod} constructor; every listener here
 * (and the client renderer registrar) no-ops via {@link DeferredHolder#isBound()} until it
 * lands, so both run configs stay green either way.
 *
 * <ul>
 *   <li><b>{@code glitched_wanderer}</b> — husk-sized (0.6×1.9) MISC stalker; MISC keeps
 *       it out of the vanilla hostile census (PLAN-B B5 law), the Backrooms spawn budget
 *       is {@code BackroomsEventService}'s own cap. Spawn placement rules only matter for
 *       {@code /summon}-adjacent tooling — standard on-ground monster rules.</li>
 *   <li><b>{@code ambient.backrooms_buzz}</b> — the W4-ATMOS-style alias sound event
 *       (IDEAS §A2): sounds.json points it at the shipped {@code gazer_whisper} bed;
 *       {@code client.backrooms.BackroomsBuzz} pitches it to 0.55 (mains-buzz register)
 *       and a real recording can replace the alias later without code changes.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class BackroomsEntities {
    public static final DeferredRegister<EntityType<?>> ENTITIES =
            DeferredRegister.create(Registries.ENTITY_TYPE, EclipseMod.MOD_ID);
    public static final DeferredRegister<SoundEvent> SOUNDS =
            DeferredRegister.create(Registries.SOUND_EVENT, EclipseMod.MOD_ID);

    /** The Wanderer — mono-yellow glitched-husk stalker (IDEAS §A3.1). */
    public static final DeferredHolder<EntityType<?>, EntityType<GlitchedWandererEntity>> GLITCHED_WANDERER =
            ENTITIES.register("glitched_wanderer",
                    () -> EntityType.Builder.of(GlitchedWandererEntity::new, MobCategory.MISC)
                            .sized(0.6F, 1.9F)
                            .eyeHeight(1.66F)
                            .clientTrackingRange(10)
                            .build("glitched_wanderer"));

    /** Fluorescent mains-buzz loop (alias of the shipped hum bed, IDEAS §A2). */
    public static final Supplier<SoundEvent> AMBIENT_BACKROOMS_BUZZ = SOUNDS.register(
            "ambient.backrooms_buzz",
            () -> SoundEvent.createVariableRangeEvent(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ambient.backrooms_buzz")));

    private BackroomsEntities() {}

    /** Wiring hook for the {@code EclipseMod} constructor. */
    public static void register(IEventBus modEventBus) {
        ENTITIES.register(modEventBus);
        SOUNDS.register(modEventBus);
    }

    @SubscribeEvent
    static void onEntityAttributeCreation(EntityAttributeCreationEvent event) {
        if (!GLITCHED_WANDERER.isBound()) {
            EclipseMod.LOGGER.warn("BackroomsEntities registrar not wired yet — the Wanderer "
                    + "stays dormant (add the EclipseMod constructor line)");
            return;
        }
        event.put(GLITCHED_WANDERER.get(), GlitchedWandererEntity.createAttributes().build());
    }

    @SubscribeEvent
    static void onRegisterSpawnPlacements(RegisterSpawnPlacementsEvent event) {
        if (!GLITCHED_WANDERER.isBound()) {
            return; // Registrar not wired yet (warning already logged by the attribute hook).
        }
        event.register(GLITCHED_WANDERER.get(), SpawnPlacementTypes.ON_GROUND,
                Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, Monster::checkMonsterSpawnRules,
                RegisterSpawnPlacementsEvent.Operation.REPLACE);
    }
}
