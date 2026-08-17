package de.sonic0810.goobymod.gametest;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.mojang.authlib.GameProfile;
import de.sonic0810.goobymod.GoobyAdvancements;
import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.entity.GoobyCommand;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.entity.goals.GoobyFetchGoal;
import de.sonic0810.goobymod.item.GoobyBallItem;
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
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.entity.ai.goal.TemptGoal;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.item.component.DyedItemColor;
import net.minecraft.world.item.crafting.CraftingInput;
import net.minecraft.world.item.crafting.RecipeType;
import net.minecraft.world.level.GameType;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.common.util.FakePlayer;
import net.neoforged.neoforge.common.util.FakePlayerFactory;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * Apportier-Wave: Gooby-Ball-Item plus {@code GoobyFetchGoal}.
 *
 * <p>Abgedeckt: Wurf-Stack-Semantik (genau ein Ball pro Wurf, Creative
 * verbraucht nichts, Use-Cooldown blockt Spam), Owner-Isolation ueber die
 * ItemEntity-PersistentData, Merge-Isolation ueber das Wurf-Target
 * (Cross-Owner und tagged-vs-untagged mergen nie, Same-Owner schon —
 * inklusive Ball-fuer-Ball-Apport des gemergten Stacks), das komplette
 * Zustands-Gating des Goals (Baby/Sitz/Schlaf/Alarm/STAY/Leine/wild),
 * atomarer Pickup ohne Dupe bei zwei Goobys, Give-up-Blacklist fuer
 * unerreichbare Baelle (kein Sofort-Retry, Trage-Phase ohne Timeout),
 * DataComponent-treuer NBT-Roundtrip des Trage-Slots, Verlustfreiheit bei
 * Goal-Abbruch, Owner-Logout und Tod (beide Loot-Pfade, exakt EIN Drop),
 * Rueckgabe mit Empfaenger-Prioritaet + Belohnungs-Cooldown + Advancement,
 * Fetch-vs-Tempt-Prioritaet (laufende Lockung gewinnt, Apport startet nach
 * ihrem Ende), der mouth_anchor-/Asset-Vertrag (Geo, Modell, Textur,
 * Rezept, Lang) und der komplette End-to-End-Apport ueber die echte KI.</p>
 */
@GameTestHolder(GoobyMod.MODID)
@PrefixGameTestTemplate(false)
public class GoobyFetchWaveTests {
    private static final String ARENA = "arena";
    private static final String ARENA_LARGE = "arena_large";

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

    private static void placeLargeFloor(GameTestHelper helper) {
        for (int x = 0; x < 17; x++) {
            for (int z = 0; z < 17; z++) {
                helper.setBlock(new BlockPos(x, 1, z), Blocks.DIRT);
            }
        }
    }

    private static JsonObject loadAssetJson(GameTestHelper helper, String path) {
        try (InputStream stream = GoobyFetchWaveTests.class.getClassLoader().getResourceAsStream(path)) {
            helper.assertTrue(stream != null, "Asset fehlt im Runtime-Classpath: " + path);
            return JsonParser.parseReader(new InputStreamReader(stream, StandardCharsets.UTF_8)).getAsJsonObject();
        } catch (IOException | RuntimeException exception) {
            helper.fail("Asset kann nicht gelesen werden: " + path + " (" + exception.getMessage() + ")");
            return new JsonObject();
        }
    }

    private static List<ItemEntity> ballsIn(GameTestHelper helper, AABB area) {
        return helper.getLevel().getEntitiesOfClass(ItemEntity.class, area,
                item -> item.getItem().is(ModItems.GOOBY_BALL.get()));
    }

    /** Parkt eine geworfene Ball-Entity bewegungslos an einer festen Stelle. */
    private static void park(ItemEntity ball, Vec3 spot) {
        ball.moveTo(spot.x, spot.y, spot.z);
        ball.setDeltaMovement(Vec3.ZERO);
    }

    /** Rueckgabe angekommen: Ball mit Owner-Target neben dem Owner ODER schon eingesammelt. */
    private static boolean ballReturnedNearOwner(GameTestHelper helper, ServerPlayer owner) {
        boolean nearOwner = !helper.getLevel().getEntitiesOfClass(ItemEntity.class,
                new AABB(owner.blockPosition()).inflate(4.0),
                item -> item.getItem().is(ModItems.GOOBY_BALL.get())
                        && owner.getUUID().equals(item.getTarget())).isEmpty();
        return nearOwner || owner.getInventory().countItem(ModItems.GOOBY_BALL.get()) > 0;
    }

    /** Ball mit Custom-Name + Faerbung: DataComponent-Erhalt ist pruefbar. */
    private static ItemStack fancyBall(int count) {
        ItemStack stack = new ItemStack(ModItems.GOOBY_BALL.get(), count);
        stack.set(DataComponents.CUSTOM_NAME, Component.literal("Lieblingsball"));
        stack.set(DataComponents.DYED_COLOR, new DyedItemColor(0x2F6AC7, true));
        return stack;
    }

    // ------------------------------------------------------------------
    // 1. Wurf: Stack-Semantik + Owner-Signatur
    // ------------------------------------------------------------------

    /** Survival verbraucht GENAU 1; Creative nichts; ItemEntity traegt die Owner-UUID. */
    @GameTest(template = ARENA)
    public static void ball_throw_stack_semantics(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer thrower = TestPlayers.create(helper, new Vec3(2.5, 2.0, 2.5));
        thrower.setGameMode(GameType.SURVIVAL);

        ItemStack stack = fancyBall(3);
        ItemEntity ball = GoobyBallItem.throwBall(helper.getLevel(), thrower, stack);
        helper.assertTrue(stack.getCount() == 2, "Survival-Wurf muss genau 1 verbrauchen, Rest: " + stack.getCount());
        helper.assertTrue(ball.getItem().getCount() == 1, "Geworfene ItemEntity muss Count 1 haben");
        helper.assertTrue(ball.getItem().is(ModItems.GOOBY_BALL.get()), "Geworfene Entity ist kein Gooby-Ball");
        helper.assertTrue("Lieblingsball".equals(ball.getItem().getHoverName().getString()),
                "DataComponents (Custom-Name) gingen beim Wurf verloren");
        helper.assertTrue(thrower.getUUID().equals(GoobyBallItem.throwerOf(ball)),
                "Owner-UUID fehlt in den PersistentData der geworfenen Entity");
        helper.assertTrue(ball.hasPickUpDelay(), "Werfer-Pickup-Delay fehlt");
        helper.assertTrue(thrower.getUUID().equals(ball.getTarget()),
                "Wurf setzte kein Owner-Target (Merge-/Fremd-Pickup-Schutz fehlt)");
        helper.assertTrue(ball.getPersistentData().getLong(GoobyEntity.GIFT_PRIORITY_UNTIL_TAG)
                        == helper.getLevel().getGameTime() + GoobyBallItem.OWNER_PRIORITY_WINDOW_TICKS,
                "Owner-Prioritaetsfenster fehlt oder ist unbegrenzt");

        // Creative: Stack bleibt unangetastet, trotzdem genau eine Entity
        thrower.setGameMode(GameType.CREATIVE);
        ItemStack creativeStack = new ItemStack(ModItems.GOOBY_BALL.get(), 5);
        GoobyBallItem.throwBall(helper.getLevel(), thrower, creativeStack);
        helper.assertTrue(creativeStack.getCount() == 5, "Creative-Wurf darf den Stack nicht verkleinern");
        helper.assertTrue(ballsIn(helper, new AABB(thrower.blockPosition()).inflate(8.0)).size() == 2,
                "Zwei Wuerfe muessen exakt zwei ItemEntities erzeugen");

        TestPlayers.remove(helper, thrower);
        helper.succeed();
    }

    /** Der Use-Pfad wirft pro Cooldown-Fenster hoechstens einen Ball. */
    @GameTest(template = ARENA)
    public static void ball_use_cooldown_blocks_spam(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer thrower = TestPlayers.create(helper, new Vec3(2.5, 2.0, 2.5));
        thrower.setGameMode(GameType.SURVIVAL);
        thrower.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(ModItems.GOOBY_BALL.get(), 8));

        GoobyBallItem item = ModItems.GOOBY_BALL.get();
        helper.assertTrue(item.use(helper.getLevel(), thrower, InteractionHand.MAIN_HAND)
                .getResult().consumesAction(), "Erster Use-Wurf muss durchgehen");
        helper.assertTrue(thrower.getCooldowns().isOnCooldown(item), "Wurf setzte keinen Item-Cooldown");
        helper.assertFalse(item.use(helper.getLevel(), thrower, InteractionHand.MAIN_HAND)
                .getResult().consumesAction(), "Use-Spam im Cooldown-Fenster wurde nicht geblockt");

        AABB area = new AABB(thrower.blockPosition()).inflate(8.0);
        helper.assertTrue(ballsIn(helper, area).size() == 1,
                "Cooldown-Spam erzeugte mehr als eine ItemEntity");
        helper.assertTrue(thrower.getMainHandItem().getCount() == 7,
                "Use-Pfad verbrauchte nicht genau 1 Ball: " + thrower.getMainHandItem().getCount());

        TestPlayers.remove(helper, thrower);
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 2. Owner-Isolation
    // ------------------------------------------------------------------

    /** Nur Baelle des EIGENEN Besitzers zaehlen; fremde/ungeworfene nie. */
    @GameTest(template = ARENA)
    public static void ball_owner_isolation(GameTestHelper helper) {
        placeFloor(helper);
        FakePlayer owner = fakePlayer(helper, "fetch_owner");
        FakePlayer stranger = fakePlayer(helper, "fetch_stranger");
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        GoobyEntity wild = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(1, 2, 1));
        gooby.tame(owner);

        Vec3 spot = helper.absoluteVec(new Vec3(2.5, 2.0, 2.5));
        owner.moveTo(spot.x, spot.y, spot.z, 0.0F, 0.0F);
        stranger.moveTo(spot.x, spot.y, spot.z, 0.0F, 0.0F);

        ItemEntity own = GoobyBallItem.throwBall(helper.getLevel(), owner, new ItemStack(ModItems.GOOBY_BALL.get()));
        ItemEntity foreign = GoobyBallItem.throwBall(helper.getLevel(), stranger,
                new ItemStack(ModItems.GOOBY_BALL.get()));
        ItemEntity unthrown = new ItemEntity(helper.getLevel(), spot.x, spot.y, spot.z,
                new ItemStack(ModItems.GOOBY_BALL.get()));
        helper.getLevel().addFreshEntity(unthrown);
        // Kein Gooby-Ball, aber mit Owner-Tag: Item-Typ MUSS mitentscheiden
        ItemEntity carrot = new ItemEntity(helper.getLevel(), spot.x, spot.y, spot.z, new ItemStack(Items.CARROT));
        carrot.getPersistentData().putUUID(GoobyBallItem.BALL_OWNER_TAG, owner.getUUID());
        helper.getLevel().addFreshEntity(carrot);

        helper.assertTrue(gooby.isOwnFetchBall(own), "Eigener geworfener Ball wurde nicht erkannt");
        helper.assertFalse(gooby.isOwnFetchBall(foreign), "Fremder Ball wurde faelschlich akzeptiert");
        helper.assertFalse(gooby.isOwnFetchBall(unthrown), "Nicht geworfener Ball wurde faelschlich akzeptiert");
        helper.assertFalse(gooby.isOwnFetchBall(carrot), "Karotte mit Owner-Tag wurde als Ball akzeptiert");
        helper.assertTrue(GoobyBallItem.throwerOf(carrot) == null, "throwerOf akzeptierte ein Nicht-Ball-Item");
        helper.assertFalse(wild.isOwnFetchBall(own), "Wilder Gooby (ohne Besitzer) darf keine Baelle beanspruchen");
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 2b. Merge-Isolation: Wurf-Target blockt Fremd-/Untagged-Merges
    // ------------------------------------------------------------------

    /**
     * Vanilla-ItemEntity-Merging (alle 40 Ticks) darf die Owner-Signatur
     * weder uebertragen noch loeschen: Cross-Owner-Baelle und
     * tagged-vs-untagged bleiben getrennt (verschiedene Targets), Baelle
     * DESSELBEN Werfers mergen weiterhin zu einem Stack.
     */
    @GameTest(template = ARENA, timeoutTicks = 200)
    public static void ball_merge_owner_isolation(GameTestHelper helper) {
        placeFloor(helper);
        FakePlayer ownerA = fakePlayer(helper, "merge_owner_a");
        FakePlayer ownerB = fakePlayer(helper, "merge_owner_b");
        Vec3 center = helper.absoluteVec(new Vec3(2.5, 2.0, 2.5));
        ownerA.moveTo(center.x, center.y, center.z, 0.0F, 0.0F);
        ownerB.moveTo(center.x, center.y, center.z, 0.0F, 0.0F);

        Vec3 crossSpot = helper.absoluteVec(new Vec3(0.7, 2.1, 0.7));
        Vec3 plainSpot = helper.absoluteVec(new Vec3(4.3, 2.1, 0.7));
        Vec3 ownSpot = helper.absoluteVec(new Vec3(0.7, 2.1, 4.3));

        // Cross-Owner: je ein Ball von A und B auf demselben Fleck
        park(GoobyBallItem.throwBall(helper.getLevel(), ownerA,
                new ItemStack(ModItems.GOOBY_BALL.get(), 2)), crossSpot);
        park(GoobyBallItem.throwBall(helper.getLevel(), ownerB,
                new ItemStack(ModItems.GOOBY_BALL.get(), 2)), crossSpot);

        // Tagged vs. untagged: geworfener A-Ball neben einem Boden-Stack
        park(GoobyBallItem.throwBall(helper.getLevel(), ownerA,
                new ItemStack(ModItems.GOOBY_BALL.get(), 2)), plainSpot);
        ItemEntity plain = new ItemEntity(helper.getLevel(), plainSpot.x, plainSpot.y, plainSpot.z,
                new ItemStack(ModItems.GOOBY_BALL.get(), 4));
        plain.setDeltaMovement(Vec3.ZERO);
        helper.getLevel().addFreshEntity(plain);

        // Same-Owner: zwei A-Baelle auf demselben Fleck
        park(GoobyBallItem.throwBall(helper.getLevel(), ownerA,
                new ItemStack(ModItems.GOOBY_BALL.get(), 2)), ownSpot);
        park(GoobyBallItem.throwBall(helper.getLevel(), ownerA,
                new ItemStack(ModItems.GOOBY_BALL.get(), 2)), ownSpot);

        // Merge-Fenster (age % 40) zweimal verstreichen lassen
        helper.startSequence().thenExecuteAfter(90, () -> {
            List<ItemEntity> cross = ballsIn(helper, new AABB(crossSpot, crossSpot).inflate(1.2));
            helper.assertTrue(cross.size() == 2,
                    "Cross-Owner-Baelle duerfen NIE mergen, gefunden: " + cross.size());
            helper.assertTrue(cross.stream().allMatch(item -> item.getItem().getCount() == 1),
                    "Cross-Owner-Merge veraenderte einen Ball-Count");
            helper.assertTrue(cross.stream().anyMatch(
                            item -> ownerA.getUUID().equals(GoobyBallItem.throwerOf(item)))
                            && cross.stream().anyMatch(
                            item -> ownerB.getUUID().equals(GoobyBallItem.throwerOf(item))),
                    "Owner-Signaturen der Cross-Owner-Baelle gingen verloren");

            List<ItemEntity> plainArea = ballsIn(helper, new AABB(plainSpot, plainSpot).inflate(1.2));
            helper.assertTrue(plainArea.size() == 2,
                    "Tagged-vs-untagged darf NIE mergen, gefunden: " + plainArea.size());
            ItemEntity taggedSurvivor = plainArea.stream()
                    .filter(item -> GoobyBallItem.throwerOf(item) != null).findFirst().orElse(null);
            helper.assertTrue(taggedSurvivor != null
                            && ownerA.getUUID().equals(GoobyBallItem.throwerOf(taggedSurvivor))
                            && taggedSurvivor.getItem().getCount() == 1,
                    "Geworfener Ball verlor neben dem Boden-Stack seine Signatur");
            helper.assertTrue(plainArea.stream().anyMatch(
                            item -> GoobyBallItem.throwerOf(item) == null && item.getItem().getCount() == 4),
                    "Boden-Stack wurde durch den Signatur-Schutz veraendert");

            List<ItemEntity> own = ballsIn(helper, new AABB(ownSpot, ownSpot).inflate(1.2));
            helper.assertTrue(own.size() == 1 && own.getFirst().getItem().getCount() == 2,
                    "Same-Owner-Baelle muessen weiterhin zu einem Stack mergen");
            helper.assertTrue(ownerA.getUUID().equals(GoobyBallItem.throwerOf(own.getFirst())),
                    "Same-Owner-Merge verlor die Owner-Signatur");
        }).thenSucceed();
    }

    /**
     * Ein same-owner-gemergter Doppel-Stack wird Ball fuer Ball apportiert:
     * jeder Pickup nimmt atomar genau EINEN Ball, der Rest bleibt signiert
     * liegen; am Ende stimmt die Ball-Bilanz exakt (kein Dupe, kein Verlust).
     */
    @GameTest(template = ARENA, timeoutTicks = 200)
    public static void same_owner_merge_fetch_ball_by_ball(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(0.5, 2.0, 0.5));
        owner.setGameMode(GameType.SURVIVAL);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(4, 2, 4));
        gooby.tame(owner);
        // KI aus: der Test steuert Pickup/Lieferung direkt und deterministisch
        gooby.setNoAi(true);

        ItemStack hand = fancyBall(2);
        Vec3 spot = helper.absoluteVec(new Vec3(2.5, 2.1, 2.5));
        park(GoobyBallItem.throwBall(helper.getLevel(), owner, hand), spot);
        park(GoobyBallItem.throwBall(helper.getLevel(), owner, hand), spot);
        helper.assertTrue(hand.isEmpty(), "Zwei Wuerfe muessen den Zweier-Stack aufbrauchen");
        AABB arena = new AABB(spot, spot).inflate(8.0);

        helper.startSequence().thenExecuteAfter(90, () -> {
            List<ItemEntity> merged = ballsIn(helper, arena);
            helper.assertTrue(merged.size() == 1 && merged.getFirst().getItem().getCount() == 2,
                    "Same-Owner-Baelle mergten nicht zu einem Doppel-Stack");
            ItemEntity stack = merged.getFirst();
            helper.assertTrue(owner.getUUID().equals(GoobyBallItem.throwerOf(stack)),
                    "Owner-Signatur ging beim Same-Owner-Merge verloren");

            // 1. Apport: genau EIN Ball ins Maul, Rest bleibt signiert liegen
            helper.assertTrue(gooby.tryPickUpFetchBall(stack), "Pickup des gemergten Stacks schlug fehl");
            helper.assertTrue(gooby.getCarriedFetchItem().getCount() == 1,
                    "Maul-Slot muss genau EINEN Ball tragen");
            helper.assertTrue(stack.isAlive() && stack.getItem().getCount() == 1,
                    "Rest-Ball fehlt oder hat den falschen Count");
            helper.assertTrue(owner.getUUID().equals(GoobyBallItem.throwerOf(stack)),
                    "Rest-Ball verlor beim Teil-Pickup die Owner-Signatur");
            helper.assertTrue(gooby.deliverFetchBallTo(owner), "Erste Rueckgabe schlug fehl");

            // 2. Apport: der letzte Ball leert die Entity atomar
            helper.assertTrue(gooby.tryPickUpFetchBall(stack), "Pickup des Rest-Balls schlug fehl");
            helper.assertFalse(stack.isAlive(), "Geleerte Entity muss atomar verschwinden");
            helper.assertTrue(gooby.deliverFetchBallTo(owner), "Zweite Rueckgabe schlug fehl");
            helper.assertFalse(gooby.isCarryingFetchItem(), "Maul-Slot muss nach der Bilanz leer sein");

            int total = ballsIn(helper, arena).stream().mapToInt(item -> item.getItem().getCount()).sum()
                    + owner.getInventory().countItem(ModItems.GOOBY_BALL.get());
            helper.assertTrue(total == 2, "Ball-Bilanz nach Ball-fuer-Ball-Apport: " + total);
            TestPlayers.remove(helper, owner);
        }).thenSucceed();
    }

    // ------------------------------------------------------------------
    // 3. Goal-Gating
    // ------------------------------------------------------------------

    /** Baby/Sitz/Schlaf/Alarm/STAY/wild blockieren; der Normalzustand nicht. */
    @GameTest(template = ARENA)
    public static void fetch_goal_state_gating(GameTestHelper helper) {
        placeFloor(helper);
        FakePlayer owner = fakePlayer(helper, "gating_owner");
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));

        helper.assertFalse(GoobyFetchGoal.canWork(gooby), "Wilder Gooby darf nicht apportieren");
        gooby.tame(owner);
        gooby.setCommandMode(GoobyCommand.WANDER);
        helper.assertTrue(GoobyFetchGoal.canWork(gooby), "Zahmer erwachsener Gooby muss apportieren duerfen");

        gooby.setAge(-24000);
        helper.assertFalse(GoobyFetchGoal.canWork(gooby), "Baby darf das Feature nicht starten");
        // Baby darf einen (z. B. per Save geladenen) Ball trotzdem TRAGEN/zeigen
        gooby.setCarriedFetchItem(new ItemStack(ModItems.GOOBY_BALL.get()));
        helper.assertTrue(gooby.isCarryingFetchItem(), "Baby muss einen geladenen Ball anzeigen koennen");
        gooby.setCarriedFetchItem(ItemStack.EMPTY);
        gooby.setAge(0);

        gooby.setSitting(true);
        helper.assertFalse(GoobyFetchGoal.canWork(gooby), "Sitzender Gooby darf nicht apportieren");
        gooby.setSitting(false);

        gooby.setGoobySleeping(true);
        helper.assertFalse(GoobyFetchGoal.canWork(gooby), "Schlafender Gooby darf nicht apportieren");
        gooby.setGoobySleeping(false);

        gooby.setAlerting(true);
        helper.assertFalse(GoobyFetchGoal.canWork(gooby), "Alarmierter Gooby darf nicht apportieren");
        gooby.setAlerting(false);

        gooby.setCommandMode(GoobyCommand.STAY);
        helper.assertFalse(GoobyFetchGoal.canWork(gooby), "STAY-Befehl muss das Apportieren blocken");
        gooby.setCommandMode(GoobyCommand.WANDER);

        gooby.setLeashedTo(owner, true);
        helper.assertFalse(GoobyFetchGoal.canWork(gooby), "Angeleinter Gooby darf nicht apportieren");
        gooby.dropLeash(true, false);

        helper.assertTrue(GoobyFetchGoal.canWork(gooby), "Gating-Reset: Normalzustand muss wieder erlauben");
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 4. Atomarer Pickup ohne Dupe
    // ------------------------------------------------------------------

    /** Zwei Goobys, ein Ball: genau EINER traegt danach; DataComponents wandern mit. */
    @GameTest(template = ARENA)
    public static void fetch_pickup_atomic_no_dupe(GameTestHelper helper) {
        placeFloor(helper);
        FakePlayer owner = fakePlayer(helper, "pickup_owner");
        Vec3 spot = helper.absoluteVec(new Vec3(2.5, 2.0, 2.5));
        owner.moveTo(spot.x, spot.y, spot.z, 0.0F, 0.0F);
        GoobyEntity first = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        GoobyEntity second = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 3));
        first.tame(owner);
        second.tame(owner);

        ItemStack hand = fancyBall(2);
        ItemEntity ball = GoobyBallItem.throwBall(helper.getLevel(), owner, hand);
        ItemStack thrown = ball.getItem().copy();

        helper.assertTrue(first.tryPickUpFetchBall(ball), "Erster Gooby muss den Ball aufnehmen");
        helper.assertFalse(ball.isAlive(), "ItemEntity muss beim Pickup atomar verschwinden");
        helper.assertFalse(second.tryPickUpFetchBall(ball), "Zweiter Gooby darf die geleerte Entity nicht nehmen");
        helper.assertFalse(second.isCarryingFetchItem(), "Zweiter Gooby traegt ploetzlich einen Phantom-Ball");
        helper.assertTrue(ItemStack.matches(thrown, first.getCarriedFetchItem()),
                "Trage-Slot verlor Stack-Daten (Count/DataComponents)");

        // Ein tragender Gooby nimmt keinen zweiten Ball (kein Verschlucken)
        ItemEntity extra = GoobyBallItem.throwBall(helper.getLevel(), owner,
                new ItemStack(ModItems.GOOBY_BALL.get()));
        helper.assertFalse(first.tryPickUpFetchBall(extra), "Tragender Gooby darf keinen zweiten Ball nehmen");
        helper.assertTrue(extra.isAlive(), "Abgelehnter Zweitball wurde trotzdem verschluckt");

        // Sync-Slot kopiert defensiv: Mutationen am Original schlagen nie durch
        ItemStack mutable = new ItemStack(ModItems.GOOBY_BALL.get());
        second.setCarriedFetchItem(mutable);
        mutable.setCount(13);
        helper.assertTrue(second.getCarriedFetchItem().getCount() == 1,
                "Trage-Slot teilt sich die Stack-Instanz mit dem Aufrufer (Dupe-Risiko)");
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 5. NBT-Roundtrip + Reload setzt Rueckgabe fort
    // ------------------------------------------------------------------

    /** Voller Stack inkl. DataComponents + Belohnungs-Cooldown ueberleben Save/Load. */
    @GameTest(template = ARENA)
    public static void carried_ball_nbt_roundtrip(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        GoobyEntity original = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        original.tame(owner);

        // Erst liefern, damit der Belohnungs-Cooldown einen echten Wert hat
        original.setCarriedFetchItem(new ItemStack(ModItems.GOOBY_BALL.get()));
        helper.assertTrue(original.deliverFetchBallTo(owner), "Setup-Lieferung schlug fehl");
        helper.assertTrue(original.getFetchRewardCooldownUntil() > 0, "Setup: Cooldown wurde nicht gesetzt");

        ItemStack carried = fancyBall(2);
        original.setCarriedFetchItem(carried);
        CompoundTag tag = new CompoundTag();
        original.saveWithoutId(tag);

        GoobyEntity reloaded = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 3));
        reloaded.load(tag);

        helper.assertTrue(ItemStack.matches(carried, reloaded.getCarriedFetchItem()),
                "Trage-Stack (Count + DataComponents) ging beim Reload verloren");
        helper.assertTrue(reloaded.getFetchRewardCooldownUntil() == original.getFetchRewardCooldownUntil(),
                "Belohnungs-Cooldown ging beim Reload verloren");
        // Nach dem Reload startet das Goal direkt in der Rueckgabe-Phase
        helper.assertTrue(new GoobyFetchGoal(reloaded, 1.0).canUse(),
                "Reload-Gooby setzt die Rueckgabe nicht fort");

        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 6. Verlustfreiheit: Abbruch, Logout, Tod
    // ------------------------------------------------------------------

    /** Goal-Abbruch und Owner-Logout loeschen den getragenen Ball NIE. */
    @GameTest(template = ARENA)
    public static void carried_ball_survives_abort_and_logout(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        gooby.tame(owner);
        ItemStack carried = fancyBall(1);
        gooby.setCarriedFetchItem(carried);

        GoobyFetchGoal goal = new GoobyFetchGoal(gooby, 1.0);
        helper.assertTrue(goal.canUse(), "Tragender Gooby mit Online-Owner muss liefern wollen");
        goal.start();
        goal.stop();
        helper.assertTrue(ItemStack.matches(carried, gooby.getCarriedFetchItem()),
                "Goal-Abbruch hat den getragenen Ball geloescht");

        // Owner-Logout: Goal pausiert, Ball bleibt im Maul, nichts spawnt
        TestPlayers.remove(helper, owner);
        helper.assertFalse(goal.canUse(), "Ohne Online-Owner darf das Goal nicht laufen");
        helper.assertFalse(goal.canContinueToUse(), "Ohne Online-Owner darf das Goal nicht weiterlaufen");
        helper.assertTrue(ItemStack.matches(carried, gooby.getCarriedFetchItem()),
                "Owner-Logout hat den getragenen Ball geloescht");
        helper.assertTrue(ballsIn(helper, gooby.getBoundingBox().inflate(6.0)).isEmpty(),
                "Owner-Logout duplizierte den Ball als ItemEntity");
        helper.succeed();
    }

    /** Tod droppt den getragenen Ball GENAU einmal (beide Loot-Pfade idempotent). */
    @GameTest(template = ARENA)
    public static void death_drops_carried_ball_exactly_once(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        ItemStack carried = fancyBall(2);
        gooby.setCarriedFetchItem(carried);
        AABB area = gooby.getBoundingBox().inflate(4.0);

        gooby.hurt(helper.getLevel().damageSources().genericKill(), Float.MAX_VALUE);

        helper.assertTrue(gooby.isDeadOrDying(), "Generic-kill toetete den Test-Gooby nicht");
        List<ItemEntity> drops = ballsIn(helper, area);
        helper.assertTrue(drops.size() == 1,
                "Todes-Drop muss GENAU ein Ball sein, gefunden: " + drops.size());
        helper.assertTrue(ItemStack.matches(carried, drops.getFirst().getItem()),
                "Todes-Drop verlor Count oder DataComponents");
        helper.assertFalse(gooby.isCarryingFetchItem(), "Trage-Slot muss nach dem Todes-Drop leer sein");
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 6b. Give-up-Blacklist: unerreichbare Baelle blockieren die KI nicht
    // ------------------------------------------------------------------

    /**
     * Nach dem Give-up-Fenster wird GENAU der unerreichbare Ball zeitlich
     * geblacklistet: kein Sofort-Retry (Follow/Tempt kommen wieder dran),
     * ein frischer Ball ist sofort apportierbar und die Trage-/Lieferphase
     * kennt kein Timeout.
     */
    @GameTest(template = ARENA)
    public static void fetch_gives_up_blacklists_and_frees_goals(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(0.5, 2.0, 0.5));
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(4, 2, 4));
        gooby.tame(owner);
        gooby.setCommandMode(GoobyCommand.WANDER);
        // KI aus: der Gooby bewegt sich nicht — der Ball ist damit garantiert
        // "unerreichbar" und nur die manuelle Goal-Instanz tickt.
        gooby.setNoAi(true);

        ItemEntity ball = GoobyBallItem.throwBall(helper.getLevel(), owner,
                new ItemStack(ModItems.GOOBY_BALL.get(), 2));
        park(ball, helper.absoluteVec(new Vec3(1.5, 2.2, 4.5)));

        GoobyFetchGoal goal = new GoobyFetchGoal(gooby, 1.0);
        helper.assertTrue(goal.canUse(), "Goal muss den Ball zunaechst anvisieren");
        goal.start();
        for (int i = 0; i <= GoobyFetchGoal.GIVE_UP_TICKS; i++) {
            goal.tick();
        }
        helper.assertFalse(goal.canContinueToUse(), "Nach dem Give-up-Fenster muss das Goal enden");
        goal.stop();
        helper.assertTrue(goal.isTemporarilyUnreachable(ball), "Aufgegebener Ball fehlt auf der Blacklist");
        helper.assertTrue(ball.isAlive(), "Give-up darf den Ball nicht loeschen");

        // Kein Sofort-Retry: auch ueber ein volles Scan-Intervall hinweg
        for (int i = 0; i < 12; i++) {
            helper.assertFalse(goal.canUse(),
                    "Geblacklisteter Ball wurde sofort erneut anvisiert (Aufruf " + i + ")");
        }

        // Ein frischer Ball ist sofort dran — die Blacklist trifft nur die Leiche
        ItemEntity fresh = GoobyBallItem.throwBall(helper.getLevel(), owner,
                new ItemStack(ModItems.GOOBY_BALL.get(), 2));
        park(fresh, helper.absoluteVec(new Vec3(4.5, 2.2, 1.5)));
        boolean retargeted = false;
        for (int i = 0; i < 12 && !retargeted; i++) {
            retargeted = goal.canUse();
        }
        helper.assertTrue(retargeted, "Frischer Ball wurde trotz freier Blacklist nicht anvisiert");
        helper.assertFalse(goal.isTemporarilyUnreachable(fresh),
                "Frischer Ball landete faelschlich auf der Blacklist");
        helper.assertTrue(goal.isTemporarilyUnreachable(ball),
                "Blacklist-Eintrag verschwand ohne Ablauf der Retry-Zeit");

        // Trage-/Lieferphase: Give-up greift NIE, der Ball bleibt im Maul
        gooby.setCarriedFetchItem(new ItemStack(ModItems.GOOBY_BALL.get()));
        GoobyFetchGoal carryGoal = new GoobyFetchGoal(gooby, 1.0);
        helper.assertTrue(carryGoal.canUse(), "Tragender Gooby muss liefern wollen");
        carryGoal.start();
        for (int i = 0; i <= GoobyFetchGoal.GIVE_UP_TICKS + 50; i++) {
            carryGoal.tick();
        }
        helper.assertTrue(carryGoal.canContinueToUse(), "Trage-Phase darf nie per Give-up abbrechen");
        helper.assertTrue(gooby.isCarryingFetchItem(), "Trage-Phase verlor den Ball");

        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 7. Rueckgabe: Empfaenger-Prioritaet, Belohnungs-Cooldown, Advancement
    // ------------------------------------------------------------------

    @GameTest(template = ARENA)
    public static void deliver_priority_reward_and_advancement(GameTestHelper helper) {
        placeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        owner.setGameMode(GameType.SURVIVAL);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));
        FakePlayer stranger = fakePlayer(helper, "deliver_stranger");
        gooby.tame(owner);
        gooby.setSatisfaction(50);
        AABB area = gooby.getBoundingBox().inflate(6.0);

        ItemStack carried = fancyBall(2);
        gooby.setCarriedFetchItem(carried);
        helper.assertFalse(gooby.deliverFetchBallTo((ServerPlayer) null), "Null-Empfaenger wurde akzeptiert");
        helper.assertTrue(gooby.isCarryingFetchItem(), "Fehlgeschlagene Lieferung leerte den Trage-Slot");

        helper.assertTrue(gooby.deliverFetchBallTo(owner), "Lieferung an den Besitzer schlug fehl");
        helper.assertFalse(gooby.isCarryingFetchItem(), "Trage-Slot muss nach der Lieferung leer sein");
        List<ItemEntity> returned = ballsIn(helper, area);
        helper.assertTrue(returned.size() == 1, "Lieferung muss GENAU eine ItemEntity spawnen");
        ItemEntity delivered = returned.getFirst();
        helper.assertTrue(ItemStack.matches(carried, delivered.getItem()),
                "Rueckgabe verlor Count oder DataComponents");
        helper.assertTrue(owner.getUUID().equals(delivered.getTarget()),
                "Rueckgabe-Ball hat keine Empfaenger-Prioritaet (Target-UUID)");
        helper.assertTrue(delivered.getPersistentData().getLong(GoobyEntity.GIFT_PRIORITY_UNTIL_TAG)
                        == helper.getLevel().getGameTime() + GoobyEntity.GIFT_PICKUP_PRIORITY_TICKS,
                "Empfaenger-Prioritaetsfenster fehlt oder ist falsch");
        helper.assertTrue(GoobyBallItem.throwerOf(delivered) == null,
                "Zurueckgegebener Ball traegt noch die Wurf-Signatur (Endlos-Apport-Schleife)");
        helper.assertFalse(gooby.isOwnFetchBall(delivered),
                "Gooby wuerde den gerade gelieferten Ball sofort wieder apportieren");

        int satisfactionAfterFirst = gooby.getSatisfaction();
        helper.assertTrue(satisfactionAfterFirst == 50 + GoobyEntity.FETCH_SATISFACTION,
                "Erster Apport gab keinen Satisfaction-Bonus");
        long cooldownUntil = gooby.getFetchRewardCooldownUntil();
        helper.assertTrue(cooldownUntil == helper.getLevel().getGameTime() + GoobyEntity.FETCH_REWARD_COOLDOWN_TICKS,
                "Belohnungs-Cooldown wurde nicht korrekt gesetzt");

        AdvancementHolder fetchAdv = helper.getLevel().getServer().getAdvancements()
                .get(ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, GoobyAdvancements.FIRST_FETCH));
        helper.assertTrue(fetchAdv != null && owner.getAdvancements().getOrStartProgress(fetchAdv).isDone(),
                "first_fetch-Advancement wurde nicht verliehen");

        // Doppel-Lieferung ohne Ball: kein zweiter Spawn (Dupe-Invariante)
        helper.assertFalse(gooby.deliverFetchBallTo(owner), "Lieferung ohne Trage-Ball wurde akzeptiert");
        helper.assertTrue(ballsIn(helper, area).size() == 1, "Leer-Lieferung duplizierte den Ball");

        // Fremde Spieler bekommen nie den Ball des Besitzers
        gooby.setCarriedFetchItem(new ItemStack(ModItems.GOOBY_BALL.get()));
        helper.assertFalse(gooby.deliverFetchBallTo(stranger),
                "Ball wurde an einen fremden Spieler geliefert");

        // Zweiter Apport im Cooldown-Fenster: Rueckgabe ja, Bonus nein
        helper.assertTrue(gooby.deliverFetchBallTo(owner), "Zweite Lieferung schlug fehl");
        helper.assertTrue(gooby.getSatisfaction() == satisfactionAfterFirst,
                "Belohnungs-Cooldown verhinderte den Spam-Bonus nicht");
        helper.assertTrue(gooby.getFetchRewardCooldownUntil() == cooldownUntil,
                "Cooldown wurde im Fenster faelschlich verlaengert");

        TestPlayers.remove(helper, owner);
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // 8. Asset-Vertrag: mouth_anchor, Modell, Textur, Rezept, Lang
    // ------------------------------------------------------------------

    @GameTest(template = ARENA)
    public static void mouth_anchor_and_asset_contract(GameTestHelper helper) {
        // mouth_anchor in BEIDEN Geos: reiner Locator (keine Cubes) am Kopf,
        // vor der Schnauze — bestehende Anker bleiben unveraendert.
        assertAnchor(helper, "assets/goobymod/geo/gooby.geo.json", "mouth_anchor", "head",
                new double[] {0.0, 12.4, -7.6});
        assertAnchor(helper, "assets/goobymod/geo/gooby.geo.json", "hat_anchor", "head",
                new double[] {0.0, 20.2, -0.5});
        assertAnchor(helper, "assets/goobymod/geo/gooby.geo.json", "neck_anchor", "body",
                new double[] {0.0, 11.5, -4.8});
        assertAnchor(helper, "assets/goobymod/geo/gooby.geo.json", "back_anchor", "body",
                new double[] {0.0, 9.5, 5.8});
        assertAnchor(helper, "assets/goobymod/geo/gooby_baby.geo.json", "mouth_anchor", "head",
                new double[] {0.0, 11.9, -9.2});
        assertAnchor(helper, "assets/goobymod/geo/gooby_baby.geo.json", "hat_anchor", "head",
                new double[] {0.0, 21.2, -0.5});

        // Item-Modell + Textur
        JsonObject model = loadAssetJson(helper, "assets/goobymod/models/item/gooby_ball.json");
        helper.assertTrue("goobymod:item/gooby_ball".equals(
                        model.getAsJsonObject("textures").get("layer0").getAsString()),
                "Item-Modell referenziert die falsche Textur");
        try (InputStream texture = GoobyFetchWaveTests.class.getClassLoader()
                .getResourceAsStream("assets/goobymod/textures/item/gooby_ball.png")) {
            helper.assertTrue(texture != null, "Ball-Textur fehlt im Runtime-Classpath");
        } catch (IOException exception) {
            helper.fail("Ball-Textur nicht lesbar: " + exception.getMessage());
        }

        // Lang-Vertrag DE/EN: Name, beide Tooltips, Advancement, Statusmeldung
        for (String lang : new String[] {"en_us", "de_de"}) {
            JsonObject entries = loadAssetJson(helper, "assets/goobymod/lang/" + lang + ".json");
            for (String key : new String[] {"item.goobymod.gooby_ball", "tooltip.goobymod.gooby_ball",
                    "tooltip.goobymod.gooby_ball.fetch", "advancements.goobymod.first_fetch.title",
                    "advancements.goobymod.first_fetch.description", "msg.goobymod.fetch_returned"}) {
                helper.assertTrue(entries.has(key), "Lang-Eintrag fehlt in " + lang + ": " + key);
            }
        }

        // Rezept matcht im echten RecipeManager und liefert Baelle
        CraftingInput input = CraftingInput.of(3, 1, List.of(
                new ItemStack(Items.SLIME_BALL), new ItemStack(Items.STRING),
                new ItemStack(ModItems.GOOBY_FLUFF.get())));
        var recipe = helper.getLevel().getRecipeManager()
                .getRecipeFor(RecipeType.CRAFTING, input, helper.getLevel());
        helper.assertTrue(recipe.isPresent(), "Ball-Rezept (Schleimball + Faden + Fluff) matcht nicht");
        ItemStack crafted = recipe.get().value().assemble(input, helper.getLevel().registryAccess());
        helper.assertTrue(crafted.is(ModItems.GOOBY_BALL.get()) && crafted.getCount() == 2,
                "Ball-Rezept liefert nicht 2x Gooby-Ball: " + crafted);

        // Recipe-Unlock + Advancement sind im Server registriert
        var advancements = helper.getLevel().getServer().getAdvancements();
        helper.assertTrue(advancements.get(ResourceLocation.fromNamespaceAndPath(
                        GoobyMod.MODID, "recipes/gooby_ball")) != null,
                "Recipe-Unlock-Advancement fehlt oder ist kaputt");
        helper.assertTrue(advancements.get(ResourceLocation.fromNamespaceAndPath(
                        GoobyMod.MODID, GoobyAdvancements.FIRST_FETCH)) != null,
                "first_fetch-Advancement fehlt oder ist kaputt");
        helper.succeed();
    }

    private static void assertAnchor(GameTestHelper helper, String geoPath, String bone, String parent,
            double[] pivot) {
        JsonArray bones = loadAssetJson(helper, geoPath)
                .getAsJsonArray("minecraft:geometry").get(0).getAsJsonObject().getAsJsonArray("bones");
        for (JsonElement element : bones) {
            JsonObject candidate = element.getAsJsonObject();
            if (!bone.equals(candidate.get("name").getAsString())) {
                continue;
            }
            helper.assertTrue(parent.equals(candidate.get("parent").getAsString()),
                    geoPath + ": " + bone + " haengt nicht an '" + parent + "'");
            helper.assertFalse(candidate.has("cubes"),
                    geoPath + ": " + bone + " muss ein reiner Locator ohne Cubes sein");
            JsonArray actual = candidate.getAsJsonArray("pivot");
            for (int axis = 0; axis < 3; axis++) {
                helper.assertTrue(Math.abs(actual.get(axis).getAsDouble() - pivot[axis]) < 1.0E-6,
                        geoPath + ": " + bone + "-Pivot verschoben: " + actual);
            }
            return;
        }
        helper.fail(geoPath + ": Bone fehlt: " + bone);
    }

    // ------------------------------------------------------------------
    // 8b. Prioritaet: laufendes Tempt gewinnt, Apport startet nach dessen Ende
    // ------------------------------------------------------------------

    /**
     * Dokumentiertes Verhalten (gleiche Prioritaet preemptet in Vanilla nie):
     * eine BEREITS laufende Nutella-Lockung wird vom Apport nicht
     * unterbrochen; sobald die Lockung endet, startet der Apport von selbst.
     */
    @GameTest(template = ARENA_LARGE, timeoutTicks = 600)
    public static void fetch_defers_to_running_tempt(GameTestHelper helper) {
        placeLargeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(2.5, 2.0, 2.5));
        owner.setGameMode(GameType.SURVIVAL);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(4, 2, 4));
        gooby.tame(owner);
        gooby.setCommandMode(GoobyCommand.WANDER);
        owner.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(ModItems.NUTELLA.get()));

        helper.onEachTick(() -> {
            // Anti-Flake wie im E2E-Test: Sitz-/Schlaf-Zufall wuerde beide
            // Goals blockieren — geprueft wird die Prioritaet, nicht der Schlaf.
            if (gooby.isSitting()) {
                gooby.setSitting(false);
            }
            if (gooby.isGoobySleeping()) {
                gooby.setGoobySleeping(false);
            }
        });

        helper.startSequence()
                .thenWaitUntil(() -> helper.assertTrue(gooby.isGoalRunning(TemptGoal.class),
                        "Nutella-Lockung startete nicht"))
                .thenExecute(() -> {
                    // Ball ERST werfen, wenn die Lockung schon laeuft — nur so
                    // ist der Preemption-Fall eindeutig (Simultanstart gewinnt
                    // der Apport per Insertion-Order).
                    ItemEntity ball = GoobyBallItem.throwBall(helper.getLevel(), owner,
                            new ItemStack(ModItems.GOOBY_BALL.get(), 2));
                    park(ball, helper.absoluteVec(new Vec3(12.5, 2.3, 12.5)));
                })
                .thenExecuteAfter(60, () -> {
                    helper.assertTrue(gooby.isGoalRunning(TemptGoal.class),
                            "Lockung brach waehrend der Beobachtung ab");
                    helper.assertFalse(gooby.isGoalRunning(GoobyFetchGoal.class),
                            "Apport unterbrach ein laufendes Tempt (gleiche Prioritaet darf nie preempten)");
                    helper.assertFalse(gooby.isCarryingFetchItem(),
                            "Gooby holte den Ball trotz laufender Lockung");
                    owner.setItemInHand(InteractionHand.MAIN_HAND, ItemStack.EMPTY);
                })
                .thenWaitUntil(() -> helper.assertTrue(gooby.isGoalRunning(GoobyFetchGoal.class)
                                || gooby.isCarryingFetchItem() || ballReturnedNearOwner(helper, owner),
                        "Nach dem Ende der Lockung startete der Apport nicht"))
                .thenExecute(() -> TestPlayers.remove(helper, owner))
                .thenSucceed();
    }

    // ------------------------------------------------------------------
    // 9. End-to-End: werfen, hinlaufen, aufnehmen, zurueckbringen
    // ------------------------------------------------------------------

    @GameTest(template = ARENA_LARGE, timeoutTicks = 600)
    public static void fetch_end_to_end(GameTestHelper helper) {
        placeLargeFloor(helper);
        ServerPlayer owner = TestPlayers.create(helper, new Vec3(2.5, 2.0, 2.5));
        owner.setGameMode(GameType.SURVIVAL);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(4, 2, 4));
        gooby.tame(owner);
        gooby.setCommandMode(GoobyCommand.WANDER);

        ItemStack hand = new ItemStack(ModItems.GOOBY_BALL.get(), 3);
        ItemEntity ball = GoobyBallItem.throwBall(helper.getLevel(), owner, hand);
        helper.assertTrue(hand.getCount() == 2, "E2E-Wurf verbrauchte nicht genau 1 Ball");
        // Ball weit weg platzieren: der Gooby muss wirklich hinlaufen
        Vec3 far = helper.absoluteVec(new Vec3(12.5, 2.3, 12.5));
        ball.moveTo(far.x, far.y, far.z);
        ball.setDeltaMovement(Vec3.ZERO);

        helper.onEachTick(() -> {
            // Anti-Flake: zufaelliges Sitzen/Einschlafen wuerde das Gating
            // blockieren — der Test prueft den Apport, nicht den Mittagsschlaf.
            if (gooby.isSitting()) {
                gooby.setSitting(false);
            }
            if (gooby.isGoobySleeping()) {
                gooby.setGoobySleeping(false);
            }
        });

        helper.succeedWhen(() -> {
            boolean returnedNearOwner = !helper.getLevel().getEntitiesOfClass(ItemEntity.class,
                    new AABB(owner.blockPosition()).inflate(4.0),
                    item -> item.getItem().is(ModItems.GOOBY_BALL.get())
                            && owner.getUUID().equals(item.getTarget())).isEmpty();
            boolean pickedUpByOwner = owner.getInventory().countItem(ModItems.GOOBY_BALL.get()) > 0;
            helper.assertTrue(returnedNearOwner || pickedUpByOwner,
                    "Ball wurde noch nicht zum Besitzer zurueckgebracht");
            helper.assertFalse(gooby.isCarryingFetchItem(),
                    "Gooby traegt nach der Rueckgabe noch einen Ball");
            TestPlayers.remove(helper, owner);
        });
    }
}
