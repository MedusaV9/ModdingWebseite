package de.sonic0810.goobymod.gametest;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.mojang.authlib.GameProfile;
import de.sonic0810.goobymod.GoobyAdvancements;
import de.sonic0810.goobymod.GoobyClientConfig;
import de.sonic0810.goobymod.GoobyConfig;
import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.api.GoobyAccessor;
import de.sonic0810.goobymod.api.GoobyApi;
import de.sonic0810.goobymod.api.event.GoobyGiftEvent;
import de.sonic0810.goobymod.api.event.GoobyTameEvent;
import de.sonic0810.goobymod.api.event.GoobyTierChangeEvent;
import de.sonic0810.goobymod.block.NutellaCakeBlock;
import de.sonic0810.goobymod.block.NutellaJarBlock;
import de.sonic0810.goobymod.block.RabbitHutchBlock;
import de.sonic0810.goobymod.block.entity.NutellaJarBlockEntity;
import de.sonic0810.goobymod.block.entity.RabbitHutchBlockEntity;
import de.sonic0810.goobymod.compat.CreateCompat;
import de.sonic0810.goobymod.compat.CuriosCompat;
import de.sonic0810.goobymod.entity.FriendshipMemory;
import de.sonic0810.goobymod.entity.FriendshipTier;
import de.sonic0810.goobymod.entity.GoobyCoatVariant;
import de.sonic0810.goobymod.entity.GoobyCommand;
import de.sonic0810.goobymod.entity.GoobyDayRhythm;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.entity.GoobyMood;
import de.sonic0810.goobymod.entity.GoobySoundLimiter;
import de.sonic0810.goobymod.entity.GoobySoundProfile;
import de.sonic0810.goobymod.entity.GoobySpeech;
import de.sonic0810.goobymod.entity.GoobyTrick;
import de.sonic0810.goobymod.entity.GoobyWardrobe;
import de.sonic0810.goobymod.entity.animation.GoobyAnimationState;
import de.sonic0810.goobymod.entity.goals.CatStareAtGoobyGoal;
import de.sonic0810.goobymod.entity.goals.GoobyAlertGoal;
import de.sonic0810.goobymod.entity.goals.GoobyRandomSitGoal;
import de.sonic0810.goobymod.entity.goals.GoobySleepGoal;
import de.sonic0810.goobymod.entity.goals.GoobyWildPanicGoal;
import de.sonic0810.goobymod.entity.goals.RabbitFollowWildGoobyGoal;
import de.sonic0810.goobymod.event.GoobyEvents;
import de.sonic0810.goobymod.item.GoobyHandbookItem;
import de.sonic0810.goobymod.item.GoobyWhistleItem;
import de.sonic0810.goobymod.registry.ModBlocks;
import de.sonic0810.goobymod.registry.ModEntities;
import de.sonic0810.goobymod.registry.ModItems;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.function.Consumer;
import net.minecraft.advancements.AdvancementHolder;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.component.DataComponents;
import net.minecraft.core.registries.Registries;
import net.minecraft.gametest.framework.AfterBatch;
import net.minecraft.gametest.framework.BeforeBatch;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.locale.Language;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.Tag;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.RandomSource;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.MobSpawnType;
import net.minecraft.world.entity.animal.Cat;
import net.minecraft.world.entity.animal.Pig;
import net.minecraft.world.entity.animal.Rabbit;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.entity.monster.Creeper;
import net.minecraft.world.entity.monster.Zombie;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.item.DyeColor;
import net.minecraft.world.item.component.DyedItemColor;
import net.minecraft.world.item.crafting.CraftingInput;
import net.minecraft.world.item.crafting.RecipeType;
import net.minecraft.world.item.enchantment.Enchantments;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.structure.templatesystem.StructurePlaceSettings;
import net.minecraft.world.level.pathfinder.PathType;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.BlockHitResult;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.common.NeoForge;
import net.neoforged.neoforge.common.util.FakePlayer;
import net.neoforged.neoforge.common.util.FakePlayerFactory;
import net.neoforged.neoforge.event.entity.living.LivingDropsEvent;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

@GameTestHolder(GoobyMod.MODID)
@PrefixGameTestTemplate(false)
public class GoobyGameTests {
    private static final String ARENA = "arena";
    private static final String ARENA_LARGE = "arena_large";
    private static final String NIGHT_BATCH = "goobyNight";
    private static final String RAIN_BATCH = "goobyRain";
    private static final String WHISTLE_BATCH = "goobyWhistle";

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

    private static void placeLargeFloor(GameTestHelper helper, net.minecraft.world.level.block.Block block) {
        for (int x = 0; x < 17; x++) {
            for (int z = 0; z < 17; z++) {
                helper.setBlock(new BlockPos(x, 1, z), block);
            }
        }
    }

    private static JsonObject loadAssetJson(GameTestHelper helper, String path) {
        try (InputStream stream = GoobyGameTests.class.getClassLoader().getResourceAsStream(path)) {
            helper.assertTrue(stream != null, "Asset fehlt im Runtime-Classpath: " + path);
            return JsonParser.parseReader(new InputStreamReader(stream, StandardCharsets.UTF_8)).getAsJsonObject();
        } catch (IOException | RuntimeException exception) {
            helper.fail("Asset kann nicht gelesen werden: " + path + " (" + exception.getMessage() + ")");
            return new JsonObject();
        }
    }

    @BeforeBatch(batch = NIGHT_BATCH)
    public static void beforeNightBatch(ServerLevel level) {
        level.setDayTime(18000);
    }

    @AfterBatch(batch = NIGHT_BATCH)
    public static void afterNightBatch(ServerLevel level) {
        level.setDayTime(6000);
    }

    @BeforeBatch(batch = RAIN_BATCH)
    public static void beforeRainBatch(ServerLevel level) {
        level.setWeatherParameters(0, 6000, true, false);
    }

    @AfterBatch(batch = RAIN_BATCH)
    public static void afterRainBatch(ServerLevel level) {
        level.setWeatherParameters(6000, 0, false, false);
    }

    // ------------------------------------------------------------------
    // 1. Rezept
    // ------------------------------------------------------------------

    /** Nutella-Rezept: 3 Kakaobohnen + Milcheimer + Zucker = Nutella-Glas. */
    @GameTest(template = ARENA)
    public static void nutella_recipe(GameTestHelper helper) {
        CraftingInput input = CraftingInput.of(3, 2, List.of(
                new ItemStack(Items.COCOA_BEANS), new ItemStack(Items.COCOA_BEANS), new ItemStack(Items.COCOA_BEANS),
                new ItemStack(Items.MILK_BUCKET), new ItemStack(Items.SUGAR), ItemStack.EMPTY));
        var recipe = helper.getLevel().getRecipeManager().getRecipeFor(RecipeType.CRAFTING, input, helper.getLevel());
        if (recipe.isEmpty()) {
            helper.fail("Nutella-Rezept matcht nicht (3x Kakao + Milch + Zucker)");
            return;
        }
        ItemStack result = recipe.get().value().assemble(input, helper.getLevel().registryAccess());
        helper.assertTrue(result.is(ModItems.NUTELLA.get()),
                "Rezept-Ergebnis ist kein Nutella-Glas: " + result);
        // Der Milcheimer muss als leerer Eimer zurueckbleiben
        var remaining = recipe.get().value().getRemainingItems(input);
        boolean bucketBack = remaining.stream().anyMatch(stack -> stack.is(Items.BUCKET));
        helper.assertTrue(bucketBack, "Milcheimer gibt keinen leeren Eimer zurueck");
        helper.succeed();
    }

    /** Nutella-Toast-Rezept: Brot + Nutella = 2 Toast, das Glas bleibt als leeres Glas zurueck. */
    @GameTest(template = ARENA)
    public static void nutella_toast_recipe_returns_empty_jar(GameTestHelper helper) {
        CraftingInput input = CraftingInput.of(2, 1, List.of(
                new ItemStack(Items.BREAD), new ItemStack(ModItems.NUTELLA.get())));
        var recipe = helper.getLevel().getRecipeManager().getRecipeFor(RecipeType.CRAFTING, input, helper.getLevel());
        if (recipe.isEmpty()) {
            helper.fail("Nutella-Toast-Rezept matcht nicht (Brot + Nutella)");
            return;
        }
        ItemStack result = recipe.get().value().assemble(input, helper.getLevel().registryAccess());
        helper.assertTrue(result.is(ModItems.NUTELLA_TOAST.get()) && result.getCount() == 2,
                "Rezept-Ergebnis ist nicht 2x Nutella-Toast: " + result);
        var remaining = recipe.get().value().getRemainingItems(input);
        long jars = remaining.stream().filter(stack -> stack.is(ModItems.EMPTY_JAR.get())).count();
        helper.assertTrue(jars == 1,
                "Nutella-Glas gibt beim Craften kein leeres Glas zurueck (gefunden: " + jars + ")");
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 2. Konversion + echter Besitz
    // ------------------------------------------------------------------

    /** Wildhase + Nutella → GOOBY-Konversion, GEZAEHMT durch den Fuetterer. */
    @GameTest(template = ARENA)
    public static void rabbit_conversion(GameTestHelper helper) {
        placeFloor(helper);
        Rabbit rabbit = helper.spawn(EntityType.RABBIT, new BlockPos(2, 2, 2));
        FakePlayer player = fakePlayer(helper, "gooby_tester");
        ItemStack nutella = new ItemStack(ModItems.NUTELLA.get());

        GoobyEntity gooby = GoobyEvents.feedNutellaToRabbit(player, rabbit, nutella);

        helper.assertTrue(gooby != null, "Konversion hat keinen Gooby erzeugt");
        helper.assertTrue(nutella.isEmpty(), "Nutella-Glas wurde nicht verbraucht");
        helper.assertTrue(rabbit.isRemoved(), "Wildhase wurde nicht entfernt");
        helper.assertEntityPresent(ModEntities.GOOBY.get());
        helper.assertTrue(gooby.getSatisfaction() >= 60, "Frisch verwandelter Gooby sollte happy sein");
        helper.assertTrue(gooby.isTame(), "Konvertierter Gooby muss gezaehmt sein");
        helper.assertTrue(player.getUUID().equals(gooby.getOwnerUUID()),
                "Besitzer muss der fuetternde Spieler sein");
        helper.assertTrue(gooby.getFriendship(player.getUUID()) == GoobyEntity.CONVERT_FRIENDSHIP,
                "Start-Freundschaft nach Konversion falsch: " + gooby.getFriendship(player.getUUID()));
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 3. Streicheln: Zufriedenheit + Freundschaft (mit Anti-Spam-Cooldown)
    // ------------------------------------------------------------------

    @GameTest(template = ARENA)
    public static void petting_satisfaction_and_friendship(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.setSatisfaction(10);
        FakePlayer player = fakePlayer(helper, "gooby_tester");

        gooby.mobInteract(player, InteractionHand.MAIN_HAND);

        helper.assertTrue(gooby.getSatisfaction() == 10 + GoobyEntity.PET_SATISFACTION,
                "Zufriedenheit stieg nicht um " + GoobyEntity.PET_SATISFACTION + " (ist: "
                        + gooby.getSatisfaction() + ")");
        helper.assertTrue(gooby.getFriendship(player.getUUID()) == GoobyEntity.PET_FRIENDSHIP,
                "Freundschaft stieg nicht um " + GoobyEntity.PET_FRIENDSHIP + " (ist: "
                        + gooby.getFriendship(player.getUUID()) + ")");

        // Sofort nochmal streicheln: Zufriedenheit ja, Freundschaft NEIN (Cooldown gegen Klickspam)
        gooby.mobInteract(player, InteractionHand.MAIN_HAND);
        helper.assertTrue(gooby.getFriendship(player.getUUID()) == GoobyEntity.PET_FRIENDSHIP,
                "Freundschafts-Cooldown greift nicht (ist: " + gooby.getFriendship(player.getUUID()) + ")");
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 4. Sophie-Lines: exakt, case-insensitive, nie fuer Fremde
    // ------------------------------------------------------------------

    @GameTest(template = ARENA)
    public static void sophie_lines(GameTestHelper helper) {
        FakePlayer sophie = fakePlayer(helper, "sophiex456");
        FakePlayer stranger = fakePlayer(helper, "TotallyNotSophie");
        RandomSource random = RandomSource.create(20260808L);

        int sophieHits = 0;
        for (int i = 0; i < 300; i++) {
            if (GoobySpeech.SOPHIE.contains(
                    GoobySpeech.pickIdleLine(sophie, false, false, false, random, true, 0.65F))) {
                sophieHits++;
            }
        }
        helper.assertTrue(sophieHits > 120, "Sophie-Lines zu selten: " + sophieHits + "/300");

        for (int i = 0; i < 300; i++) {
            String key = GoobySpeech.pickIdleLine(stranger, false, false, false, random, true, 0.65F);
            helper.assertFalse(GoobySpeech.SOPHIE.contains(key), "Sophie-Line fuer fremden Spieler: " + key);
        }

        helper.assertTrue(GoobySpeech.isSophie("SoPhIeX456"), "Username-Check muss case-insensitive sein");
        helper.assertFalse(GoobySpeech.isSophie("sophiex4567"), "Aehnliche Namen duerfen nicht matchen");
        helper.assertFalse(GoobySpeech.isSophie("sophiex45"), "Praefix-Namen duerfen nicht matchen");
        helper.assertTrue(GoobySpeech.isSpecialLine("bubble.goobymod.sophie3"),
                "sophie-Keys muessen als Special-Line erkannt werden");
        helper.assertFalse(GoobySpeech.isSpecialLine("bubble.goobymod.idle1"),
                "Normale Keys duerfen keine Special-Lines sein");

        // Die drei exakten Pflicht-Lines (deutsch in BEIDEN Sprachdateien)
        Language lang = Language.getInstance();
        helper.assertTrue("Hey Sophie ich habe gehört Vincent liebt dich stimmt das?"
                .equals(lang.getOrDefault("bubble.goobymod.sophie1")), "sophie1 stimmt nicht exakt");
        helper.assertTrue("Du hast es schön mit Vincent ich bin richtig Goobyneidisch"
                .equals(lang.getOrDefault("bubble.goobymod.sophie2")), "sophie2 stimmt nicht exakt");
        helper.assertTrue("Du Goobycoopter Sophie!"
                .equals(lang.getOrDefault("bubble.goobymod.sophie3")), "sophie3 stimmt nicht exakt");
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 5. Sophie: KEIN Gameplay-Bonus + Killswitch
    // ------------------------------------------------------------------

    @GameTest(template = ARENA)
    public static void sophie_no_gameplay_bonus_and_killswitch(GameTestHelper helper) {
        placeFloor(helper);
        FakePlayer sophie = fakePlayer(helper, "sophiex456");
        FakePlayer stranger = fakePlayer(helper, "TotallyNotSophie");
        RandomSource random = RandomSource.create(20260810L);

        // Identischer Zufriedenheits-Effekt fuer ALLE Spielernamen beim Schlagen
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.setSatisfaction(50);
        gooby.hurt(helper.getLevel().damageSources().playerAttack(sophie), 5.0F);
        int afterSophie = gooby.getSatisfaction();
        gooby.setSatisfaction(50);
        gooby.hurt(helper.getLevel().damageSources().playerAttack(stranger), 5.0F);
        int afterStranger = gooby.getSatisfaction();
        helper.assertTrue(afterSophie == afterStranger,
                "Gameplay-Unterschied nach Spielername: " + afterSophie + " vs " + afterStranger);

        // Killswitch (enableSpecialLines=false): NIE Special-Lines, auch nicht fuer Sophie
        for (int i = 0; i < 300; i++) {
            String idle = GoobySpeech.pickIdleLine(sophie, false, false, false, random, false, 1.0F);
            helper.assertFalse(GoobySpeech.SOPHIE.contains(idle), "Killswitch ignoriert (idle): " + idle);
            String reaction = GoobySpeech.pickReaction(GoobySpeech.PET, sophie, random, false);
            helper.assertFalse(GoobySpeech.SOPHIE.contains(reaction), "Killswitch ignoriert (reaction): " + reaction);
        }
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 6. Unverwundbarkeit gegenueber Spielern
    // ------------------------------------------------------------------

    @GameTest(template = ARENA)
    public static void player_invulnerability(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        FakePlayer attacker = fakePlayer(helper, "gooby_tester");
        float healthBefore = gooby.getHealth();

        boolean hurt = gooby.hurt(helper.getLevel().damageSources().playerAttack(attacker), 100.0F);

        helper.assertFalse(hurt, "hurt() darf bei Spieler-Schaden nicht greifen");
        helper.assertTrue(gooby.getHealth() == healthBefore, "Gooby hat Schaden von einem Spieler genommen!");
        helper.assertFalse(gooby.isRemoved(), "Gooby wurde entfernt");
        helper.assertTrue(gooby.isSad(), "Gooby sollte nach dem Schlag traurig gucken");
        helper.succeed();
    }

    /** Schutzengel: Mob-Schaden setzt Panik, kostet einem gezaehmten Gooby aber kein Leben. */
    @GameTest(template = ARENA)
    public static void mob_damage_protection(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        Zombie zombie = helper.spawn(EntityType.ZOMBIE, new BlockPos(3, 2, 2));
        FakePlayer owner = fakePlayer(helper, "guardian_owner");
        gooby.tame(owner);
        float healthBefore = gooby.getHealth();

        boolean hurt = gooby.hurt(helper.getLevel().damageSources().mobAttack(zombie), 12.0F);

        helper.assertFalse(hurt, "Gezaehmter Gooby darf Mob-Schaden nicht annehmen");
        helper.assertTrue(gooby.getHealth() == healthBefore, "Schutzengel hat Lebenspunkte verloren");
        helper.assertTrue(gooby.isPanicking(), "Abgefangener Mob-Angriff muss Panik setzen");
        helper.assertTrue(gooby.getPanicTicks() == GoobyEntity.GUARDIAN_PANIC_TICKS,
                "Panik-Timer wurde nicht voll gesetzt");
        helper.succeed();
    }

    /** Bei <=30% virtueller Schutz-Ausdauer flieht Gooby sicher zum Besitzer. */
    @GameTest(template = ARENA_LARGE)
    public static void escape_teleport_to_owner(GameTestHelper helper) {
        placeLargeFloor(helper, Blocks.DIRT);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        Zombie zombie = helper.spawn(EntityType.ZOMBIE, new BlockPos(3, 2, 2));
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(14.5, 2.0, 14.5));
        gooby.tame(owner);
        float healthBefore = gooby.getHealth();

        for (int i = 0; i < 3; i++) {
            gooby.hurt(helper.getLevel().damageSources().mobAttack(zombie), 10.0F);
        }

        helper.assertTrue(gooby.distanceToSqr(owner) <= 16.0,
                "Gooby ist bei niedrigem Schutzdruck nicht zum Besitzer geflohen: " + gooby.distanceToSqr(owner));
        helper.assertTrue(gooby.getHealth() == healthBefore, "Flucht darf keine Lebenspunkte kosten");
        helper.assertTrue(gooby.getGuardianPressure() == gooby.getMaxHealth(),
                "Schutz-Ausdauer muss nach erfolgreicher Flucht zurueckgesetzt sein");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Auch unvermeidbare Tode (/kill/void) retten das synchronisierte Hut-Item. */
    @GameTest(template = ARENA)
    public static void hat_drops_on_forced_death(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.setHatItemId("minecraft:poppy");
        AABB area = gooby.getBoundingBox().inflate(4.0);

        gooby.hurt(helper.getLevel().damageSources().genericKill(), Float.MAX_VALUE);

        helper.assertTrue(gooby.isDeadOrDying(), "Generic-kill muss den ungeschuetzten Restpfad erreichen");
        helper.assertFalse(gooby.hasHat(), "Hut-Sync muss nach dem Drop geleert sein");
        helper.assertTrue(!helper.getLevel().getEntitiesOfClass(ItemEntity.class, area,
                        item -> item.getItem().is(Items.POPPY)).isEmpty(),
                "Erzwungener Tod hat den Hut verschluckt");
        helper.succeed();
    }

    /** Spieler-Klickspam darf pro Spieler nur einmal je Cooldown Zufriedenheit abziehen. */
    @GameTest(template = ARENA)
    public static void satisfaction_spam_cooldown(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        FakePlayer attacker = fakePlayer(helper, "click_spammer");
        gooby.setSatisfaction(50);

        for (int i = 0; i < 20; i++) {
            gooby.hurt(helper.getLevel().damageSources().playerAttack(attacker), 1.0F);
        }

        helper.assertTrue(gooby.getSatisfaction() == 47,
                "20 Sofort-Klicks duerfen nur einmal -3 geben, waren: " + gooby.getSatisfaction());
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 7. Gooby-Wolle daempft Fallschaden
    // ------------------------------------------------------------------

    @GameTest(template = ARENA)
    public static void gooby_wool_no_fall_damage(GameTestHelper helper) {
        for (int x = 1; x <= 3; x++) {
            for (int z = 1; z <= 3; z++) {
                helper.setBlock(new BlockPos(x, 1, z), ModBlocks.GOOBY_WOOL.get());
            }
        }
        // KEIN setNoAi: NoAI-Mobs bekommen keine Gravitation und wuerden ewig schweben
        Pig pig = helper.spawn(EntityType.PIG, new Vec3(2.5, 7.0, 2.5));
        float healthBefore = pig.getHealth();

        helper.succeedWhen(() -> {
            helper.assertTrue(pig.onGround(), "Schwein ist noch in der Luft");
            helper.assertTrue(pig.getHealth() >= healthBefore - 0.01F,
                    "Fallschaden trotz Gooby-Wolle: " + pig.getHealth() + " < " + healthBefore);
        });
    }

    // ------------------------------------------------------------------
    // 8. Zaehmung per Nutella (echter Besitz)
    // ------------------------------------------------------------------

    @GameTest(template = ARENA)
    public static void taming_via_nutella(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        FakePlayer player = fakePlayer(helper, "gooby_tester");
        helper.assertFalse(gooby.isTame(), "Frisch gespawnter Gooby muss wild sein");

        ItemStack nutella = new ItemStack(ModItems.NUTELLA.get());
        player.setItemInHand(InteractionHand.MAIN_HAND, nutella);
        gooby.mobInteract(player, InteractionHand.MAIN_HAND);

        helper.assertTrue(gooby.isTame(), "Nutella-Fuettern muss zaehmen");
        helper.assertTrue(player.getUUID().equals(gooby.getOwnerUUID()), "Besitzer-UUID falsch");
        helper.assertTrue(player.getItemInHand(InteractionHand.MAIN_HAND).isEmpty(),
                "Nutella-Glas wurde nicht verbraucht");
        helper.assertTrue(gooby.getFriendship(player.getUUID()) == GoobyEntity.FEED_FRIENDSHIP,
                "Fuettern muss Freundschaft geben (ist: " + gooby.getFriendship(player.getUUID()) + ")");
        helper.assertTrue(gooby.getGiftCharges() == 1,
                "Fuettern muss eine Geschenk-Ladung geben (ist: " + gooby.getGiftCharges() + ")");

        // Reit-Progression: Fremde ohne Freundschaft nein, Freunde ab Schwelle ja
        // (der Besitzer-Pfad braucht einen im Level aufloesbaren Owner und wird
        // in create_compat_degrades mit einem echten ServerPlayer getestet)
        FakePlayer strangerNoFriend = fakePlayer(helper, "some_stranger");
        helper.assertFalse(gooby.canRide(strangerNoFriend), "Fremde ohne Freundschaft duerfen nicht reiten");
        gooby.setFriendship(strangerNoFriend.getUUID(), FriendshipTier.FRIEND.minimum());
        helper.assertTrue(gooby.canRide(strangerNoFriend),
                "FRIEND-Stufe muss Reiten erlauben");
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 9. Pfeife: owner-gebunden, Wander → Follow → Stay
    // ------------------------------------------------------------------

    @GameTest(template = ARENA)
    public static void whistle_owner_binding(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        FakePlayer stranger = fakePlayer(helper, "whistle_thief");
        ItemStack whistle = new ItemStack(ModItems.GOOBY_WHISTLE.get());

        // Wild: Pfeife bewirkt nichts
        stranger.setItemInHand(InteractionHand.MAIN_HAND, whistle.copy());
        gooby.mobInteract(stranger, InteractionHand.MAIN_HAND);
        helper.assertTrue(gooby.getCommandMode() == GoobyCommand.WANDER, "Wilder Gooby nimmt keine Kommandos an");

        gooby.tame(owner);
        gooby.setCommandMode(GoobyCommand.WANDER);

        // Fremder mit Pfeife: kein Kommando-Wechsel
        gooby.mobInteract(stranger, InteractionHand.MAIN_HAND);
        helper.assertTrue(gooby.getCommandMode() == GoobyCommand.WANDER,
                "Fremde duerfen den Kommando-Modus nicht aendern");

        // Besitzer schaltet durch: WANDER → FOLLOW → STAY → WANDER
        owner.setItemInHand(InteractionHand.MAIN_HAND, whistle.copy());
        gooby.mobInteract(owner, InteractionHand.MAIN_HAND);
        helper.assertTrue(gooby.getCommandMode() == GoobyCommand.FOLLOW, "1. Pfiff muss FOLLOW ergeben");
        helper.assertFalse(gooby.isOrderedToSit(), "FOLLOW darf nicht sitzen");
        gooby.mobInteract(owner, InteractionHand.MAIN_HAND);
        helper.assertTrue(gooby.getCommandMode() == GoobyCommand.STAY, "2. Pfiff muss STAY ergeben");
        helper.assertTrue(gooby.isOrderedToSit(), "STAY muss sitzen lassen");
        gooby.mobInteract(owner, InteractionHand.MAIN_HAND);
        helper.assertTrue(gooby.getCommandMode() == GoobyCommand.WANDER, "3. Pfiff muss WANDER ergeben");
        helper.assertFalse(gooby.isOrderedToSit(), "WANDER darf nicht sitzen");

        // Pfeifen-Advancement wurde dem Besitzer verliehen
        AdvancementHolder whistleAdv = helper.getLevel().getServer().getAdvancements()
                .get(ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, GoobyAdvancements.WHISTLE_COMMAND));
        helper.assertTrue(whistleAdv != null
                        && owner.getAdvancements().getOrStartProgress(whistleAdv).isDone(),
                "whistle_command-Advancement fehlt");

        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 10. STAY haelt Gooby an Ort und Stelle
    // ------------------------------------------------------------------

    @GameTest(template = ARENA, timeoutTicks = 300)
    public static void stay_blocks_movement(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        FakePlayer owner = fakePlayer(helper, "gooby_tester");
        gooby.tame(owner);
        gooby.setCommandMode(GoobyCommand.STAY);
        Vec3 start = gooby.position();

        helper.runAfterDelay(100, () -> {
            helper.assertTrue(gooby.isOrderedToSit(), "STAY-Gooby muss sitzen");
            helper.assertTrue(gooby.position().distanceToSqr(start) < 0.25,
                    "STAY-Gooby ist weggelaufen: " + gooby.position().distanceToSqr(start));
            helper.succeed();
        });
    }

    // ------------------------------------------------------------------
    // 11. FOLLOW bewegt Gooby zum Besitzer
    // ------------------------------------------------------------------

    @GameTest(template = ARENA_LARGE, timeoutTicks = 600)
    public static void follow_moves_toward_owner(GameTestHelper helper) {
        placeLargeFloor(helper, Blocks.DIRT);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(14.5, 2.0, 14.5));
        gooby.tame(owner);
        gooby.setCommandMode(GoobyCommand.FOLLOW);
        double startDistance = gooby.distanceToSqr(owner);
        helper.assertTrue(startDistance > 100.0, "Testaufbau: Besitzer muss weit weg starten");

        helper.succeedWhen(() -> {
            helper.assertTrue(gooby.distanceToSqr(owner) < 36.0,
                    "Gooby folgt nicht (Distanz²: " + gooby.distanceToSqr(owner) + ")");
            TestPlayers.remove(helper, owner);
        });
    }

    // ------------------------------------------------------------------
    // 12. Geschenke: Kosten (Nutella-Ladung) + Cooldown + Freundschaft
    // ------------------------------------------------------------------

    @GameTest(template = ARENA)
    public static void gift_cooldown_and_cost(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        ServerPlayer friend = TestPlayers.create(helper, new Vec3(3.5, 2.0, 3.5));
        RandomSource random = RandomSource.create(20260810L);
        AABB dropArea = new AABB(helper.absolutePos(new BlockPos(2, 2, 2))).inflate(6.0);

        // Ohne Geschenk-Ladung: Buddeln foerdert NICHTS zutage (kein Endlos-Karotten-Exploit)
        gooby.setFriendship(friend.getUUID(), FriendshipTier.FRIEND.minimum() + 10);
        gooby.finishDig(random);
        helper.assertTrue(helper.getLevel().getEntitiesOfClass(ItemEntity.class, dropArea).isEmpty(),
                "Buddeln ohne Ladung darf nichts droppen");

        // Ladung ohne Freund in Reichweite: kein Geschenk
        gooby.setGiftCharges(1);
        gooby.setFriendship(friend.getUUID(), 10);
        helper.assertFalse(gooby.tryGiveGift(random), "Geschenk ohne Freundschaft >= 50 verteilt");

        // Ladung + Freundschaft: genau EIN Geschenk, Ladung weg, Cooldown gesetzt
        gooby.setFriendship(friend.getUUID(), FriendshipTier.FRIEND.minimum());
        helper.assertTrue(gooby.tryGiveGift(random), "Geschenk trotz erfuellter Bedingungen verweigert");
        helper.assertTrue(gooby.getGiftCharges() == 0, "Geschenk-Ladung wurde nicht verbraucht");
        helper.assertTrue(gooby.getGiftCooldown() > 0, "Geschenk-Cooldown wurde nicht gesetzt");
        helper.assertFalse(helper.getLevel().getEntitiesOfClass(ItemEntity.class, dropArea).isEmpty(),
                "Geschenk-Item fehlt");

        // Cooldown blockiert das naechste Geschenk trotz neuer Ladung
        gooby.setGiftCharges(1);
        helper.assertFalse(gooby.tryGiveGift(random), "Geschenk trotz laufendem Cooldown verteilt");

        // Geschenk-Advancement kam beim Empfaenger an
        AdvancementHolder giftAdv = helper.getLevel().getServer().getAdvancements()
                .get(ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, GoobyAdvancements.GIFT_RECEIVED));
        helper.assertTrue(giftAdv != null
                        && friend.getAdvancements().getOrStartProgress(giftAdv).isDone(),
                "gift_received-Advancement fehlt");

        TestPlayers.remove(helper, friend);
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 13. Persistenz: ALLES uebersteht Save/Reload
    // ------------------------------------------------------------------

    @GameTest(template = ARENA)
    public static void persistence_roundtrip(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity original = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        FakePlayer owner = fakePlayer(helper, "gooby_tester");
        UUID friendA = UUID.nameUUIDFromBytes("friendA".getBytes(StandardCharsets.UTF_8));
        UUID friendB = UUID.nameUUIDFromBytes("friendB".getBytes(StandardCharsets.UTF_8));

        original.tame(owner);
        original.setSatisfaction(73);
        original.setFriendship(friendA, 42);
        original.setFriendship(friendB, 99);
        original.setCommandMode(GoobyCommand.STAY);
        original.setGiftCharges(2);
        original.setGiftCooldown(1234);
        original.setHatItemId("minecraft:poppy");
        original.setMood(GoobyMood.LONELY);
        original.setLastFedTime(9876L);
        original.setOwnerAwayTicks(4321);
        BlockPos home = helper.absolutePos(new BlockPos(1, 2, 1));
        BlockPos jar = helper.absolutePos(new BlockPos(3, 2, 3));
        original.setHomePos(home);
        original.setJarTarget(jar);

        CompoundTag tag = new CompoundTag();
        original.saveWithoutId(tag);

        GoobyEntity reloaded = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 3));
        reloaded.load(tag);

        helper.assertTrue(reloaded.isTame(), "Zaehmung ging beim Reload verloren");
        helper.assertTrue(owner.getUUID().equals(reloaded.getOwnerUUID()), "Besitzer ging beim Reload verloren");
        helper.assertTrue(reloaded.getSatisfaction() == 73, "Zufriedenheit ging verloren");
        helper.assertTrue(reloaded.getFriendship(friendA) == 42, "Freundschaft (A) ging verloren");
        helper.assertTrue(reloaded.getFriendship(friendB) == 99, "Freundschaft (B) ging verloren");
        helper.assertTrue(reloaded.getFriendship(UUID.randomUUID()) == 0, "Unbekannte UUID muss 0 sein");
        helper.assertTrue(reloaded.getCommandMode() == GoobyCommand.STAY, "Kommando-Modus ging verloren");
        helper.assertTrue(reloaded.isOrderedToSit(), "STAY-Sitzen ging verloren");
        helper.assertTrue(reloaded.getGiftCharges() == 2, "Geschenk-Ladungen gingen verloren");
        helper.assertTrue(reloaded.getGiftCooldown() == 1234, "Geschenk-Cooldown ging verloren");
        helper.assertTrue("minecraft:poppy".equals(reloaded.getHatItemId()), "Hut ging verloren");
        helper.assertTrue(reloaded.getMood() == GoobyMood.LONELY, "Mood ging verloren");
        helper.assertTrue(reloaded.getLastFedTime() == 9876L, "Letzte Fuetterzeit ging verloren");
        helper.assertTrue(reloaded.getOwnerAwayTicks() == 4321, "Owner-Abwesenheit ging verloren");
        helper.assertTrue(home.equals(reloaded.getHomePos()), "Zuhause (Nest) ging verloren");
        helper.assertTrue(jar.equals(reloaded.getJarTarget()), "Glas-Ziel ging verloren");
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 14. Huete: synchronisiert (EntityData), owner-gebunden, Schere entfernt
    // ------------------------------------------------------------------

    @GameTest(template = ARENA)
    public static void hat_equip_sync_persist(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(net.minecraft.world.level.GameType.SURVIVAL); // sonst wird das Hut-Item nicht verbraucht
        FakePlayer stranger = fakePlayer(helper, "hat_thief");
        gooby.tame(owner);

        // Fremde duerfen keinen Hut aufsetzen
        stranger.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(Items.POPPY));
        gooby.mobInteract(stranger, InteractionHand.MAIN_HAND);
        helper.assertFalse(gooby.hasHat(), "Fremde duerfen Gooby keinen Hut aufsetzen");

        // Besitzer setzt eine Mohnblume auf: synchronisiert via EntityData
        owner.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(Items.POPPY));
        gooby.mobInteract(owner, InteractionHand.MAIN_HAND);
        helper.assertTrue("minecraft:poppy".equals(gooby.getHatItemId()),
                "Hut nicht gesetzt/synchronisiert: '" + gooby.getHatItemId() + "'");
        helper.assertTrue(owner.getItemInHand(InteractionHand.MAIN_HAND).isEmpty(),
                "Hut-Item wurde nicht verbraucht");
        helper.assertTrue(gooby.getHatStack().is(Items.POPPY), "getHatStack liefert falsches Item");

        // Schere (Besitzer) nimmt den Hut ab und gibt das Item zurueck
        owner.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(Items.SHEARS));
        gooby.mobInteract(owner, InteractionHand.MAIN_HAND);
        helper.assertFalse(gooby.hasHat(), "Schere muss den Hut abnehmen");
        AABB area = new AABB(helper.absolutePos(new BlockPos(2, 2, 2))).inflate(4.0);
        boolean poppyBack = !helper.getLevel().getEntitiesOfClass(ItemEntity.class, area,
                item -> item.getItem().is(Items.POPPY)).isEmpty();
        helper.assertTrue(poppyBack, "Abgenommener Hut wurde nicht gedroppt");

        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 15. Nutella-Glas: atomare Reservierung — EIN Gooby pro Glas
    // ------------------------------------------------------------------

    @GameTest(template = ARENA_LARGE, batch = NIGHT_BATCH, timeoutTicks = 300)
    public static void nutella_jar_single_spawn(GameTestHelper helper) {
        placeLargeFloor(helper, Blocks.GRASS_BLOCK);
        BlockPos jarRel = new BlockPos(8, 2, 8);
        helper.setBlock(jarRel, ModBlocks.NUTELLA_JAR.get());
        BlockPos jarAbs = helper.absolutePos(jarRel);
        ServerLevel level = helper.getLevel();

        // 30 randomTicks im selben Server-Tick: ohne atomare Reservierung
        // wuerden hier ~15 Goobys spawnen. Erwartet: EXAKT einer.
        for (int i = 0; i < 30; i++) {
            BlockState state = level.getBlockState(jarAbs);
            helper.assertTrue(state.is(ModBlocks.NUTELLA_JAR.get()), "Glas verschwunden?");
            state.randomTick(level, jarAbs, level.random);
        }

        helper.assertTrue(level.getBlockState(jarAbs).getValue(NutellaJarBlock.CLAIMED),
                "Glas muss nach dem Spawn reserviert (claimed) sein");
        List<GoobyEntity> dispatched = level.getEntitiesOfClass(GoobyEntity.class,
                new AABB(jarAbs).inflate(24.0), gooby -> jarAbs.equals(gooby.getJarTarget()));
        helper.assertTrue(dispatched.size() == 1,
                "Genau EIN Gooby pro Glas erwartet, waren: " + dispatched.size());

        // Ein Entity-Unload/-Discard darf die persistente Lease NICHT sofort freigeben.
        dispatched.get(0).discard();
        helper.assertTrue(level.getBlockState(jarAbs).getValue(NutellaJarBlock.CLAIMED),
                "Reservierung wurde vor Ablauf der Lease freigegeben");
        helper.succeed();
    }

    /** Chunk-Unload-Simulation: keine zweite Spawnchance bis Lease-Ablauf + UUID-Fehlschlag. */
    @GameTest(template = ARENA_LARGE, batch = NIGHT_BATCH, timeoutTicks = 300)
    public static void jar_lease_no_double_spawn(GameTestHelper helper) {
        placeLargeFloor(helper, Blocks.GRASS_BLOCK);
        BlockPos jarRel = new BlockPos(8, 2, 8);
        helper.setBlock(jarRel, ModBlocks.NUTELLA_JAR.get());
        BlockPos jarAbs = helper.absolutePos(jarRel);
        ServerLevel level = helper.getLevel();

        for (int i = 0; i < 40; i++) {
            level.getBlockState(jarAbs).randomTick(level, jarAbs, level.random);
        }
        List<GoobyEntity> firstClaimers = level.getEntitiesOfClass(GoobyEntity.class,
                new AABB(jarAbs).inflate(32.0), gooby -> jarAbs.equals(gooby.getJarTarget()));
        helper.assertTrue(firstClaimers.size() == 1, "Testaufbau braucht genau einen ersten Claimer");
        helper.assertTrue(level.getBlockEntity(jarAbs) instanceof NutellaJarBlockEntity,
                "Nutella-Glas hat kein Lease-BlockEntity");
        NutellaJarBlockEntity lease = (NutellaJarBlockEntity) level.getBlockEntity(jarAbs);
        UUID firstId = firstClaimers.get(0).getUUID();
        helper.assertTrue(firstId.equals(lease.getClaimingGooby()), "Lease speichert nicht die Claimer-UUID");

        // discard simuliert, dass der Claimer nicht mehr serverweit per UUID aufloesbar ist.
        firstClaimers.get(0).discard();
        for (int i = 0; i < 40; i++) {
            level.getBlockState(jarAbs).randomTick(level, jarAbs, level.random);
        }
        helper.assertTrue(level.getBlockState(jarAbs).getValue(NutellaJarBlock.CLAIMED),
                "Nicht abgelaufene Lease wurde nach Entity-Unload freigegeben");
        helper.assertTrue(level.getEntitiesOfClass(GoobyEntity.class,
                new AABB(jarAbs).inflate(32.0), gooby -> jarAbs.equals(gooby.getJarTarget())).isEmpty(),
                "Vor Lease-Ablauf ist ein zweiter Gooby gespawnt");

        lease.setLeaseExpiry(level.getGameTime());
        level.getBlockState(jarAbs).randomTick(level, jarAbs, level.random);
        helper.assertFalse(level.getBlockState(jarAbs).getValue(NutellaJarBlock.CLAIMED),
                "Abgelaufene verwaiste Lease wurde nicht selbst geheilt");
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 16. Schlaf: Stall-Nest wird gemerkt, Aufwecken unterbricht ECHT
    // ------------------------------------------------------------------

    @GameTest(template = ARENA, batch = NIGHT_BATCH, timeoutTicks = 1200)
    public static void sleep_interrupt_and_home(GameTestHelper helper) {
        placeFloor(helper);
        BlockPos hutchRel = new BlockPos(2, 2, 2);
        helper.setBlock(hutchRel, ModBlocks.RABBIT_HUTCH.get());
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 3));
        FakePlayer player = fakePlayer(helper, "gooby_tester");
        BlockPos hutchAbs = helper.absolutePos(hutchRel);

        helper.startSequence()
                .thenWaitUntil(() -> helper.assertTrue(gooby.isGoobySleeping(), "Gooby schlaeft noch nicht"))
                .thenExecute(() -> {
                    helper.assertTrue(hutchAbs.equals(gooby.getHomePos()),
                            "Gooby muss sich den Stall als Zuhause merken");
                    helper.assertTrue(gooby.position().distanceToSqr(RabbitHutchBlock.interiorAnchor(hutchAbs)) < 0.05,
                            "Gooby schlaeft nicht wirklich im Stall-Innenanker: " + gooby.position());
                    // Streicheln weckt auf …
                    gooby.pet(player);
                    helper.assertFalse(gooby.isGoobySleeping(), "Streicheln muss aufwecken");
                    helper.assertTrue(gooby.isSleepSuppressed(), "Aufwecken muss die Schlaf-Sperre setzen");
                })
                // … und Gooby schlaeft NICHT sofort wieder ein (frueher: Sofort-Wiedereinschlafen)
                .thenExecuteAfter(150, () -> helper.assertFalse(gooby.isGoobySleeping(),
                        "Gooby ist trotz Schlaf-Sperre sofort wieder eingeschlafen"))
                .thenSucceed();
    }

    // ------------------------------------------------------------------
    // 17. Create-Kompat: ohne Create sicher degradieren, Reiten als Fallback
    // ------------------------------------------------------------------

    @GameTest(template = ARENA)
    public static void create_compat_degrades(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(2.5, 2.0, 1.5));
        gooby.tame(owner);

        // Dev-Umgebung hat kein Create: trySeatGooby degradiert sauber (false, KEINE Exception)
        helper.assertFalse(CreateCompat.isCreateLoaded(), "Testumgebung darf Create nicht laden");
        helper.assertFalse(CreateCompat.trySeatGooby(gooby), "Ohne Create muss trySeatGooby false liefern");
        helper.assertFalse(CreateCompat.isDegraded(), "Fehlendes Create ist KEINE Degradierung (nur Fallback)");

        // Fallback: Besitzer reitet normal per Shift-Rechtsklick mit leerer Hand
        owner.setItemInHand(InteractionHand.MAIN_HAND, ItemStack.EMPTY);
        owner.setShiftKeyDown(true);
        gooby.mobInteract(owner, InteractionHand.MAIN_HAND);
        helper.assertTrue(owner.getVehicle() == gooby, "Reit-Fallback funktioniert nicht");

        owner.stopRiding();
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 18. Advancement-Baum: alle definiert + best_friends wird bei 100 verliehen
    // ------------------------------------------------------------------

    @GameTest(template = ARENA)
    public static void advancement_tree(GameTestHelper helper) {
        placeFloor(helper);
        var advancements = helper.getLevel().getServer().getAdvancements();
        for (String name : List.of(GoobyAdvancements.ROOT, "tame_gooby", GoobyAdvancements.BEST_FRIENDS,
                GoobyAdvancements.WHISTLE_COMMAND, GoobyAdvancements.GOOBY_RIDE,
                GoobyAdvancements.GIFT_RECEIVED, GoobyAdvancements.HAT_FASHION,
                GoobyAdvancements.SNUGGLE_TIME, GoobyAdvancements.FIRST_TRICK,
                GoobyAdvancements.ALL_TRICKS_MASTERED, GoobyAdvancements.GOOBY_FAMILY,
                GoobyAdvancements.FULL_OUTFIT)) {
            helper.assertTrue(advancements.get(ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, name)) != null,
                    "Advancement fehlt oder ist kaputt: " + name);
        }

        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        ServerPlayer player = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        gooby.tame(player);

        // tame_animal-Trigger (Vanilla) hat tame_gooby verliehen
        AdvancementHolder tameAdv = advancements
                .get(ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "tame_gooby"));
        helper.assertTrue(tameAdv != null && player.getAdvancements().getOrStartProgress(tameAdv).isDone(),
                "tame_gooby muss ueber den echten tame_animal-Trigger kommen");

        // Freundschaft 100 verleiht best_friends
        gooby.setFriendship(player.getUUID(), 99);
        gooby.gainFriendship(player, 5, false);
        helper.assertTrue(gooby.getFriendship(player.getUUID()) == GoobyEntity.MAX_FRIENDSHIP,
                "Freundschaft muss bei 100 gedeckelt sein");
        AdvancementHolder bestAdv = advancements
                .get(ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, GoobyAdvancements.BEST_FRIENDS));
        helper.assertTrue(bestAdv != null && player.getAdvancements().getOrStartProgress(bestAdv).isDone(),
                "best_friends-Advancement fehlt bei Freundschaft 100");

        TestPlayers.remove(helper, player);
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 24+. Release-Rails-Regressions: Sprache, Stall, Hat-Anchor
    // ------------------------------------------------------------------

    /** C3 fail-closed: jede EN-Zeichenkette braucht exakt denselben DE-Key und umgekehrt. */
    @GameTest(template = ARENA)
    public static void lang_parity(GameTestHelper helper) {
        JsonObject english = loadAssetJson(helper, "assets/goobymod/lang/en_us.json");
        JsonObject german = loadAssetJson(helper, "assets/goobymod/lang/de_de.json");
        Set<String> onlyEnglish = new HashSet<>(english.keySet());
        onlyEnglish.removeAll(german.keySet());
        Set<String> onlyGerman = new HashSet<>(german.keySet());
        onlyGerman.removeAll(english.keySet());

        helper.assertTrue(onlyEnglish.isEmpty(), "DE fehlen Keys: " + onlyEnglish);
        helper.assertTrue(onlyGerman.isEmpty(), "EN fehlen Keys: " + onlyGerman);
        helper.succeed();
    }

    /** Der visuelle Stall ist ein offener Shell-Block und blockiert seinen Innenanker nicht. */
    @GameTest(template = ARENA)
    public static void hutch_entrance_is_enterable(GameTestHelper helper) {
        placeFloor(helper);
        BlockPos relative = new BlockPos(2, 2, 2);
        helper.setBlock(relative, ModBlocks.RABBIT_HUTCH.get());
        BlockPos absolute = helper.absolutePos(relative);
        BlockState state = helper.getLevel().getBlockState(absolute);

        helper.assertTrue(state.getCollisionShape(helper.getLevel(), absolute).isEmpty(),
                "Stall-Kollisionsform versperrt Gooby weiterhin den Eingang");
        helper.succeed();
    }

    /** Der Hut muss an einem eigenen Kind-Bone des animierten Kopfes haengen. */
    @GameTest(template = ARENA)
    public static void hat_anchor_follows_head(GameTestHelper helper) {
        JsonObject geometry = loadAssetJson(helper, "assets/goobymod/geo/gooby.geo.json");
        var bones = geometry.getAsJsonArray("minecraft:geometry")
                .get(0).getAsJsonObject().getAsJsonArray("bones");
        boolean anchored = false;
        for (var element : bones) {
            JsonObject bone = element.getAsJsonObject();
            if ("hat_anchor".equals(bone.get("name").getAsString())
                    && "head".equals(bone.get("parent").getAsString())) {
                anchored = true;
                break;
            }
        }

        helper.assertTrue(anchored, "hat_anchor fehlt oder ist nicht Kind des animierten head-Bones");
        helper.succeed();
    }

    /** Ein laufender Blink darf die unabhaengige Movement-Auswahl nie von HOP abhalten. */
    @GameTest(template = ARENA)
    public static void micro_controller_never_blocks_movement(GameTestHelper helper) {
        GoobyAnimationState.Pose pose = GoobyAnimationState.selectPose(
                true, false, false, false, false);
        helper.assertTrue(pose == GoobyAnimationState.Pose.HOP,
                "Bewegung muss unabhaengig vom additiven Micro-Controller HOP waehlen");
        helper.succeed();
    }

    /** Plain state holder: Bruecken laufen vollstaendig und enden deterministisch. */
    @GameTest(template = ARENA)
    public static void transition_state_machine(GameTestHelper helper) {
        GoobyAnimationState state = new GoobyAnimationState();
        state.update(GoobyAnimationState.Pose.SIT, 10);
        helper.assertTrue(state.transition() == GoobyAnimationState.Transition.SIT_DOWN,
                "IDLE -> SIT braucht sit_down");
        state.update(GoobyAnimationState.Pose.HOP, 14);
        helper.assertTrue(state.transition() == GoobyAnimationState.Transition.SIT_DOWN,
                "Laufende Transition wurde vorzeitig abgeschnitten");
        state.update(GoobyAnimationState.Pose.SIT, 18);
        helper.assertFalse(state.isTransitioning(), "sit_down endet nicht deterministisch");
        helper.assertTrue(state.stablePose() == GoobyAnimationState.Pose.SIT,
                "sit_down endet nicht im SIT-Loop");
        state.update(GoobyAnimationState.Pose.HOP, 19);
        helper.assertTrue(state.transition() == GoobyAnimationState.Transition.STAND_UP,
                "SIT -> HOP braucht zuerst stand_up");
        helper.succeed();
    }

    /** Neue Action-Requests werden freundlich ignoriert statt einen Clip abzuschneiden. */
    @GameTest(template = ARENA)
    public static void action_animation_no_interrupt(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        helper.assertTrue(gooby.tryTriggerAction("pet", 34), "Erste Action wurde nicht angenommen");
        helper.assertFalse(gooby.tryTriggerAction("wave", 32), "Zweite Action hat den Pet-Clip abgeschnitten");
        helper.assertTrue(gooby.getActionAnimationTicks() == 34, "Action-Cooldown wurde unerwartet ersetzt");
        helper.succeed();
    }

    /** Ein echter Fall ueber zwei Bloecke loest Squash + Partikelpfad serverseitig aus. */
    @GameTest(template = ARENA, timeoutTicks = 300)
    public static void landing_squash_after_drop(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new Vec3(2.5, 7.0, 2.5));
        helper.succeedWhen(() -> helper.assertTrue(gooby.getLandingSquashes() == 1,
                "Fall >2 Bloecke hat keinen eindeutigen Landing-Squash ausgeloest"));
    }

    /** Ressourcen-Gate fuer alle v3.1-Clips, Eyelids und Sound-Keyframes. */
    @GameTest(template = ARENA)
    public static void micro_animation_assets_complete(GameTestHelper helper) {
        JsonObject animationRoot = loadAssetJson(helper, "assets/goobymod/animations/gooby.animation.json");
        JsonObject animations = animationRoot.getAsJsonObject("animations");
        for (String clip : List.of("blink", "ear_twitch_l", "ear_twitch_r", "nose_wiggle",
                "stretch_yawn", "tail_wiggle", "sit_down", "stand_up", "sleep_down", "wake_up", "land")) {
            helper.assertTrue(animations.has("animation.gooby." + clip), "Animationsclip fehlt: " + clip);
        }
        helper.assertTrue(animations.getAsJsonObject("animation.gooby.nose_wiggle").has("sound_effects"),
                "Nose-Wiggle hat keinen Sniff-Keyframe");
        helper.assertTrue(animations.getAsJsonObject("animation.gooby.stretch_yawn").has("sound_effects"),
                "Stretch-Yawn hat keinen Yawn-Keyframe");

        JsonObject geometry = loadAssetJson(helper, "assets/goobymod/geo/gooby.geo.json");
        Set<String> boneNames = new HashSet<>();
        for (var element : geometry.getAsJsonArray("minecraft:geometry")
                .get(0).getAsJsonObject().getAsJsonArray("bones")) {
            boneNames.add(element.getAsJsonObject().get("name").getAsString());
        }
        helper.assertTrue(boneNames.contains("eyelidLeft") && boneNames.contains("eyelidRight"),
                "Eyelid-Planes fehlen im Modell");
        helper.succeed();
    }

    /** Mood-Pool-Auswahl ist rein, stabil und priorisiert Nacht/Schlaefrigkeit. */
    @GameTest(template = ARENA)
    public static void ambient_pool_matches_mood(GameTestHelper helper) {
        helper.assertTrue(GoobySoundProfile.ambientPool(80, false) == GoobySoundProfile.AmbientPool.HAPPY,
                "Hohe Zufriedenheit muss den Happy-Trill-Pool waehlen");
        helper.assertTrue(GoobySoundProfile.ambientPool(45, false) == GoobySoundProfile.AmbientPool.NEUTRAL,
                "Mittlere Zufriedenheit muss neutral muemmeln");
        helper.assertTrue(GoobySoundProfile.ambientPool(15, false) == GoobySoundProfile.AmbientPool.SLEEPY,
                "Sehr niedrige Zufriedenheit muss sleepy klingen");
        helper.assertTrue(GoobySoundProfile.ambientPool(90, true) == GoobySoundProfile.AmbientPool.SLEEPY,
                "Nacht muss selbst bei hoher Zufriedenheit sleepy priorisieren");
        helper.succeed();
    }

    /** Jeder Pfeifenmodus besitzt eine eindeutig lernbare Sound-ID. */
    @GameTest(template = ARENA)
    public static void whistle_mode_sound_mapping(GameTestHelper helper) {
        Set<String> sounds = new HashSet<>();
        for (GoobyCommand command : GoobyCommand.values()) {
            sounds.add(GoobySoundProfile.whistleSound(command));
        }
        helper.assertTrue(sounds.size() == GoobyCommand.values().length,
                "Pfeifenmodi teilen sich eine Sound-ID: " + sounds);
        helper.assertTrue(GoobySoundProfile.whistleSound(GoobyCommand.WANDER).endsWith("whistle_wander"),
                "WANDER-Sound falsch zugeordnet");
        helper.assertTrue(GoobySoundProfile.whistleSound(GoobyCommand.FOLLOW).endsWith("whistle_follow"),
                "FOLLOW-Sound falsch zugeordnet");
        helper.assertTrue(GoobySoundProfile.whistleSound(GoobyCommand.STAY).endsWith("whistle_stay"),
                "STAY-Sound falsch zugeordnet");
        helper.succeed();
    }

    /** Der lokale Loop ist exakt an den ausloesenden Petter gebunden. */
    @GameTest(template = ARENA)
    public static void purr_loop_petter_binding(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        FakePlayer petter = fakePlayer(helper, "purr_petter");
        FakePlayer observer = fakePlayer(helper, "purr_observer");

        gooby.pet(petter);

        helper.assertTrue(gooby.isBeingPettedBy(petter.getUUID()), "Petter-UUID wurde nicht synchronisiert");
        helper.assertFalse(gooby.isBeingPettedBy(observer.getUUID()), "Observer bekam den lokalen Purr-Loop");
        helper.succeed();
    }

    /** Jeder Sound hat Untertitel in DE+EN; Kernereignisse besitzen echte Variant-Pools. */
    @GameTest(template = ARENA)
    public static void sound_subtitles_and_variants_complete(GameTestHelper helper) {
        JsonObject sounds = loadAssetJson(helper, "assets/goobymod/sounds.json");
        JsonObject english = loadAssetJson(helper, "assets/goobymod/lang/en_us.json");
        JsonObject german = loadAssetJson(helper, "assets/goobymod/lang/de_de.json");
        for (var entry : sounds.entrySet()) {
            JsonObject definition = entry.getValue().getAsJsonObject();
            helper.assertTrue(definition.has("subtitle"), "Sound ohne Subtitle-Key: " + entry.getKey());
            String subtitle = definition.get("subtitle").getAsString();
            helper.assertTrue(english.has(subtitle), "EN-Subtitle fehlt: " + subtitle);
            helper.assertTrue(german.has(subtitle), "DE-Subtitle fehlt: " + subtitle);
        }
        for (String event : List.of("entity.gooby.squeak", "entity.gooby.purr", "entity.gooby.munch",
                "entity.gooby.ambient_neutral", "entity.gooby.ambient_happy")) {
            helper.assertTrue(sounds.getAsJsonObject(event).getAsJsonArray("sounds").size() >= 3,
                    "Sound-Pool hat weniger als drei Varianten: " + event);
        }
        helper.succeed();
    }

    /** Reine Mood-Ableitung deckt jede priorisierte Zustandsklasse ab. */
    @GameTest(template = ARENA)
    public static void mood_derivation_pure(GameTestHelper helper) {
        int hunger = 36000;
        int lonely = 12000;
        helper.assertTrue(GoobyMood.derive(90, 0, false, 0, hunger, lonely, false) == GoobyMood.HAPPY,
                "HAPPY falsch abgeleitet");
        helper.assertTrue(GoobyMood.derive(50, 0, false, 0, hunger, lonely, false) == GoobyMood.CONTENT,
                "CONTENT falsch abgeleitet");
        helper.assertTrue(GoobyMood.derive(90, hunger, false, 0, hunger, lonely, false) == GoobyMood.HUNGRY,
                "HUNGRY falsch abgeleitet");
        helper.assertTrue(GoobyMood.derive(90, 0, true, 0, hunger, lonely, false) == GoobyMood.SLEEPY,
                "SLEEPY falsch abgeleitet");
        helper.assertTrue(GoobyMood.derive(50, 0, false, lonely, hunger, lonely, false) == GoobyMood.LONELY,
                "LONELY falsch abgeleitet");
        helper.assertTrue(GoobyMood.derive(90, 0, false, 0, hunger, lonely, true) == GoobyMood.SCARED,
                "SCARED muss hoechste Prioritaet haben");
        helper.succeed();
    }

    /** Aufmerksames Fuettern im HUNGRY-Zustand gibt +2 Bonusfreundschaft. */
    @GameTest(template = ARENA)
    public static void hungry_feed_bonus(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        FakePlayer player = fakePlayer(helper, "needs_feeder");
        gooby.setMood(GoobyMood.HUNGRY);

        gooby.eatNutella(player, new ItemStack(ModItems.NUTELLA.get()));

        helper.assertTrue(gooby.getFriendship(player.getUUID()) == GoobyEntity.FEED_FRIENDSHIP + 2,
                "Hungry-Feed-Bonus fehlt: " + gooby.getFriendship(player.getUUID()));
        helper.assertTrue(gooby.getLastFedTime() == helper.getLevel().getGameTime(),
                "lastFedTime wurde beim Fuettern nicht aktualisiert");
        helper.succeed();
    }

    /** Mood und beide Needs-Zeitgeber ueberstehen einen isolierten NBT-Roundtrip. */
    @GameTest(template = ARENA)
    public static void mood_persistence_roundtrip(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity original = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        original.setMood(GoobyMood.HUNGRY);
        original.setLastFedTime(2468L);
        original.setOwnerAwayTicks(1357);

        CompoundTag tag = new CompoundTag();
        original.saveWithoutId(tag);
        GoobyEntity reloaded = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 3));
        reloaded.load(tag);

        helper.assertTrue(reloaded.getMood() == GoobyMood.HUNGRY, "Mood ging beim NBT-Roundtrip verloren");
        helper.assertTrue(reloaded.getLastFedTime() == 2468L, "Fuetterzeit ging beim NBT-Roundtrip verloren");
        helper.assertTrue(reloaded.getOwnerAwayTicks() == 1357,
                "Owner-Abwesenheit ging beim NBT-Roundtrip verloren");
        helper.succeed();
    }

    /** Die Bettelpose ist strikt an HUNGRY plus sichtbares Nutella gebunden. */
    @GameTest(template = ARENA)
    public static void beg_only_when_hungry(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        FakePlayer player = fakePlayer(helper, "needs_beg");
        player.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(ModItems.NUTELLA.get()));

        for (GoobyMood mood : GoobyMood.values()) {
            gooby.setMood(mood);
            helper.assertTrue(gooby.shouldBegForNutella(player) == (mood == GoobyMood.HUNGRY),
                    "Bettelpose hat falsches Mood-Gating fuer " + mood);
        }
        gooby.setMood(GoobyMood.HUNGRY);
        player.setItemInHand(InteractionHand.MAIN_HAND, ItemStack.EMPTY);
        helper.assertFalse(gooby.shouldBegForNutella(player), "Bettelpose darf ohne Nutella nicht laufen");
        helper.succeed();
    }

    /** Einsamkeit verdoppelt nur Zufriedenheit, nicht den Freundschaftswert. */
    @GameTest(template = ARENA)
    public static void lonely_pet_bonus(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        FakePlayer player = fakePlayer(helper, "lonely_petter");
        gooby.setMood(GoobyMood.LONELY);
        gooby.setSatisfaction(10);

        gooby.pet(player);

        helper.assertTrue(gooby.getSatisfaction() == 10 + GoobyEntity.PET_SATISFACTION * 2,
                "Lonely-Pet-Zufriedenheit wurde nicht verdoppelt");
        helper.assertTrue(gooby.getFriendship(player.getUUID()) == GoobyEntity.PET_FRIENDSHIP,
                "Lonely-Pet darf Freundschaft nicht verdoppeln");
        helper.succeed();
    }

    /** Mood-Dwell verhindert Flattern; Needs-Clips sind als Assets vorhanden. */
    @GameTest(template = ARENA)
    public static void mood_dwell_and_needs_assets(GameTestHelper helper) {
        helper.assertFalse(GoobyMood.canTransition(1000L, 1599L), "Mood darf vor 30 s wechseln");
        helper.assertTrue(GoobyMood.canTransition(1000L, 1600L), "Mood muss nach 30 s wechseln duerfen");
        JsonObject animations = loadAssetJson(helper, "assets/goobymod/animations/gooby.animation.json")
                .getAsJsonObject("animations");
        for (String clip : List.of("ears_droop", "beg", "happy_bounce_in_place")) {
            helper.assertTrue(animations.has("animation.gooby." + clip), "Needs-Clip fehlt: " + clip);
        }
        helper.succeed();
    }

    /** Zombie in Normalreichweite loest binnen 40 Ticks Alarm und SCARED aus. */
    @GameTest(template = ARENA, timeoutTicks = 100)
    public static void alert_on_zombie(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        Zombie zombie = helper.spawn(EntityType.ZOMBIE, new BlockPos(4, 2, 2));
        zombie.setNoAi(true);

        helper.succeedWhen(() -> {
            helper.assertTrue(gooby.isAlerting(), "Gooby hat den Zombie nicht als Bedrohung erkannt");
            helper.assertTrue(gooby.getMood() == GoobyMood.SCARED, "Zombie-Alarm setzt SCARED nicht");
            helper.assertTrue(gooby.getAlarmCount() > 0, "Zombie-Alarm hat keinen Alarmton ausgeloest");
        });
    }

    /** Creeper werden vier Bloecke vor der normalen Hostile-Grenze erkannt. */
    @GameTest(template = ARENA_LARGE, timeoutTicks = 100)
    public static void creeper_early_warning_radius(GameTestHelper helper) {
        placeLargeFloor(helper, Blocks.DIRT);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(1, 2, 8));
        Creeper creeper = helper.spawn(EntityType.CREEPER, new BlockPos(16, 2, 8));
        creeper.setNoAi(true);
        helper.assertTrue(GoobyAlertGoal.detectionRadius(creeper) > 15.0,
                "Creeper-Fruehwarnradius reicht nicht ueber 15 Bloecke");

        helper.succeedWhen(() -> {
            helper.assertTrue(gooby.isAlerting(), "Creeper im Fruehwarnring wurde nicht erkannt");
            helper.assertTrue(gooby.getAlarmCount() > 0, "Creeper-Fruehwarnung blieb stumm");
        });
    }

    /** Bei Regen verlaesst Gooby freien Himmel und laeuft unter das Testdach. */
    @GameTest(template = ARENA_LARGE, batch = RAIN_BATCH, timeoutTicks = 400)
    public static void rain_seeks_shelter(GameTestHelper helper) {
        placeLargeFloor(helper, Blocks.DIRT);
        for (int x = 9; x <= 11; x++) {
            for (int z = 7; z <= 9; z++) {
                helper.setBlock(new BlockPos(x, 4, z), Blocks.STONE);
            }
        }
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 8));
        helper.assertTrue(helper.getLevel().canSeeSky(gooby.blockPosition()),
                "Regen-Test startet nicht unter freiem Himmel");

        helper.succeedWhen(() -> helper.assertFalse(helper.getLevel().canSeeSky(gooby.blockPosition()),
                "Gooby hat das trockene Testdach nicht aufgesucht"));
    }

    /** 50 Teleportversuche an einem Lava-Moat akzeptieren nie ein Fluessigkeitsziel. */
    @GameTest(template = ARENA_LARGE)
    public static void follow_teleport_never_lands_in_lava(GameTestHelper helper) {
        placeLargeFloor(helper, Blocks.DIRT);
        BlockPos ownerRelative = new BlockPos(8, 2, 8);
        for (int x = -3; x <= 3; x++) {
            for (int z = -3; z <= 3; z++) {
                if (Math.abs(x) >= 2 || Math.abs(z) >= 2) {
                    helper.setBlock(ownerRelative.offset(x, -1, z), Blocks.LAVA);
                }
            }
        }
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(8.5, 2.0, 8.5));
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(1, 2, 1));
        gooby.tame(owner);
        Vec3 reset = gooby.position();

        for (int attempt = 0; attempt < 50; attempt++) {
            gooby.trySafeFollowTeleportAround(owner.blockPosition());
            helper.assertTrue(helper.getLevel().getFluidState(gooby.blockPosition()).isEmpty()
                            && helper.getLevel().getFluidState(gooby.blockPosition().below()).isEmpty(),
                    "Follow-Teleport landete im Lava-Moat bei Versuch " + attempt);
            gooby.moveTo(reset);
        }
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Fire, cactus and powder snow carry explicit avoidance/impassable costs. */
    @GameTest(template = ARENA)
    public static void pathfinding_avoids_fire(GameTestHelper helper) {
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        helper.assertTrue(gooby.getPathfindingMalus(PathType.DANGER_FIRE) >= 16.0F,
                "Feuer-Nachbarschaft hat keinen erhoehten Malus");
        helper.assertTrue(gooby.getPathfindingMalus(PathType.DAMAGE_FIRE) < 0.0F,
                "Direktes Feuer muss unpassierbar sein");
        helper.assertTrue(gooby.getPathfindingMalus(PathType.DANGER_OTHER) >= 16.0F,
                "Kaktus-Nachbarschaft hat keinen erhoehten Malus");
        helper.assertTrue(gooby.getPathfindingMalus(PathType.DAMAGE_OTHER) < 0.0F,
                "Direkter Kaktus-Schaden muss unpassierbar sein");
        helper.assertTrue(gooby.getPathfindingMalus(PathType.POWDER_SNOW) < 0.0F,
                "Pulverschnee muss unpassierbar sein");
        helper.succeed();
    }

    /** Wild-Gooby nutzt PanicGoal nach echtem Mob-Schaden, ein gezaehmter nicht. */
    @GameTest(template = ARENA_LARGE)
    public static void wild_damage_panics(GameTestHelper helper) {
        placeLargeFloor(helper, Blocks.DIRT);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(8, 2, 8));
        Zombie zombie = helper.spawn(EntityType.ZOMBIE, new BlockPos(9, 2, 8));
        zombie.setNoAi(true);
        helper.assertTrue(gooby.hurt(helper.getLevel().damageSources().mobAttack(zombie), 2.0F),
                "Wild-Gooby muss Mob-Schaden erhalten");
        helper.assertTrue(new GoobyWildPanicGoal(gooby).canUse(),
                "Wild-Gooby startet nach Mob-Schaden keinen PanicGoal");
        gooby.tame(fakePlayer(helper, "panic_owner"));
        helper.assertFalse(new GoobyWildPanicGoal(gooby).canUse(),
                "Gezaehmter Gooby darf den Wild-PanicGoal nicht starten");
        helper.succeed();
    }

    /** Tagesrhythmus moduliert bestehende Buddel-, Sitz- und Wanderintervalle. */
    @GameTest(template = ARENA)
    public static void day_rhythm_modulation(GameTestHelper helper) {
        helper.assertTrue(GoobyDayRhythm.at(6000).digInterval()
                        < GoobyDayRhythm.at(11000).digInterval(),
                "Mittag muss aktiver buddeln als der Abend");
        helper.assertTrue(GoobyDayRhythm.at(11000).sitInterval()
                        < GoobyDayRhythm.at(6000).sitInterval(),
                "Abend muss Sitzverhalten verstaerken");
        helper.assertTrue(GoobyDayRhythm.at(6000).strollInterval()
                        < GoobyDayRhythm.at(18000).strollInterval(),
                "Mittag muss haeufiger wandern als die Nacht");
        helper.succeed();
    }

    /** Ressourcen-Gate fuer Awareness-Clips, Varianten und Untertitel. */
    @GameTest(template = ARENA)
    public static void awareness_assets_complete(GameTestHelper helper) {
        JsonObject animations = loadAssetJson(helper, "assets/goobymod/animations/gooby.animation.json")
                .getAsJsonObject("animations");
        for (String clip : List.of("alert", "shake_off_water", "hide_behind", "shiver")) {
            helper.assertTrue(animations.has("animation.gooby." + clip), "Awareness-Clip fehlt: " + clip);
        }
        JsonObject sounds = loadAssetJson(helper, "assets/goobymod/sounds.json");
        JsonObject alarm = sounds.getAsJsonObject("entity.gooby.alarm_squeak");
        helper.assertTrue(alarm != null && alarm.has("subtitle")
                        && alarm.getAsJsonArray("sounds").size() == 2,
                "Alarm-Sound braucht Untertitel und zwei Varianten");
        JsonObject shake = sounds.getAsJsonObject("entity.gooby.shake");
        helper.assertTrue(shake != null && shake.has("subtitle"), "Shake-Sound oder Untertitel fehlt");
        helper.succeed();
    }

    /** Exakte 0-100-Grenzen der migrationsfreien Friendship-Tiers. */
    @GameTest(template = ARENA)
    public static void tier_boundaries_table(GameTestHelper helper) {
        int[] values = {0, 19, 20, 49, 50, 89, 90, 100};
        FriendshipTier[] expected = {
                FriendshipTier.STRANGER, FriendshipTier.STRANGER,
                FriendshipTier.BUDDY, FriendshipTier.BUDDY,
                FriendshipTier.FRIEND, FriendshipTier.FRIEND,
                FriendshipTier.BEST_FRIEND, FriendshipTier.BEST_FRIEND
        };
        for (int index = 0; index < values.length; index++) {
            helper.assertTrue(FriendshipTier.of(values[index]) == expected[index],
                    "Tier-Grenze falsch bei " + values[index]);
        }
        helper.succeed();
    }

    /** BEST_FRIEND-Kuscheln gibt Regeneration genau einmal pro Ingame-Tag. */
    @GameTest(template = ARENA)
    public static void snuggle_once_per_day(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        FakePlayer player = fakePlayer(helper, "snuggle_friend");
        gooby.tame(player);
        gooby.setFriendship(player.getUUID(), FriendshipTier.BEST_FRIEND.minimum());

        helper.assertTrue(gooby.trySnuggle(player, 0L), "Erstes Tageskuscheln wurde abgelehnt");
        helper.assertTrue(player.hasEffect(MobEffects.REGENERATION), "Kuscheln gibt kein Regeneration I");
        helper.assertFalse(gooby.trySnuggle(player, 23999L), "Zweites Kuscheln am selben Tag wurde erlaubt");
        helper.assertTrue(gooby.trySnuggle(player, 24000L), "Kuscheln am Folgetag blieb gesperrt");
        helper.succeed();
    }

    /** Die alte 30er-Schwelle ist BUDDY; erst FRIEND (50) schaltet Reiten frei. */
    @GameTest(template = ARENA)
    public static void ride_gate_tier_based_matches_legacy_30(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        FakePlayer owner = fakePlayer(helper, "tier_owner");
        FakePlayer rider = fakePlayer(helper, "tier_rider");
        gooby.tame(owner);

        gooby.setFriendship(rider.getUUID(), 30);
        helper.assertTrue(gooby.getFriendshipTier(rider.getUUID()) == FriendshipTier.BUDDY,
                "Legacy 30 muss BUDDY ergeben");
        helper.assertFalse(gooby.canRide(rider), "Legacy-30 darf nach Tier-Migration nicht reiten");
        gooby.setFriendship(rider.getUUID(), FriendshipTier.FRIEND.minimum());
        helper.assertTrue(gooby.canRide(rider), "FRIEND-Stufe schaltet Reiten nicht frei");
        helper.succeed();
    }

    /** Firsts, Tier-Zeit und Kuscheltag ueberstehen Entity-NBT. */
    @GameTest(template = ARENA)
    public static void memory_persistence(GameTestHelper helper) {
        placeFloor(helper);
        UUID playerId = UUID.nameUUIDFromBytes("memory_friend".getBytes(StandardCharsets.UTF_8));
        GoobyEntity original = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        FriendshipMemory memory = original.getMemory(playerId);
        memory.rememberFirstPet(123L);
        memory.rememberFirstFeed(456L);
        memory.rememberTier(FriendshipTier.FRIEND, 789L);
        memory.markSnuggle(24000L);

        CompoundTag tag = new CompoundTag();
        original.saveWithoutId(tag);
        GoobyEntity reloaded = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 3));
        reloaded.load(tag);
        FriendshipMemory loaded = reloaded.getMemory(playerId);

        helper.assertTrue(loaded.firstPet() == 123L, "FirstPet ging verloren");
        helper.assertTrue(loaded.firstFeed() == 456L, "FirstFeed ging verloren");
        helper.assertTrue(loaded.tierAt(FriendshipTier.FRIEND) == 789L, "FRIEND-Tierzeit ging verloren");
        helper.assertTrue(loaded.lastSnuggleDay() == 1L, "Kuscheltag ging verloren");
        helper.assertTrue(loaded.isAnniversaryDue(123L + FriendshipMemory.ANNIVERSARY_AGE_TICKS),
                "Sieben-Tage-Erinnerung wird nicht faellig");
        helper.succeed();
    }

    /** Jede Threshold-Ueberschreitung feiert einmal; Zwischenwerte bleiben still. */
    @GameTest(template = ARENA)
    public static void tierup_fires_exactly_once(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        FakePlayer player = fakePlayer(helper, "tierup_friend");
        gooby.setFriendship(player.getUUID(), 19);

        gooby.gainFriendship(player, 1, false);
        helper.assertTrue(gooby.getTierUpCount() == 1, "BUDDY-Tierup feuerte nicht genau einmal");
        gooby.gainFriendship(player, 1, false);
        helper.assertTrue(gooby.getTierUpCount() == 1, "Zwischenwert feuerte Tierup erneut");
        helper.assertFalse(GoobyEntity.shouldDisplayFriendshipProgress(0, 2),
                "+2 ohne Fuenfergrenze darf Actionbar nicht spammen");
        helper.assertTrue(GoobyEntity.shouldDisplayFriendshipProgress(4, 6),
                "Ueberschrittene Fuenfergrenze muss Status zeigen");
        helper.assertTrue(GoobyEntity.shouldDisplayFriendshipProgress(19, 20),
                "Tiergrenze muss Status zeigen");
        helper.succeed();
    }

    /** Owner-Chat erkennt Custom-Namen case-insensitive und reagiert einmal. */
    @GameTest(template = ARENA)
    public static void name_recognition_owner_chat(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        gooby.setCustomName(Component.literal("Goobert"));

        helper.assertTrue(GoobyEvents.handleNameRecognition(owner, "Hello GOOBERT!") == 1,
                "Owner-Nachricht erkannte Gooby-Namen nicht");
        helper.assertTrue(gooby.getNameReactionCount() == 1, "Name-Reaktion feuerte nicht genau einmal");
        helper.assertFalse(GoobyEvents.mentionsName("hello there", "Goobert"),
                "Unpassende Nachricht erzeugt False Positive");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Sprint-Tag-along wird exakt mit FRIEND und nicht im STAY-Modus frei. */
    @GameTest(template = ARENA)
    public static void friend_sprint_tag_along(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        FakePlayer owner = fakePlayer(helper, "tag_owner");
        FakePlayer runner = fakePlayer(helper, "tag_runner");
        gooby.tame(owner);
        runner.setSprinting(true);
        gooby.setFriendship(runner.getUUID(), 49);
        helper.assertFalse(gooby.shouldTagAlong(runner), "BUDDY darf Tag-along nicht starten");
        gooby.setFriendship(runner.getUUID(), 50);
        helper.assertTrue(gooby.shouldTagAlong(runner), "FRIEND startet Tag-along nicht");
        gooby.setCommandMode(GoobyCommand.STAY);
        helper.assertFalse(gooby.shouldTagAlong(runner), "STAY muss Tag-along blockieren");
        helper.succeed();
    }

    /** Bonding-Clips, Sounds, Goldherz und Advancement sind paketiert. */
    @GameTest(template = ARENA)
    public static void bonding_assets_complete(GameTestHelper helper) {
        JsonObject animations = loadAssetJson(helper, "assets/goobymod/animations/gooby.animation.json")
                .getAsJsonObject("animations");
        for (String clip : List.of("snuggle_lean", "tier_up_bounce", "ears_perk")) {
            helper.assertTrue(animations.has("animation.gooby." + clip), "Bonding-Clip fehlt: " + clip);
        }
        JsonObject sounds = loadAssetJson(helper, "assets/goobymod/sounds.json");
        for (String sound : List.of("entity.gooby.tier_up_jingle", "entity.gooby.snuggle_purr_long")) {
            helper.assertTrue(sounds.has(sound) && sounds.getAsJsonObject(sound).has("subtitle"),
                    "Bonding-Sound/Untertitel fehlt: " + sound);
        }
        loadAssetJson(helper, "assets/goobymod/particles/heart_gold.json");
        helper.assertTrue(GoobyGameTests.class.getClassLoader()
                        .getResource("assets/goobymod/textures/particle/heart_gold.png") != null,
                "Goldherz-Textur fehlt");
        loadAssetJson(helper, "data/goobymod/advancement/snuggle_time.json");
        helper.succeed();
    }

    /** Drei erfolgreiche Sitzungen steigern die persistente Beherrschung exakt 0→3. */
    @GameTest(template = ARENA)
    public static void training_proficiency_progression(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(net.minecraft.world.level.GameType.SURVIVAL);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        ItemStack treats = new ItemStack(ModItems.TRAINING_TREAT.get(), 3);

        helper.assertTrue(gooby.trainSelectedTrick(owner, treats, 0L), "Erstes Training scheiterte");
        helper.assertFalse(gooby.trainSelectedTrick(owner, treats, 1L), "Training ignorierte Cooldown");
        helper.assertTrue(gooby.trainSelectedTrick(owner, treats, GoobyEntity.TRAINING_COOLDOWN_TICKS),
                "Zweites Training scheiterte");
        helper.assertTrue(gooby.trainSelectedTrick(owner, treats, GoobyEntity.TRAINING_COOLDOWN_TICKS * 2L),
                "Drittes Training scheiterte");
        helper.assertTrue(gooby.getTrickProficiency(GoobyTrick.SPIN) == 3,
                "SPIN erreichte nicht drei Sterne");
        helper.assertTrue(treats.isEmpty(), "Erfolgreiche Sitzungen verbrauchten nicht exakt drei Happen");

        CompoundTag saved = new CompoundTag();
        gooby.saveWithoutId(saved);
        GoobyEntity reloaded = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 3));
        reloaded.load(saved);
        helper.assertTrue(reloaded.getTrickProficiency(GoobyTrick.SPIN) == 3,
                "Kunststück-Fortschritt ging beim Laden verloren");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Ein untrainiertes Kunststück wird verweigert, ein Stern schaltet es frei. */
    @GameTest(template = ARENA)
    public static void trick_request_requires_training(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        gooby.tame(owner);

        helper.assertTrue(gooby.isOwnedBy(owner), "Testspieler wurde nicht als Besitzer gebunden");
        helper.assertFalse(gooby.requestSelectedTrick(owner), "Untrainiertes Kunststueck wurde ausgefuehrt");
        helper.assertTrue(gooby.getPerformedTrickCount() == 0, "Verweigerter Trick zaehlte als Ausfuehrung");
        gooby.setTrickProficiency(gooby.getSelectedTrick(), 1);
        helper.assertTrue(gooby.getTrickProficiency(gooby.getSelectedTrick()) == 1,
                "Testaufbau setzte keinen Trainingsstern");
        helper.assertTrue(gooby.requestSelectedTrick(owner), "Trainiertes Kunststueck wurde verweigert");
        helper.assertTrue(gooby.getPerformedTrickCount() == 1, "Trainierter Trick feuerte nicht genau einmal");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Luftpfiff teleportiert den naechsten eigenen Gooby sicher aus mehr als 32 Bloecken Entfernung. */
    @GameTest(template = ARENA_LARGE, batch = WHISTLE_BATCH)
    public static void whistle_air_call_teleports_beyond_32(GameTestHelper helper) {
        placeLargeFloor(helper, Blocks.DIRT);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(8.5, 2.0, 8.5));
        // NeoForge reuses one embedded-player UUID across structures. Remove owned
        // Goobys left by completed batches before exercising the global nearest search.
        for (var entity : helper.getLevel().getAllEntities()) {
            if (entity instanceof GoobyEntity stale && stale.isOwnedBy(owner)) {
                stale.discard();
            }
        }
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        BlockPos far = helper.absolutePos(new BlockPos(48, 2, 8));
        gooby.moveTo(far.getX() + 0.5, far.getY(), far.getZ() + 0.5);
        helper.assertTrue(gooby.distanceToSqr(owner) > 32.0 * 32.0, "Test-Gooby startet nicht weit genug weg");

        owner.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(ModItems.GOOBY_WHISTLE.get()));
        helper.assertTrue(GoobyWhistleItem.findNearestOwned(owner) == gooby,
                "Isolierter Luftpfiff waehlte nicht seinen Test-Gooby");
        ModItems.GOOBY_WHISTLE.get().use(helper.getLevel(), owner, InteractionHand.MAIN_HAND);
        helper.assertTrue(gooby.distanceToSqr(owner) < 32.0 * 32.0,
                "Luftpfiff teleportierte entfernten Gooby nicht");
        helper.assertTrue(gooby.getCommandMode() == GoobyCommand.FOLLOW,
                "Luftpfiff setzte Gooby nicht auf FOLLOW");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Ein fremder Gooby reagiert weder auf Luftpfiff noch auf Kommando-Pfiff. */
    @GameTest(template = ARENA)
    public static void whistle_denial_foreign_gooby(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer stranger = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        FakePlayer owner = fakePlayer(helper, "foreign_whistle_owner");
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        gooby.setCommandMode(GoobyCommand.WANDER);

        helper.assertTrue(GoobyWhistleItem.findNearestOwned(stranger) == null,
                "Luftpfiff waehlt fremden Gooby");
        stranger.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(ModItems.GOOBY_WHISTLE.get()));
        ModItems.GOOBY_WHISTLE.get().use(helper.getLevel(), stranger, InteractionHand.MAIN_HAND);
        gooby.handleWhistle(stranger);
        helper.assertTrue(gooby.getCommandMode() == GoobyCommand.WANDER,
                "Fremder Pfiff aenderte den Kommandomodus");
        TestPlayers.remove(helper, stranger);
        helper.succeed();
    }

    /** Das lokalisierte Buch wird durch den persistenten Spieler-Marker nur einmal vergeben. */
    @GameTest(template = ARENA)
    public static void handbook_given_once_on_tame(GameTestHelper helper) {
        ServerPlayer player = TestPlayers.create(helper);
        GoobyEntity first = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        GoobyEntity second = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 3));
        first.tame(player);
        helper.assertFalse(GoobyHandbookItem.giveOnce(player), "Erstes Zaehmen setzte keinen Give-once-Marker");
        second.tame(player);
        helper.assertTrue(player.getInventory().countItem(ModItems.GOOBY_HANDBOOK.get()) == 1,
                "Inventar enthaelt nicht exakt ein Handbuch");
        ItemStack handbook = new ItemStack(ModItems.GOOBY_HANDBOOK.get());
        helper.assertTrue(handbook.has(DataComponents.WRITTEN_BOOK_CONTENT)
                        && handbook.get(DataComponents.WRITTEN_BOOK_CONTENT).pages().size() == 16,
                "Handbuch besitzt nicht sechzehn geschriebene Seiten");
        TestPlayers.remove(helper, player);
        helper.succeed();
    }

    /** Training-Modelle, Rezepte, Clips, Sounds und Advancements sind vollstaendig paketiert. */
    @GameTest(template = ARENA)
    public static void training_assets_complete(GameTestHelper helper) {
        JsonObject animations = loadAssetJson(helper, "assets/goobymod/animations/gooby.animation.json")
                .getAsJsonObject("animations");
        for (String clip : List.of("trick_spin", "trick_high_five", "trick_flop",
                "trick_speak", "training_success_hop")) {
            helper.assertTrue(animations.has("animation.gooby." + clip), "Training-Clip fehlt: " + clip);
        }
        JsonObject sounds = loadAssetJson(helper, "assets/goobymod/sounds.json");
        for (String sound : List.of("entity.gooby.trick_chime", "entity.gooby.flop_thud",
                "entity.gooby.whistle_denied")) {
            helper.assertTrue(sounds.has(sound) && sounds.getAsJsonObject(sound).has("subtitle"),
                    "Training-Sound/Untertitel fehlt: " + sound);
        }
        loadAssetJson(helper, "assets/goobymod/models/item/training_treat.json");
        loadAssetJson(helper, "assets/goobymod/models/item/gooby_handbook.json");
        loadAssetJson(helper, "data/goobymod/recipe/training_treat.json");
        loadAssetJson(helper, "data/goobymod/recipe/gooby_handbook.json");
        loadAssetJson(helper, "data/goobymod/advancement/first_trick.json");
        loadAssetJson(helper, "data/goobymod/advancement/all_tricks_mastered.json");
        helper.assertTrue(GoobyGameTests.class.getClassLoader()
                        .getResource("assets/goobymod/textures/item/training_treat.png") != null
                        && GoobyGameTests.class.getClassLoader()
                        .getResource("assets/goobymod/textures/item/gooby_handbook.png") != null,
                "Trainingstexturen fehlen");
        helper.succeed();
    }

    /** Der Bodennavigator erreicht den Eingang; dort uebernimmt die Hutch-Enter-Animation. */
    @GameTest(template = ARENA, timeoutTicks = 300)
    public static void hutch_entrance_pathable(GameTestHelper helper) {
        placeFloor(helper);
        BlockPos hutchRel = new BlockPos(3, 2, 2);
        helper.setBlock(hutchRel, ModBlocks.RABBIT_HUTCH.get());
        BlockPos hutch = helper.absolutePos(hutchRel);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(1, 2, 2));
        gooby.goalSelector.removeAllGoals(goal -> true);
        BlockState hutchState = helper.getLevel().getBlockState(hutch);
        Vec3 entrance = RabbitHutchBlock.exitAnchor(hutch,
                hutchState.getValue(HorizontalDirectionalBlock.FACING));
        helper.assertTrue(hutchState
                        .getCollisionShape(helper.getLevel(), hutch).isEmpty(),
                "Offener Stall besitzt noch eine blockierende Kollisionsform");
        helper.assertTrue(hutchState.getBlockPathType(helper.getLevel(), hutch, gooby) == PathType.OPEN,
                "Stall wird vom Bodennavigator nicht als OPEN bewertet");

        helper.startSequence()
                // Give the freshly spawned mob one server tick to settle on the floor and
                // initialize its node evaluator before asking for a reachability proof.
                .thenIdle(2)
                .thenExecute(() -> {
                    var path = gooby.getNavigation().createPath(BlockPos.containing(entrance), 0);
                    helper.assertTrue(path != null && path.canReach(),
                            "Bodennavigator kann keinen Pfad zum Stalleingang berechnen");
                    gooby.getNavigation().moveTo(path, 1.1);
                })
                .thenWaitUntil(() -> helper.assertTrue(
                        gooby.position().distanceToSqr(entrance) < 1.5,
                        "Gooby erreicht den Animations-Uebergabepunkt nicht: " + gooby.position()))
                .thenSucceed();
    }

    /** Drei Woll-Interaktionen bilden exakt die persistenten Komfortstufen 1–3 ab. */
    @GameTest(template = ARENA)
    public static void bedding_upgrade_levels(GameTestHelper helper) {
        placeFloor(helper);
        BlockPos relative = new BlockPos(2, 2, 2);
        helper.setBlock(relative, ModBlocks.RABBIT_HUTCH.get());
        BlockPos pos = helper.absolutePos(relative);
        ServerPlayer player = TestPlayers.create(helper, Vec3.atCenterOf(pos.relative(Direction.NORTH)));
        ItemStack wool = new ItemStack(Items.WHITE_WOOL, 4);
        player.setItemInHand(InteractionHand.MAIN_HAND, wool);
        BlockHitResult hit = new BlockHitResult(Vec3.atCenterOf(pos), Direction.UP, pos, false);

        for (int comfort = 1; comfort <= RabbitHutchBlock.MAX_COMFORT; comfort++) {
            helper.getLevel().getBlockState(pos).useItemOn(
                    wool, helper.getLevel(), player, InteractionHand.MAIN_HAND, hit);
            BlockState state = helper.getLevel().getBlockState(pos);
            helper.assertTrue(state.getValue(RabbitHutchBlock.BEDDING) == comfort,
                    "Blockstate-Komfort ist nicht " + comfort);
            helper.assertTrue(helper.getLevel().getBlockEntity(pos) instanceof RabbitHutchBlockEntity hutch
                            && hutch.getComfort() == comfort,
                    "BlockEntity-Komfort ist nicht " + comfort);
        }
        int countAtMaximum = wool.getCount();
        helper.getLevel().getBlockState(pos).useItemOn(
                wool, helper.getLevel(), player, InteractionHand.MAIN_HAND, hit);
        helper.assertTrue(helper.getLevel().getBlockState(pos).getValue(RabbitHutchBlock.BEDDING) == 3,
                "Komfort darf Stufe 3 nicht ueberschreiten");
        helper.assertTrue(wool.getCount() == countAtMaximum, "Maximaler Komfort verbraucht weitere Wolle");
        TestPlayers.remove(helper, player);
        helper.succeed();
    }

    /** Ein explizit gebundener Stall gewinnt immer gegen den naeheren freien Stall. */
    @GameTest(template = ARENA_LARGE)
    public static void bound_hutch_priority(GameTestHelper helper) {
        placeLargeFloor(helper, Blocks.DIRT);
        BlockPos nearRel = new BlockPos(3, 2, 3);
        BlockPos boundRel = new BlockPos(13, 2, 3);
        helper.setBlock(nearRel, ModBlocks.RABBIT_HUTCH.get());
        helper.setBlock(boundRel, ModBlocks.RABBIT_HUTCH.get());
        BlockPos near = helper.absolutePos(nearRel);
        BlockPos bound = helper.absolutePos(boundRel);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(5, 2, 3));
        helper.assertTrue(helper.getLevel().getBlockEntity(bound) instanceof RabbitHutchBlockEntity,
                "Gebundener Teststall hat keine BlockEntity");
        RabbitHutchBlockEntity hutch = (RabbitHutchBlockEntity) helper.getLevel().getBlockEntity(bound);
        hutch.bind(gooby);
        gooby.setHomePos(bound);

        helper.assertTrue(bound.equals(GoobySleepGoal.findPreferredHutch(gooby)),
                "Naeherer freier Stall hat den gebundenen Stall verdraengt");
        helper.assertFalse(near.equals(GoobySleepGoal.findPreferredHutch(gooby)),
                "Fuzzy-Radiussuche ignoriert die explizite Bindung");
        helper.succeed();
    }

    /** Beim Abbau wird ein schlafender Bewohner lebend ausgeworfen und verliert das Zuhause. */
    @GameTest(template = ARENA)
    public static void hutch_break_ejects_safely(GameTestHelper helper) {
        placeFloor(helper);
        BlockPos relative = new BlockPos(2, 2, 2);
        helper.setBlock(relative, ModBlocks.RABBIT_HUTCH.get());
        BlockPos pos = helper.absolutePos(relative);
        RabbitHutchBlockEntity hutch = (RabbitHutchBlockEntity) helper.getLevel().getBlockEntity(pos);
        hutch.setComfort(3);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), relative);
        Vec3 interior = RabbitHutchBlock.interiorAnchor(pos);
        gooby.setPos(interior.x, interior.y, interior.z);
        gooby.setHomePos(pos);
        gooby.setInHutch(true);
        gooby.setGoobySleeping(true);
        hutch.bind(gooby);
        hutch.occupy(gooby);

        helper.getLevel().destroyBlock(pos, true);
        helper.assertTrue(gooby.isAlive(), "Bewohner starb beim Stallabbau");
        helper.assertFalse(gooby.isGoobySleeping() || gooby.isInHutch(),
                "Bewohner blieb nach Stallabbau im Schlaf-/Innenzustand");
        helper.assertTrue(gooby.getHomePos() == null, "Abgebauter Stall blieb als Zuhause gespeichert");
        helper.assertTrue(gooby.position().distanceToSqr(RabbitHutchBlock.interiorAnchor(pos)) > 0.25,
                "Bewohner wurde nicht aus dem Stall ausgeworfen");
        int droppedWool = helper.getLevel().getEntitiesOfClass(ItemEntity.class, new AABB(pos).inflate(3.0),
                        item -> item.getItem().is(Items.WHITE_WOOL))
                .stream().mapToInt(item -> item.getItem().getCount()).sum();
        helper.assertTrue(droppedWool == 3, "Komfort-3-Stall gab nicht exakt drei Wolle zurueck");
        helper.succeed();
    }

    /** Komfort 3 regeneriert maximal und kann genau ein morgendliches Geschenk erzeugen. */
    @GameTest(template = ARENA)
    public static void comfort3_morning_gift(GameTestHelper helper) {
        placeFloor(helper);
        BlockPos relative = new BlockPos(2, 2, 2);
        helper.setBlock(relative, ModBlocks.RABBIT_HUTCH.get());
        BlockPos pos = helper.absolutePos(relative);
        RabbitHutchBlockEntity hutch = (RabbitHutchBlockEntity) helper.getLevel().getBlockEntity(pos);
        hutch.setComfort(3);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), relative);
        gooby.setSatisfaction(0);
        hutch.occupy(gooby);

        long giftSeed = 0;
        while (giftSeed < 1000 && hutch.createMorningGift(RandomSource.create(giftSeed)).isEmpty()) {
            giftSeed++;
        }
        helper.assertTrue(giftSeed < 1000, "Kein deterministischer Komfort-3-Geschenkseed gefunden");
        helper.assertTrue(hutch.applyMorningComfort(
                        helper.getLevel(), gooby, RandomSource.create(giftSeed)),
                "Komfort 3 erzeugte mit Trefferseed kein Morgengeschenk");
        helper.assertTrue(gooby.getSatisfaction() == 25,
                "Komfort 3 regenerierte nicht exakt 25 Zufriedenheit");
        helper.assertFalse(hutch.isOccupied(), "Morgenroutine liess Stall als belegt markiert");
        helper.assertTrue(!helper.getLevel().getEntitiesOfClass(
                        ItemEntity.class, new AABB(pos).inflate(3.0)).isEmpty(),
                "Morgengeschenk wurde nicht in die Welt gelegt");
        helper.succeed();
    }

    /** Komfort, Bindung, Schild, Belegung und Geschenktag ueberstehen BlockEntity-NBT. */
    @GameTest(template = ARENA)
    public static void hutch_block_entity_persistence_roundtrip(GameTestHelper helper) {
        placeFloor(helper);
        BlockPos relative = new BlockPos(2, 2, 2);
        helper.setBlock(relative, ModBlocks.RABBIT_HUTCH.get());
        BlockPos pos = helper.absolutePos(relative);
        RabbitHutchBlockEntity original =
                (RabbitHutchBlockEntity) helper.getLevel().getBlockEntity(pos);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), relative);
        gooby.setCustomName(Component.literal("Mochi"));
        original.setComfort(2);
        original.bind(gooby);
        original.occupy(gooby);

        CompoundTag tag = original.saveWithoutMetadata(helper.getLevel().registryAccess());
        RabbitHutchBlockEntity reloaded = new RabbitHutchBlockEntity(pos,
                helper.getLevel().getBlockState(pos));
        reloaded.loadWithComponents(tag, helper.getLevel().registryAccess());
        helper.assertTrue(reloaded.getComfort() == 2, "Komfort ging im BlockEntity-NBT verloren");
        helper.assertTrue(gooby.getUUID().equals(reloaded.getResident()), "Bewohnerbindung ging verloren");
        helper.assertTrue("Mochi".equals(reloaded.getResidentName()), "Namensschild ging verloren");
        helper.assertTrue(gooby.getUUID().equals(reloaded.getOccupant()), "Belegung ging verloren");
        helper.assertTrue(reloaded.getLastMorningGiftDay() == -1L,
                "Initialer Geschenktag ging im NBT verloren");
        helper.succeed();
    }

    /** Modelle, Overlays, Clips, Texturen und beide Hutch-Sounds bleiben fail-closed paketiert. */
    @GameTest(template = ARENA)
    public static void hutch_assets_complete(GameTestHelper helper) {
        JsonObject animations = loadAssetJson(helper, "assets/goobymod/animations/gooby.animation.json")
                .getAsJsonObject("animations");
        for (String clip : List.of("hutch_enter", "hutch_exit", "sleep_curl_tight")) {
            helper.assertTrue(animations.has("animation.gooby." + clip), "Hutch-Clip fehlt: " + clip);
        }
        loadAssetJson(helper, "assets/goobymod/blockstates/rabbit_hutch.json");
        loadAssetJson(helper, "assets/goobymod/models/block/rabbit_hutch.json");
        for (int comfort = 1; comfort <= 3; comfort++) {
            loadAssetJson(helper, "assets/goobymod/models/block/rabbit_hutch_bedding_" + comfort + ".json");
            helper.assertTrue(GoobyGameTests.class.getClassLoader().getResource(
                            "assets/goobymod/textures/block/rabbit_hutch_bedding_" + comfort + ".png") != null,
                    "Bettzeugtextur fehlt fuer Komfort " + comfort);
        }
        JsonObject sounds = loadAssetJson(helper, "assets/goobymod/sounds.json");
        for (String sound : List.of("entity.gooby.hutch_rustle", "entity.gooby.hutch_creak")) {
            helper.assertTrue(sounds.has(sound) && sounds.getAsJsonObject(sound).has("subtitle"),
                    "Hutch-Sound/Untertitel fehlt: " + sound);
        }
        helper.succeed();
    }

    /** Der Kuchen-Ritus erzeugt atomar ein Baby; Paar-Lease blockiert Ersatzkuchen am selben Tag. */
    @GameTest(template = ARENA)
    public static void ritual_spawns_one_baby(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(2.5, 2.0, 1.5));
        GoobyEntity first = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(1, 2, 2));
        GoobyEntity second = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 2));
        for (GoobyEntity parent : List.of(first, second)) {
            parent.tame(owner);
            parent.setFriendship(owner.getUUID(), FriendshipTier.FRIEND.minimum());
        }
        BlockPos cakeRel = new BlockPos(2, 2, 3);
        BlockPos cake = helper.absolutePos(cakeRel);
        helper.setBlock(cakeRel, ModBlocks.NUTELLA_CAKE.get());

        helper.assertTrue(NutellaCakeBlock.tryRitual(helper.getLevel(), cake, owner),
                "Gueltiges Familienritual scheiterte");
        List<GoobyEntity> babies = helper.getLevel().getEntitiesOfClass(GoobyEntity.class,
                new AABB(cake).inflate(8.0), GoobyEntity::isBaby);
        helper.assertTrue(babies.size() == 1, "Ritual erzeugte nicht exakt ein Baby: " + babies.size());
        helper.assertFalse(helper.getLevel().getBlockState(cake).is(ModBlocks.NUTELLA_CAKE.get()),
                "Verbrauchter Ritualkuchen blieb stehen");

        helper.setBlock(cakeRel, ModBlocks.NUTELLA_CAKE.get());
        helper.assertFalse(NutellaCakeBlock.tryRitual(helper.getLevel(), cake, owner),
                "Dasselbe Paar umging die Tages-Lease mit einem Ersatzkuchen");
        helper.assertTrue(helper.getLevel().getEntitiesOfClass(GoobyEntity.class,
                new AABB(cake).inflate(8.0), GoobyEntity::isBaby).size() == 1,
                "Cooldown-Versuch erzeugte ein zweites Baby");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Beide Eltern muessen bei ihrem jeweiligen Besitzer mindestens FRIEND sein. */
    @GameTest(template = ARENA)
    public static void ritual_requires_friend_tier(GameTestHelper helper) {
        placeFloor(helper);
        FakePlayer firstOwner = fakePlayer(helper, "family_owner_a");
        FakePlayer secondOwner = fakePlayer(helper, "family_owner_b");
        GoobyEntity first = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(1, 2, 2));
        GoobyEntity second = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 2));
        first.tame(firstOwner);
        second.tame(secondOwner);
        first.setFriendship(firstOwner.getUUID(), FriendshipTier.FRIEND.minimum());
        second.setFriendship(secondOwner.getUUID(), FriendshipTier.FRIEND.minimum() - 1);
        BlockPos cakeRel = new BlockPos(2, 2, 3);
        BlockPos cake = helper.absolutePos(cakeRel);
        helper.setBlock(cakeRel, ModBlocks.NUTELLA_CAKE.get());

        helper.assertFalse(NutellaCakeBlock.tryRitual(helper.getLevel(), cake, null),
                "Ritual akzeptierte einen Elternteil unter FRIEND");
        helper.assertTrue(helper.getLevel().getBlockState(cake).is(ModBlocks.NUTELLA_CAKE.get()),
                "Fehlgeschlagenes Ritual verbrauchte den Kuchen");
        helper.assertTrue(helper.getLevel().getEntitiesOfClass(GoobyEntity.class,
                new AABB(cake).inflate(8.0), GoobyEntity::isBaby).isEmpty(),
                "Ritual unter FRIEND erzeugte trotzdem Nachwuchs");
        helper.succeed();
    }

    /** Konfigurierter Startwert entspricht 1,5 Tagen; Vanilla-Age-Tick laesst das Baby erwachsen werden. */
    @GameTest(template = ARENA, timeoutTicks = 40)
    public static void baby_growth_timing(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity parent = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(1, 2, 2));
        GoobyEntity baby = parent.getBreedOffspring(helper.getLevel(), parent);
        helper.assertTrue(baby != null, "getBreedOffspring lieferte null");
        baby.moveTo(Vec3.atBottomCenterOf(helper.absolutePos(new BlockPos(3, 2, 2))));
        helper.getLevel().addFreshEntity(baby);
        helper.assertTrue(baby.getAge() == -GoobyConfig.familyGrowthTicks(),
                "Baby startete nicht mit konfigurierter 1,5-Tage-Wachstumszeit");

        baby.setAge(-2);
        helper.startSequence()
                .thenIdle(4)
                .thenExecute(() -> helper.assertFalse(baby.isBaby(),
                        "Vanilla-Age-Ticks liessen Baby nicht persistent erwachsen werden"))
                .thenSucceed();
    }

    /** Luft- und Direktpfiff ueberspringen Babys und waehlen einen erwachsenen Gooby. */
    @GameTest(template = ARENA)
    public static void baby_ignores_whistle(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(2.5, 2.0, 2.5));
        GoobyEntity baby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        baby.tame(owner);
        baby.setAge(-200);
        GoobyEntity adult = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(4, 2, 2));
        adult.tame(owner);
        baby.setCommandMode(GoobyCommand.WANDER);

        helper.assertTrue(GoobyWhistleItem.findNearestOwned(owner) == adult,
                "Luftpfiff waehlte das naehere Baby statt des Erwachsenen");
        baby.handleWhistle(owner);
        helper.assertTrue(baby.getCommandMode() == GoobyCommand.WANDER,
                "Direktpfiff aenderte den Baby-Kommandomodus");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Alter, beide Eltern und Familiennest ueberstehen einen vollstaendigen Entity-NBT-Roundtrip. */
    @GameTest(template = ARENA)
    public static void baby_persistence_roundtrip(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity baby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        UUID firstParent = UUID.randomUUID();
        UUID secondParent = UUID.randomUUID();
        BlockPos nest = helper.absolutePos(new BlockPos(3, 2, 3));
        baby.setAge(-12345);
        baby.setFamilyData(firstParent, secondParent, nest);

        CompoundTag saved = new CompoundTag();
        baby.saveWithoutId(saved);
        GoobyEntity reloaded = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 2));
        reloaded.load(saved);
        helper.assertTrue(reloaded.isBaby() && reloaded.getAge() == -12345,
                "Babyalter ging im Vanilla-NBT verloren: " + reloaded.getAge());
        helper.assertTrue(firstParent.equals(reloaded.getFirstParentUUID())
                        && secondParent.equals(reloaded.getSecondParentUUID()),
                "Eltern-UUIDs gingen im NBT verloren");
        helper.assertTrue(nest.equals(reloaded.getFamilyNestPos()), "Familiennest ging im NBT verloren");
        helper.succeed();
    }

    /** Vanilla-Futterzucht bleibt aus, waehrend der explizite Ritual-Nachwuchspfad implementiert ist. */
    @GameTest(template = ARENA)
    public static void no_vanilla_breeding_via_food(GameTestHelper helper) {
        GoobyEntity first = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(1, 2, 2));
        GoobyEntity second = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 2));
        helper.assertFalse(first.isFood(new ItemStack(ModItems.NUTELLA.get())),
                "Nutella aktivierte unerlaubte Vanilla-Zucht");
        helper.assertFalse(first.isFood(new ItemStack(Items.CARROT)),
                "Karotte aktivierte unerlaubte Vanilla-Zucht");
        GoobyEntity offspring = first.getBreedOffspring(helper.getLevel(), second);
        helper.assertTrue(offspring != null && offspring.isBaby(),
                "Expliziter Ritual-Nachwuchspfad ist nicht implementiert");
        helper.succeed();
    }

    /** Baby-Modell, Kuchen, vier Clips, Sounds und Familien-Advancement sind paketiert. */
    @GameTest(template = ARENA)
    public static void family_assets_complete(GameTestHelper helper) {
        JsonObject animations = loadAssetJson(helper, "assets/goobymod/animations/gooby.animation.json")
                .getAsJsonObject("animations");
        for (String clip : List.of("baby_hop", "baby_tumble", "parent_nuzzle", "grow_up_pop")) {
            helper.assertTrue(animations.has("animation.gooby." + clip), "Familien-Clip fehlt: " + clip);
        }
        loadAssetJson(helper, "assets/goobymod/geo/gooby_baby.geo.json");
        loadAssetJson(helper, "assets/goobymod/blockstates/nutella_cake.json");
        loadAssetJson(helper, "assets/goobymod/models/block/nutella_cake.json");
        loadAssetJson(helper, "data/goobymod/advancement/gooby_family.json");
        JsonObject sounds = loadAssetJson(helper, "assets/goobymod/sounds.json");
        for (String sound : List.of("entity.gooby.baby_squeak", "entity.gooby.nuzzle")) {
            helper.assertTrue(sounds.has(sound) && sounds.getAsJsonObject(sound).has("subtitle"),
                    "Familien-Sound/Untertitel fehlt: " + sound);
        }
        helper.assertTrue(GoobyGameTests.class.getClassLoader()
                        .getResource("assets/goobymod/textures/entity/gooby_baby.png") != null
                        && GoobyGameTests.class.getClassLoader()
                        .getResource("assets/goobymod/textures/block/nutella_cake_top.png") != null,
                "Baby- oder Nutella-Kuchen-Textur fehlt");
        helper.succeed();
    }

    /** All three synchronized wardrobe slots, including scarf RGB, survive entity NBT. */
    @GameTest(template = ARENA)
    public static void wardrobe_sync_and_persist(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(net.minecraft.world.level.GameType.SURVIVAL);
        GoobyEntity original = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        original.tame(owner);

        CraftingInput dyeInput = CraftingInput.of(2, 1, List.of(
                new ItemStack(ModItems.GOOBY_SCARF.get()), new ItemStack(Items.RED_DYE)));
        var dyeRecipe = helper.getLevel().getRecipeManager()
                .getRecipeFor(RecipeType.CRAFTING, dyeInput, helper.getLevel());
        helper.assertTrue(dyeRecipe.isPresent(), "Vanilla-Faerberezept erkannte den Gooby-Schal nicht");
        ItemStack recipeScarf = dyeRecipe.get().value().assemble(dyeInput, helper.getLevel().registryAccess());
        helper.assertTrue(GoobyWardrobe.color(recipeScarf) == DyeColor.RED.getTextureDiffuseColor(),
                "Vanilla-Faerberezept uebernahm die rote Farbe nicht");

        owner.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(Items.RED_CARPET));
        original.mobInteract(owner, InteractionHand.MAIN_HAND);
        ItemStack scarf = new ItemStack(ModItems.GOOBY_SCARF.get());
        scarf.set(DataComponents.DYED_COLOR, new DyedItemColor(0x2F6AC7, true));
        owner.setItemInHand(InteractionHand.MAIN_HAND, scarf);
        original.mobInteract(owner, InteractionHand.MAIN_HAND);
        owner.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(ModItems.TINY_SATCHEL.get()));
        original.mobInteract(owner, InteractionHand.MAIN_HAND);
        owner.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(Items.LIME_DYE));
        original.mobInteract(owner, InteractionHand.MAIN_HAND);

        helper.assertTrue(original.getHatStack().is(Items.RED_CARPET),
                "Head-Slot synchronisierte den tag-basierten Teppichhut nicht");
        helper.assertTrue(original.getNeckStack().is(ModItems.GOOBY_SCARF.get())
                        && GoobyWardrobe.color(original.getNeckStack()) == DyeColor.LIME.getTextureDiffuseColor(),
                "Neck-Slot verlor Item oder RGB");
        helper.assertTrue(original.getBackStack().is(ModItems.TINY_SATCHEL.get()),
                "Back-Slot synchronisierte die Tasche nicht");

        CompoundTag saved = new CompoundTag();
        original.saveWithoutId(saved);
        GoobyEntity reloaded = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 2));
        reloaded.load(saved);
        helper.assertTrue(reloaded.getHatStack().is(Items.RED_CARPET)
                        && reloaded.getNeckStack().is(ModItems.GOOBY_SCARF.get())
                        && reloaded.getBackStack().is(ModItems.TINY_SATCHEL.get()),
                "Mindestens ein Garderoben-Slot ging im NBT verloren");
        helper.assertTrue(GoobyWardrobe.color(reloaded.getNeckStack()) == DyeColor.LIME.getTextureDiffuseColor(),
                "Gefärbter Schal verlor sein RGB im NBT");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Flowers and carpets are accepted exclusively through the extensible hat item tag. */
    @GameTest(template = ARENA)
    public static void hat_tag_driven(GameTestHelper helper) {
        helper.assertTrue(GoobyEntity.isHatItem(new ItemStack(Items.AZURE_BLUET)),
                "Kleine Blume fehlt im Gooby-Hut-Tag");
        helper.assertTrue(GoobyEntity.isHatItem(new ItemStack(Items.RED_CARPET)),
                "Gefärbter Teppich fehlt im Gooby-Hut-Tag");
        helper.assertTrue(GoobyEntity.isHatItem(new ItemStack(ModItems.GOOBY_FLUFF.get())),
                "Gooby-Fussel fehlt im Gooby-Hut-Tag");
        helper.assertFalse(GoobyEntity.isHatItem(new ItemStack(Items.STICK)),
                "Nicht getaggter Gegenstand wurde weiterhin als Hut hardcodiert");
        helper.succeed();
    }

    /** Best-friend shimmer drop, four-fluff unlock, coat sync, cycling, and persistence. */
    @GameTest(template = ARENA)
    public static void coat_variant_unlock_and_persist(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(net.minecraft.world.level.GameType.SURVIVAL);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        gooby.setFriendship(owner.getUUID(), FriendshipTier.BEST_FRIEND.minimum());

        boolean shimmerRolled = false;
        RandomSource seeded = RandomSource.create(3900L);
        for (int attempt = 0; attempt < 512; attempt++) {
            if (gooby.createBrushDrop(owner, seeded).is(ModItems.SHIMMER_FLUFF.get())) {
                shimmerRolled = true;
                break;
            }
        }
        helper.assertTrue(shimmerRolled, "5%-Funkel-Fusselpfad war fuer BEST_FRIEND unerreichbar");

        owner.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(ModItems.SHIMMER_FLUFF.get(), 4));
        gooby.mobInteract(owner, InteractionHand.MAIN_HAND);
        helper.assertTrue(gooby.getCoatVariant() == GoobyCoatVariant.CREAM
                        && gooby.isCoatUnlocked(GoobyCoatVariant.CREAM),
                "Vier Funkel-Fussel schalteten das erste Fell nicht frei");

        CompoundTag saved = new CompoundTag();
        gooby.saveWithoutId(saved);
        GoobyEntity reloaded = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 2));
        reloaded.load(saved);
        helper.assertTrue(reloaded.getCoatVariant() == GoobyCoatVariant.CREAM
                        && reloaded.isCoatUnlocked(GoobyCoatVariant.CREAM),
                "Fellvariante oder permanente Freischaltung ging im NBT verloren");

        owner.setShiftKeyDown(true);
        owner.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(ModItems.GOOBY_BRUSH.get()));
        reloaded.mobInteract(owner, InteractionHand.MAIN_HAND);
        owner.setShiftKeyDown(false);
        helper.assertTrue(reloaded.getCoatVariant() == GoobyCoatVariant.CLASSIC,
                "Schleich-Buersten wechselte nicht zur naechsten freigeschalteten Fellvariante");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** One owner shear action returns every equipped accessory and clears all slots. */
    @GameTest(template = ARENA)
    public static void shears_strip_all_slots(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(net.minecraft.world.level.GameType.SURVIVAL);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        for (ItemStack accessory : List.of(
                new ItemStack(Items.POPPY),
                new ItemStack(ModItems.GOOBY_BOWTIE.get()),
                new ItemStack(ModItems.TINY_SATCHEL.get()))) {
            owner.setItemInHand(InteractionHand.MAIN_HAND, accessory);
            gooby.mobInteract(owner, InteractionHand.MAIN_HAND);
        }
        helper.assertTrue(gooby.hasHat()
                        && gooby.getNeckStack().is(ModItems.GOOBY_BOWTIE.get())
                        && gooby.getBackStack().is(ModItems.TINY_SATCHEL.get()),
                "Test-Outfit wurde vor dem Scheren nicht vollstaendig ausgeruestet");
        owner.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(Items.SHEARS));
        gooby.mobInteract(owner, InteractionHand.MAIN_HAND);

        helper.assertFalse(gooby.hasWardrobe(), "Schere liess mindestens einen Garderoben-Slot belegt");
        int drops = helper.getLevel().getEntitiesOfClass(ItemEntity.class,
                gooby.getBoundingBox().inflate(3.0)).stream()
                .mapToInt(item -> item.getItem().getCount()).sum();
        helper.assertTrue(drops == 3, "Schere gab nicht exakt alle drei Accessoires zurueck: " + drops);
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Compile-only Curios integration remains dormant and data-only when the mod is absent. */
    @GameTest(template = ARENA)
    public static void curios_absent_no_crash(GameTestHelper helper) {
        helper.assertFalse(CuriosCompat.isLoaded(), "Default-CI enthielt unerwartet Curios");
        JsonObject charmTag = loadAssetJson(helper, "data/curios/tags/item/charm.json");
        helper.assertTrue(charmTag.getAsJsonArray("values").toString().contains("goobymod:gooby_whistle"),
                "Curios-Charm-Tag enthaelt die Gooby-Pfeife nicht");
        helper.assertTrue(new ItemStack(ModItems.GOOBY_WHISTLE.get()).is(ModItems.GOOBY_WHISTLE.get()),
                "Pfeife konnte ohne Curios nicht instanziiert werden");
        helper.succeed();
    }

    /** 3D attachments, recipes, recolors, sound, advancement, and tint assets ship together. */
    @GameTest(template = ARENA)
    public static void fashion_assets_complete(GameTestHelper helper) {
        for (String path : List.of(
                "assets/goobymod/geo/scarf.geo.json",
                "assets/goobymod/geo/satchel.geo.json",
                "assets/goobymod/models/item/gooby_scarf.json",
                "assets/goobymod/models/item/gooby_bowtie.json",
                "assets/goobymod/models/item/tiny_satchel.json",
                "data/goobymod/recipe/gooby_scarf.json",
                "data/goobymod/recipe/gooby_bowtie.json",
                "data/goobymod/recipe/tiny_satchel.json",
                "data/goobymod/advancement/full_outfit.json",
                "data/goobymod/tags/item/gooby_hats.json",
                "data/minecraft/tags/item/dyeable.json")) {
            loadAssetJson(helper, path);
        }
        JsonObject sounds = loadAssetJson(helper, "assets/goobymod/sounds.json");
        helper.assertTrue(sounds.getAsJsonObject("entity.gooby.dress_up").has("subtitle"),
                "Dress-up-Sound oder Untertitel fehlt");
        for (String texture : List.of("gooby_scarf.png", "gooby_bowtie.png", "tiny_satchel.png",
                "shimmer_fluff.png")) {
            helper.assertTrue(GoobyGameTests.class.getClassLoader().getResource(
                    "assets/goobymod/textures/item/" + texture) != null,
                    "Fashion-Itemtextur fehlt: " + texture);
        }
        for (String coat : List.of("gooby_cream.png", "gooby_cocoa.png", "gooby_spotted.png")) {
            helper.assertTrue(GoobyGameTests.class.getClassLoader().getResource(
                    "assets/goobymod/textures/entity/" + coat) != null,
                    "Felltextur fehlt: " + coat);
        }
        helper.succeed();
    }

    /** Default CI proves every Create feature is dormant without loading the typed bridge. */
    @GameTest(template = ARENA)
    public static void create_absent_all_features_dormant(GameTestHelper helper) {
        if (CreateCompat.isCreateLoaded()) {
            helper.succeed();
            return;
        }
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        helper.assertTrue(CreateCompat.integrationLevel() == CreateCompat.IntegrationLevel.DORMANT,
                "Fehlendes Create wurde nicht als DORMANT erkannt");
        helper.assertFalse(CreateCompat.trySeatGooby(gooby), "Sitzpfad war ohne Create aktiv");
        helper.assertFalse(CreateCompat.isOnContraption(gooby), "Konstruktionspfad war ohne Create aktiv");
        helper.assertFalse(CreateCompat.hasRunningMachineNearby(helper.getLevel(), gooby.blockPosition(), 5),
                "Maschinenkomfort war ohne Create aktiv");
        helper.assertTrue(helper.getLevel().getRecipeManager()
                        .byKey(ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "create/mixing_nutella"))
                        .isEmpty(),
                "Bedingtes Mixer-Rezept wurde ohne Create geladen");
        helper.assertTrue(new ItemStack(ModItems.EMPTY_JAR.get()).is(ModItems.EMPTY_JAR.get()),
                "Leeres Glas konnte ohne Create nicht instanziiert werden");
        helper.succeed();
    }

    /** v4.0 item, processing data, animation clips, and conditional recipes ship as one contract. */
    @GameTest(template = ARENA)
    public static void create_express_assets_complete(GameTestHelper helper) {
        loadAssetJson(helper, "assets/goobymod/models/item/empty_jar.json");
        loadAssetJson(helper, "data/goobymod/recipe/empty_jar.json");
        for (String recipe : List.of("mixing_nutella", "filling_nutella")) {
            JsonObject json = loadAssetJson(helper, "data/goobymod/recipe/create/" + recipe + ".json");
            helper.assertTrue(json.has("neoforge:conditions")
                            && json.getAsJsonArray("neoforge:conditions").toString()
                            .contains("\"modid\":\"create\""),
                    "Create-Rezept ist nicht mod-loaded-bedingt: " + recipe);
        }
        JsonObject animations = loadAssetJson(helper, "assets/goobymod/animations/gooby.animation.json")
                .getAsJsonObject("animations");
        for (String clip : List.of("seated_contraption_idle", "train_lean")) {
            helper.assertTrue(animations.has("animation.gooby." + clip),
                    "Create-Express-Animation fehlt: " + clip);
        }
        helper.assertTrue(GoobyGameTests.class.getClassLoader()
                        .getResource("assets/goobymod/textures/item/empty_jar.png") != null,
                "Textur fuer leeres Glas fehlt");
        helper.succeed();
    }

    /** Only unnamed natural Goobys despawn; every player-associated path remains persistent. */
    @GameTest(template = ARENA)
    public static void wild_despawn_rules(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity natural = ModEntities.GOOBY.get().create(helper.getLevel());
        helper.assertTrue(natural != null, "Natur-Gooby konnte nicht erzeugt werden");
        natural.moveTo(Vec3.atBottomCenterOf(helper.absolutePos(new BlockPos(1, 2, 1))));
        natural.finalizeSpawn(helper.getLevel(), helper.getLevel().getCurrentDifficultyAt(natural.blockPosition()),
                MobSpawnType.NATURAL, null);
        helper.getLevel().addFreshEntity(natural);
        helper.assertTrue(natural.isNaturallySpawnedWild() && natural.removeWhenFarAway(256.0),
                "Natuerlicher unbenannter Wild-Gooby darf nicht normal despawnen");
        helper.assertTrue(natural.getSatisfaction() == 70,
                "Natuerlicher Spawn erhielt nicht die vereinheitlichte Zufriedenheit");

        ServerPlayer owner = fakePlayer(helper, "wild-persistence-owner");
        natural.tame(owner);
        helper.assertFalse(natural.removeWhenFarAway(256.0),
                "Gezaehmter Natur-Gooby blieb despawnbar");

        Rabbit rabbit = helper.spawn(EntityType.RABBIT, new BlockPos(3, 2, 1));
        GoobyEntity converted = GoobyEntity.convertFromRabbit(rabbit, owner);
        helper.assertTrue(converted != null && converted.isPersistenceRequired()
                        && !converted.removeWhenFarAway(256.0),
                "Verwandelter Gooby wurde nicht persistent");

        GoobyEntity egg = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(1, 2, 3));
        egg.finalizeSpawn(helper.getLevel(), helper.getLevel().getCurrentDifficultyAt(egg.blockPosition()),
                MobSpawnType.SPAWN_EGG, null);
        helper.assertTrue(egg.getSatisfaction() == 70 && egg.isPersistenceRequired()
                        && !egg.removeWhenFarAway(256.0),
                "Spawn-Ei-Gooby ist nicht konsistent und persistent");
        helper.succeed();
    }

    /** A burrow resident immediately owns its chamber home and survives NBT reload. */
    @GameTest(template = ARENA)
    public static void burrow_gooby_has_home(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.markBurrowResident();
        helper.assertTrue(gooby.isBurrowResident() && gooby.getHomePos() != null
                        && gooby.getHomePos().equals(gooby.blockPosition()),
                "Bau-Gooby erhielt keinen Kammer-Heimatanker");
        helper.assertTrue(gooby.isPersistenceRequired() && !gooby.removeWhenFarAway(512.0),
                "Bau-Gooby ist nicht permanent");

        CompoundTag tag = new CompoundTag();
        gooby.addAdditionalSaveData(tag);
        GoobyEntity loaded = ModEntities.GOOBY.get().create(helper.getLevel());
        helper.assertTrue(loaded != null, "Reload-Gooby konnte nicht erzeugt werden");
        loaded.readAdditionalSaveData(tag);
        helper.assertTrue(loaded.isBurrowResident() && loaded.getHomePos() != null,
                "Bau-Heimat ging beim NBT-Roundtrip verloren");
        helper.succeed();
    }

    /** Wild Gooby starts shy; the first Nutella feed permanently clears that state. */
    @GameTest(template = ARENA)
    public static void shy_until_fed(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.finalizeSpawn(helper.getLevel(), helper.getLevel().getCurrentDifficultyAt(gooby.blockPosition()),
                MobSpawnType.NATURAL, null);
        helper.assertTrue(gooby.isShyWild() && !gooby.hasBeenFed(),
                "Natuerlicher Wild-Gooby startete nicht scheu");
        ServerPlayer player = fakePlayer(helper, "patient-explorer");
        gooby.eatNutella(player, new ItemStack(ModItems.NUTELLA.get()));
        helper.assertTrue(gooby.hasBeenFed() && !gooby.isShyWild() && gooby.isTame(),
                "Erste Fuetterung beendete Scheu und Zaehmung nicht");
        helper.succeed();
    }

    /** Loads and places the real burrow NBT, including its persistent resident entity. */
    @GameTest(template = ARENA_LARGE, timeoutTicks = 200)
    public static void burrow_structure_placement(GameTestHelper helper) {
        ResourceLocation id = ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID,
                "burrow/gooby_burrow");
        var template = helper.getLevel().getStructureManager().get(id);
        helper.assertTrue(template.isPresent(), "Gooby-Bau-NBT fehlt im StructureTemplateManager");
        helper.assertTrue(template.get().getSize().getX() == 9 && template.get().getSize().getZ() == 9,
                "Gooby-Bau hat nicht die erwartete 9x9-Grundflaeche");
        BlockPos origin = helper.absolutePos(new BlockPos(4, 2, 4));
        helper.assertTrue(template.get().placeInWorld(helper.getLevel(), origin, origin,
                        new StructurePlaceSettings(), RandomSource.create(410), 3),
                "Gooby-Bau konnte nicht headless platziert werden");
        for (String path : List.of(
                "data/goobymod/worldgen/structure/gooby_burrow.json",
                "data/goobymod/worldgen/template_pool/burrow/start_pool.json",
                "data/goobymod/worldgen/structure_set/gooby_burrows.json",
                "data/goobymod/neoforge/biome_modifier/add_wild_goobys.json",
                "data/goobymod/loot_table/chests/gooby_burrow.json")) {
            loadAssetJson(helper, path);
        }
        helper.startSequence()
                .thenIdle(2)
                .thenExecute(() -> {
                    AABB bounds = new AABB(Vec3.atLowerCornerOf(origin),
                            Vec3.atLowerCornerOf(origin.offset(9, 5, 9)));
                    List<GoobyEntity> residents = helper.getLevel().getEntitiesOfClass(GoobyEntity.class, bounds);
                    helper.assertTrue(residents.size() == 1, "Bau platzierte nicht exakt einen Gooby");
                    GoobyEntity resident = residents.getFirst();
                    helper.assertTrue(resident.isBurrowResident() && resident.getHomePos() != null,
                            "Platzierter Bau-Gooby besitzt keine Heimat");
                })
                .thenSucceed();
    }

    /** Initiator and partner publish opposite halves of one synchronized greeting handshake. */
    @GameTest(template = ARENA)
    public static void greeting_ritual_synchronizes(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity initiator = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        GoobyEntity mirror = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 2));
        mirror.setCustomName(Component.literal("Mochi"));
        helper.assertTrue(initiator.startGreetingRitual(mirror),
                "Sozialer Begruessungs-Handshake startete nicht");
        helper.assertTrue(initiator.getSocialAction() == GoobyEntity.SOCIAL_GREETING_INITIATOR
                        && mirror.getSocialAction() == GoobyEntity.SOCIAL_GREETING_MIRROR,
                "Initiator und Spiegel erhielten nicht beide Begruessungsphasen");
        helper.assertTrue(mirror.getUUID().equals(initiator.getSocialPartnerId())
                        && initiator.getUUID().equals(mirror.getSocialPartnerId()),
                "Begruessung synchronisierte Partner-UUIDs nicht");
        helper.assertTrue("Mochi".equals(initiator.getBubbleArgument()),
                "Benannter Flauschfreund fehlt als lokalisierter Bubble-Parameter");

        JsonObject animations = loadAssetJson(helper, "assets/goobymod/animations/gooby.animation.json")
                .getAsJsonObject("animations");
        for (String clip : List.of("greeting_bounce", "play_chase_lunge", "bow", "nap_huddle")) {
            helper.assertTrue(animations.has("animation.gooby." + clip),
                    "Sozial-Animation fehlt: " + clip);
        }
        loadAssetJson(helper, "assets/goobymod/font/icons.json");
        helper.assertTrue(GoobyGameTests.class.getClassLoader()
                        .getResource("assets/goobymod/textures/font/icons.png") != null,
                "Bubble-Iconatlas fehlt");
        helper.succeed();
    }

    /** Sacred STAY command prevents both participants from entering low-priority social movement. */
    @GameTest(template = ARENA)
    public static void social_never_overrides_stay(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity staying = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        GoobyEntity visitor = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 2));
        staying.setCommandMode(GoobyCommand.STAY);
        helper.assertFalse(staying.canStartSocialBehavior(),
                "Bleiben-Gooby meldete sich als sozial bewegungsbereit");
        helper.assertFalse(staying.startGreetingRitual(visitor),
                "Begruessung ueberschrieb das Bleiben-Kommando");
        helper.assertFalse(staying.startPlayChase(visitor, helper.getLevel().getGameTime()),
                "Fangspiel ueberschrieb das Bleiben-Kommando");
        helper.assertTrue(staying.getSocialAction() == GoobyEntity.SOCIAL_NONE,
                "Bleiben-Gooby erhielt trotzdem einen Sozialzustand");
        helper.succeed();
    }

    /** Play chase stops at 30 seconds and leaves a symmetric five-minute pair cooldown. */
    @GameTest(template = ARENA)
    public static void play_chase_terminates_and_cooldowns(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity first = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        GoobyEntity second = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 2));
        long now = helper.getLevel().getGameTime();
        helper.assertTrue(first.startSocialInteraction(second, now, true),
                "Produktions-Sozialauswahl startete bevorzugtes Fangspiel nicht");
        helper.assertTrue(first.getSocialAction() == GoobyEntity.SOCIAL_PLAY_CHASE
                        && first.canContinueSocialBehavior(),
                "Aktives Fangspiel verlor seine AI-Fortsetzungsbedingung");
        for (int tick = 0; tick < GoobyEntity.SOCIAL_CHASE_TICKS; tick++) {
            first.tickSocialStateForTest();
            second.tickSocialStateForTest();
        }
        helper.assertTrue(first.getSocialAction() == GoobyEntity.SOCIAL_NONE
                        && second.getSocialAction() == GoobyEntity.SOCIAL_NONE,
                "Fangspiel endete nicht nach exakt 600 Ticks");
        helper.assertTrue(first.isPlayChaseCoolingDown(second.getUUID(), now)
                        && second.isPlayChaseCoolingDown(first.getUUID(), now),
                "Fuenf-Minuten-Paarcooldown ist nicht symmetrisch");
        helper.assertFalse(first.startPlayChase(second, now + 100),
                "Fangspiel ignorierte den Paarcooldown");
        helper.succeed();
    }

    /** Three nearby sleepers grant the photo-op advancement to an observing player. */
    @GameTest(template = ARENA)
    public static void group_nap_advancement(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity first = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(1, 2, 2));
        GoobyEntity second = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        GoobyEntity third = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 2));
        first.setGoobySleeping(true);
        second.setGoobySleeping(true);
        third.setGoobySleeping(true);
        ServerPlayer player = TestPlayers.create(helper, new Vec3(2.5, 2.0, 4.5));
        helper.assertTrue(first.checkGroupNapAdvancement(helper.getLevel()),
                "Drei schlafende Goobys wurden nicht als Flauschhaufen erkannt");
        AdvancementHolder advancement = helper.getLevel().getServer().getAdvancements()
                .get(ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, GoobyAdvancements.GROUP_NAP));
        helper.assertTrue(advancement != null
                        && player.getAdvancements().getOrStartProgress(advancement).isDone(),
                "group_nap-Advancement wurde dem Beobachter nicht verliehen");
        TestPlayers.remove(helper, player);
        helper.succeed();
    }

    /** Two deliberate crouch presses inside one second trigger exactly one bow response. */
    @GameTest(template = ARENA)
    public static void bow_detection_window(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        ServerPlayer player = TestPlayers.create(helper, new Vec3(2.5, 2.0, 4.5));
        helper.assertFalse(gooby.recordSneakToggle(player, 100L, true),
                "Erster Schleichdruck loeste bereits eine Verbeugung aus");
        helper.assertTrue(gooby.recordSneakToggle(player, 119L, true),
                "Zweiter Schleichdruck im Ein-Sekunden-Fenster wurde nicht erkannt");
        helper.assertTrue(gooby.getBowReactionCount() == 1
                        && GoobySpeech.EMOTE_BOW.equals(gooby.getBubbleKey()),
                "Verbeugungsreaktion feuerte nicht exakt einmal");
        helper.assertFalse(gooby.recordSneakToggle(player, 150L, true)
                        || gooby.recordSneakToggle(player, 171L, true),
                "Schleichdruecke ausserhalb des Fensters erzeugten False Positive");
        TestPlayers.remove(helper, player);
        helper.succeed();
    }

    /** Four slots persist and only the owning player can construct or keep the menu open. */
    @GameTest(template = ARENA)
    public static void satchel_persistence_and_owner_gate(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        ServerPlayer stranger = TestPlayers.create(helper, new Vec3(3.5, 2.0, 1.5));
        owner.setGameMode(net.minecraft.world.level.GameType.SURVIVAL);
        GoobyEntity original = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        original.tame(owner);
        owner.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(ModItems.TINY_SATCHEL.get()));
        original.mobInteract(owner, InteractionHand.MAIN_HAND);
        original.satchelInventory().setItem(0, new ItemStack(Items.CARROT, 7));
        original.satchelInventory().setItem(3, new ItemStack(ModItems.GOOBY_FLUFF.get(), 2));
        helper.assertTrue(original.hasSatchel(), "Tasche wurde im Test nicht ausgeruestet");

        CompoundTag saved = new CompoundTag();
        original.saveWithoutId(saved);
        helper.assertTrue(saved.getList("SatchelInventory", net.minecraft.nbt.Tag.TAG_COMPOUND).size() == 2,
                "Tascheninventar schrieb nicht zwei belegte Slots ins NBT");
        GoobyEntity reloaded = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 2));
        reloaded.load(saved);
        helper.assertTrue(reloaded.hasSatchel(), "Ausgeruestete Tasche ging im NBT verloren");
        helper.assertTrue(reloaded.satchelInventory().getItem(0).is(Items.CARROT)
                        && reloaded.satchelInventory().getItem(0).getCount() == 7,
                "Karottenstapel ging im Taschen-NBT verloren: "
                        + reloaded.satchelInventory().getItem(0));
        helper.assertTrue(reloaded.satchelInventory().getItem(3).is(ModItems.GOOBY_FLUFF.get())
                        && reloaded.satchelInventory().getItem(3).getCount() == 2,
                "Fusselstapel ging im Taschen-NBT verloren: "
                        + reloaded.satchelInventory().getItem(3));
        helper.assertTrue(reloaded.canUseSatchel(owner)
                        && reloaded.createMenu(1, owner.getInventory(), owner) != null,
                "Besitzer konnte die Tasche nicht oeffnen");
        helper.assertFalse(reloaded.canUseSatchel(stranger)
                        || reloaded.createMenu(2, stranger.getInventory(), stranger) != null,
                "Fremder Spieler umging das Besitzer-Gate der Tasche");
        TestPlayers.remove(helper, owner);
        TestPlayers.remove(helper, stranger);
        helper.succeed();
    }

    /** A shown underground block is found by the bounded 24-block seek scan. */
    @GameTest(template = ARENA)
    public static void seek_finds_planted_target(GameTestHelper helper) {
        placeFloor(helper);
        BlockPos target = new BlockPos(4, 1, 2);
        helper.setBlock(target, Blocks.CHEST);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(net.minecraft.world.level.GameType.SURVIVAL);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(1, 2, 2));
        gooby.tame(owner);
        gooby.setFriendship(owner.getUUID(), FriendshipTier.FRIEND.minimum());
        ItemStack sample = new ItemStack(Items.CHEST);
        owner.setItemInHand(InteractionHand.MAIN_HAND, sample);
        owner.setItemInHand(InteractionHand.OFF_HAND, new ItemStack(ModItems.TRAINING_TREAT.get()));

        helper.assertTrue(gooby.tryStartSeek(owner, sample, helper.getLevel().getGameTime()),
                "Schnueffel & Such startete fuer Freund mit Happen nicht");
        helper.assertTrue(helper.absolutePos(target).equals(gooby.getSeekTarget()),
                "Suche fand nicht die gepflanzte unterirdische Truhe: " + gooby.getSeekTarget());
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Empty searches are still rate-limited, preventing repeated 24-block scans. */
    @GameTest(template = ARENA)
    public static void seek_respects_cooldown(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(net.minecraft.world.level.GameType.CREATIVE);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        gooby.setFriendship(owner.getUUID(), FriendshipTier.FRIEND.minimum());
        ItemStack sample = new ItemStack(Items.CARROT);
        owner.setItemInHand(InteractionHand.MAIN_HAND, sample);
        owner.setItemInHand(InteractionHand.OFF_HAND, new ItemStack(ModItems.TRAINING_TREAT.get()));
        long now = helper.getLevel().getGameTime();

        helper.assertFalse(gooby.tryStartSeek(owner, sample, now),
                "Leere Suche meldete unerwartet ein Ziel");
        long firstCooldown = gooby.getSeekCooldownUntil();
        helper.assertFalse(gooby.tryStartSeek(owner, sample, now + 1)
                        || gooby.getSeekCooldownUntil() != firstCooldown,
                "Such-Cooldown blockierte den zweiten Scan nicht");
        helper.assertFalse(gooby.tryStartSeek(owner, sample, firstCooldown),
                "Leere Suche nach Cooldown meldete unerwartet ein Ziel");
        helper.assertTrue(gooby.getSeekCooldownUntil() > firstCooldown,
                "Suche wurde nach Ablauf des Cooldowns nicht erneut zugelassen");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Dug gifts carry ten seconds of recipient-only pickup ownership. */
    @GameTest(template = ARENA)
    public static void gift_recipient_pickup_priority(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer recipient = TestPlayers.create(helper, new Vec3(2.5, 2.0, 3.5));
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(recipient);
        gooby.setFriendship(recipient.getUUID(), FriendshipTier.FRIEND.minimum());
        gooby.setGiftCharges(1);
        helper.assertTrue(gooby.tryGiveGift(RandomSource.create(4301L)),
                "Geladenes Geschenk wurde nicht erzeugt");
        List<ItemEntity> drops = helper.getLevel().getEntitiesOfClass(
                ItemEntity.class, gooby.getBoundingBox().inflate(3.0));
        helper.assertTrue(drops.size() == 1 && recipient.getUUID().equals(drops.getFirst().getTarget()),
                "Buddelgeschenk besitzt keine Empfaenger-Prioritaet");
        helper.assertTrue(drops.getFirst().getPersistentData()
                        .getLong(GoobyEntity.GIFT_PRIORITY_UNTIL_TAG)
                        == helper.getLevel().getGameTime() + GoobyEntity.GIFT_PICKUP_PRIORITY_TICKS,
                "Empfaenger-Prioritaet dauert nicht exakt zehn Sekunden");
        TestPlayers.remove(helper, recipient);
        helper.succeed();
    }

    /** A far-away recipient causes exactly one atomic satchel insert and no world drop. */
    @GameTest(template = ARENA_LARGE)
    public static void no_dupe_satchel_stash_cycle(GameTestHelper helper) {
        placeLargeFloor(helper, Blocks.DIRT);
        ServerPlayer recipient = TestPlayers.create(helper, new Vec3(15.5, 2.0, 15.5));
        recipient.setGameMode(net.minecraft.world.level.GameType.SURVIVAL);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(recipient);
        gooby.setFriendship(recipient.getUUID(), FriendshipTier.BEST_FRIEND.minimum());
        recipient.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(ModItems.TINY_SATCHEL.get()));
        gooby.mobInteract(recipient, InteractionHand.MAIN_HAND);
        gooby.setGiftCharges(1);

        helper.assertTrue(gooby.tryGiveGift(RandomSource.create(4302L)),
                "Fernes Geschenk wurde nicht in die Tasche verarbeitet");
        int stored = gooby.satchelInventory().getItems().stream().mapToInt(ItemStack::getCount).sum();
        int dropped = helper.getLevel().getEntitiesOfClass(
                ItemEntity.class, gooby.getBoundingBox().inflate(5.0)).stream()
                .mapToInt(item -> item.getItem().getCount()).sum();
        helper.assertTrue(stored == 1 && dropped == 0 && gooby.getGiftCharges() == 0,
                "Stash-Zyklus duplizierte oder verlor das Geschenk: stored=" + stored + ", dropped=" + dropped);
        helper.assertFalse(gooby.tryGiveGift(RandomSource.create(4303L)),
                "Zweiter Stash ohne Ladung/Cooldown wurde zugelassen");
        helper.assertTrue(gooby.satchelInventory().getItems().stream()
                        .mapToInt(ItemStack::getCount).sum() == 1,
                "Fehlgeschlagener zweiter Zyklus veraenderte den Tascheninhalt");
        TestPlayers.remove(helper, recipient);
        helper.succeed();
    }

    /** Seeded best-friend scrap rolls remain rare and all v4.3 assets are packaged. */
    @GameTest(template = ARENA)
    public static void map_scrap_drop_rate_bounds(GameTestHelper helper) {
        RandomSource random = RandomSource.create(4300L);
        int scraps = 0;
        for (int roll = 0; roll < 10_000; roll++) {
            if (GoobyEntity.rollsTreasureScrap(random, FriendshipTier.BEST_FRIEND)) {
                scraps++;
            }
        }
        helper.assertTrue(scraps >= 400 && scraps <= 600,
                "5%-Kartenfetzenrate verliess seeded Grenzen: " + scraps);
        helper.assertFalse(GoobyEntity.rollsTreasureScrap(
                        RandomSource.create(43L), FriendshipTier.FRIEND),
                "Nicht-BEST_FRIEND konnte Kartenfetzen wuerfeln");
        for (String path : List.of(
                "assets/goobymod/models/item/torn_map_scrap.json",
                "assets/goobymod/models/item/gooby_treasure_map.json",
                "data/goobymod/recipe/gooby_treasure_map.json",
                "data/goobymod/advancement/treasure_map_complete.json",
                "data/goobymod/advancement/satchel_full.json",
                "data/goobymod/worldgen/structure/gooby_treasure_cache.json",
                "data/goobymod/worldgen/template_pool/treasure_cache/start_pool.json",
                "data/goobymod/worldgen/structure_set/gooby_treasure_caches.json",
                "data/goobymod/loot_table/chests/gooby_treasure_cache.json")) {
            loadAssetJson(helper, path);
        }
        JsonObject animations = loadAssetJson(helper, "assets/goobymod/animations/gooby.animation.json")
                .getAsJsonObject("animations");
        for (String clip : List.of("sniff_seek", "dig_excited", "present_item")) {
            helper.assertTrue(animations.has("animation.gooby." + clip),
                    "Schatzsucher-Animation fehlt: " + clip);
        }
        helper.assertTrue(GoobyGameTests.class.getClassLoader()
                        .getResource("assets/goobymod/textures/gui/gooby_satchel.png") != null,
                "Taschen-GUI-Textur fehlt");
        helper.succeed();
    }

    /** The frozen addon view and all three lifecycle event payloads expose safe values. */
    @GameTest(template = ARENA)
    public static void addon_api_surface_and_events(GameTestHelper helper) {
        ServerPlayer owner = TestPlayers.create(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        gooby.setSatisfaction(73);
        gooby.setFriendship(owner.getUUID(), FriendshipTier.FRIEND.minimum());

        GoobyAccessor accessor = gooby;
        helper.assertTrue(owner.getUUID().equals(accessor.goobyOwnerId())
                        && accessor.goobySatisfaction() == 73
                        && accessor.goobyFriendshipTier(owner.getUUID()) == FriendshipTier.FRIEND,
                "Stabile GoobyAccessor-Sicht liefert falsche Werte");
        GoobyTameEvent tame = new GoobyTameEvent(gooby, owner);
        GoobyTierChangeEvent tier = new GoobyTierChangeEvent(
                gooby, owner, FriendshipTier.BUDDY, FriendshipTier.FRIEND);
        GoobyGiftEvent gift = new GoobyGiftEvent(gooby, owner, new ItemStack(Items.CARROT, 2), true);
        helper.assertTrue(tame.getGooby() == gooby && tame.getOwner() == owner
                        && tier.getPreviousTier() == FriendshipTier.BUDDY
                        && tier.getNewTier() == FriendshipTier.FRIEND
                        && gift.getGift().is(Items.CARROT) && gift.getGift().getCount() == 2
                        && gift.isStashed(),
                "Addon-Event-Payload ist nicht vollstaendig");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** LRU storage retains the owner plus at most 32 other relationships across save/load. */
    @GameTest(template = ARENA)
    public static void friendship_lru_is_bounded_and_owner_safe(GameTestHelper helper) {
        ServerPlayer owner = TestPlayers.create(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        gooby.setFriendship(owner.getUUID(), 77);
        UUID firstVisitor = new UUID(50L, 0L);
        for (int index = 0; index < 40; index++) {
            gooby.setFriendship(new UUID(50L, index), index + 1);
        }
        helper.assertTrue(gooby.getStoredFriendshipCount() == GoobyEntity.MAX_STORED_FRIENDSHIPS + 1,
                "Freundschafts-LRU ist nicht auf 32 plus Besitzer begrenzt: "
                        + gooby.getStoredFriendshipCount());
        helper.assertTrue(gooby.getFriendship(owner.getUUID()) == 77,
                "Besitzer wurde aus Freundschafts-LRU entfernt");
        helper.assertTrue(gooby.getFriendship(firstVisitor) == 0,
                "Aeltester Besucher wurde nicht per LRU entfernt");

        CompoundTag saved = new CompoundTag();
        gooby.saveWithoutId(saved);
        GoobyEntity loaded = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 2));
        loaded.load(saved);
        helper.assertTrue(loaded.getStoredFriendshipCount() == GoobyEntity.MAX_STORED_FRIENDSHIPS + 1
                        && loaded.getFriendship(owner.getUUID()) == 77,
                "Begrenzte Freundschaften ueberstanden Save/Load nicht");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Built-in pools have four lines and addons can register localized speech keys. */
    @GameTest(template = ARENA)
    public static void speech_pools_are_extensible_and_audited(GameTestHelper helper) {
        ResourceLocation testPool = ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "gametest_lts");
        if (!GoobyApi.speechPools().containsKey(testPool)) {
            GoobyApi.registerSpeechPool(testPool, List.of(
                    "bubble.goobymod.idle1", "bubble.goobymod.idle2",
                    "bubble.goobymod.idle3", "bubble.goobymod.idle4"));
        }
        helper.assertTrue(GoobyApi.GOOBY_HATS == de.sonic0810.goobymod.registry.ModItemTags.GOOBY_HATS,
                "API-Hut-Tag ist nicht der Laufzeit-Tag");
        helper.assertTrue(GoobyApi.addonSpeechKeys().size() >= 4,
                "Code-registrierter Sprachpool ist nicht aktiv");
        for (List<String> pool : List.of(
                GoobySpeech.RAIN, GoobySpeech.NIGHT, GoobySpeech.CAKE, GoobySpeech.GREET,
                GoobySpeech.PET, GoobySpeech.EAT, GoobySpeech.SAD, GoobySpeech.DIG,
                GoobySpeech.RIDE, GoobySpeech.GIFT, GoobySpeech.HUNGRY, GoobySpeech.LONELY,
                GoobySpeech.SLEEPY, GoobySpeech.SCARED, GoobySpeech.GREET_BUDDY,
                GoobySpeech.GREET_FRIEND, GoobySpeech.GREET_BEST_FRIEND,
                GoobySpeech.ANNIVERSARY, GoobySpeech.BABY, GoobySpeech.MACHINERY,
                GoobySpeech.CONTRAPTION_ARRIVAL, GoobySpeech.SHY, GoobySpeech.SOCIAL)) {
            helper.assertTrue(pool.size() >= 4, "Sprachpool hat weniger als vier Lines: " + pool);
        }
        helper.succeed();
    }

    /** Reduced-motion, render-distance LOD, handbook art, and whistle glyphs are deterministic. */
    @GameTest(template = ARENA)
    public static void accessibility_lod_and_handbook_assets(GameTestHelper helper) {
        helper.assertFalse(GoobyClientConfig.DEFAULT_REDUCED_MOTION
                        || GoobyClientConfig.DEFAULT_HIGH_CONTRAST_BUBBLES,
                "Barrierefreiheitsoptionen muessen opt-in sein");
        helper.assertTrue(GoobyEntity.shouldRunClientMicroAnimations(1, 24.0 * 24.0, false),
                "Micro-LOD deaktiviert sichtbaren Gooby");
        helper.assertFalse(GoobyEntity.shouldRunClientMicroAnimations(1, 24.0 * 24.0 + 1.0, false)
                        || GoobyEntity.shouldRunClientMicroAnimations(1, 1.0, true)
                        || GoobyEntity.shouldRunClientMicroAnimations(3, 1.0, false),
                "Micro-LOD ignoriert Distanz, Renderstatus oder Reduced Motion");
        helper.assertTrue(Set.of(
                        GoobyCommand.WANDER.icon(), GoobyCommand.FOLLOW.icon(), GoobyCommand.STAY.icon()).size() == 3,
                "Pfeifenmodi besitzen keine eindeutigen visuellen Glyphen");
        helper.assertTrue(GoobyHandbookItem.PAGE_COUNT == 16,
                "Fallback-Handbuch hat nicht sechzehn LTS-Seiten");
        for (int frame = 0; frame < 4; frame++) {
            helper.assertTrue(GoobyGameTests.class.getClassLoader().getResource(
                            "assets/goobymod/textures/gui/handbook/portrait_" + frame + ".png") != null,
                    "Animiertes Handbuch-Portrait fehlt: " + frame);
        }
        for (int chapter = 0; chapter < 8; chapter++) {
            helper.assertTrue(GoobyGameTests.class.getClassLoader().getResource(
                            "assets/goobymod/textures/gui/handbook/chapter_" + chapter + ".png") != null,
                    "Handbuch-Kapitelbild fehlt: " + chapter);
        }
        helper.succeed();
    }

    /** Periodic ambience is coalesced per dimension, chunk, and sound without unbounded state. */
    @GameTest(template = ARENA)
    public static void sound_limiter_coalesces_chunk_crowds(GameTestHelper helper) {
        GoobySoundLimiter.clear();
        ResourceLocation dimension = ResourceLocation.withDefaultNamespace("overworld");
        ResourceLocation sound = ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "entity.gooby.ambient");
        helper.assertTrue(GoobySoundLimiter.tryAcquire(dimension, 42L, sound, 100L, 20),
                "Erster Chunk-Sound wurde blockiert");
        helper.assertFalse(GoobySoundLimiter.tryAcquire(dimension, 42L, sound, 119L, 20),
                "Gleicher Chunk-Sound umging Cooldown");
        helper.assertTrue(GoobySoundLimiter.tryAcquire(dimension, 42L, sound, 120L, 20)
                        && GoobySoundLimiter.tryAcquire(dimension, 43L, sound, 120L, 20),
                "Sound-Limiter gab Ablauf oder Nachbarchunk nicht frei");
        helper.assertTrue(GoobySoundLimiter.trackedBucketCount() == 2,
                "Sound-Limiter erzeugte unerwartete Bucket-Anzahl");
        helper.assertTrue(GoobySoundLimiter.tryAcquire(dimension, 42L, sound, 1L, 20),
                "Zurueckgesetzte Weltzeit blieb an einem alten statischen Cooldown haengen");
        for (int index = 0; index < GoobySoundLimiter.MAX_BUCKETS + 32; index++) {
            GoobySoundLimiter.tryAcquire(dimension, 10_000L + index, sound, 200L, 20);
        }
        helper.assertTrue(GoobySoundLimiter.trackedBucketCount() == GoobySoundLimiter.MAX_BUCKETS,
                "Sound-Limiter ueberschritt sein Bucket-Limit: " + GoobySoundLimiter.trackedBucketCount());
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // Stabilitaets-Regressionen (v5.0.1 Hardening)
    // ------------------------------------------------------------------

    /**
     * Regression: in reinem Wasser-Terrain (Fluss/Ozean) erstickten Goobys, weil der
     * Notfall-Teleport Wasser kategorisch ablehnte. Der strikte Pass muss Wasser weiter
     * ablehnen, der Notnagel-Pass muss auf der Wasseroberflaeche aufsetzen.
     */
    @GameTest(template = ARENA)
    public static void escape_teleport_water_fallback(GameTestHelper helper) {
        placeFloor(helper);
        helper.setBlock(new BlockPos(3, 0, 3), Blocks.DIRT);
        helper.setBlock(new BlockPos(3, 1, 3), Blocks.WATER);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(1, 2, 1));
        BlockPos waterLanding = helper.absolutePos(new BlockPos(3, 2, 3));

        helper.assertFalse(gooby.escapeLandingForTest(waterLanding, false),
                "Strikter Pass akzeptierte eine Wasseroberflaeche als trockenes Land");
        helper.assertTrue(gooby.escapeLandingForTest(waterLanding, true),
                "Notnagel-Pass lehnte eine sichere Wasseroberflaeche ab");
        helper.assertTrue(gooby.blockPosition().equals(waterLanding),
                "Gooby landete nicht auf der Wasseroberflaeche: " + gooby.blockPosition());
        helper.assertTrue(gooby.isAlive() && !gooby.isInWall(),
                "Gooby ist nach der Wasserlandung nicht wohlauf");
        helper.succeed();
    }

    /** Ein im Fels eingeschlossener Gooby befreit sich per Notfall-Teleport, statt zu ersticken. */
    @GameTest(template = ARENA_LARGE)
    public static void escape_teleport_from_wall(GameTestHelper helper) {
        placeLargeFloor(helper, Blocks.DIRT);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(8, 2, 8));
        helper.setBlock(new BlockPos(8, 2, 8), Blocks.STONE);
        helper.setBlock(new BlockPos(8, 3, 8), Blocks.STONE);
        helper.assertTrue(gooby.isInWall(), "Testaufbau hat den Gooby nicht eingemauert");

        helper.assertTrue(gooby.teleportOutOfDanger(),
                "Eingemauerter Gooby fand keinen Notfall-Teleport");
        helper.assertTrue(gooby.isAlive() && !gooby.isInWall(),
                "Gooby steckt nach dem Notfall-Teleport weiterhin fest: " + gooby.blockPosition());
        helper.succeed();
    }

    /**
     * Regression: Emote-, Sozialcooldown- und Ritual-Maps wuchsen unbegrenzt mit jedem
     * je getroffenen Spieler/Partner (Speicherleck auf Langzeit-Servern).
     */
    @GameTest(template = ARENA)
    public static void transient_social_state_pruned(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        GoobyEntity partner = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 2));
        FakePlayer player = fakePlayer(helper, "emote_pruning");
        long now = helper.getLevel().getGameTime();

        gooby.recordSneakToggle(player, now, false);
        helper.assertTrue(gooby.startPlayChase(partner, now), "Fangspiel-Seed startete nicht");
        gooby.recordFamilyRitual(partner, now);
        int seeded = gooby.transientStateSizeForTest();
        helper.assertTrue(seeded >= 3, "Testaufbau erzeugte zu wenige transiente Eintraege: " + seeded);

        gooby.pruneTransientStateForTest(now + 1);
        helper.assertTrue(gooby.transientStateSizeForTest() == seeded,
                "Pruning entfernte noch gueltige Eintraege");

        long farFuture = now + GoobyConfig.familyRitualCooldown() + 1_000_000L;
        gooby.pruneTransientStateForTest(farFuture);
        helper.assertTrue(gooby.transientStateSizeForTest() == 0,
                "Abgelaufene transiente Eintraege wurden nicht entfernt: "
                        + gooby.transientStateSizeForTest());
        helper.succeed();
    }

    /** Player logout clears session maps immediately while persistent friendship remains. */
    @GameTest(template = ARENA)
    public static void transient_player_state_released_on_logout(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        FakePlayer player = fakePlayer(helper, "logout_cleanup");
        long now = helper.getLevel().getGameTime();

        gooby.recordSneakToggle(player, now, false);
        gooby.handleBareHandInteraction(player, now);
        gooby.hurt(helper.getLevel().damageSources().playerAttack(player), 1.0F);
        helper.assertTrue(gooby.transientStateSizeForTest() >= 3,
                "Testaufbau erzeugte keine transienten Spieler-Caches");
        int friendship = gooby.getFriendship(player.getUUID());

        gooby.removeTransientPlayerState(player.getUUID());
        helper.assertTrue(gooby.transientStateSizeForTest() == 0,
                "Logout liess transiente Spieler-Caches zurueck: " + gooby.transientStateSizeForTest());
        helper.assertTrue(gooby.getFriendship(player.getUUID()) == friendship && friendship > 0,
                "Logout entfernte persistenten Freundschaftsfortschritt");
        helper.succeed();
    }

    /** Corrupt or addon-authored NBT cannot inflate persistent relationship collections. */
    @GameTest(template = ARENA)
    public static void relationship_nbt_collections_are_hard_bounded(GameTestHelper helper) {
        GoobyEntity original = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        CompoundTag oversized = new CompoundTag();
        original.saveWithoutId(oversized);
        ListTag friendships = new ListTag();
        ListTag memories = new ListTag();
        ListTag rituals = new ListTag();
        ListTag social = new ListTag();
        long now = helper.getLevel().getGameTime();
        for (int index = 0; index < 512; index++) {
            UUID id = new UUID(91L, index);
            CompoundTag friend = new CompoundTag();
            friend.putUUID("UUID", id);
            friend.putInt("Value", index % 101);
            friendships.add(friend);
            CompoundTag memory = new CompoundTag();
            memory.putUUID("UUID", id);
            memories.add(memory);
            CompoundTag ritual = new CompoundTag();
            ritual.putUUID("Partner", id);
            ritual.putLong("Time", now + index);
            rituals.add(ritual);
            CompoundTag cooldown = new CompoundTag();
            cooldown.putUUID("Partner", id);
            cooldown.putLong("Until", now + 10_000L + index);
            social.add(cooldown);
        }
        oversized.put("Friendship", friendships);
        oversized.put("Memories", memories);
        oversized.put("FamilyRituals", rituals);
        oversized.put("SocialCooldowns", social);

        GoobyEntity loaded = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 2));
        loaded.load(oversized);
        CompoundTag bounded = new CompoundTag();
        loaded.saveWithoutId(bounded);
        helper.assertTrue(bounded.getList("Friendship", Tag.TAG_COMPOUND).size()
                        <= GoobyEntity.MAX_STORED_FRIENDSHIPS,
                "Uebergrosse Freundschaftsliste blieb ungebunden");
        helper.assertTrue(bounded.getList("Memories", Tag.TAG_COMPOUND).size()
                        <= GoobyEntity.MAX_STORED_FRIENDSHIPS,
                "Uebergrosse Erinnerungsliste blieb ungebunden");
        helper.assertTrue(bounded.getList("FamilyRituals", Tag.TAG_COMPOUND).size()
                        <= GoobyEntity.MAX_PARTNER_HISTORY_ENTRIES
                        && bounded.getList("SocialCooldowns", Tag.TAG_COMPOUND).size()
                        <= GoobyEntity.MAX_PARTNER_HISTORY_ENTRIES,
                "Persistente Partnerhistorie ueberschritt das Hard-Limit");
        helper.succeed();
    }

    /** Every ordinary crafting recipe has a discoverable recipe-book advancement. */
    @GameTest(template = ARENA)
    public static void recipe_unlocks_and_usage_tooltips_are_complete(GameTestHelper helper) {
        for (String recipe : List.of(
                "empty_jar", "gooby_bowtie", "gooby_brush", "gooby_handbook",
                "gooby_scarf", "gooby_treasure_map", "gooby_whistle", "gooby_wool",
                "nutella", "rabbit_hutch", "tiny_satchel", "training_treat")) {
            JsonObject unlock = loadAssetJson(
                    helper, "data/goobymod/advancement/recipes/" + recipe + ".json");
            helper.assertTrue(unlock.getAsJsonObject("rewards").getAsJsonArray("recipes").toString()
                            .contains("\"goobymod:" + recipe + "\""),
                    "Recipe-Book-Unlock fehlt oder zeigt auf das falsche Rezept: " + recipe);
        }
        JsonObject english = loadAssetJson(helper, "assets/goobymod/lang/en_us.json");
        JsonObject german = loadAssetJson(helper, "assets/goobymod/lang/de_de.json");
        for (String key : List.of(
                "tooltip.goobymod.nutella", "tooltip.goobymod.nutella.cake",
                "tooltip.goobymod.gooby_brush", "tooltip.goobymod.shimmer_fluff",
                "tooltip.goobymod.training_treat", "tooltip.goobymod.treasure_map")) {
            helper.assertTrue(english.has(key) && german.has(key),
                    "DE/EN-Nutzungstooltip fehlt: " + key);
        }
        helper.succeed();
    }

    /** Entity and block-entity sync strings reject oversized save/addon input. */
    @GameTest(template = ARENA)
    public static void synchronized_strings_are_packet_bounded(GameTestHelper helper) {
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.showBubble("k".repeat(2_000), "a".repeat(4_000));
        gooby.setNeckAccessoryData("n".repeat(2_000));
        helper.assertTrue(gooby.getBubbleKey().length() <= 128
                        && gooby.getBubbleArgument().length() <= 256
                        && gooby.getNeckAccessoryData().length() <= 128,
                "EntityData akzeptierte einen uebergrossen synchronisierten String");

        BlockPos hutchPos = new BlockPos(3, 2, 2);
        helper.setBlock(hutchPos, ModBlocks.RABBIT_HUTCH.get());
        RabbitHutchBlockEntity hutch = (RabbitHutchBlockEntity) helper.getLevel()
                .getBlockEntity(helper.absolutePos(hutchPos));
        hutch.bind(new UUID(92L, 1L), "r".repeat(2_000));
        helper.assertTrue(hutch.getResidentName().length() == RabbitHutchBlockEntity.MAX_RESIDENT_NAME_LENGTH,
                "Stall-Update-NBT akzeptierte einen uebergrossen Bewohnernamen");
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 30. v5.1.0 Interaktions-Politur
    // ------------------------------------------------------------------

    /** Klickspam-Streicheln wird nie zur Trick-Absage (Fremde und Untrainierte streicheln einfach weiter). */
    @GameTest(template = ARENA)
    public static void pet_spam_never_swallowed_by_trick_denial(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.setSatisfaction(10);
        FakePlayer stranger = fakePlayer(helper, "spam_petter");

        gooby.mobInteract(stranger, InteractionHand.MAIN_HAND);
        gooby.mobInteract(stranger, InteractionHand.MAIN_HAND);

        helper.assertTrue(gooby.getSatisfaction() == 10 + 2 * GoobyEntity.PET_SATISFACTION,
                "Zweiter Klick wurde verschluckt statt zu streicheln (Zufriedenheit: "
                        + gooby.getSatisfaction() + ")");
        helper.assertTrue(gooby.getPerformedTrickCount() == 0,
                "Fremder Klickspam loeste ein Kunststueck aus");
        helper.succeed();
    }

    /** Der Besitzer-Doppelklick fuehrt den trainierten Trick weiterhin aus — untrainiert bleibt es Streicheln. */
    @GameTest(template = ARENA)
    public static void owner_double_click_performs_trained_trick(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        gooby.tame(owner);
        gooby.setTrickProficiency(gooby.getSelectedTrick(), 1);

        long now = helper.getLevel().getGameTime();
        helper.assertFalse(gooby.handleBareHandInteraction(owner, now),
                "Erster Klick haette streicheln muessen");
        helper.assertTrue(gooby.handleBareHandInteraction(owner, now + 4),
                "Besitzer-Doppelklick fuehrte den trainierten Trick nicht aus");
        helper.assertTrue(gooby.getPerformedTrickCount() == 1,
                "Trainierter Doppelklick-Trick feuerte nicht genau einmal");

        gooby.setTrickProficiency(gooby.getSelectedTrick(), 0);
        gooby.handleBareHandInteraction(owner, now + 40);
        helper.assertFalse(gooby.handleBareHandInteraction(owner, now + 44),
                "Untrainierter Doppelklick haette streicheln muessen");
        helper.assertTrue(gooby.getPerformedTrickCount() == 1,
                "Untrainierter Doppelklick zaehlte faelschlich als Trick");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Buerste im Cooldown: keine Doppel-Drops und keine Doppel-Abnutzung, aber niemals ein stummer Klick. */
    @GameTest(template = ARENA)
    public static void brush_cooldown_no_double_drop(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        FakePlayer player = fakePlayer(helper, "brush_tester");
        ItemStack brush = new ItemStack(ModItems.GOOBY_BRUSH.get());
        player.setItemInHand(InteractionHand.MAIN_HAND, brush);

        gooby.mobInteract(player, InteractionHand.MAIN_HAND);
        gooby.mobInteract(player, InteractionHand.MAIN_HAND);

        helper.assertTrue(brush.getDamageValue() == 1,
                "Cooldown-Klick nutzte die Buerste ab (Schaden: " + brush.getDamageValue() + ")");
        List<ItemEntity> drops = helper.getLevel().getEntitiesOfClass(ItemEntity.class,
                gooby.getBoundingBox().inflate(6.0),
                drop -> drop.getItem().is(ModItems.GOOBY_FLUFF.get())
                        || drop.getItem().is(ModItems.SHIMMER_FLUFF.get()));
        helper.assertTrue(drops.size() == 1,
                "Buersten-Cooldown liess " + drops.size() + " Drops statt genau einem zu");
        drops.forEach(ItemEntity::discard);
        helper.succeed();
    }

    /** Externes Aufwecken (Streicheln/Fuettern) gibt die Flags des Zufalls-Sitz-Goals sofort frei. */
    @GameTest(template = ARENA)
    public static void random_sit_releases_after_wake(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        GoobyRandomSitGoal goal = new GoobyRandomSitGoal(gooby);
        goal.start();
        helper.assertTrue(gooby.isSitting(), "Sitz-Goal setzte den Sitz-Zustand nicht");
        helper.assertTrue(goal.canContinueToUse(), "Sitz-Goal lief nicht regulaer weiter");
        gooby.wakeUp();
        helper.assertFalse(goal.canContinueToUse(),
                "Sitz-Goal hielt nach dem Aufwecken die MOVE/JUMP-Flags fest (Freeze)");
        helper.succeed();
    }

    /** Scheue Wild-Goobys betteln nicht um Streicheleinheiten, waehrend sie vor Spielern fliehen. */
    @GameTest(template = ARENA)
    public static void shy_wild_not_open_to_players(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.finalizeSpawn(helper.getLevel(),
                helper.getLevel().getCurrentDifficultyAt(gooby.blockPosition()), MobSpawnType.NATURAL, null);
        helper.assertTrue(gooby.isShyWild(), "Setup: natuerlicher Wild-Gooby startete nicht scheu");
        helper.assertFalse(gooby.isOpenToPlayers(),
                "Scheuer Wild-Gooby bettelt weiterhin um Naehe, waehrend er flieht");

        FakePlayer player = fakePlayer(helper, "shy_feeder");
        gooby.eatNutella(player, new ItemStack(ModItems.NUTELLA.get()));
        helper.assertTrue(gooby.isOpenToPlayers(), "Gefuetterter Gooby blieb spielerscheu");
        helper.succeed();
    }

    /** Leere Haupthand + Pflegeitem in der Zweithand: Streicheln verschluckt das Item nicht mehr. */
    @GameTest(template = ARENA)
    public static void offhand_care_item_not_swallowed(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.setSatisfaction(10);
        FakePlayer player = fakePlayer(helper, "offhand_feeder");
        player.setItemInHand(InteractionHand.OFF_HAND, new ItemStack(ModItems.NUTELLA.get()));

        InteractionResult mainHand = gooby.mobInteract(player, InteractionHand.MAIN_HAND);
        helper.assertTrue(mainHand == InteractionResult.PASS,
                "Leere Haupthand reichte nicht an die Zweithand durch: " + mainHand);
        helper.assertTrue(gooby.getSatisfaction() == 10,
                "Der durchgereichte Haupthand-Klick streichelte trotzdem");

        InteractionResult offHand = gooby.mobInteract(player, InteractionHand.OFF_HAND);
        helper.assertTrue(offHand.consumesAction(), "Zweithand-Nutella wurde nicht ausgefuehrt");
        helper.assertTrue(gooby.isTame() && player.getUUID().equals(gooby.getOwnerUUID()),
                "Zweithand-Fuetterung zaehmte den Gooby nicht");
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 31. Persistenz-/Korrektheits-Wave: Fauna-Goals, volle Garderobe, Tod
    // ------------------------------------------------------------------

    private static long faunaGoalCount(Mob mob) {
        return mob.goalSelector.getAvailableGoals().stream()
                .filter(goal -> goal.getGoal() instanceof RabbitFollowWildGoobyGoal
                        || goal.getGoal() instanceof CatStareAtGoobyGoal)
                .count();
    }

    /** Transiente Fauna-Goals ueberleben Reloads: das Legacy-NBT-Flag darf die Injektion nicht blockieren. */
    @GameTest(template = ARENA)
    public static void fauna_goals_reinjected_after_reload(GameTestHelper helper) {
        placeFloor(helper);
        Rabbit fresh = helper.spawn(EntityType.RABBIT, new BlockPos(1, 2, 1));
        helper.assertTrue(faunaGoalCount(fresh) == 1,
                "Frischer Hase erhielt kein Wild-Gooby-Folge-Goal");

        // Legacy-Save simulieren: das Pre-5.1-Flag persistierte im NBT,
        // waehrend die Goals selbst beim Reload verloren gingen.
        Rabbit reloaded = EntityType.RABBIT.create(helper.getLevel());
        helper.assertTrue(reloaded != null, "Reload-Hase konnte nicht erzeugt werden");
        reloaded.getPersistentData().putBoolean("GoobyModFaunaGoals", true);
        reloaded.moveTo(helper.absoluteVec(new Vec3(3.5, 2.0, 3.5)));
        helper.getLevel().addFreshEntity(reloaded);
        helper.assertTrue(faunaGoalCount(reloaded) == 1,
                "Persistentes Legacy-Flag unterdrueckte die Goal-Injektion nach dem Reload");
        helper.assertFalse(reloaded.getPersistentData().contains("GoobyModFaunaGoals"),
                "Legacy-Flag wurde beim Join nicht aus dem NBT entfernt");

        // Idempotenz: doppelte Join-Pfade (z.B. Dimensionswechsel) stapeln keine Goals.
        helper.assertFalse(GoobyEvents.injectFaunaGoals(reloaded),
                "Erneute Injektion meldete faelschlich ein neues Goal");
        helper.assertTrue(faunaGoalCount(reloaded) == 1,
                "Goal-Injektion ist nicht idempotent: " + faunaGoalCount(reloaded));

        Cat cat = helper.spawn(EntityType.CAT, new BlockPos(3, 2, 1));
        helper.assertTrue(faunaGoalCount(cat) == 1, "Katze erhielt kein Starr-Goal");
        helper.assertFalse(GoobyEvents.injectFaunaGoals(cat),
                "Katzen-Injektion ist nicht idempotent");
        helper.assertTrue(faunaGoalCount(cat) == 1,
                "Katzen-Goal wurde doppelt gestapelt: " + faunaGoalCount(cat));
        helper.succeed();
    }

    /** Garderobe persistiert komplette ItemStacks (Name, Verzauberung, Components) und migriert Legacy-Saves. */
    @GameTest(template = ARENA)
    public static void wardrobe_full_itemstack_roundtrip_and_migration(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(net.minecraft.world.level.GameType.SURVIVAL);
        GoobyEntity original = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        original.tame(owner);

        ItemStack fancyHat = new ItemStack(Items.POPPY);
        fancyHat.set(DataComponents.CUSTOM_NAME, Component.literal("Sonntagshut"));
        fancyHat.enchant(helper.getLevel().registryAccess()
                .registryOrThrow(Registries.ENCHANTMENT).getHolderOrThrow(Enchantments.UNBREAKING), 2);
        ItemStack expectedHat = fancyHat.copyWithCount(1);
        owner.setItemInHand(InteractionHand.MAIN_HAND, fancyHat);
        original.mobInteract(owner, InteractionHand.MAIN_HAND);

        ItemStack namedScarf = new ItemStack(ModItems.GOOBY_SCARF.get());
        namedScarf.set(DataComponents.CUSTOM_NAME, Component.literal("Omas Schal"));
        namedScarf.set(DataComponents.DYED_COLOR, new DyedItemColor(0x2F6AC7, true));
        ItemStack expectedScarf = namedScarf.copyWithCount(1);
        owner.setItemInHand(InteractionHand.MAIN_HAND, namedScarf);
        original.mobInteract(owner, InteractionHand.MAIN_HAND);

        helper.assertTrue(ItemStack.matches(expectedHat, original.getHatStack()),
                "Server-Slot verlor Custom-Components direkt nach dem Ausruesten");

        CompoundTag saved = new CompoundTag();
        original.saveWithoutId(saved);
        // saveWithoutId schreibt das UUID-Tag mit — entfernen, damit die
        // Reload-Kopien keine Duplikat-UUIDs im Test-Level erzeugen.
        saved.remove("UUID");
        helper.assertTrue(saved.getCompound("WardrobeItems").contains("Head")
                        && saved.getCompound("WardrobeItems").contains("Neck"),
                "Volles WardrobeItems-NBT fehlt im Save");
        GoobyEntity reloaded = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 2));
        reloaded.load(saved);
        helper.assertTrue(ItemStack.matches(expectedHat, reloaded.getHatStack()),
                "Hut verlor Custom Name/Verzauberung im NBT-Roundtrip");
        helper.assertTrue(ItemStack.matches(expectedScarf, reloaded.getNeckStack()),
                "Schal verlor Custom Name oder Farbe im NBT-Roundtrip");
        helper.assertTrue("Sonntagshut".equals(reloaded.getHatStack().getHoverName().getString()),
                "Custom Name des Huts kam nicht zurueck: " + reloaded.getHatStack().getHoverName().getString());

        // Legacy-Save (nur Wire-Strings, kein WardrobeItems): Item + Farbe
        // ueberleben die Migration als Basis-Stacks.
        saved.remove("WardrobeItems");
        GoobyEntity legacy = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(1, 2, 3));
        legacy.load(saved);
        helper.assertTrue(legacy.getHatStack().is(Items.POPPY),
                "Legacy-Migration verlor das Hut-Item");
        // color() liefert seit 1.21.1 opake ARGB-Werte — nur die RGB-Bits vergleichen.
        helper.assertTrue(legacy.getNeckStack().is(ModItems.GOOBY_SCARF.get())
                        && (GoobyWardrobe.color(legacy.getNeckStack()) & 0xFFFFFF) == 0x2F6AC7,
                "Legacy-Migration verlor Schal-Item oder RGB: wire='" + legacy.getNeckAccessoryData()
                        + "', color=" + Integer.toHexString(GoobyWardrobe.color(legacy.getNeckStack())));
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Die Schere gibt den kompletten Custom-Stack zurueck (Name + Verzauberung), nicht nur das Basis-Item. */
    @GameTest(template = ARENA)
    public static void wardrobe_drop_preserves_custom_stack(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(net.minecraft.world.level.GameType.SURVIVAL);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);

        ItemStack keepsake = new ItemStack(Items.POPPY);
        keepsake.set(DataComponents.CUSTOM_NAME, Component.literal("Erbstueck"));
        keepsake.enchant(helper.getLevel().registryAccess()
                .registryOrThrow(Registries.ENCHANTMENT).getHolderOrThrow(Enchantments.UNBREAKING), 1);
        ItemStack expected = keepsake.copyWithCount(1);
        owner.setItemInHand(InteractionHand.MAIN_HAND, keepsake);
        gooby.mobInteract(owner, InteractionHand.MAIN_HAND);
        helper.assertTrue(gooby.hasHat(), "Custom-Hut wurde nicht ausgeruestet");

        owner.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(Items.SHEARS));
        gooby.mobInteract(owner, InteractionHand.MAIN_HAND);

        List<ItemEntity> drops = helper.getLevel().getEntitiesOfClass(ItemEntity.class,
                gooby.getBoundingBox().inflate(4.0), item -> item.getItem().is(Items.POPPY));
        helper.assertTrue(drops.size() == 1,
                "Schere gab nicht exakt einen Hut zurueck: " + drops.size());
        helper.assertTrue(ItemStack.matches(expected, drops.get(0).getItem()),
                "Abgelegter Hut verlor Custom Name oder Verzauberung");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /** Auch mit doMobLoot=false rettet ein erzwungener Tod das komplette Outfit samt Tascheninhalt. */
    @GameTest(template = ARENA)
    public static void outfit_and_satchel_survive_forced_death_without_mob_loot(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(net.minecraft.world.level.GameType.SURVIVAL);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        ItemStack luckyHat = new ItemStack(Items.POPPY);
        luckyHat.set(DataComponents.CUSTOM_NAME, Component.literal("Glueckshut"));
        for (ItemStack accessory : List.of(luckyHat,
                new ItemStack(ModItems.GOOBY_BOWTIE.get()),
                new ItemStack(ModItems.TINY_SATCHEL.get()))) {
            owner.setItemInHand(InteractionHand.MAIN_HAND, accessory);
            gooby.mobInteract(owner, InteractionHand.MAIN_HAND);
        }
        gooby.satchelInventory().setItem(0, new ItemStack(Items.CARROT, 5));
        helper.assertTrue(gooby.hasWardrobe() && gooby.hasSatchel(),
                "Test-Outfit wurde nicht vollstaendig ausgeruestet");
        AABB area = gooby.getBoundingBox().inflate(4.0);

        var mobLoot = helper.getLevel().getGameRules().getRule(net.minecraft.world.level.GameRules.RULE_DOMOBLOOT);
        boolean lootBefore = mobLoot.get();
        mobLoot.set(false, helper.getLevel().getServer());
        try {
            gooby.hurt(helper.getLevel().damageSources().genericKill(), Float.MAX_VALUE);
        } finally {
            mobLoot.set(lootBefore, helper.getLevel().getServer());
        }

        helper.assertTrue(gooby.isDeadOrDying(), "Generic-kill toetete den Test-Gooby nicht");
        List<ItemEntity> hats = helper.getLevel().getEntitiesOfClass(ItemEntity.class, area,
                item -> item.getItem().is(Items.POPPY));
        helper.assertTrue(hats.size() == 1
                        && "Glueckshut".equals(hats.get(0).getItem().getHoverName().getString()),
                "Erzwungener Tod ohne doMobLoot verschluckte den benannten Hut");
        helper.assertTrue(!helper.getLevel().getEntitiesOfClass(ItemEntity.class, area,
                        item -> item.getItem().is(ModItems.GOOBY_BOWTIE.get())).isEmpty(),
                "Fliege ging beim erzwungenen Tod verloren");
        helper.assertTrue(!helper.getLevel().getEntitiesOfClass(ItemEntity.class, area,
                        item -> item.getItem().is(ModItems.TINY_SATCHEL.get())).isEmpty(),
                "Tasche ging beim erzwungenen Tod verloren");
        int carrots = helper.getLevel().getEntitiesOfClass(ItemEntity.class, area,
                        item -> item.getItem().is(Items.CARROT)).stream()
                .mapToInt(item -> item.getItem().getCount()).sum();
        helper.assertTrue(carrots == 5,
                "Tascheninhalt ging beim erzwungenen Tod verloren: " + carrots + "/5 Karotten");
        helper.assertTrue(gooby.satchelInventory().isEmpty(),
                "Tascheninventar wurde nach dem Drop nicht geleert");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /**
     * Normaler Tod (doMobLoot=true): der Outfit-Drop laeuft durchs
     * LivingDropsEvent (Grave-/Loot-Mods sehen ihn) und der doppelte
     * dropWardrobe-Aufruf (Normal- + Rettungspfad) dupliziert nichts.
     */
    @GameTest(template = ARENA)
    public static void wardrobe_death_drops_via_living_drops_event_once(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(net.minecraft.world.level.GameType.SURVIVAL);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        ItemStack hat = new ItemStack(Items.POPPY);
        hat.set(DataComponents.CUSTOM_NAME, Component.literal("Einzelstueck"));
        owner.setItemInHand(InteractionHand.MAIN_HAND, hat);
        gooby.mobInteract(owner, InteractionHand.MAIN_HAND);
        helper.assertTrue(gooby.hasHat(), "Hut wurde nicht ausgeruestet");
        AABB area = gooby.getBoundingBox().inflate(4.0);

        List<ItemStack> eventDrops = new ArrayList<>();
        Consumer<LivingDropsEvent> listener = event -> {
            if (event.getEntity() == gooby) {
                event.getDrops().forEach(drop -> eventDrops.add(drop.getItem().copy()));
            }
        };
        NeoForge.EVENT_BUS.addListener(LivingDropsEvent.class, listener);
        try {
            gooby.hurt(helper.getLevel().damageSources().genericKill(), Float.MAX_VALUE);
        } finally {
            NeoForge.EVENT_BUS.unregister(listener);
        }

        helper.assertTrue(gooby.isDeadOrDying(), "Generic-kill toetete den Test-Gooby nicht");
        helper.assertTrue(eventDrops.stream().anyMatch(drop -> drop.is(Items.POPPY)),
                "Outfit-Drop war fuer LivingDropsEvent-Listener (Grave-Mods) unsichtbar");
        List<ItemEntity> hats = helper.getLevel().getEntitiesOfClass(ItemEntity.class, area,
                item -> item.getItem().is(Items.POPPY));
        helper.assertTrue(hats.size() == 1,
                "Outfit-Drop wurde dupliziert oder verschluckt: " + hats.size());
        helper.assertTrue("Einzelstueck".equals(hats.get(0).getItem().getHoverName().getString()),
                "Custom Name ging beim Todes-Drop verloren");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    /**
     * Deinstallierter Fremd-Mod: unparsebare Accessoire-NBT wird konserviert
     * statt vernichtet — Wire-Id und rohes WardrobeItems-Tag ueberstehen den
     * kompletten Load/Save-Roundtrip ohne den Mod.
     */
    @GameTest(template = ARENA)
    public static void wardrobe_unknown_accessory_id_survives_reload(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        CompoundTag saved = new CompoundTag();
        gooby.saveWithoutId(saved);
        saved.remove("UUID");
        saved.putString("Hat", "fakemod:unobtainium_hat");
        CompoundTag head = new CompoundTag();
        head.putString("id", "fakemod:unobtainium_hat");
        head.putInt("count", 1);
        CompoundTag wardrobeItems = new CompoundTag();
        wardrobeItems.put("Head", head);
        saved.put("WardrobeItems", wardrobeItems);

        GoobyEntity reloaded = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 2));
        reloaded.load(saved);
        helper.assertTrue(reloaded.getHatStack().isEmpty(),
                "Unbekannte Item-Id darf keinen nutzbaren Stack ergeben");
        helper.assertTrue("fakemod:unobtainium_hat".equals(reloaded.getHatItemId()),
                "Legacy-Wire-String wurde beim Load ueberschrieben: '" + reloaded.getHatItemId() + "'");

        CompoundTag resaved = new CompoundTag();
        reloaded.saveWithoutId(resaved);
        helper.assertTrue("fakemod:unobtainium_hat".equals(resaved.getString("Hat")),
                "Wire-Id ging beim Re-Save verloren");
        helper.assertTrue("fakemod:unobtainium_hat".equals(
                        resaved.getCompound("WardrobeItems").getCompound("Head").getString("id")),
                "Rohes WardrobeItems-NBT wurde nicht konserviert");

        // Explizites Abstreifen per Schere raeumt auch das konservierte NBT ab
        // — sonst wuerde der Hut nach Mod-Reinstall wieder auftauchen, obwohl
        // der Spieler den Slot sichtbar geleert hat.
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(net.minecraft.world.level.GameType.SURVIVAL);
        reloaded.tame(owner);
        owner.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(Items.SHEARS));
        reloaded.mobInteract(owner, InteractionHand.MAIN_HAND);
        CompoundTag afterShear = new CompoundTag();
        reloaded.saveWithoutId(afterShear);
        helper.assertTrue(afterShear.getString("Hat").isEmpty(),
                "Schere leerte den Wire-String des unaufloesbaren Slots nicht");
        helper.assertFalse(afterShear.getCompound("WardrobeItems").contains("Head"),
                "Konserviertes NBT ueberlebte das explizite Abstreifen");
        TestPlayers.remove(helper, owner);
        helper.succeed();
    }
}
