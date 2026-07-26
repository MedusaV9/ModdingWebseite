package dev.projecteclipse.eclipse.gametest.minigames;

import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.minigames.ArenaGame;
import dev.projecteclipse.eclipse.minigames.CourseBlocks;
import dev.projecteclipse.eclipse.minigames.LegacyRace;
import dev.projecteclipse.eclipse.minigames.MinigameDimensions;
import dev.projecteclipse.eclipse.minigames.MinigameService;
import dev.projecteclipse.eclipse.minigames.MinigameSigns;
import dev.projecteclipse.eclipse.minigames.MinigameState;
import dev.projecteclipse.eclipse.minigames.RaceTrackBuilder;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
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
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * W4-MINIGAMES gametests (the {@code XboxEventGameTests} pattern): state machine + NBT
 * round-trip incl. tickets, the bulletproof ticket capture/restore path with a real mock
 * player, deterministic-per-seed course generation (incl. the F-061 Legacy circuit's
 * seed-independent racing line), notice-board support geometry, crash resume (past
 * {@code endsAt} boots straight into CLOSING→IDLE), participation-reward idempotence and
 * lap-time formatting. The full E2E (portal walk-in, protected death, kit combat, a driven
 * heat) needs a client and is covered by the manual walkthrough in the worker report.
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
        state.setRaceLap(racer, 2);
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
        helper.assertTrue(loaded.raceLap(racer) == 2, "race lap survives NBT");
        helper.assertTrue(loaded.raceLapStart(racer) == 1_000_000L, "lap start survives NBT");
        loaded.clearRacer(racer);
        helper.assertTrue(loaded.raceProgress(racer) == 0 && loaded.raceLap(racer) == 0
                && loaded.raceLapStart(racer) == 0L, "clearRacer wipes the live heat state");
        helper.assertTrue(loaded.raceFinishersSnapshot().equals(List.of(racer)),
                "clearRacer keeps the instance finisher record");
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

        // Race (F-061): the Legacy circuit is a hand-authored racing line, so its geometry
        // must NOT vary with the seed (only cosmetic accents do), and a rebuild has to
        // reproduce the previous layout block for block — the clear-then-build in
        // MinigameService derives the clear job from the persisted OLD seed.
        RaceTrackBuilder.Track track = LegacyRace.trackFor(3);
        List<RaceTrackBuilder.Checkpoint> gates = List.copyOf(track.checkpoints());
        List<CourseBlocks.Placement> blocks = List.copyOf(track.blocks());
        double lap = track.lapLength();
        helper.assertTrue(lap > 300.0D && lap < 500.0D,
                "lap length 300..500 blocks (got " + (int) lap + ")");
        helper.assertTrue(gates.size() == 7, "seven checkpoint gates (got " + gates.size() + ")");
        helper.assertTrue(gates.get(0).index() == 0, "gate 0 closes the lap");
        helper.assertTrue(track.lightSwitches().size() == 5, "five start lamps on the gantry");
        helper.assertTrue(track.gridSpots().size() == 12, "twelve grid slots");
        helper.assertTrue(track.signs().size() == 2, "both gantry pillars carry a board");
        for (RaceTrackBuilder.Checkpoint gate : gates) {
            helper.assertTrue(RaceTrackBuilder.bounds().contains(gate.center()),
                    "gate " + gate.index() + " lies inside the swept course bounds");
            helper.assertTrue(gate.center().y > RaceTrackBuilder.FALL_RESCUE_Y,
                    "gate " + gate.index() + " sits above the fall-rescue line");
        }

        // A boost straight has to stay walkable: blue ice cannot carry the half-step slab
        // the rest of the surface ramps on, so no ice block may ever be covered — an ice
        // cell with something on top means the zone drifted onto a slope.
        Set<BlockPos> occupied = new HashSet<>();
        for (CourseBlocks.Placement placement : blocks) {
            occupied.add(placement.pos());
        }
        int ice = 0;
        for (CourseBlocks.Placement placement : blocks) {
            if (placement.state().is(Blocks.BLUE_ICE)) {
                ice++;
                helper.assertTrue(!occupied.contains(placement.pos().above()),
                        "blue ice at " + placement.pos() + " is the top of the racing surface");
            }
        }
        helper.assertTrue(ice > 100, "both boost straights are paved with ice (got " + ice + ")");

        LegacyRace.trackFor(4); // evict the single-entry cache
        helper.assertTrue(LegacyRace.trackFor(3).blocks().equals(blocks),
                "race course deterministic per seed");
        helper.assertTrue(LegacyRace.trackFor(4).checkpoints().equals(gates),
                "the racing line is seed-independent");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void noticeBoardsHangOnTheirOwnLayout(GameTestHelper helper) {
        // A wall sign needs the block BEHIND its facing; if the pillar is missing from the
        // layout the board silently pops off the first time the chunk updates.
        Set<BlockPos> arenaBlocks = new HashSet<>();
        for (CourseBlocks.Placement placement : ArenaGame.layout(2)) {
            arenaBlocks.add(placement.pos());
        }
        List<MinigameSigns.SignSpec> arenaSigns = ArenaGame.signs();
        helper.assertTrue(arenaSigns.size() == 4, "four arena notice boards");
        for (MinigameSigns.SignSpec spec : arenaSigns) {
            Direction facing = spec.state().getValue(HorizontalDirectionalBlock.FACING);
            helper.assertTrue(arenaBlocks.contains(spec.pos()),
                    "the arena board at " + spec.pos() + " is part of the layout");
            helper.assertTrue(arenaBlocks.contains(spec.pos().relative(facing.getOpposite())),
                    "the arena board at " + spec.pos() + " has a support pillar");
            helper.assertTrue(spec.lines().size() == 4, "a board fills all four sign lines");
        }

        Set<BlockPos> raceBlocks = new HashSet<>();
        for (CourseBlocks.Placement placement : LegacyRace.layout(2)) {
            raceBlocks.add(placement.pos());
        }
        for (MinigameSigns.SignSpec spec : LegacyRace.signs(2)) {
            Direction facing = spec.state().getValue(HorizontalDirectionalBlock.FACING);
            helper.assertTrue(raceBlocks.contains(spec.pos()),
                    "the race board at " + spec.pos() + " is part of the layout");
            helper.assertTrue(raceBlocks.contains(spec.pos().relative(facing.getOpposite())),
                    "the race board at " + spec.pos() + " has a gantry pillar behind it");
        }
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

        helper.assertTrue("01:23.456".equals(LegacyRace.lapTime(83_456L)), "lap time formatting");
        helper.succeed();
    }
}
