package de.sonic0810.goobymod.registry;

import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.item.EmptyJarItem;
import de.sonic0810.goobymod.item.GoobyAccessoryItem;
import de.sonic0810.goobymod.item.GoobyBallItem;
import de.sonic0810.goobymod.item.GoobyHandbookItem;
import de.sonic0810.goobymod.item.GoobyTooltipItem;
import de.sonic0810.goobymod.item.GoobyTreasureMapItem;
import de.sonic0810.goobymod.item.GoobyWhistleItem;
import de.sonic0810.goobymod.item.NutellaItem;
import de.sonic0810.goobymod.item.NutellaToastItem;
import de.sonic0810.goobymod.item.TooltipBlockItem;
import de.sonic0810.goobymod.item.TornMapScrapItem;
import net.minecraft.core.component.DataComponents;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.Rarity;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.common.DeferredSpawnEggItem;
import net.neoforged.neoforge.registries.DeferredItem;
import net.neoforged.neoforge.registries.DeferredRegister;

public final class ModItems {
    public static final DeferredRegister.Items ITEMS = DeferredRegister.createItems(GoobyMod.MODID);

    /** Nutella-Glas: 3 Kakaobohnen + Milcheimer + Zucker. Platzierbar auf Grasblock! */
    public static final DeferredItem<NutellaItem> NUTELLA = ITEMS.register("nutella",
            () -> new NutellaItem(new Item.Properties().rarity(Rarity.UNCOMMON)));

    public static final DeferredItem<EmptyJarItem> EMPTY_JAR = ITEMS.register("empty_jar",
            () -> new EmptyJarItem(new Item.Properties()));

    /** Nutella-Toast: Brot + Nutella-Glas → 2 Scheiben Zuckerschub-Fruehstueck. */
    public static final DeferredItem<NutellaToastItem> NUTELLA_TOAST = ITEMS.register("nutella_toast",
            () -> new NutellaToastItem(new Item.Properties()));

    /** Knopfauge: Sammelmaterial aus Bau- und Schatztruhen; naeht Pluesch & Statue. */
    public static final DeferredItem<Item> BUTTON_EYE = ITEMS.register("button_eye",
            () -> new GoobyTooltipItem(new Item.Properties(),
                    "tooltip.goobymod.button_eye"));

    public static final DeferredItem<Item> GOOBY_BRUSH = ITEMS.register("gooby_brush",
            () -> new GoobyTooltipItem(new Item.Properties().durability(96),
                    "tooltip.goobymod.gooby_brush"));

    public static final DeferredItem<Item> GOOBY_FLUFF = ITEMS.register("gooby_fluff",
            () -> new GoobyAccessoryItem(new Item.Properties(), "tooltip.goobymod.gooby_hat_tag"));

    public static final DeferredItem<Item> SHIMMER_FLUFF = ITEMS.register("shimmer_fluff",
            () -> new GoobyTooltipItem(new Item.Properties().rarity(Rarity.RARE),
                    "tooltip.goobymod.shimmer_fluff"));

    public static final DeferredItem<Item> GOOBY_SCARF = ITEMS.register("gooby_scarf",
            () -> new GoobyAccessoryItem(new Item.Properties().stacksTo(1),
                    "tooltip.goobymod.gooby_scarf"));

    public static final DeferredItem<Item> GOOBY_BOWTIE = ITEMS.register("gooby_bowtie",
            () -> new GoobyAccessoryItem(new Item.Properties().stacksTo(1),
                    "tooltip.goobymod.gooby_accessory"));

    public static final DeferredItem<Item> TINY_SATCHEL = ITEMS.register("tiny_satchel",
            () -> new GoobyAccessoryItem(new Item.Properties().stacksTo(1),
                    "tooltip.goobymod.tiny_satchel"));

    // ------------------------------------------------------------------
    // Explorer-Outfit (v5.4): drei aufeinander abgestimmte Accessoires fuer
    // Kopf-, Hals- und Ruecken-Slot. Der Blumenkranz laeuft ueber den
    // bestehenden #goobymod:gooby_hats-Tag-Pfad; Halstuch und Rucksack
    // werden von ExplorerOutfitEvents ausgeruestet (GoobyEntity unveraendert).
    // ------------------------------------------------------------------

    /** Blumenkranz: Explorer-Hut via Tag; selten im Picknick-Loot. */
    public static final DeferredItem<Item> FLOWER_CROWN = ITEMS.register("flower_crown",
            () -> new GoobyAccessoryItem(new Item.Properties().stacksTo(1).rarity(Rarity.UNCOMMON),
                    "tooltip.goobymod.flower_crown"));

    /** Abenteuer-Halstuch: faerbbar wie der Schal (Crafting UND direkt am Gooby). */
    public static final DeferredItem<Item> ADVENTURE_BANDANA = ITEMS.register("adventure_bandana",
            () -> new GoobyAccessoryItem(new Item.Properties().stacksTo(1),
                    "tooltip.goobymod.adventure_bandana"));

    /** Picknick-Rucksack: kosmetisches Ruecken-Accessoire; selten im Schatzversteck. */
    public static final DeferredItem<Item> PICNIC_BACKPACK = ITEMS.register("picnic_backpack",
            () -> new GoobyAccessoryItem(new Item.Properties().stacksTo(1).rarity(Rarity.UNCOMMON),
                    "tooltip.goobymod.picnic_backpack"));

    public static final DeferredItem<TornMapScrapItem> TORN_MAP_SCRAP = ITEMS.register("torn_map_scrap",
            () -> new TornMapScrapItem(new Item.Properties().rarity(Rarity.UNCOMMON)));

    public static final DeferredItem<GoobyTreasureMapItem> GOOBY_TREASURE_MAP =
            ITEMS.register("gooby_treasure_map",
                    () -> new GoobyTreasureMapItem(new Item.Properties().stacksTo(1).rarity(Rarity.RARE)));

    public static final DeferredItem<Item> TRAINING_TREAT = ITEMS.register("training_treat",
            () -> new GoobyTooltipItem(new Item.Properties(),
                    "tooltip.goobymod.training_treat"));

    /** Gooby-Ball: werfen — der eigene Gooby apportiert ihn zurueck. */
    public static final DeferredItem<GoobyBallItem> GOOBY_BALL = ITEMS.register("gooby_ball",
            () -> new GoobyBallItem(new Item.Properties().stacksTo(16)));

    /** Gooby-Pfeife: schaltet fuer den BESITZER Wander → Follow → Stay durch. */
    public static final DeferredItem<GoobyWhistleItem> GOOBY_WHISTLE = ITEMS.register("gooby_whistle",
            () -> new GoobyWhistleItem(new Item.Properties().stacksTo(1)));

    public static final DeferredItem<GoobyHandbookItem> GOOBY_HANDBOOK = ITEMS.register("gooby_handbook",
            () -> new GoobyHandbookItem(new Item.Properties().stacksTo(1)
                    .component(DataComponents.WRITTEN_BOOK_CONTENT, GoobyHandbookItem.content())));

    public static final DeferredItem<BlockItem> GOOBY_WOOL = ITEMS.registerSimpleBlockItem(ModBlocks.GOOBY_WOOL);

    public static final DeferredItem<BlockItem> GOOBY_PLUSHIE = ITEMS.register("gooby_plushie",
            () -> new TooltipBlockItem(ModBlocks.GOOBY_PLUSHIE.get(), new Item.Properties(),
                    "tooltip.goobymod.gooby_plushie"));

    public static final DeferredItem<BlockItem> GOOBY_STATUE = ITEMS.register("gooby_statue",
            () -> new TooltipBlockItem(ModBlocks.GOOBY_STATUE.get(),
                    new Item.Properties().rarity(Rarity.UNCOMMON),
                    "tooltip.goobymod.gooby_statue"));

    public static final DeferredItem<BlockItem> RABBIT_HUTCH = ITEMS.registerSimpleBlockItem(ModBlocks.RABBIT_HUTCH);

    public static final DeferredItem<DeferredSpawnEggItem> GOOBY_SPAWN_EGG = ITEMS.register("gooby_spawn_egg",
            () -> new DeferredSpawnEggItem(ModEntities.GOOBY, 0x9C6B4A, 0xF5A9C4, new Item.Properties()));

    public static void register(IEventBus bus) {
        ITEMS.register(bus);
    }

    private ModItems() {
    }
}
