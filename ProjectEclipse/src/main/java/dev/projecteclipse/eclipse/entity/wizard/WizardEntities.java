package dev.projecteclipse.eclipse.entity.wizard;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.component.DataComponents;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.MobCategory;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.Rarity;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityAttributeCreationEvent;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;

/**
 * Registrar of the wizard family (W4-WIZARD, {@code docs/plans_v3/ideas_wave4/
 * IDEA-19_wand.md} §3) — this family's OWN {@code DeferredRegister}s per the P6
 * no-shared-file rule: {@code EclipseEntities}/{@code EclipseItems} are never touched.
 * {@link #register(IEventBus)} needs one wiring line in the {@code EclipseMod}
 * constructor — listed in {@code docs/plans_v3/wiring/W4-WIZARD_wiring.md}. Until that
 * line lands, every listener here (attributes, renderers, the observatory's Orin spawn)
 * no-ops via {@link DeferredHolder#isBound()}, so builds and both run configs stay green.
 *
 * <p>No spawn egg (house rule) and no natural spawning: Orin is placed exclusively by
 * {@link WizardService} inside the mountain observatory
 * ({@code worldgen/structure/WizardObservatory}).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class WizardEntities {
    public static final DeferredRegister<EntityType<?>> ENTITIES =
            DeferredRegister.create(Registries.ENTITY_TYPE, EclipseMod.MOD_ID);
    public static final DeferredRegister<Item> ITEMS =
            DeferredRegister.create(Registries.ITEM, EclipseMod.MOD_ID);

    /**
     * Orin the Sun-Reader — neutral hermit astronomer NPC on the highest mountain
     * (id FROZEN {@code eclipse:wizard_orin}). CREATURE so nothing hunts him; ~2.1
     * blocks with the pointed hat.
     */
    public static final DeferredHolder<EntityType<?>, EntityType<WizardOrinEntity>> WIZARD_ORIN =
            ENTITIES.register("wizard_orin",
                    () -> EntityType.Builder.of(WizardOrinEntity::new, MobCategory.CREATURE)
                            .sized(0.7F, 2.1F)
                            .eyeHeight(1.8F)
                            .clientTrackingRange(10)
                            .build("wizard_orin"));

    /**
     * Sun-Core Catalyst (id FROZEN {@code eclipse:wizard_catalyst}) — the veil-wand
     * craft gate (IDEA-19 §1.3): earned once per player via Orin's fetch quest, or
     * taken from his corpse (guaranteed single drop, {@link WizardOrinEntity}).
     */
    public static final DeferredHolder<Item, Item> WIZARD_CATALYST =
            ITEMS.register("wizard_catalyst",
                    () -> new Item(new Item.Properties()
                            .stacksTo(16)
                            .rarity(Rarity.EPIC)
                            .component(DataComponents.ENCHANTMENT_GLINT_OVERRIDE, Boolean.TRUE)));

    private WizardEntities() {}

    /** Wiring hook for the {@code EclipseMod} constructor (integrator-applied). */
    public static void register(IEventBus modEventBus) {
        ENTITIES.register(modEventBus);
        ITEMS.register(modEventBus);
    }

    @SubscribeEvent
    static void onEntityAttributeCreation(EntityAttributeCreationEvent event) {
        if (!WIZARD_ORIN.isBound()) {
            EclipseMod.LOGGER.warn("WizardEntities registrar not wired yet — wizard_orin dormant "
                    + "(apply docs/plans_v3/wiring/W4-WIZARD_wiring.md)");
            return;
        }
        event.put(WIZARD_ORIN.get(), WizardOrinEntity.createAttributes().build());
    }
}
