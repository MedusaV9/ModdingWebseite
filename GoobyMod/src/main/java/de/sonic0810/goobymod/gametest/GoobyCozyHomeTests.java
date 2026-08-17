package de.sonic0810.goobymod.gametest;

import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.block.GoobyCouchBlock;
import de.sonic0810.goobymod.block.RabbitHutchBlock;
import de.sonic0810.goobymod.entity.CouchSeatEntity;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.entity.goals.GoobySleepGoal;
import de.sonic0810.goobymod.registry.ModBlocks;
import de.sonic0810.goobymod.registry.ModEntities;
import de.sonic0810.goobymod.registry.ModItems;
import java.util.List;
import net.minecraft.core.BlockPos;
import net.minecraft.gametest.framework.AfterBatch;
import net.minecraft.gametest.framework.BeforeBatch;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.item.crafting.CraftingInput;
import net.minecraft.world.item.crafting.RecipeType;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.BlockHitResult;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * Welle 6 "Cozy Home & Performance" (v5.3.0): Gooby-Woll-Couch —
 * Rezept/Loot, serverautoritatives Sitzen ueber das Sitz-Entity und die
 * Couch-Prioritaet im Schlaf-Goal (Stall gewinnt weiterhin immer).
 */
@GameTestHolder(GoobyMod.MODID)
@PrefixGameTestTemplate(false)
public class GoobyCozyHomeTests {
    private static final String ARENA = "arena";
    // Eigene Ein-Test-Batches statt "goobyNight": Sozialschlaf hat im
    // Produktions-Goal Prioritaet vor Couch/Stall, d.h. ein schlafender
    // Nachbar-Gooby aus einem parallel laufenden Batch-Test wuerde den
    // Prueflingsschlaf nichtdeterministisch umlenken (6-Block-Scan).
    private static final String COUCH_NAP_BATCH = "goobyCouchNap";
    private static final String COUCH_VS_HUTCH_BATCH = "goobyCouchVsHutch";

    @BeforeBatch(batch = COUCH_NAP_BATCH)
    public static void beforeCouchNapBatch(ServerLevel level) {
        level.setDayTime(18000);
    }

    @AfterBatch(batch = COUCH_NAP_BATCH)
    public static void afterCouchNapBatch(ServerLevel level) {
        level.setDayTime(6000);
    }

    @BeforeBatch(batch = COUCH_VS_HUTCH_BATCH)
    public static void beforeCouchVsHutchBatch(ServerLevel level) {
        level.setDayTime(18000);
    }

    @AfterBatch(batch = COUCH_VS_HUTCH_BATCH)
    public static void afterCouchVsHutchBatch(ServerLevel level) {
        level.setDayTime(6000);
    }

    private static void placeFloor(GameTestHelper helper) {
        for (int x = 0; x < 5; x++) {
            for (int z = 0; z < 5; z++) {
                helper.setBlock(new BlockPos(x, 1, z), Blocks.DIRT);
            }
        }
    }

    /**
     * Entfernt uebrig gebliebene Goobys frueherer (bereits abgeschlossener)
     * Batches rund um die Arena. Ein dort noch schlafender Gooby waere sonst
     * ein Sozialschlaf-Magnet fuer den Pruefling (siehe Batch-Kommentar).
     */
    private static void purgeForeignGoobys(GameTestHelper helper) {
        AABB area = new AABB(helper.absolutePos(BlockPos.ZERO)).inflate(24.0);
        helper.getLevel().getEntitiesOfClass(GoobyEntity.class, area).forEach(GoobyEntity::discard);
    }

    private static BlockHitResult couchHit(GameTestHelper helper, BlockPos couchRel) {
        BlockPos abs = helper.absolutePos(couchRel);
        return new BlockHitResult(Vec3.atCenterOf(abs), net.minecraft.core.Direction.UP, abs, false);
    }

    // ------------------------------------------------------------------
    // Rezept + Loot
    // ------------------------------------------------------------------

    /** Couch-Rezept: 4x Gooby-Wolle (L-Lehne) ueber 3x Bretter = 1 Couch. */
    @GameTest(template = ARENA)
    public static void couch_recipe(GameTestHelper helper) {
        CraftingInput input = CraftingInput.of(3, 3, List.of(
                new ItemStack(ModItems.GOOBY_WOOL.get()), ItemStack.EMPTY, ItemStack.EMPTY,
                new ItemStack(ModItems.GOOBY_WOOL.get()), new ItemStack(ModItems.GOOBY_WOOL.get()),
                new ItemStack(ModItems.GOOBY_WOOL.get()),
                new ItemStack(Items.OAK_PLANKS), new ItemStack(Items.SPRUCE_PLANKS),
                new ItemStack(Items.CHERRY_PLANKS)));
        var recipe = helper.getLevel().getRecipeManager().getRecipeFor(RecipeType.CRAFTING, input, helper.getLevel());
        if (recipe.isEmpty()) {
            helper.fail("Couch-Rezept matcht nicht (4x Gooby-Wolle + 3x Bretter)");
            return;
        }
        ItemStack result = recipe.get().value().assemble(input, helper.getLevel().registryAccess());
        helper.assertTrue(result.is(ModItems.GOOBY_COUCH.get()) && result.getCount() == 1,
                "Rezept-Ergebnis ist keine Gooby-Woll-Couch: " + result);
        helper.succeed();
    }

    /** Abgebaute Couch droppt sich selbst (zustandsloses Standard-Loot). */
    @GameTest(template = ARENA)
    public static void couch_loot_drops_self(GameTestHelper helper) {
        placeFloor(helper);
        BlockPos couchRel = new BlockPos(2, 2, 2);
        helper.setBlock(couchRel, ModBlocks.GOOBY_COUCH.get());
        BlockPos abs = helper.absolutePos(couchRel);
        ServerLevel level = helper.getLevel();
        List<ItemStack> drops = Block.getDrops(level.getBlockState(abs), level, abs, null);
        helper.assertTrue(drops.size() == 1 && drops.getFirst().is(ModItems.GOOBY_COUCH.get())
                        && drops.getFirst().getCount() == 1,
                "Couch-Loot ist nicht genau 1x Gooby-Woll-Couch: " + drops);
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // Sitzen: serverautoritatives Sitz-Entity
    // ------------------------------------------------------------------

    /** Rechtsklick setzt den Spieler auf ein Sitz-Entity; Absteigen raeumt es ab. */
    @GameTest(template = ARENA)
    public static void couch_sit_and_dismount(GameTestHelper helper) {
        placeFloor(helper);
        BlockPos couchRel = new BlockPos(2, 2, 2);
        helper.setBlock(couchRel, ModBlocks.GOOBY_COUCH.get());
        BlockPos abs = helper.absolutePos(couchRel);
        ServerPlayer player = TestPlayers.create(helper, new Vec3(2.5, 2.0, 1.5));
        BlockState state = helper.getLevel().getBlockState(abs);

        state.useWithoutItem(helper.getLevel(), player, couchHit(helper, couchRel));
        helper.assertTrue(player.getVehicle() instanceof CouchSeatEntity,
                "Spieler sitzt nach Rechtsklick nicht auf dem Couch-Sitz");
        CouchSeatEntity seat = (CouchSeatEntity) player.getVehicle();
        helper.assertTrue(abs.equals(seat.blockPosition()),
                "Sitz-Entity steht nicht im Couch-Block: " + seat.blockPosition());
        helper.assertTrue(seat.position().distanceToSqr(GoobyCouchBlock.seatAnchor(abs)) < 0.01,
                "Sitz-Entity sitzt nicht auf dem Kissen-Anker: " + seat.position());

        // Zweiter Spieler darf sich NICHT dazusetzen (Couch ist belegt)
        ServerPlayer second = TestPlayers.create(helper, new Vec3(1.5, 2.0, 1.5));
        helper.assertFalse(CouchSeatEntity.seatPlayer(helper.getLevel(), abs, second),
                "Belegte Couch nahm einen zweiten Sitzenden an");

        player.stopRiding();
        helper.startSequence()
                .thenExecuteAfter(2, () -> {
                    helper.assertTrue(helper.getLevel().getEntitiesOfClass(CouchSeatEntity.class,
                                    new AABB(abs).inflate(2.0)).isEmpty(),
                            "Leerer Couch-Sitz hat sich nicht selbst abgeraeumt");
                    TestPlayers.remove(helper, player);
                    TestPlayers.remove(helper, second);
                })
                .thenSucceed();
    }

    /** Abbau der Couch wirft den Sitzenden sicher ab und entfernt den Sitz sofort. */
    @GameTest(template = ARENA)
    public static void couch_seat_cleans_up_on_break(GameTestHelper helper) {
        placeFloor(helper);
        BlockPos couchRel = new BlockPos(2, 2, 2);
        helper.setBlock(couchRel, ModBlocks.GOOBY_COUCH.get());
        BlockPos abs = helper.absolutePos(couchRel);
        ServerPlayer player = TestPlayers.create(helper, new Vec3(2.5, 2.0, 1.5));

        helper.assertTrue(CouchSeatEntity.seatPlayer(helper.getLevel(), abs, player),
                "Testaufbau: Spieler konnte sich nicht setzen");
        helper.setBlock(couchRel, Blocks.AIR);
        helper.assertFalse(player.isPassenger(), "Spieler haengt nach Couch-Abbau noch am Sitz");
        helper.assertTrue(helper.getLevel().getEntitiesOfClass(CouchSeatEntity.class,
                        new AABB(abs).inflate(2.0)).isEmpty(),
                "Sitz-Entity ueberlebte den Couch-Abbau");
        TestPlayers.remove(helper, player);
        helper.succeed();
    }

    // ------------------------------------------------------------------
    // Nap-Spot: Selektor + echtes Nacht-Nickerchen
    // ------------------------------------------------------------------

    /** Produktions-Selektor: freie Couch wird gefunden, belegte kategorisch ignoriert. */
    @GameTest(template = ARENA)
    public static void couch_nap_selector(GameTestHelper helper) {
        placeFloor(helper);
        BlockPos couchRel = new BlockPos(1, 2, 1);
        helper.setBlock(couchRel, ModBlocks.GOOBY_COUCH.get());
        BlockPos abs = helper.absolutePos(couchRel);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 3));

        helper.assertTrue(abs.equals(GoobySleepGoal.findPreferredCouch(gooby)),
                "Freie Couch wurde nicht als Nap-Spot gefunden");

        // Sitzender Spieler blockiert das Nickerchen ...
        ServerPlayer player = TestPlayers.create(helper, new Vec3(2.5, 2.0, 1.5));
        helper.assertTrue(CouchSeatEntity.seatPlayer(helper.getLevel(), abs, player),
                "Testaufbau: Spieler konnte sich nicht setzen");
        helper.assertTrue(GoobySleepGoal.findPreferredCouch(gooby) == null,
                "Couch mit sitzendem Spieler wurde als Nap-Spot gewaehlt");
        player.stopRiding();
        TestPlayers.remove(helper, player);

        // ... genauso wie ein bereits schlafender Artgenosse auf dem Kissen.
        GoobyEntity napper = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(1, 2, 3));
        Vec3 anchor = GoobyCouchBlock.napAnchor(abs);
        napper.setPos(anchor.x, anchor.y, anchor.z);
        napper.setGoobySleeping(true);
        helper.assertTrue(GoobySleepGoal.findPreferredCouch(gooby) == null,
                "Belegtes Kissen wurde als Nap-Spot gewaehlt");
        helper.assertTrue(abs.equals(GoobySleepGoal.findPreferredCouch(napper)),
                "Der Schlaefer selbst darf seine eigene Couch behalten");
        helper.succeed();
    }

    /** Nachts kuschelt sich Gooby auf das Kissen — exakt auf den Nap-Anker. */
    @GameTest(template = ARENA, batch = COUCH_NAP_BATCH, timeoutTicks = 1200)
    public static void couch_night_nap(GameTestHelper helper) {
        purgeForeignGoobys(helper);
        placeFloor(helper);
        BlockPos couchRel = new BlockPos(2, 2, 2);
        helper.setBlock(couchRel, ModBlocks.GOOBY_COUCH.get());
        BlockPos abs = helper.absolutePos(couchRel);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 3));

        helper.startSequence()
                .thenWaitUntil(() -> helper.assertTrue(gooby.isGoobySleeping(), "Gooby schlaeft noch nicht"))
                .thenExecute(() -> {
                    helper.assertTrue(gooby.position().distanceToSqr(GoobyCouchBlock.napAnchor(abs)) < 0.05,
                            "Gooby schlaeft nicht auf dem Kissen-Anker: " + gooby.position());
                    helper.assertFalse(gooby.isInHutch(),
                            "Couch-Nickerchen darf den Stall-Zustand nicht setzen");
                })
                .thenSucceed();
    }

    /** Regression: ein verfuegbarer Stall gewinnt IMMER gegen die Couch. */
    @GameTest(template = ARENA, batch = COUCH_VS_HUTCH_BATCH, timeoutTicks = 1200)
    public static void hutch_beats_couch(GameTestHelper helper) {
        purgeForeignGoobys(helper);
        placeFloor(helper);
        BlockPos hutchRel = new BlockPos(1, 2, 1);
        BlockPos couchRel = new BlockPos(3, 2, 3);
        helper.setBlock(hutchRel, ModBlocks.RABBIT_HUTCH.get());
        helper.setBlock(couchRel, ModBlocks.GOOBY_COUCH.get());
        BlockPos hutchAbs = helper.absolutePos(hutchRel);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(2, 2, 2));

        helper.assertTrue(hutchAbs.equals(GoobySleepGoal.findPreferredHutch(gooby)),
                "Selektor-Vorbedingung: Stall muss verfuegbar sein");
        helper.startSequence()
                .thenWaitUntil(() -> helper.assertTrue(gooby.isGoobySleeping(), "Gooby schlaeft noch nicht"))
                .thenExecute(() -> {
                    helper.assertTrue(gooby.isInHutch(), "Gooby hat den Stall zugunsten der Couch ignoriert");
                    helper.assertTrue(gooby.position().distanceToSqr(
                                    RabbitHutchBlock.interiorAnchor(hutchAbs)) < 0.05,
                            "Gooby schlaeft nicht im Stall-Innenanker: " + gooby.position());
                })
                .thenSucceed();
    }

    /** Landungen auf der Couch sind komplett wollweich (kein Fallschaden-Callback). */
    @GameTest(template = ARENA)
    public static void couch_softens_falls(GameTestHelper helper) {
        placeFloor(helper);
        BlockPos couchRel = new BlockPos(2, 2, 2);
        helper.setBlock(couchRel, ModBlocks.GOOBY_COUCH.get());
        BlockPos abs = helper.absolutePos(couchRel);
        ItemEntity probe = new ItemEntity(helper.getLevel(),
                abs.getX() + 0.5, abs.getY() + 4.0, abs.getZ() + 0.5,
                new ItemStack(Items.APPLE));
        helper.getLevel().addFreshEntity(probe);
        // fallOn ist beim Item-Aufprall exception-frei und daempft komplett;
        // der eigentliche Schadens-Verzicht steckt im fehlenden super-Aufruf.
        helper.getLevel().getBlockState(abs).getBlock().fallOn(
                helper.getLevel(), helper.getLevel().getBlockState(abs), abs, probe, 6.0F);
        helper.assertTrue(probe.isAlive(), "Fall-Probe hat die Couch-Landung nicht ueberlebt");
        probe.discard();
        helper.succeed();
    }
}
