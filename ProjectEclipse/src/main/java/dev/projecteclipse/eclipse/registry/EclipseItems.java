package dev.projecteclipse.eclipse.registry;

import java.util.function.Supplier;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.artifact.ArmArtifactItem;
import dev.projecteclipse.eclipse.economy.GraveDowserItem;
import dev.projecteclipse.eclipse.economy.UmbralShardItem;
import dev.projecteclipse.eclipse.economy.UmbralTier;
import dev.projecteclipse.eclipse.economy.VitaeShardItem;
import dev.projecteclipse.eclipse.economy.WatcherCompassItem;
import dev.projecteclipse.eclipse.ritual.HeraldsLureItem;
import dev.projecteclipse.eclipse.ritual.HeartExtractorItem;
import dev.projecteclipse.eclipse.ritual.ReviveSigilItem;
import net.minecraft.core.component.DataComponents;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.PickaxeItem;
import net.minecraft.world.item.Rarity;
import net.minecraft.world.item.SwordItem;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredRegister;

/** Item registry for Project: Eclipse. */
public final class EclipseItems {
    public static final DeferredRegister<Item> ITEMS =
            DeferredRegister.create(Registries.ITEM, EclipseMod.MOD_ID);

    /** Admin/debug item for the grave block; not obtainable in survival (grave has no loot table). */
    public static final Supplier<BlockItem> GRAVE = ITEMS.register("grave",
            () -> new BlockItem(EclipseBlocks.GRAVE.get(), new Item.Properties()));

    /** Dropped when a player voluntarily sacrifices a life at the altar. Revive-sigil ingredient. */
    public static final Supplier<Item> HEART_FRAGMENT = ITEMS.register("heart_fragment",
            () -> new Item(new Item.Properties()
                    .component(DataComponents.ENCHANTMENT_GLINT_OVERRIDE, Boolean.TRUE)));

    /**
     * Player-wielded heart tap (R8): sacrifices one life for two {@link #HEART_FRAGMENT} on
     * use-finish. Behavior completed by P4-B8; shell registers item + hold duration now.
     */
    public static final Supplier<HeartExtractorItem> HEART_EXTRACTOR = ITEMS.register("heart_extractor",
            () -> new HeartExtractorItem(new Item.Properties()
                    .stacksTo(1)
                    .durability(4)
                    .rarity(Rarity.UNCOMMON)));

    /**
     * Glitched mob drop (R9). Crafted into {@link #VITAE_SHARD} via glitch recipe; epic rarity.
     */
    public static final Supplier<Item> GLITCH_SHARD = ITEMS.register("glitch_shard",
            () -> new Item(new Item.Properties()
                    .stacksTo(64)
                    .rarity(Rarity.EPIC)
                    .component(DataComponents.ENCHANTMENT_GLINT_OVERRIDE, Boolean.TRUE)));

    /**
     * Night-mob drop (The Other, Umbral Stalker). Crafting currency for boss summon items
     * AND the altar shard shop's currency (W13): sneak-right-click the altar to bank a
     * stack ({@code economy.UmbralShardItem#useOn} → {@code economy.ShardEconomy}).
     */
    public static final Supplier<UmbralShardItem> UMBRAL_SHARD = ITEMS.register("umbral_shard",
            () -> new UmbralShardItem(new Item.Properties()));

    // --- W13 shard-shop rewards (spec §4; purchased at the altar via economy.ShardEconomy) ---

    /** 8 shards: needle follows the nearest OTHER player (updated every 40t); never says who. */
    public static final Supplier<WatcherCompassItem> COMPASS_OF_WATCHER = ITEMS.register("compass_of_watcher",
            () -> new WatcherCompassItem(new Item.Properties().stacksTo(1)));

    /** 4 shards: needle follows the holder's nearest own grave (EclipseWorldState.gravePositions). */
    public static final Supplier<GraveDowserItem> GRAVE_DOWSER = ITEMS.register("grave_dowser",
            () -> new GraveDowserItem(new Item.Properties().stacksTo(1)));

    /** 12 shards: 32t-use consumable, +1 permanent heart capped at HeartsService.MAX_HEARTS. */
    public static final Supplier<VitaeShardItem> VITAE_SHARD = ITEMS.register("vitae_shard",
            () -> new VitaeShardItem(new Item.Properties()
                    .stacksTo(16)
                    .rarity(Rarity.RARE)
                    .component(DataComponents.ENCHANTMENT_GLINT_OVERRIDE, Boolean.TRUE)));

    /** 12 shards: diamond-class pick, +50% break speed under open night sky; unrepairable. */
    public static final Supplier<PickaxeItem> UMBRAL_PICK = ITEMS.register("umbral_pick",
            () -> new PickaxeItem(UmbralTier.INSTANCE, new Item.Properties()
                    .attributes(PickaxeItem.createAttributes(UmbralTier.INSTANCE, 1.0F, -2.8F))));

    /** 16 shards: diamond-class blade, +1 heart lifesteal on player kill (lives.LifecycleEvents); unrepairable. */
    public static final Supplier<SwordItem> UMBRAL_BLADE = ITEMS.register("umbral_blade",
            () -> new SwordItem(UmbralTier.INSTANCE, new Item.Properties()
                    .attributes(SwordItem.createAttributes(UmbralTier.INSTANCE, 3, -2.4F))));

    /** Consumed at the altar to start the revive ritual for a banned player. */
    public static final Supplier<ReviveSigilItem> REVIVE_SIGIL = ITEMS.register("revive_sigil",
            () -> new ReviveSigilItem(new Item.Properties()
                    .component(DataComponents.ENCHANTMENT_GLINT_OVERRIDE, Boolean.TRUE)));

    /**
     * Herald summon item (W11, spec §2.1): 4 umbral shards + 1 heart fragment. Sneak-use
     * on the altar after dusk to call the day-7 boss down onto the sanctum.
     */
    public static final Supplier<HeraldsLureItem> HERALDS_LURE = ITEMS.register("heralds_lure",
            () -> new HeraldsLureItem(new Item.Properties()
                    .component(DataComponents.ENCHANTMENT_GLINT_OVERRIDE, Boolean.TRUE)));

    /**
     * Guaranteed Herald drop; REQUIRED for altar milestone L4 (W13 wires the L4 cost:
     * herald_core ×1 + ender_pearl ×16).
     */
    public static final Supplier<Item> HERALD_CORE = ITEMS.register("herald_core",
            () -> new Item(new Item.Properties()
                    .stacksTo(16)
                    .rarity(Rarity.EPIC)
                    .component(DataComponents.ENCHANTMENT_GLINT_OVERRIDE, Boolean.TRUE)));

    /**
     * Guaranteed Ferryman drop (W12, spec §2.2): the day-14 finale trophy. W13 decides its
     * economy uses (credits/epilogue); nothing consumes it yet.
     */
    public static final Supplier<Item> FERRYMAN_TOLL = ITEMS.register("ferryman_toll",
            () -> new Item(new Item.Properties()
                    .stacksTo(16)
                    .rarity(Rarity.EPIC)
                    .component(DataComponents.ENCHANTMENT_GLINT_OVERRIDE, Boolean.TRUE)));

    /** Admin/debug item for the altar block; not craftable (admins place the altar manually). */
    public static final Supplier<BlockItem> ALTAR = ITEMS.register("altar",
            () -> new BlockItem(EclipseBlocks.ALTAR.get(), new Item.Properties()));

    /**
     * The permanent in-game interface artifact, slot-locked to hotbar slot 8 by
     * {@code artifact.ArtifactSlotLock}. Id must stay exactly {@code eclipse:arm_artifact}
     * — other systems (e.g. {@code progression.PhaseInventoryLock}) resolve it by that id.
     */
    public static final Supplier<ArmArtifactItem> ARM_ARTIFACT = ITEMS.register("arm_artifact",
            () -> new ArmArtifactItem(new Item.Properties()
                    .stacksTo(1)
                    .fireResistant()
                    .rarity(Rarity.EPIC)
                    .component(DataComponents.ENCHANTMENT_GLINT_OVERRIDE, Boolean.TRUE)));

    private EclipseItems() {}

    public static void register(IEventBus modEventBus) {
        ITEMS.register(modEventBus);
    }
}
