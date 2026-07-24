package dev.projecteclipse.eclipse.gametest.minigames;

import java.util.List;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.minigames.ArenaGame;
import dev.projecteclipse.eclipse.minigames.ElytraRace;
import dev.projecteclipse.eclipse.minigames.MinigameDimensions;
import dev.projecteclipse.eclipse.minigames.MinigameService;
import dev.projecteclipse.eclipse.minigames.MinigameState;
import net.minecraft.core.BlockPos;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.EquipmentSlot;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.GameType;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * W4-MINIGAMES gametests (the {@code XboxEventGameTests} pattern): state machine + NBT
 * round-trip incl. tickets, the bulletproof ticket capture/restore path with a real mock
 * player, deterministic-per-seed course generation, crash resume (past {@code endsAt}
 * boots straight into CLOSING→IDLE), participation-reward idempotence and lap-time
 * formatting. The full E2E (portal walk-in, protected death, kit combat, elytra laps)
 * needs a client and is covered by the manual walkthrough in the worker report.
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class MinigameGameTests {

    private MinigameGameTests() {}

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void stateMachineNbtRoundTrip(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        MinigameState state = new MinigameState();
        long endsAt = System.currentTimeMillis() + 30L * 60_000L;
        state.beginInstance("arena", endsAt);
        helper.assertTrue(state.phase() == MinigameState.Phase.OPEN, "beginInstance → OPEN");
        state.setPhase(MinigameState.Phase.RUNNING);

        UUID fighter = GameTestSupport.testUuid(1);
        UUID racer = GameTestSupport.testUuid(2);
        state.addParticipant(fighter);
        state.addParticipant(racer);
        state.addKill(fighter);
        state.addKill(fighter);
        state.setRaceProgress(racer, 4);
        state.setRaceLapStart(racer, 1_000_000L);
        helper.assertTrue(state.addRaceFinisher(racer) == 1, "first finisher position 1");
        helper.assertTrue(state.addRaceFinisher(racer) == 0, "double finish not counted");
        helper.assertTrue(state.offerBestLap(83_456L), "first lap is the best lap");
        helper.assertTrue(!state.offerBestLap(90_000L), "slower lap is not the best lap");
        state.setBuiltSeed("arena", state.openCount());
        state.setPortal(net.minecraft.world.level.Level.OVERWORLD, new BlockPos(10, 70, -4));

        ListTag main = new ListTag();
        CompoundTag stack = new CompoundTag();
        stack.putString("id", "minecraft:diamond");
        stack.putInt("count", 3);
        main.add(stack);
        state.putTicket(fighter, new MinigameState.Ticket(
                new MinigameState.ReturnAnchor(net.minecraft.world.level.Level.OVERWORLD,
                        1.5D, 64.0D, -7.5D, 90.0F, 10.0F),
                GameType.SURVIVAL.getId(), 18.0F, 13, 2.5F, main, new ListTag(), new ListTag()));

        CompoundTag saved = state.save(new CompoundTag(), server.registryAccess());
        MinigameState loaded = MinigameState.load(saved, server.registryAccess());

        helper.assertTrue(loaded.phase() == MinigameState.Phase.RUNNING, "phase survives NBT");
        helper.assertTrue("arena".equals(loaded.gameId()), "gameId survives NBT");
        helper.assertTrue(loaded.endsAtEpochMillis() == endsAt, "endsAt survives NBT");
        helper.assertTrue(loaded.openCount() == state.openCount(), "openCount survives NBT");
        helper.assertTrue(loaded.isParticipant(fighter) && loaded.isParticipant(racer),
                "participants survive NBT");
        helper.assertTrue(loaded.killsOf(fighter) == 2, "kills survive NBT");
        helper.assertTrue(loaded.raceProgress(racer) == 4, "race progress survives NBT");
        helper.assertTrue(loaded.raceLapStart(racer) == 1_000_000L, "lap start survives NBT");
        helper.assertTrue(loaded.raceFinishersSnapshot().equals(List.of(racer)),
                "finish order survives NBT");
        helper.assertTrue(loaded.bestLapMillis() == 83_456L, "best lap survives NBT");
        helper.assertTrue(loaded.builtSeed("arena") == state.openCount(), "built seed survives NBT");
        helper.assertTrue(new BlockPos(10, 70, -4).equals(loaded.portalPos()), "portal pos survives NBT");

        MinigameState.Ticket ticket = loaded.ticket(fighter);
        helper.assertTrue(ticket != null, "ticket survives NBT");
        helper.assertTrue(ticket.anchor().x() == 1.5D && ticket.anchor().yaw() == 90.0F
                && ticket.anchor().dimension().equals(net.minecraft.world.level.Level.OVERWORLD),
                "ticket anchor survives NBT");
        helper.assertTrue(ticket.gameModeId() == GameType.SURVIVAL.getId()
                && ticket.health() == 18.0F && ticket.foodLevel() == 13
                && ticket.saturation() == 2.5F, "ticket vitals survive NBT");
        helper.assertTrue(ticket.main().size() == 1
                && "minecraft:diamond".equals(ticket.main().getCompound(0).getString("id")),
                "ticket inventory tags survive NBT verbatim");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void ticketCaptureRestoreRoundTrip(GameTestHelper helper) {
        ServerPlayer player = GameTestSupport.mockSurvivalPlayer(helper);
        player.getInventory().clearContent();
        player.getInventory().add(new ItemStack(Items.DIAMOND, 3));
        player.setItemSlot(EquipmentSlot.HEAD, new ItemStack(Items.IRON_HELMET));
        player.setItemSlot(EquipmentSlot.OFFHAND, new ItemStack(Items.SHIELD));
        player.getFoodData().setFoodLevel(13);
        player.getFoodData().setSaturation(3.5F);
        float healthBefore = player.getHealth();

        MinigameState.Ticket ticket = MinigameState.captureTicket(player);

        // Simulate the minigame kit + damage, exactly what an exit must undo.
        player.setGameMode(GameType.ADVENTURE);
        player.getInventory().clearContent();
        player.getInventory().add(new ItemStack(Items.STONE_SWORD));
        player.setItemSlot(EquipmentSlot.CHEST, new ItemStack(Items.ELYTRA));
        player.setHealth(5.0F);
        player.getFoodData().setFoodLevel(2);

        MinigameState.restoreTicket(player, ticket);

        helper.assertTrue(player.gameMode.getGameModeForPlayer() == GameType.SURVIVAL,
                "game mode restored");
        ItemStack slot0 = player.getInventory().items.get(0);
        helper.assertTrue(slot0.is(Items.DIAMOND) && slot0.getCount() == 3,
                "main inventory restored (slot + count)");
        helper.assertTrue(player.getItemBySlot(EquipmentSlot.HEAD).is(Items.IRON_HELMET),
                "armor restored");
        helper.assertTrue(player.getItemBySlot(EquipmentSlot.CHEST).isEmpty(),
                "kit elytra vanished");
        helper.assertTrue(player.getItemBySlot(EquipmentSlot.OFFHAND).is(Items.SHIELD),
                "offhand restored");
        boolean kitGone = true;
        for (ItemStack stack : player.getInventory().items) {
            if (stack.is(Items.STONE_SWORD)) {
                kitGone = false;
            }
        }
        helper.assertTrue(kitGone, "kit sword vanished");
        helper.assertTrue(player.getHealth() == healthBefore, "health restored");
        helper.assertTrue(player.getFoodData().getFoodLevel() == 13
                && player.getFoodData().getSaturationLevel() == 3.5F, "food restored");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void coursesAreDeterministicPerSeed(GameTestHelper helper) {
        // Arena: same seed → identical layout; footprint independent of seed.
        var arenaA = ArenaGame.layout(5);
        var arenaB = ArenaGame.layout(5);
        helper.assertTrue(arenaA.size() == arenaB.size(), "arena layout size deterministic");
        helper.assertTrue(arenaA.get(0).equals(arenaB.get(0))
                && arenaA.get(arenaA.size() - 1).equals(arenaB.get(arenaB.size() - 1)),
                "arena layout blocks deterministic");
        helper.assertTrue(ArenaGame.layout(6).size() == arenaA.size(),
                "arena footprint constant across seeds");

        // Race: cache-busting recompute must reproduce the same course; rings 12..16.
        ElytraRace.Course course3 = ElytraRace.courseFor(3);
        List<Vec3> centers = List.copyOf(course3.ringCenters());
        int rings = centers.size();
        helper.assertTrue(rings >= 12 && rings <= 16, "ring count in 12..16 (got " + rings + ")");
        ElytraRace.courseFor(4); // evict the single-entry cache
        ElytraRace.Course recomputed = ElytraRace.courseFor(3);
        helper.assertTrue(recomputed.ringCenters().equals(centers), "race course deterministic");
        helper.assertTrue(!ElytraRace.courseFor(4).ringCenters().equals(centers),
                "different seeds vary the course");
        double loop = 0.0D;
        for (int i = 0; i < rings; i++) {
            loop += centers.get(i).distanceTo(centers.get((i + 1) % rings));
        }
        helper.assertTrue(loop > 400.0D && loop < 900.0D,
                "loop length ~600 blocks (got " + (int) loop + ")");
        helper.assertTrue(!course3.blocks().isEmpty(), "race course has blocks");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void crashResumePastEndsAtClosesOnBoot(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        MinigameState state = MinigameState.get(server);
        // Simulate a crash mid-event: persisted RUNNING with endsAt in the past.
        state.beginInstance("arena", System.currentTimeMillis() - 1_000L);
        state.setPhase(MinigameState.Phase.RUNNING);

        MinigameService.resumeOnBoot(server);

        helper.assertTrue(state.phase() == MinigameState.Phase.IDLE,
                "boot with past endsAt resumes CLOSING and lands in IDLE");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void dimensionsLoadAndParticipationRewardIsIdempotent(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        for (String gameId : MinigameDimensions.gameIds()) {
            helper.assertTrue(MinigameDimensions.byGameId(gameId) != null,
                    gameId + " has a dimension key");
            helper.assertTrue(server.getLevel(MinigameDimensions.byGameId(gameId)) != null,
                    "dimension for " + gameId + " is loaded");
        }
        helper.assertTrue("arena".equals(MinigameDimensions.gameIdOf(MinigameDimensions.ARENA))
                && "race".equals(MinigameDimensions.gameIdOf(MinigameDimensions.SKY)),
                "reverse lookup");

        MinigameState state = new MinigameState();
        state.beginInstance("race", System.currentTimeMillis() + 60_000L);
        UUID uuid = GameTestSupport.testUuid(3);
        helper.assertTrue(state.markParticipationRewarded(uuid), "first payout attempt passes");
        helper.assertTrue(!state.markParticipationRewarded(uuid), "second payout attempt refused");
        state.beginInstance("race", System.currentTimeMillis() + 60_000L);
        helper.assertTrue(state.markParticipationRewarded(uuid), "new instance re-arms the payout");

        helper.assertTrue("01:23.456".equals(ElytraRace.lapTime(83_456L)), "lap time formatting");
        helper.succeed();
    }
}
