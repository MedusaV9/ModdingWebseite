package dev.projecteclipse.eclipse.wand;

import java.util.UUID;
import java.util.function.Supplier;

import com.mojang.serialization.Codec;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.devtools.dev.DevReloadRegistry;
import net.minecraft.core.UUIDUtil;
import net.minecraft.core.component.DataComponentType;
import net.minecraft.core.registries.Registries;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.Rarity;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;

/**
 * W4-WAND registrar: the Zauberstab item family + its data components. Self-contained —
 * the ONLY hub wiring is one {@code WandItems.register(modEventBus);} line in
 * {@code EclipseMod} (see {@code docs/plans_v3/wiring/W4-WAND_wiring.md}). Everything else
 * in the wand package self-registers via {@code @EventBusSubscriber}.
 *
 * <p>The wand is the mod's first GeckoLib <b>item</b>; asset triple (frozen GeckoLib-4
 * defaulted paths, item flavor): {@code geo/item/eclipse_wand.geo.json},
 * {@code animations/item/eclipse_wand.animation.json}, per-path textures under
 * {@code textures/item/wand/} (selected by the client renderer).</p>
 *
 * <p>Components are int-based where possible so dev commands and payload validation stay
 * trivially range-checkable; {@code WandPath} owns the id mapping.</p>
 */
public final class WandItems {
    public static final DeferredRegister<Item> ITEMS =
            DeferredRegister.create(Registries.ITEM, EclipseMod.MOD_ID);
    public static final DeferredRegister.DataComponents COMPONENTS =
            DeferredRegister.createDataComponents(Registries.DATA_COMPONENT_TYPE, EclipseMod.MOD_ID);

    // ------------------------------------------------------------------ data components

    /** Soulbind owner. Absent on a freshly crafted wand until first inventory tick. */
    public static final Supplier<DataComponentType<UUID>> WAND_OWNER =
            COMPONENTS.registerComponentType("wand_owner", builder -> builder
                    .persistent(UUIDUtil.CODEC).networkSynchronized(UUIDUtil.STREAM_CODEC));

    /** {@link WandPath} wire id (0 none / 1 riss / 2 glut / 3 stern). Locked once != 0. */
    public static final Supplier<DataComponentType<Integer>> WAND_PATH =
            COMPONENTS.registerComponentType("wand_path", builder -> builder
                    .persistent(Codec.intRange(0, 3)).networkSynchronized(ByteBufCodecs.VAR_INT));

    /** Wand level 1..{@link WandPath#MAX_LEVEL}. */
    public static final Supplier<DataComponentType<Integer>> WAND_LEVEL =
            COMPONENTS.registerComponentType("wand_level", builder -> builder
                    .persistent(Codec.intRange(1, WandPath.MAX_LEVEL)).networkSynchronized(ByteBufCodecs.VAR_INT));

    /** Wand XP toward the next level (whole points; curve in {@code WandConfig.levelCosts}). */
    public static final Supplier<DataComponentType<Integer>> WAND_XP =
            COMPONENTS.registerComponentType("wand_xp", builder -> builder
                    .persistent(Codec.intRange(0, Integer.MAX_VALUE)).networkSynchronized(ByteBufCodecs.VAR_INT));

    /** Veilladung charge 0..{@code WandConfig.charge().max()} (HUD pips read this client-side). */
    public static final Supplier<DataComponentType<Integer>> WAND_CHARGE =
            COMPONENTS.registerComponentType("wand_charge", builder -> builder
                    .persistent(Codec.intRange(0, Integer.MAX_VALUE)).networkSynchronized(ByteBufCodecs.VAR_INT));

    /** Selected power index 0..4 (cycled with sneak-use; casting uses this server-side value). */
    public static final Supplier<DataComponentType<Integer>> WAND_SELECTED =
            COMPONENTS.registerComponentType("wand_selected", builder -> builder
                    .persistent(Codec.intRange(0, WandPath.MAX_LEVEL - 1)).networkSynchronized(ByteBufCodecs.VAR_INT));

    // ------------------------------------------------------------------ items

    /**
     * The Zauberstab. Id deliberately {@code eclipse:eclipse_wand} (spec) — NOT to be
     * confused with the op-only {@code eclipse:display_wand} from {@code /dev display give}.
     */
    public static final DeferredHolder<Item, EclipseWandItem> ECLIPSE_WAND = ITEMS.register("eclipse_wand",
            () -> new EclipseWandItem(new Item.Properties()
                    .stacksTo(1)
                    .fireResistant()
                    .rarity(Rarity.EPIC)));

    /**
     * Craft gate: the recipe ({@code data/eclipse/recipe/eclipse_wand.json}) requires one
     * <b>Sonnenkern-Katalysator</b> ({@code eclipse:wizard_catalyst}). That item is
     * registered by the W4-WIZARD sibling ({@code entity/wizard/WizardEntities} — id frozen
     * there; registering it here too would be a duplicate-id crash), so this worker ships
     * only the recipe + the item TEXTURE/MODEL assets and references the id as a string.
     * The wand recipe therefore needs the W4-WIZARD registrar wired first (see the
     * W4-WAND wiring doc); until then {@code /give @s eclipse:wizard_catalyst} fails and
     * the recipe logs an unknown-item parse error (harmless, nothing crashes).
     */
    public static final String WIZARD_CATALYST_ID = "eclipse:wizard_catalyst";

    private WandItems() {}

    /** One-line {@code EclipseMod} hook (see the W4-WAND wiring doc). */
    public static void register(IEventBus modEventBus) {
        ITEMS.register(modEventBus);
        COMPONENTS.register(modEventBus);
        // config/eclipse/wand.json rides /dev reload like the other additive loaders.
        DevReloadRegistry.register("wand.json", WandConfig::reload);
    }
}
