package de.sonic0810.goobymod.gametest;

import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.registry.ModEntities;
import de.sonic0810.goobymod.registry.ModItems;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import com.mojang.authlib.GameProfile;
import net.minecraft.core.BlockPos;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.entity.MobSpawnType;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.block.Blocks;
import net.neoforged.neoforge.common.util.FakePlayer;
import net.neoforged.neoforge.common.util.FakePlayerFactory;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * Langzeit-Soak in eigenem Namespace ({@code -PwithSoak}), damit die normale
 * Suite schnell bleibt. 12 Goobys (gezaehmt, wild, scheu, Babys mit Familie)
 * leben 12.000 Ticks (10 Spielminuten) unter dauerhafter Interaktions-Last:
 * Streicheln, Klickspam, Fuettern, Buersten, Training, Pfeife, Doppelklick-
 * Tricks, Garderobe und Schnueffel-Suche — abwechselnd von zwei Spielern.
 * Invarianten werden alle 100 Ticks geprueft.
 */
@GameTestHolder("goobymod_soak")
@PrefixGameTestTemplate(false)
public final class GoobySoakTests {
    private static final String ARENA_LARGE = "arena_large";
    private static final int SOAK_TICKS = 12_000;

    @GameTest(template = ARENA_LARGE, timeoutTicks = SOAK_TICKS + 1_000)
    public static void interaction_soak_ten_minutes(GameTestHelper helper) {
        for (int x = 0; x < 17; x++) {
            for (int z = 0; z < 17; z++) {
                helper.setBlock(new BlockPos(x, 1, z), Blocks.GRASS_BLOCK);
            }
        }

        FakePlayer keeper = fakePlayer(helper, "soak_keeper");
        FakePlayer visitor = fakePlayer(helper, "soak_visitor");
        keeper.moveTo(helper.absoluteVec(new net.minecraft.world.phys.Vec3(8.5, 2.0, 8.5)));

        List<GoobyEntity> goobys = new ArrayList<>();
        // Sechs gezaehmte Erwachsene rund um den Halter.
        for (int index = 0; index < 6; index++) {
            GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(),
                    new BlockPos(4 + (index % 3) * 3, 2, 4 + (index / 3) * 3));
            gooby.tame(keeper);
            gooby.setSatisfaction(60);
            goobys.add(gooby);
        }
        // Ein Bestfreund-Gooby fuer Snuggle/Reit-Interaktionen.
        goobys.get(0).setFriendship(keeper.getUUID(), 100);
        // Zwei Babys mit persistierten Ritual-Eltern (Familien-KI).
        for (int index = 0; index < 2; index++) {
            GoobyEntity baby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(6 + index * 2, 2, 10));
            baby.setAge(-24_000 * 5);
            baby.tame(keeper);
            baby.setFamilyData(goobys.get(index).getUUID(), goobys.get(index + 1).getUUID(),
                    helper.absolutePos(new BlockPos(7, 2, 10)));
            goobys.add(baby);
        }
        // Zwei freilaufende Wilde und zwei scheue Natur-Spawns.
        for (int index = 0; index < 2; index++) {
            goobys.add(helper.spawn(ModEntities.GOOBY.get(), new BlockPos(12, 2, 4 + index * 3)));
        }
        for (int index = 0; index < 2; index++) {
            GoobyEntity shy = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(13, 2, 10 + index * 2));
            shy.finalizeSpawn(helper.getLevel(),
                    helper.getLevel().getCurrentDifficultyAt(shy.blockPosition()), MobSpawnType.NATURAL, null);
            shy.setPersistenceRequired();
            goobys.add(shy);
        }
        helper.assertTrue(goobys.size() == 12, "Soak-Aufbau erzeugte nicht exakt 12 Goobys");

        int[] step = {0};
        helper.startSequence()
                .thenExecuteFor(SOAK_TICKS, () -> {
                    int tick = step[0]++;
                    if (tick % 40 == 0) {
                        driveInteraction(helper, goobys, keeper, visitor, tick / 40);
                    }
                    if (tick % 100 == 99) {
                        assertInvariants(helper, goobys);
                    }
                })
                .thenExecute(() -> {
                    assertInvariants(helper, goobys);
                    long dropCount = helper.getLevel().getEntitiesOfClass(ItemEntity.class,
                            goobys.get(0).getBoundingBox().inflate(64.0)).size();
                    helper.assertTrue(dropCount < 400,
                            "Soak hinterliess verdaechtig viele Item-Entities: " + dropCount);
                })
                .thenSucceed();
    }

    /** Rotiert durch alle Spieler-Interaktionen; jeder Schritt trifft einen anderen Gooby. */
    private static void driveInteraction(GameTestHelper helper, List<GoobyEntity> goobys,
            FakePlayer keeper, FakePlayer visitor, int round) {
        GoobyEntity gooby = goobys.get(round % goobys.size());
        if (!gooby.isAlive()) {
            return;
        }
        long now = helper.getLevel().getGameTime();
        switch (round % 9) {
            case 0 -> { // Streichel-Klickspam (beide Spieler)
                gooby.mobInteract(keeper, InteractionHand.MAIN_HAND);
                gooby.mobInteract(keeper, InteractionHand.MAIN_HAND);
                gooby.mobInteract(visitor, InteractionHand.MAIN_HAND);
            }
            case 1 -> gooby.eatNutella(keeper, new ItemStack(ModItems.NUTELLA.get()));
            case 2 -> { // Buerste inkl. absichtlichem Cooldown-Klick
                ItemStack brush = new ItemStack(ModItems.GOOBY_BRUSH.get());
                keeper.setItemInHand(InteractionHand.MAIN_HAND, brush);
                gooby.mobInteract(keeper, InteractionHand.MAIN_HAND);
                gooby.mobInteract(keeper, InteractionHand.MAIN_HAND);
                keeper.setItemInHand(InteractionHand.MAIN_HAND, ItemStack.EMPTY);
            }
            case 3 -> gooby.trainSelectedTrick(keeper, new ItemStack(ModItems.TRAINING_TREAT.get()), now);
            case 4 -> gooby.handleWhistle(keeper);
            case 5 -> { // Doppelklick: erst Trick sichern, dann anfordern
                gooby.setTrickProficiency(gooby.getSelectedTrick(), 1);
                gooby.handleBareHandInteraction(keeper, now);
                gooby.handleBareHandInteraction(keeper, now + 2);
            }
            case 6 -> { // Garderobe an- und wieder ausziehen
                keeper.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(Items.POPPY));
                gooby.mobInteract(keeper, InteractionHand.MAIN_HAND);
                keeper.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(Items.SHEARS));
                gooby.mobInteract(keeper, InteractionHand.MAIN_HAND);
                keeper.setItemInHand(InteractionHand.MAIN_HAND, ItemStack.EMPTY);
            }
            case 7 -> gooby.trySnuggle(keeper, now);
            case 8 -> { // Schnueffel-Suche (inkl. Denials fuer Wilde/Babys)
                keeper.setItemInHand(InteractionHand.MAIN_HAND, new ItemStack(Items.CARROT));
                keeper.setItemInHand(InteractionHand.OFF_HAND, new ItemStack(ModItems.TRAINING_TREAT.get()));
                gooby.tryStartSeek(keeper, keeper.getMainHandItem(), now);
                keeper.setItemInHand(InteractionHand.MAIN_HAND, ItemStack.EMPTY);
                keeper.setItemInHand(InteractionHand.OFF_HAND, ItemStack.EMPTY);
            }
        }
    }

    private static void assertInvariants(GameTestHelper helper, List<GoobyEntity> goobys) {
        int minimumY = helper.getLevel().getMinBuildHeight();
        for (GoobyEntity gooby : goobys) {
            helper.assertTrue(gooby.isAlive(), "Ein Soak-Gooby ist gestorben: " + gooby.getUUID());
            int satisfaction = gooby.getSatisfaction();
            helper.assertTrue(satisfaction >= 0 && satisfaction <= GoobyEntity.MAX_SATISFACTION,
                    "Zufriedenheit ausserhalb der Grenzen: " + satisfaction);
            helper.assertTrue(gooby.getY() > minimumY,
                    "Ein Soak-Gooby fiel aus der Welt: " + gooby.position());
            helper.assertTrue(Double.isFinite(gooby.getX()) && Double.isFinite(gooby.getY())
                    && Double.isFinite(gooby.getZ()), "Nicht-endliche Position: " + gooby.position());
            helper.assertTrue(gooby.transientStateSizeForTest() <= 512,
                    "Transienter Spielerzustand waechst unbegrenzt: " + gooby.transientStateSizeForTest());
            helper.assertTrue(gooby.getStoredFriendshipCount()
                            <= GoobyEntity.MAX_STORED_FRIENDSHIPS + 1,
                    "Freundschafts-Map ueberschritt ihr Limit");
        }
    }

    private static FakePlayer fakePlayer(GameTestHelper helper, String name) {
        return FakePlayerFactory.get(helper.getLevel(),
                new GameProfile(UUID.nameUUIDFromBytes(name.getBytes(StandardCharsets.UTF_8)), name));
    }

    private GoobySoakTests() {
    }
}
