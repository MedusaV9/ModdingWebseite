package de.sonic0810.goobymod.gametest;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.mojang.authlib.GameProfile;
import de.sonic0810.goobymod.GoobyAdvancements;
import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.entity.GoobyWardrobe;
import de.sonic0810.goobymod.event.ExplorerOutfitEvents;
import de.sonic0810.goobymod.registry.ModCreativeTabs;
import de.sonic0810.goobymod.registry.ModEntities;
import de.sonic0810.goobymod.registry.ModItems;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.UUID;
import net.minecraft.advancements.AdvancementHolder;
import net.minecraft.core.BlockPos;
import net.minecraft.core.component.DataComponents;
import net.minecraft.core.registries.Registries;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.RandomSource;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.flag.FeatureFlags;
import net.minecraft.world.item.CreativeModeTab;
import net.minecraft.world.item.DyeColor;
import net.minecraft.world.item.DyeItem;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.item.component.DyedItemColor;
import net.minecraft.world.item.crafting.CraftingInput;
import net.minecraft.world.item.crafting.RecipeType;
import net.minecraft.world.item.enchantment.Enchantments;
import net.minecraft.world.level.GameType;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.storage.loot.LootParams;
import net.minecraft.world.level.storage.loot.LootTable;
import net.minecraft.world.level.storage.loot.parameters.LootContextParamSets;
import net.minecraft.world.level.storage.loot.parameters.LootContextParams;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.common.util.FakePlayer;
import net.neoforged.neoforge.common.util.FakePlayerFactory;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * Explorer-Outfit (v5.4): Blumenkranz (HEAD, Tag-Pfad), Abenteuer-Halstuch
 * (NECK, faerbbar) und Picknick-Rucksack (BACK). Alle drei Teile laufen
 * ueber den serverautoritativen Entity-Pfad
 * {@link GoobyEntity#tryEquipAccessory}; {@link ExplorerOutfitEvents} ist
 * nur noch ein duenner Advancement-Layer ueber
 * {@code PlayerInteractEvent.EntityInteract}. Die Equip-Tests laufen ueber
 * {@code Player#interactOn}, den echten Server-Interaktionspfad, der das
 * Event feuert.
 *
 * <p>Abgedeckt: Equip/Sync/Persist ueber den Interaktionspfad, Policy-Gates
 * (Baby/wild/fremd), volle ItemStack-Treue inkl. Swap-Drop, Faerben im
 * Crafting UND am getragenen Halstuch, Satchel-Rueckgabe beim Rucksack-Tausch,
 * Slot-Isolation, das explorer_outfit-Advancement in beiden Reihenfolgen
 * (Kranz zuletzt = deferred TickTask-Pfad), Rezepte + Unlock-Advancements,
 * Loot-Seltenheit per echtem Tabellen-Roll, Modelle/Texturen/Lang/
 * Creative-Tab als Asset-Vertrag sowie die direkte Entity-API:
 * Zweithand-Paritaet, Slot↔Item-Mismatch fail-closed und keine
 * Health/Navigation/Carry-Seiteneffekte beim Equip.</p>
 */
@GameTestHolder(GoobyMod.MODID)
@PrefixGameTestTemplate(false)
public class GoobyExplorerOutfitTests {
    private static final String ARENA = "arena";

    // ------------------------------------------------------------------
    // Helfer
    // ------------------------------------------------------------------

    private static FakePlayer fakePlayer(GameTestHelper helper, String name) {
        return FakePlayerFactory.get(helper.getLevel(),
                new GameProfile(UUID.nameUUIDFromBytes(name.getBytes(StandardCharsets.UTF_8)), name));
    }

    private static void placeFloor(GameTestHelper helper) {
        for (int x = 0; x < 5; x++) {
            for (int z = 0; z < 5; z++) {
                helper.setBlock(new BlockPos(x, 1, z), Blocks.DIRT);
            }
        }
    }

    private static JsonObject loadAssetJson(GameTestHelper helper, String path) {
        try (InputStream stream = GoobyExplorerOutfitTests.class.getClassLoader().getResourceAsStream(path)) {
            helper.assertTrue(stream != null, "Asset fehlt im Runtime-Classpath: " + path);
            return JsonParser.parseReader(new InputStreamReader(stream, StandardCharsets.UTF_8)).getAsJsonObject();
        } catch (IOException | RuntimeException exception) {
            helper.fail("Asset kann nicht gelesen werden: " + path + " (" + exception.getMessage() + ")");
            return new JsonObject();
        }
    }

    private static GoobyEntity spawnTamedAdult(GameTestHelper helper, ServerPlayer owner) {
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        return gooby;
    }

    /** Echter Server-Interaktionspfad: feuert das EntityInteract-Event. */
    private static void interactHolding(ServerPlayer player, GoobyEntity gooby, ItemStack stack) {
        player.setItemInHand(InteractionHand.MAIN_HAND, stack);
        player.interactOn(gooby, InteractionHand.MAIN_HAND);
    }

    private static boolean advancementDone(GameTestHelper helper, ServerPlayer player, String path) {
        AdvancementHolder holder = helper.getLevel().getServer().getAdvancements()
                .get(ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, path));
        return holder != null && player.getAdvancements().getOrStartProgress(holder).isDone();
    }

    private static LootTable lootTable(GameTestHelper helper, String path) {
        return helper.getLevel().getServer().reloadableRegistries().getLootTable(
                ResourceKey.create(Registries.LOOT_TABLE,
                        ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, path)));
    }

    // ------------------------------------------------------------------
    // 1. Equip + Sync + Persist ueber den echten Event-Pfad
    // ------------------------------------------------------------------

    /** Alle drei Teile ruesten ueber interactOn aus; Sync-Strings und NBT-Reload stimmen. */
    @GameTest(template = ARENA)
    public static void explorer_pieces_equip_via_event_and_persist(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(GameType.SURVIVAL);
        GoobyEntity gooby = spawnTamedAdult(helper, owner);

        interactHolding(owner, gooby, new ItemStack(ModItems.FLOWER_CROWN.get()));
        interactHolding(owner, gooby, new ItemStack(ModItems.ADVENTURE_BANDANA.get()));
        interactHolding(owner, gooby, new ItemStack(ModItems.PICNIC_BACKPACK.get()));

        helper.assertTrue(gooby.getHatStack().is(ModItems.FLOWER_CROWN.get()),
                "Blumenkranz landete nicht im Head-Slot (Tag-Pfad kaputt?)");
        helper.assertTrue(gooby.getNeckStack().is(ModItems.ADVENTURE_BANDANA.get()),
                "Halstuch landete nicht im Neck-Slot (Event-Pfad kaputt?)");
        helper.assertTrue(gooby.getBackStack().is(ModItems.PICNIC_BACKPACK.get()),
                "Rucksack landete nicht im Back-Slot (Event-Pfad kaputt?)");
        helper.assertTrue(owner.getMainHandItem().isEmpty(),
                "Survival-Ausruesten verbrauchte das Item nicht aus der Hand");

        // Wire-Sync: exakt die kompakte Registry-Id (Renderer-Vertrag).
        helper.assertTrue("goobymod:flower_crown".equals(gooby.getHatItemId()),
                "Head-Sync-String falsch: '" + gooby.getHatItemId() + "'");
        helper.assertTrue("goobymod:adventure_bandana".equals(gooby.getNeckAccessoryData()),
                "Neck-Sync-String falsch: '" + gooby.getNeckAccessoryData() + "'");
        helper.assertTrue("goobymod:picnic_backpack".equals(gooby.getBackAccessoryData()),
                "Back-Sync-String falsch: '" + gooby.getBackAccessoryData() + "'");

        CompoundTag saved = new CompoundTag();
        gooby.saveWithoutId(saved);
        saved.remove("UUID");
        GoobyEntity reloaded = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 3));
        reloaded.load(saved);
        helper.assertTrue(reloaded.getHatStack().is(ModItems.FLOWER_CROWN.get())
                        && reloaded.getNeckStack().is(ModItems.ADVENTURE_BANDANA.get())
                        && reloaded.getBackStack().is(ModItems.PICNIC_BACKPACK.get()),
                "Mindestens ein Explorer-Teil ging im NBT-Roundtrip verloren");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Baby, wilder und fremder Gooby lehnen Halstuch/Rucksack ab — Item bleibt beim Spieler. */
    @GameTest(template = ARENA)
    public static void explorer_equip_policy_gates(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(GameType.SURVIVAL);

        GoobyEntity wild = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(1, 2, 3));
        interactHolding(owner, wild, new ItemStack(ModItems.ADVENTURE_BANDANA.get()));
        helper.assertTrue(wild.getNeckStack().isEmpty(), "Wilder Gooby nahm das Halstuch an");
        helper.assertTrue(owner.getMainHandItem().is(ModItems.ADVENTURE_BANDANA.get()),
                "Abgelehntes Halstuch wurde trotzdem verbraucht");

        GoobyEntity baby = spawnTamedAdult(helper, owner);
        baby.setBaby(true);
        interactHolding(owner, baby, new ItemStack(ModItems.PICNIC_BACKPACK.get()));
        helper.assertTrue(baby.getBackStack().isEmpty(), "Baby-Gooby nahm den Rucksack an");
        helper.assertTrue(owner.getMainHandItem().is(ModItems.PICNIC_BACKPACK.get()),
                "Abgelehnter Rucksack wurde trotzdem verbraucht");

        GoobyEntity owned = spawnTamedAdult(helper, owner);
        FakePlayer stranger = fakePlayer(helper, "explorer_stranger");
        stranger.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(ModItems.ADVENTURE_BANDANA.get()));
        stranger.interactOn(owned, InteractionHand.MAIN_HAND);
        helper.assertTrue(owned.getNeckStack().isEmpty(), "Fremder ruestete das Halstuch aus");
        helper.assertTrue(stranger.getMainHandItem().is(ModItems.ADVENTURE_BANDANA.get()),
                "Fremden-Halstuch wurde trotzdem verbraucht");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 2. Volle ItemStack-Treue + Swap-Drop
    // ------------------------------------------------------------------

    /** Name + Verzauberung + Farbe ueberleben Equip, NBT-Reload und den Swap-Drop. */
    @GameTest(template = ARENA)
    public static void explorer_full_component_fidelity_and_swap_drop(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(GameType.SURVIVAL);
        GoobyEntity gooby = spawnTamedAdult(helper, owner);

        ItemStack heirloom = new ItemStack(ModItems.ADVENTURE_BANDANA.get());
        heirloom.set(DataComponents.CUSTOM_NAME, Component.literal("Fernwehtuch"));
        heirloom.set(DataComponents.DYED_COLOR, new DyedItemColor(0x2F6AC7, true));
        heirloom.enchant(helper.getLevel().registryAccess()
                .registryOrThrow(Registries.ENCHANTMENT).getHolderOrThrow(Enchantments.UNBREAKING), 2);
        ItemStack expected = heirloom.copyWithCount(1);
        interactHolding(owner, gooby, heirloom);
        helper.assertTrue(ItemStack.matches(expected, gooby.getNeckStack()),
                "Neck-Slot verlor Custom-Components direkt nach dem Event-Equip");

        CompoundTag saved = new CompoundTag();
        gooby.saveWithoutId(saved);
        saved.remove("UUID");
        GoobyEntity reloaded = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 3));
        reloaded.load(saved);
        helper.assertTrue(ItemStack.matches(expected, reloaded.getNeckStack()),
                "Halstuch verlor Name/Verzauberung/Farbe im NBT-Roundtrip");

        // Swap: das plain Ersatztuch verdraengt das Erbstueck — voller Stack faellt.
        interactHolding(owner, gooby, new ItemStack(ModItems.ADVENTURE_BANDANA.get()));
        List<ItemEntity> drops = helper.getLevel().getEntitiesOfClass(ItemEntity.class,
                gooby.getBoundingBox().inflate(4.0),
                item -> item.getItem().is(ModItems.ADVENTURE_BANDANA.get()));
        helper.assertTrue(drops.size() == 1,
                "Swap gab nicht exakt ein Halstuch zurueck: " + drops.size());
        helper.assertTrue(ItemStack.matches(expected, drops.get(0).getItem()),
                "Verdraengtes Halstuch verlor Custom Name oder Verzauberung");
        helper.assertTrue(gooby.getNeckStack().is(ModItems.ADVENTURE_BANDANA.get())
                        && gooby.getNeckStack().get(DataComponents.CUSTOM_NAME) == null,
                "Ersatztuch sitzt nicht als frischer Stack im Slot");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 3. Faerben: Crafting-Tag-Pfad UND direkt am getragenen Tuch
    // ------------------------------------------------------------------

    /** minecraft:dyeable traegt das Tuch im Crafting; Owner faerbt live, Fremde nicht. */
    @GameTest(template = ARENA)
    public static void bandana_dyes_in_crafting_and_while_worn(GameTestHelper helper) {
        placeFloor(helper);
        CraftingInput dyeInput = CraftingInput.of(2, 1, List.of(
                new ItemStack(ModItems.ADVENTURE_BANDANA.get()), new ItemStack(Items.RED_DYE)));
        var dyeRecipe = helper.getLevel().getRecipeManager()
                .getRecipeFor(RecipeType.CRAFTING, dyeInput, helper.getLevel());
        helper.assertTrue(dyeRecipe.isPresent(),
                "Vanilla-Faerberezept erkennt das Halstuch nicht (dyeable-Tag fehlt?)");
        ItemStack crafted = dyeRecipe.get().value().assemble(dyeInput, helper.getLevel().registryAccess());
        helper.assertTrue(crafted.is(ModItems.ADVENTURE_BANDANA.get())
                        && GoobyWardrobe.color(crafted) == DyeColor.RED.getTextureDiffuseColor(),
                "Crafting-Faerben lieferte falsches Item oder falsche Farbe");

        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(GameType.SURVIVAL);
        GoobyEntity gooby = spawnTamedAdult(helper, owner);
        interactHolding(owner, gooby, new ItemStack(ModItems.ADVENTURE_BANDANA.get()));

        // Fremde duerfen das getragene Tuch nicht umfaerben.
        FakePlayer stranger = fakePlayer(helper, "bandana_stranger");
        stranger.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(Items.LIME_DYE));
        stranger.interactOn(gooby, InteractionHand.MAIN_HAND);
        helper.assertTrue(gooby.getNeckStack().get(DataComponents.DYED_COLOR) == null,
                "Fremder faerbte das getragene Halstuch um");

        interactHolding(owner, gooby, new ItemStack(Items.LIME_DYE));
        int expected = DyeColor.LIME.getTextureDiffuseColor() & 0xFFFFFF;
        helper.assertTrue((GoobyWardrobe.color(gooby.getNeckStack()) & 0xFFFFFF) == expected,
                "Live-Faerben setzte die Farbe nicht: "
                        + Integer.toHexString(GoobyWardrobe.color(gooby.getNeckStack())));
        helper.assertTrue(owner.getMainHandItem().isEmpty(),
                "Live-Faerben verbrauchte den Farbstoff nicht");

        // Farbe uebersteht den Reload (Wire-String + volles NBT).
        CompoundTag saved = new CompoundTag();
        gooby.saveWithoutId(saved);
        saved.remove("UUID");
        GoobyEntity reloaded = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 3));
        reloaded.load(saved);
        helper.assertTrue((GoobyWardrobe.color(reloaded.getNeckStack()) & 0xFFFFFF) == expected,
                "Gefaerbtes Halstuch verlor sein RGB im NBT");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 4. Slot-Isolation + Satchel-Rueckgabe beim Rucksack-Tausch
    // ------------------------------------------------------------------

    /** Rucksack verdraengt die Tasche: Inhalt + Tasche fallen, andere Slots bleiben unberuehrt. */
    @GameTest(template = ARENA)
    public static void backpack_swap_returns_satchel_and_keeps_other_slots(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(GameType.SURVIVAL);
        GoobyEntity gooby = spawnTamedAdult(helper, owner);

        interactHolding(owner, gooby, new ItemStack(Items.POPPY));
        interactHolding(owner, gooby, new ItemStack(ModItems.GOOBY_BOWTIE.get()));
        interactHolding(owner, gooby, new ItemStack(ModItems.TINY_SATCHEL.get()));
        gooby.satchelInventory().setItem(0, new ItemStack(Items.CARROT, 5));

        interactHolding(owner, gooby, new ItemStack(ModItems.PICNIC_BACKPACK.get()));

        helper.assertTrue(gooby.getBackStack().is(ModItems.PICNIC_BACKPACK.get()),
                "Rucksack ersetzte die Tasche nicht");
        helper.assertTrue(gooby.satchelInventory().isEmpty(),
                "Tascheninventar wurde beim Tausch nicht geleert");
        // Slot-Isolation: HEAD und NECK ueberleben den BACK-Tausch unveraendert.
        helper.assertTrue(gooby.getHatStack().is(Items.POPPY),
                "BACK-Tausch veraenderte den Head-Slot");
        helper.assertTrue(gooby.getNeckStack().is(ModItems.GOOBY_BOWTIE.get()),
                "BACK-Tausch veraenderte den Neck-Slot");

        List<ItemEntity> satchels = helper.getLevel().getEntitiesOfClass(ItemEntity.class,
                gooby.getBoundingBox().inflate(4.0),
                item -> item.getItem().is(ModItems.TINY_SATCHEL.get()));
        helper.assertTrue(satchels.size() == 1,
                "Alte Tasche fiel nicht genau einmal: " + satchels.size());
        int carrots = helper.getLevel().getEntitiesOfClass(ItemEntity.class,
                        gooby.getBoundingBox().inflate(4.0),
                        item -> item.getItem().is(Items.CARROT)).stream()
                .mapToInt(item -> item.getItem().getCount()).sum();
        helper.assertTrue(carrots == 5,
                "Tascheninhalt kam nicht vollstaendig zurueck: " + carrots + "/5 Karotten");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 5. Advancement: beide Reihenfolgen (Kranz zuletzt = deferred Pfad)
    // ------------------------------------------------------------------

    /** Kranz als LETZTES Teil: die End-of-Tick-Nachpruefung vergibt das Set-Advancement. */
    @GameTest(template = ARENA, timeoutTicks = 200)
    public static void explorer_advancement_completes_with_crown_last(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(GameType.SURVIVAL);
        GoobyEntity gooby = spawnTamedAdult(helper, owner);

        interactHolding(owner, gooby, new ItemStack(ModItems.ADVENTURE_BANDANA.get()));
        interactHolding(owner, gooby, new ItemStack(ModItems.PICNIC_BACKPACK.get()));
        helper.assertFalse(advancementDone(helper, owner, GoobyAdvancements.EXPLORER_OUTFIT),
                "Set-Advancement kam schon mit zwei von drei Teilen");
        interactHolding(owner, gooby, new ItemStack(ModItems.FLOWER_CROWN.get()));

        // Der Kranz laeuft ueber mobInteract; die Set-Pruefung haengt als
        // TickTask in der Task-Queue und muss erst drainen (max. +4 Ticks).
        helper.runAfterDelay(10, () -> {
            helper.assertTrue(ExplorerOutfitEvents.isExplorerOutfitComplete(gooby),
                    "Explorer-Set ist nicht komplett angelegt");
            helper.assertTrue(advancementDone(helper, owner, GoobyAdvancements.EXPLORER_OUTFIT),
                    "explorer_outfit fehlt nach Kranz-zuletzt (deferred Check kaputt)");
            helper.assertTrue(advancementDone(helper, owner, GoobyAdvancements.FULL_OUTFIT),
                    "full_outfit fehlt trotz drei belegter Slots");
            TestPlayers.remove(helper, owner);
            helper.succeed();
        });
    }

    /** Halstuch als letztes Teil: der Event-Pfad vergibt sofort, ohne Umweg. */
    @GameTest(template = ARENA)
    public static void explorer_advancement_completes_with_bandana_last(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(GameType.SURVIVAL);
        GoobyEntity gooby = spawnTamedAdult(helper, owner);

        interactHolding(owner, gooby, new ItemStack(ModItems.FLOWER_CROWN.get()));
        interactHolding(owner, gooby, new ItemStack(ModItems.PICNIC_BACKPACK.get()));
        interactHolding(owner, gooby, new ItemStack(ModItems.ADVENTURE_BANDANA.get()));

        helper.assertTrue(advancementDone(helper, owner, GoobyAdvancements.EXPLORER_OUTFIT),
                "explorer_outfit fehlt direkt nach dem dritten Teil (Event-Pfad)");
        helper.assertTrue(advancementDone(helper, owner, GoobyAdvancements.FULL_OUTFIT),
                "full_outfit fehlt trotz komplettem Outfit");

        // Gemischtes Outfit (Schal statt Halstuch) darf NICHT als Explorer-Set zaehlen.
        GoobyEntity mixed = spawnTamedAdult(helper, owner);
        interactHolding(owner, mixed, new ItemStack(ModItems.FLOWER_CROWN.get()));
        interactHolding(owner, mixed, new ItemStack(ModItems.GOOBY_SCARF.get()));
        interactHolding(owner, mixed, new ItemStack(ModItems.PICNIC_BACKPACK.get()));
        helper.assertFalse(ExplorerOutfitEvents.isExplorerOutfitComplete(mixed),
                "Schal-Outfit zaehlte faelschlich als Explorer-Set");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 6. Rezepte + Unlock-Advancements
    // ------------------------------------------------------------------

    /** Alle drei Rezepte matchen mit den dokumentierten Zutaten und liefern je 1 Teil. */
    @GameTest(template = ARENA)
    public static void explorer_recipes_craft_and_unlock(GameTestHelper helper) {
        // Blumenkranz: FFF / SGS (kleine Blumen, Faden, Gooby-Fussel).
        CraftingInput crown = CraftingInput.of(3, 2, List.of(
                new ItemStack(Items.DANDELION), new ItemStack(Items.POPPY), new ItemStack(Items.CORNFLOWER),
                new ItemStack(Items.STRING), new ItemStack(ModItems.GOOBY_FLUFF.get()), new ItemStack(Items.STRING)));
        var crownRecipe = helper.getLevel().getRecipeManager()
                .getRecipeFor(RecipeType.CRAFTING, crown, helper.getLevel());
        helper.assertTrue(crownRecipe.isPresent(), "Blumenkranz-Rezept matcht nicht (FFF/SGS)");
        helper.assertTrue(crownRecipe.get().value().assemble(crown, helper.getLevel().registryAccess())
                        .is(ModItems.FLOWER_CROWN.get()),
                "Blumenkranz-Rezept liefert falsches Ergebnis");

        // Halstuch: WSW / _G_ (Wolle, Faden, Gooby-Fussel).
        CraftingInput bandana = CraftingInput.of(3, 2, List.of(
                new ItemStack(Items.WHITE_WOOL), new ItemStack(Items.STRING), new ItemStack(Items.LIME_WOOL),
                ItemStack.EMPTY, new ItemStack(ModItems.GOOBY_FLUFF.get()), ItemStack.EMPTY));
        var bandanaRecipe = helper.getLevel().getRecipeManager()
                .getRecipeFor(RecipeType.CRAFTING, bandana, helper.getLevel());
        helper.assertTrue(bandanaRecipe.isPresent(), "Halstuch-Rezept matcht nicht (WSW/_G_)");
        helper.assertTrue(bandanaRecipe.get().value().assemble(bandana, helper.getLevel().registryAccess())
                        .is(ModItems.ADVENTURE_BANDANA.get()),
                "Halstuch-Rezept liefert falsches Ergebnis");

        // Rucksack: SLS / LWL / LBL (Faden, Leder, Gooby-Wolle, Knopfauge).
        CraftingInput backpack = CraftingInput.of(3, 3, List.of(
                new ItemStack(Items.STRING), new ItemStack(Items.LEATHER), new ItemStack(Items.STRING),
                new ItemStack(Items.LEATHER), new ItemStack(ModItems.GOOBY_WOOL.get()), new ItemStack(Items.LEATHER),
                new ItemStack(Items.LEATHER), new ItemStack(ModItems.BUTTON_EYE.get()), new ItemStack(Items.LEATHER)));
        var backpackRecipe = helper.getLevel().getRecipeManager()
                .getRecipeFor(RecipeType.CRAFTING, backpack, helper.getLevel());
        helper.assertTrue(backpackRecipe.isPresent(), "Rucksack-Rezept matcht nicht (SLS/LWL/LBL)");
        helper.assertTrue(backpackRecipe.get().value().assemble(backpack, helper.getLevel().registryAccess())
                        .is(ModItems.PICNIC_BACKPACK.get()),
                "Rucksack-Rezept liefert falsches Ergebnis");

        // Unlock-Advancements sind registriert und belohnen das jeweilige Rezept.
        var advancements = helper.getLevel().getServer().getAdvancements();
        for (String id : List.of("flower_crown", "adventure_bandana", "picnic_backpack")) {
            AdvancementHolder unlock = advancements.get(
                    ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "recipes/" + id));
            helper.assertTrue(unlock != null, "Recipe-Unlock-Advancement fehlt: recipes/" + id);
            helper.assertTrue(unlock.value().rewards().recipes().stream().anyMatch(
                            recipe -> recipe.equals(ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, id))),
                    "Unlock-Advancement belohnt nicht das Rezept: " + id);
        }
        // Set-Advancement haengt unter full_outfit (Datenvertrag).
        JsonObject setJson = loadAssetJson(helper, "data/goobymod/advancement/explorer_outfit.json");
        helper.assertTrue("goobymod:full_outfit".equals(setJson.get("parent").getAsString()),
                "explorer_outfit haengt nicht unter full_outfit");
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 7. Loot: selten, aber real erhaeltlich (echte Tabellen-Rolls)
    // ------------------------------------------------------------------

    /** Kranz (Picknick) und Rucksack (Schatzversteck) fallen selten, aber nachweisbar. */
    @GameTest(template = ARENA)
    public static void explorer_loot_rare_but_obtainable(GameTestHelper helper) {
        LootParams params = new LootParams.Builder(helper.getLevel())
                .withParameter(LootContextParams.ORIGIN, helper.absoluteVec(new Vec3(2.0, 2.0, 2.0)))
                .create(LootContextParamSets.CHEST);

        LootTable picnic = lootTable(helper, "chests/gooby_picnic");
        LootTable cache = lootTable(helper, "chests/gooby_treasure_cache");
        helper.assertTrue(picnic != LootTable.EMPTY && cache != LootTable.EMPTY,
                "Mindestens eine Explorer-Loot-Table wurde nicht geladen");

        int crownChests = 0;
        int backpackChests = 0;
        final int samples = 240;
        // Sequenzielle Seeds sind fuer LegacyRandomSource stark korreliert
        // (erste Ziehung wandert nur durch ~2% des Wertebereichs) — deshalb
        // deterministisch entzerrte Seeds aus einer eigenen Quelle ziehen.
        RandomSource seeds = RandomSource.create(5406L);
        for (int sample = 0; sample < samples; sample++) {
            long seed = seeds.nextLong();
            if (seed == 0L) {
                seed = 1L; // Seed 0 wuerde auf den Level-Zufall zurueckfallen.
            }
            if (picnic.getRandomItems(params, seed).stream()
                    .anyMatch(stack -> stack.is(ModItems.FLOWER_CROWN.get()))) {
                crownChests++;
            }
            if (cache.getRandomItems(params, seed).stream()
                    .anyMatch(stack -> stack.is(ModItems.PICNIC_BACKPACK.get()))) {
                backpackChests++;
            }
        }
        // Erwartung Kranz: 0.5 Rolls * Gewicht 1/4 = 12.5% — selten, nicht ausgestorben.
        helper.assertTrue(crownChests >= 1,
                "Blumenkranz fiel in " + samples + " Picknick-Truhen nie");
        helper.assertTrue(crownChests <= samples * 3 / 10,
                "Blumenkranz ueberflutet den Picknick-Loot: " + crownChests + "/" + samples);
        // Erwartung Rucksack: 1 Roll * Gewicht 1/8 = 12.5%.
        helper.assertTrue(backpackChests >= 1,
                "Rucksack fiel in " + samples + " Schatzverstecken nie");
        helper.assertTrue(backpackChests <= samples * 3 / 10,
                "Rucksack ueberflutet den Schatz-Loot: " + backpackChests + "/" + samples);
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 8. Asset-Vertrag: 3D-Modelle, Texturen, Lang, Creative-Tab
    // ------------------------------------------------------------------

    /** Handmodellierte Multi-Element-Modelle mit GUI/Hand/Head-Displays + Texturen + Lang. */
    @GameTest(template = ARENA)
    public static void explorer_assets_and_lang_complete(GameTestHelper helper) {
        for (String id : List.of("flower_crown", "adventure_bandana", "picnic_backpack")) {
            JsonObject model = loadAssetJson(helper, "assets/goobymod/models/item/" + id + ".json");
            JsonArray elements = model.getAsJsonArray("elements");
            helper.assertTrue(elements != null && elements.size() >= 5,
                    id + ": echtes 3D-Modell braucht mehrere Elemente, hat "
                            + (elements == null ? 0 : elements.size()));
            JsonObject display = model.getAsJsonObject("display");
            helper.assertTrue(display != null, id + ": display-Block fehlt");
            for (String context : List.of("gui", "head", "thirdperson_righthand", "firstperson_righthand")) {
                helper.assertTrue(display.has(context), id + ": Display fehlt fuer " + context);
            }
            String textureRef = model.getAsJsonObject("textures").entrySet().iterator().next()
                    .getValue().getAsString();
            helper.assertTrue(textureRef.startsWith("goobymod:item/"),
                    id + ": Modell referenziert fremde Textur: " + textureRef);
            helper.assertTrue(GoobyExplorerOutfitTests.class.getClassLoader().getResource(
                            "assets/goobymod/textures/item/" + id + ".png") != null,
                    id + ": Itemtextur fehlt im Classpath");
        }

        JsonObject english = loadAssetJson(helper, "assets/goobymod/lang/en_us.json");
        JsonObject german = loadAssetJson(helper, "assets/goobymod/lang/de_de.json");
        for (String key : List.of(
                "item.goobymod.flower_crown", "item.goobymod.adventure_bandana",
                "item.goobymod.picnic_backpack",
                "tooltip.goobymod.flower_crown", "tooltip.goobymod.adventure_bandana",
                "tooltip.goobymod.picnic_backpack",
                "msg.goobymod.bandana_dyed",
                "advancements.goobymod.explorer_outfit.title",
                "advancements.goobymod.explorer_outfit.description")) {
            helper.assertTrue(english.has(key), "EN-Lang-Key fehlt: " + key);
            helper.assertTrue(german.has(key), "DE-Lang-Key fehlt: " + key);
        }

        CreativeModeTab tab = ModCreativeTabs.GOOBY_TAB.get();
        tab.buildContents(new CreativeModeTab.ItemDisplayParameters(
                FeatureFlags.REGISTRY.allFlags(), true, helper.getLevel().registryAccess()));
        for (var item : List.of(ModItems.FLOWER_CROWN.get(), ModItems.ADVENTURE_BANDANA.get(),
                ModItems.PICNIC_BACKPACK.get())) {
            helper.assertTrue(tab.getDisplayItems().stream().anyMatch(stack -> stack.is(item)),
                    "Creative-Tab zeigt Item nicht: " + item.getDescriptionId());
        }
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 9. Direkter Entity-Pfad: Zweithand-Paritaet, Slot-Validierung,
    //    keine Reload-Seiteneffekte
    // ------------------------------------------------------------------

    /** Leere Haupthand reicht an Halstuch/Rucksack/Farbstoff in der ZWEITHAND durch (isCareItem). */
    @GameTest(template = ARENA)
    public static void explorer_offhand_parity_equips_and_dyes(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(GameType.SURVIVAL);
        GoobyEntity gooby = spawnTamedAdult(helper, owner);

        // Halstuch in der Offhand: die leere Haupthand muss PASSen, statt die
        // Interaktion mit Streicheln zu verschlucken — erst dann erreicht der
        // Client die Zweithand ueberhaupt.
        owner.setItemInHand(InteractionHand.MAIN_HAND, ItemStack.EMPTY);
        owner.setItemInHand(InteractionHand.OFF_HAND, new ItemStack(ModItems.ADVENTURE_BANDANA.get()));
        InteractionResult mainResult = owner.interactOn(gooby, InteractionHand.MAIN_HAND);
        helper.assertTrue(mainResult == InteractionResult.PASS,
                "Leere Haupthand verschluckte das Offhand-Halstuch (war: " + mainResult + ")");
        owner.interactOn(gooby, InteractionHand.OFF_HAND);
        helper.assertTrue(gooby.getNeckStack().is(ModItems.ADVENTURE_BANDANA.get()),
                "Halstuch aus der Zweithand wurde nicht angelegt");
        helper.assertTrue(owner.getOffhandItem().isEmpty(),
                "Offhand-Equip verbrauchte das Halstuch nicht");

        // Rucksack in der Offhand.
        owner.setItemInHand(InteractionHand.OFF_HAND, new ItemStack(ModItems.PICNIC_BACKPACK.get()));
        helper.assertTrue(owner.interactOn(gooby, InteractionHand.MAIN_HAND) == InteractionResult.PASS,
                "Leere Haupthand verschluckte den Offhand-Rucksack");
        owner.interactOn(gooby, InteractionHand.OFF_HAND);
        helper.assertTrue(gooby.getBackStack().is(ModItems.PICNIC_BACKPACK.get()),
                "Rucksack aus der Zweithand wurde nicht angelegt");

        // Farbstoff in der Offhand faerbt das getragene Halstuch.
        owner.setItemInHand(InteractionHand.OFF_HAND, new ItemStack(Items.PURPLE_DYE));
        helper.assertTrue(owner.interactOn(gooby, InteractionHand.MAIN_HAND) == InteractionResult.PASS,
                "Leere Haupthand verschluckte den Offhand-Farbstoff");
        owner.interactOn(gooby, InteractionHand.OFF_HAND);
        int expected = DyeColor.PURPLE.getTextureDiffuseColor() & 0xFFFFFF;
        helper.assertTrue((GoobyWardrobe.color(gooby.getNeckStack()) & 0xFFFFFF) == expected,
                "Offhand-Farbstoff faerbte das Halstuch nicht: "
                        + Integer.toHexString(GoobyWardrobe.color(gooby.getNeckStack())));
        helper.assertTrue(owner.getOffhandItem().isEmpty(),
                "Offhand-Faerben verbrauchte den Farbstoff nicht");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Direkte Entity-API: Slot↔Item-Mismatch und Fremd-Zugriff fail-closed, ohne Konsum. */
    @GameTest(template = ARENA)
    public static void explorer_direct_api_validates_slot_and_owner(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(GameType.SURVIVAL);
        GoobyEntity gooby = spawnTamedAdult(helper, owner);

        ItemStack bandana = new ItemStack(ModItems.ADVENTURE_BANDANA.get());
        helper.assertFalse(gooby.tryEquipAccessory(owner, bandana, GoobyWardrobe.Slot.HEAD),
                "Halstuch durfte nicht in den HEAD-Slot");
        helper.assertFalse(gooby.tryEquipAccessory(owner, new ItemStack(ModItems.PICNIC_BACKPACK.get()),
                GoobyWardrobe.Slot.NECK), "Rucksack durfte nicht in den NECK-Slot");
        helper.assertFalse(gooby.tryEquipAccessory(owner, new ItemStack(ModItems.FLOWER_CROWN.get()),
                GoobyWardrobe.Slot.BACK), "Kranz durfte nicht in den BACK-Slot");
        helper.assertTrue(gooby.getHatStack().isEmpty() && gooby.getNeckStack().isEmpty()
                        && gooby.getBackStack().isEmpty(),
                "Slot-Mismatch veraenderte die Garderobe");
        helper.assertTrue(bandana.getCount() == 1, "Slot-Mismatch konsumierte das Item");

        FakePlayer stranger = fakePlayer(helper, "direct_api_stranger");
        helper.assertFalse(gooby.tryEquipAccessory(stranger, bandana, GoobyWardrobe.Slot.NECK),
                "Fremder ruestete ueber die direkte API aus");
        helper.assertTrue(bandana.getCount() == 1, "Abgelehnter Fremd-Equip konsumierte das Item");

        helper.assertTrue(gooby.tryEquipAccessory(owner, bandana, GoobyWardrobe.Slot.NECK),
                "Passender Slot wurde faelschlich abgelehnt");
        helper.assertTrue(gooby.getNeckStack().is(ModItems.ADVENTURE_BANDANA.get()),
                "Direkte API legte das Halstuch nicht an");
        helper.assertTrue(bandana.isEmpty(), "Direkte API verbrauchte das Item nicht");

        // Dye-API fail-closed, wenn nichts Faerbbares getragen wird.
        GoobyEntity bare = spawnTamedAdult(helper, owner);
        helper.assertFalse(bare.tryDyeNeckAccessory(owner, new ItemStack(Items.RED_DYE),
                (DyeItem) Items.RED_DYE), "Dye-API faerbte ohne getragenes Hals-Accessoire");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Kein Entity-Reload mehr beim Equip: Health, Navigation, Ball und UUID bleiben unberuehrt. */
    @GameTest(template = ARENA)
    public static void explorer_equip_keeps_health_navigation_and_carry_state(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(GameType.SURVIVAL);
        GoobyEntity gooby = spawnTamedAdult(helper, owner);

        float halfHealth = gooby.getMaxHealth() / 2.0F;
        gooby.setHealth(halfHealth);
        ItemStack carried = new ItemStack(ModItems.GOOBY_BALL.get());
        carried.set(DataComponents.CUSTOM_NAME, Component.literal("Lieblingsball"));
        gooby.setCarriedFetchItem(carried.copy());
        UUID uuid = gooby.getUUID();
        // Frisch gespawnte Entities haben noch keinen Bodenkontakt —
        // GroundPathNavigation#canUpdatePath wuerde die Pfadsuche ablehnen.
        gooby.setOnGround(true);
        Vec3 target = helper.absoluteVec(new Vec3(4.5, 2.0, 4.5));
        helper.assertTrue(gooby.getNavigation().moveTo(target.x, target.y, target.z, 1.0),
                "Navigation startete nicht — Testaufbau kaputt");
        helper.assertFalse(gooby.getNavigation().isDone(), "Navigationspfad fehlt vor dem Equip");

        interactHolding(owner, gooby, new ItemStack(ModItems.ADVENTURE_BANDANA.get()));

        helper.assertTrue(gooby.getNeckStack().is(ModItems.ADVENTURE_BANDANA.get()),
                "Equip schlug im Seiteneffekt-Test fehl");
        helper.assertTrue(Math.abs(gooby.getHealth() - halfHealth) < 1.0E-4F,
                "Equip veraenderte die Health: " + gooby.getHealth());
        helper.assertFalse(gooby.getNavigation().isDone(), "Equip stoppte die laufende Navigation");
        helper.assertTrue(ItemStack.matches(carried, gooby.getCarriedFetchItem()),
                "Equip veraenderte den getragenen Apportier-Ball");
        helper.assertTrue(uuid.equals(gooby.getUUID()), "Equip aenderte die Entity-UUID");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }
}
