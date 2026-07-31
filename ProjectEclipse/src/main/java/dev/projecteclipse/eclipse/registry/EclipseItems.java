package dev.projecteclipse.eclipse.registry;

import java.util.List;
import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.artifact.ArmArtifactItem;
import dev.projecteclipse.eclipse.economy.FerrymanTollItem;
import dev.projecteclipse.eclipse.economy.GraveDowserItem;
import dev.projecteclipse.eclipse.economy.UmbralBladeItem;
import dev.projecteclipse.eclipse.economy.UmbralPickItem;
import dev.projecteclipse.eclipse.economy.UmbralShardItem;
import dev.projecteclipse.eclipse.economy.UmbralTier;
import dev.projecteclipse.eclipse.economy.VitaeShardItem;
import dev.projecteclipse.eclipse.economy.WatcherCompassItem;
import dev.projecteclipse.eclipse.ritual.HeraldsLureItem;
import dev.projecteclipse.eclipse.ritual.HeartExtractorItem;
import dev.projecteclipse.eclipse.ritual.ReviveSigilItem;
import dev.projecteclipse.eclipse.ritual.StormHeartItem;
import net.minecraft.core.component.DataComponents;
import net.minecraft.core.registries.Registries;
import net.minecraft.network.chat.Component;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.PickaxeItem;
import net.minecraft.world.item.Rarity;
import net.minecraft.world.item.SwordItem;
import net.minecraft.world.item.component.ItemLore;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredRegister;

/**
 * Item registry for Project: Eclipse.
 *
 * <p>Rarity / glint / lore hygiene follows the PLAN-ITEMS §2.3 table (ITEMS-B is the
 * sole owner of this file). Glint discipline: glint = "charged consumable/ritual fuel"
 * (heart_fragment, glitch_shard, vitae_shard, revive_sigil, heralds_lure); trophies and
 * geo-rendered items carry NO {@code ENCHANTMENT_GLINT_OVERRIDE} — their custom icons,
 * glowmasks and rarity colors do the shimmering. Every player-facing custom item bakes
 * one poetic {@code item.eclipse.<id>.lore} line at registration (storm_heart / V6
 * gap-fix precedent); keys ship via {@code docs/plans_v3/langdrop/V7-ITEMSB.json}.</p>
 */
public final class EclipseItems {
    public static final DeferredRegister<Item> ITEMS =
            DeferredRegister.create(Registries.ITEM, EclipseMod.MOD_ID);

    /** Admin/debug item for the grave block; not obtainable in survival (grave has no loot table). */
    public static final Supplier<BlockItem> GRAVE = ITEMS.register("grave",
            () -> new BlockItem(EclipseBlocks.GRAVE.get(), new Item.Properties()));

    /** Dropped when a player voluntarily sacrifices a life at the altar. Revive-sigil ingredient. */
    public static final Supplier<Item> HEART_FRAGMENT = ITEMS.register("heart_fragment",
            () -> new Item(new Item.Properties()
                    .rarity(Rarity.UNCOMMON)
                    .component(DataComponents.ENCHANTMENT_GLINT_OVERRIDE, Boolean.TRUE)
                    .component(DataComponents.LORE, loreLine("heart_fragment"))));

    /**
     * Player-wielded heart tap (R8): sacrifices one life for two {@link #HEART_FRAGMENT} on
     * use-finish. Behavior completed by P4-B8; shell registers item + hold duration now.
     */
    public static final Supplier<HeartExtractorItem> HEART_EXTRACTOR = ITEMS.register("heart_extractor",
            () -> new HeartExtractorItem(new Item.Properties()
                    .stacksTo(1)
                    .durability(4)
                    .rarity(Rarity.UNCOMMON)
                    .component(DataComponents.LORE, loreLine("heart_extractor"))));

    /**
     * Glitched mob drop (R9). Crafted into {@link #VITAE_SHARD} via glitch recipe; epic rarity.
     */
    public static final Supplier<Item> GLITCH_SHARD = ITEMS.register("glitch_shard",
            () -> new Item(new Item.Properties()
                    .stacksTo(64)
                    .rarity(Rarity.EPIC)
                    .component(DataComponents.ENCHANTMENT_GLINT_OVERRIDE, Boolean.TRUE)
                    .component(DataComponents.LORE, loreLine("glitch_shard"))));

    /**
     * Night-mob drop (The Other, Umbral Stalker). Crafting currency for boss summon items
     * AND the altar shard shop's currency (W13): sneak-right-click the altar to bank a
     * stack ({@code economy.UmbralShardItem#useOn} → {@code economy.ShardEconomy}).
     */
    public static final Supplier<UmbralShardItem> UMBRAL_SHARD = ITEMS.register("umbral_shard",
            () -> new UmbralShardItem(new Item.Properties()
                    .component(DataComponents.LORE, loreLine("umbral_shard"))));

    // --- W13 shard-shop rewards (spec §4; purchased at the altar via economy.ShardEconomy) ---

    /** 8 shards: needle follows the nearest OTHER player (updated every 40t); never says who. */
    public static final Supplier<WatcherCompassItem> COMPASS_OF_WATCHER = ITEMS.register("compass_of_watcher",
            () -> new WatcherCompassItem(new Item.Properties()
                    .stacksTo(1)
                    .rarity(Rarity.UNCOMMON)
                    .component(DataComponents.LORE, loreLine("compass_of_watcher"))));

    /** 4 shards: needle follows the holder's nearest own grave (EclipseWorldState.gravePositions). */
    public static final Supplier<GraveDowserItem> GRAVE_DOWSER = ITEMS.register("grave_dowser",
            () -> new GraveDowserItem(new Item.Properties()
                    .stacksTo(1)
                    .rarity(Rarity.UNCOMMON)
                    .component(DataComponents.LORE, loreLine("grave_dowser"))));

    /** 12 shards: 32t-use consumable, +1 permanent heart capped at HeartsService.MAX_HEARTS. */
    public static final Supplier<VitaeShardItem> VITAE_SHARD = ITEMS.register("vitae_shard",
            () -> new VitaeShardItem(new Item.Properties()
                    .stacksTo(16)
                    .rarity(Rarity.RARE)
                    .component(DataComponents.ENCHANTMENT_GLINT_OVERRIDE, Boolean.TRUE)
                    .component(DataComponents.LORE, loreLine("vitae_shard"))));

    /**
     * 12 shards: diamond-class pick, +50% break speed under open night sky; unrepairable.
     * POLISH3: {@code economy.UmbralPickItem} = same {@code PickaxeItem} gameplay + GeckoLib
     * hand-3D geo (gui/ground/fixed keep the 2D icon via separate_transforms).
     */
    public static final Supplier<UmbralPickItem> UMBRAL_PICK = ITEMS.register("umbral_pick",
            () -> new UmbralPickItem(UmbralTier.INSTANCE, new Item.Properties()
                    .rarity(Rarity.RARE)
                    .component(DataComponents.LORE, loreLine("umbral_pick"))
                    .attributes(PickaxeItem.createAttributes(UmbralTier.INSTANCE, 1.0F, -2.8F))));

    /**
     * 16 shards: diamond-class blade, +1 heart lifesteal on player kill (lives.LifecycleEvents);
     * unrepairable. POLISH3: {@code economy.UmbralBladeItem} = same {@code SwordItem} gameplay +
     * GeckoLib hand-3D geo (gui/ground/fixed keep the 2D icon via separate_transforms).
     */
    public static final Supplier<UmbralBladeItem> UMBRAL_BLADE = ITEMS.register("umbral_blade",
            () -> new UmbralBladeItem(UmbralTier.INSTANCE, new Item.Properties()
                    .rarity(Rarity.RARE)
                    .component(DataComponents.LORE, loreLine("umbral_blade"))
                    .attributes(SwordItem.createAttributes(UmbralTier.INSTANCE, 3, -2.4F))));

    /**
     * Consumed at the altar to start the revive ritual for a banned player. GeckoLib rune
     * tablet (PLAN-ITEMS B3); keeps its glint — ritual fuel under the §2.3 discipline.
     */
    public static final Supplier<ReviveSigilItem> REVIVE_SIGIL = ITEMS.register("revive_sigil",
            () -> new ReviveSigilItem(new Item.Properties()
                    .rarity(Rarity.RARE)
                    .component(DataComponents.ENCHANTMENT_GLINT_OVERRIDE, Boolean.TRUE)
                    .component(DataComponents.LORE, loreLine("revive_sigil"))));

    /**
     * Herald summon item (W11, spec §2.1): 4 umbral shards + 1 heart fragment. Sneak-use
     * on the altar after dusk to call the day-7 boss down onto the sanctum. GeckoLib
     * shard cage (PLAN-ITEMS B2); keeps its glint — ritual fuel.
     */
    public static final Supplier<HeraldsLureItem> HERALDS_LURE = ITEMS.register("heralds_lure",
            () -> new HeraldsLureItem(new Item.Properties()
                    .rarity(Rarity.RARE)
                    .component(DataComponents.ENCHANTMENT_GLINT_OVERRIDE, Boolean.TRUE)
                    .component(DataComponents.LORE, loreLine("heralds_lure"))));

    /**
     * Guaranteed Herald drop; REQUIRED for altar milestone L4 (W13 wires the L4 cost:
     * herald_core ×1 + ender_pearl ×16). Trophy — no glint (§2.3 discipline).
     */
    public static final Supplier<Item> HERALD_CORE = ITEMS.register("herald_core",
            () -> new Item(new Item.Properties()
                    .stacksTo(16)
                    .rarity(Rarity.EPIC)
                    .component(DataComponents.LORE, loreLine("herald_core"))));

    /**
     * Guaranteed Ferryman drop (W12, spec §2.2): the day-14 finale trophy. W13 decides its
     * economy uses (credits/epilogue); nothing consumes it yet. Trophy — no glint.
     * POLISH3: {@code economy.FerrymanTollItem} = same no-op trophy + GeckoLib hand-3D
     * spectral coin (gui/ground/fixed keep the 2D icon via separate_transforms).
     */
    public static final Supplier<FerrymanTollItem> FERRYMAN_TOLL = ITEMS.register("ferryman_toll",
            () -> new FerrymanTollItem(new Item.Properties()
                    .stacksTo(16)
                    .rarity(Rarity.EPIC)
                    .component(DataComponents.LORE, loreLine("ferryman_toll"))));

    /**
     * Guaranteed Fog Tyrant drop (C8 reward upgrade): the storm's condensed heart, epic
     * trophy in the {@link #HERALD_CORE} family. Seam note (PLAN-C C8): if PLAN-D's
     * economy packages add a loot config, its costs/uses route through there. Trophy —
     * no glint.
     */
    public static final Supplier<Item> FOG_CORE = ITEMS.register("fog_core",
            () -> new Item(new Item.Properties()
                    .stacksTo(16)
                    .rarity(Rarity.EPIC)
                    .component(DataComponents.LORE, loreLine("fog_core"))));

    /**
     * Unique cosmetic keepsake off the tyrant's mantle (C8 reward upgrade): a fog-cloak
     * trim. Pure trophy/cosmetic — nothing consumes it; deliberately unstackable so the
     * one cut per kill stays "the one". Trophy — no glint.
     */
    public static final Supplier<Item> FOG_CLOAK_TRIM = ITEMS.register("fog_cloak_trim",
            () -> new Item(new Item.Properties()
                    .stacksTo(1)
                    .rarity(Rarity.EPIC)
                    .component(DataComponents.LORE, loreLine("fog_cloak_trim"))));

    /**
     * The storm's beating heart (plan §2.4, closed by the V6 gap-fix): guaranteed Fog
     * Tyrant drop with baked-in lore. Registering it retires the tyrant's 6-umbral-shard
     * registry-lookup fallback — the shards still drop alongside as the storm's loose
     * change ({@code FogTyrantEntity#dropCustomDeathLoot}). GeckoLib caged-core showpiece
     * (PLAN-ITEMS B1) — the glowmask replaces the old glint.
     */
    public static final Supplier<StormHeartItem> STORM_HEART = ITEMS.register("storm_heart",
            () -> new StormHeartItem(new Item.Properties()
                    .stacksTo(16)
                    .rarity(Rarity.EPIC)
                    .component(DataComponents.LORE, loreLine("storm_heart"))));

    /** Admin/debug item for the altar block; not craftable (admins place the altar manually). */
    public static final Supplier<BlockItem> ALTAR = ITEMS.register("altar",
            () -> new BlockItem(EclipseBlocks.ALTAR.get(), new Item.Properties()));

    /**
     * The permanent in-game interface artifact, slot-locked to hotbar slot 8 by
     * {@code artifact.ArtifactSlotLock}. Id must stay exactly {@code eclipse:arm_artifact}
     * — other systems (e.g. {@code progression.PhaseInventoryLock}) resolve it by that id.
     * No glint (§2.3: ITEMS-A's geo ledger-glow replaces it); keeps its dynamic
     * {@code item.eclipse.arm_artifact.tooltip} instead of a baked lore line.
     */
    public static final Supplier<ArmArtifactItem> ARM_ARTIFACT = ITEMS.register("arm_artifact",
            () -> new ArmArtifactItem(new Item.Properties()
                    .stacksTo(1)
                    .fireResistant()
                    .rarity(Rarity.EPIC)));

    private EclipseItems() {}

    /** One baked italic lore line, translated via {@code item.eclipse.<id>.lore} (storm_heart pattern). */
    private static ItemLore loreLine(String itemId) {
        return new ItemLore(List.of(Component.translatable("item.eclipse." + itemId + ".lore")));
    }

    public static void register(IEventBus modEventBus) {
        ITEMS.register(modEventBus);
    }
}
