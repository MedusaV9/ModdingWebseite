package dev.projecteclipse.eclipse.gametest.lives;

import java.util.UUID;

import com.google.gson.JsonObject;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.contracts.ContractService;
import dev.projecteclipse.eclipse.contracts.ContractState;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import dev.projecteclipse.eclipse.core.time.EclipseClock;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.lives.HeartTheftService;
import dev.projecteclipse.eclipse.lives.HeartTheftService.TheftState;
import dev.projecteclipse.eclipse.lives.HeartTheftService.Verdict;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.GameType;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * D4 acceptance: the out-of-event heart-theft policy. Covers the STEAL verdict, the pair
 * cooldown (both directions, freezes ALL Leben movement), the victim floor at 1 Leben
 * (murder can never ghost anyone), the contract-pair exemption (both role orientations;
 * non-pair kills during a window stay steals), ghost/spectator/pre-event exemptions, the
 * config defaults + live dev toggle, and the cooldown SavedData round-trip.
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class HeartTheftTests {
    private HeartTheftTests() {}

    private static ServerPlayer mockPlayer(GameTestHelper helper) {
        // WAVE10: central helper — configures the mock connection so tick broadcasters
        // (InvLockSync/UnlockSync) can't crash the GameTestServer on a lingering mock.
        ServerPlayer player = GameTestSupport.mockServerPlayerInLevel(helper);
        player.setGameMode(GameType.SURVIVAL);
        return player;
    }

    /** Shared setup: event done, theft on, clean cooldowns, killer 3 / victim 5 Leben. */
    private static boolean arm(ServerPlayer killer, ServerPlayer victim) {
        MinecraftServer server = killer.server;
        boolean eventWasDone = EclipseWorldState.get(server).isStartEventDone();
        EclipseWorldState.get(server).setStartEventDone(true);
        HeartTheftService.setEnabledLive(true);
        HeartTheftService.clearCooldowns(server);
        LivesApi.set(killer, 3);
        LivesApi.set(victim, 5);
        return eventWasDone;
    }

    private static void disarm(MinecraftServer server, boolean eventWasDone) {
        EclipseWorldState.get(server).setStartEventDone(eventWasDone);
        HeartTheftService.setEnabledLive(true);
        HeartTheftService.clearCooldowns(server);
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void stealVerdictAndPairCooldown(GameTestHelper helper) {
        ServerPlayer killer = mockPlayer(helper);
        ServerPlayer victim = mockPlayer(helper);
        MinecraftServer server = killer.server;
        boolean eventWasDone = arm(killer, victim);
        try {
            helper.assertTrue(HeartTheftService.evaluate(killer, victim) == Verdict.STEAL,
                    "clean out-of-event PvP kill = STEAL");

            HeartTheftService.recordSteal(killer, victim);
            long now = EclipseClock.epochMillis();
            long remaining = HeartTheftService.cooldownRemainingMillis(server,
                    killer.getUUID(), victim.getUUID(), now);
            helper.assertTrue(remaining > 0L, "cooldown armed after the steal");
            helper.assertTrue(HeartTheftService.evaluate(killer, victim) == Verdict.NO_STEAL_COOLDOWN,
                    "same pair on cooldown");
            helper.assertTrue(HeartTheftService.evaluate(victim, killer) == Verdict.NO_STEAL_COOLDOWN,
                    "cooldown blocks the reverse direction too");
            helper.assertTrue(Verdict.NO_STEAL_COOLDOWN.freezesDeathLoss(),
                    "cooldown kills move NO Leben in either direction");

            long cooldownMillis = HeartTheftService.config().cooldownMillis();
            helper.assertTrue(HeartTheftService.cooldownRemainingMillis(server,
                            killer.getUUID(), victim.getUUID(), now + cooldownMillis + 1L) == 0L,
                    "cooldown frees the pair after cooldownMinutes");
        } finally {
            disarm(server, eventWasDone);
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void victimFloorNeverGhostsFromTheft(GameTestHelper helper) {
        ServerPlayer killer = mockPlayer(helper);
        ServerPlayer victim = mockPlayer(helper);
        MinecraftServer server = killer.server;
        boolean eventWasDone = arm(killer, victim);
        try {
            LivesApi.set(victim, 1);
            helper.assertTrue(HeartTheftService.evaluate(killer, victim) == Verdict.NO_STEAL_FLOOR,
                    "victim at the floor = no steal");
            helper.assertTrue(Verdict.NO_STEAL_FLOOR.freezesDeathLoss(),
                    "floor kills take NOTHING (no victim loss, no killer gain)");
            LivesApi.set(victim, 2);
            helper.assertTrue(HeartTheftService.evaluate(killer, victim) == Verdict.STEAL,
                    "one above the floor steals again");
        } finally {
            disarm(server, eventWasDone);
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void contractPairKillsAreExempt(GameTestHelper helper) {
        ServerPlayer killer = mockPlayer(helper);
        ServerPlayer victim = mockPlayer(helper);
        MinecraftServer server = killer.server;
        boolean eventWasDone = arm(killer, victim);
        ContractState contract = ContractService.stateOf(server);
        try {
            contract.setMode(ContractState.Mode.REAL);
            contract.setPair(killer.getUUID(), victim.getUUID());
            contract.setEndsAtEpochMillis(EclipseClock.epochMillis() + 600_000L);
            contract.setPhase(ContractState.Phase.ACTIVE);
            helper.assertTrue(HeartTheftService.evaluate(killer, victim) == Verdict.NO_STEAL_CONTRACT_PAIR,
                    "hunter kills target: contract economy, no steal");
            helper.assertTrue(HeartTheftService.evaluate(victim, killer) == Verdict.NO_STEAL_CONTRACT_PAIR,
                    "target kills hunter (tables turned): no steal either");
            helper.assertTrue(!Verdict.NO_STEAL_CONTRACT_PAIR.freezesDeathLoss(),
                    "contract kills keep the normal death economy");

            // A NON-pair kill during the window stays a normal steal (the wrong-kill
            // Blutschuld already punishes the hunter case separately).
            contract.setPair(killer.getUUID(), GameTestSupport.testUuid(77));
            helper.assertTrue(HeartTheftService.evaluate(killer, victim) == Verdict.STEAL,
                    "non-pair kill during an active window remains a steal");
        } finally {
            contract.clearContract();
            disarm(server, eventWasDone);
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void ghostSpectatorAndPreEventExemptions(GameTestHelper helper) {
        ServerPlayer killer = mockPlayer(helper);
        ServerPlayer victim = mockPlayer(helper);
        MinecraftServer server = killer.server;
        boolean eventWasDone = arm(killer, victim);
        try {
            victim.setData(EclipseAttachments.BANNED, true);
            helper.assertTrue(HeartTheftService.evaluate(killer, victim) == Verdict.NO_STEAL_GHOST,
                    "banned ghost victim is exempt");
            victim.setData(EclipseAttachments.BANNED, false);
            killer.setData(EclipseAttachments.BANNED, true);
            helper.assertTrue(HeartTheftService.evaluate(killer, victim) == Verdict.NO_STEAL_GHOST,
                    "banned ghost killer is exempt");
            killer.setData(EclipseAttachments.BANNED, false);

            killer.setGameMode(GameType.SPECTATOR);
            helper.assertTrue(HeartTheftService.evaluate(killer, victim) == Verdict.NO_STEAL_SPECTATOR,
                    "spectators never steal");
            killer.setGameMode(GameType.SURVIVAL);

            EclipseWorldState.get(server).setStartEventDone(false);
            helper.assertTrue(HeartTheftService.evaluate(killer, victim) == Verdict.NO_STEAL_PRE_EVENT,
                    "no theft before the start event");
            EclipseWorldState.get(server).setStartEventDone(true);
            helper.assertTrue(HeartTheftService.evaluate(killer, victim) == Verdict.STEAL,
                    "back to STEAL once every exemption is lifted");
        } finally {
            disarm(server, eventWasDone);
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void configDefaultsAndLiveToggle(GameTestHelper helper) {
        ServerPlayer killer = mockPlayer(helper);
        ServerPlayer victim = mockPlayer(helper);
        MinecraftServer server = killer.server;
        boolean eventWasDone = arm(killer, victim);
        try {
            HeartTheftService.Values defaults = HeartTheftService.parse(HeartTheftService.defaultsJson());
            helper.assertTrue(defaults.enabled(), "theft ships enabled");
            helper.assertTrue(defaults.cooldownMinutes() == 30, "default cooldownMinutes 30");
            helper.assertTrue(defaults.floorLives() == 1, "default floor 1 Leben");
            helper.assertTrue(defaults.ceremony(), "ceremony ships on");
            // A legacy/empty hearts.json behaves like the defaults (migration-safe).
            HeartTheftService.Values legacy = HeartTheftService.parse(new JsonObject());
            helper.assertTrue(legacy.enabled() && legacy.cooldownMinutes() == 30
                    && legacy.floorLives() == 1, "missing heartTheft block = defaults");

            // /dev contract theft off: the live snapshot flips without touching the file.
            HeartTheftService.setEnabledLive(false);
            helper.assertTrue(HeartTheftService.evaluate(killer, victim) == Verdict.NO_STEAL_DISABLED,
                    "toggle off denies the steal");
            helper.assertTrue(!Verdict.NO_STEAL_DISABLED.freezesDeathLoss(),
                    "disabled theft keeps the normal death loss");
            HeartTheftService.setEnabledLive(true);
            helper.assertTrue(HeartTheftService.evaluate(killer, victim) == Verdict.STEAL,
                    "toggle on restores the steal");
        } finally {
            disarm(server, eventWasDone);
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void theftStateNbtRoundTrip(GameTestHelper helper) {
        UUID a = GameTestSupport.testUuid(41);
        UUID b = GameTestSupport.testUuid(42);
        UUID c = GameTestSupport.testUuid(43);
        var registries = helper.getLevel().registryAccess();

        TheftState state = new TheftState();
        state.record(a, b, 1_000L, 3_600_000L);
        state.record(a, c, 2_000L, 3_600_000L);
        CompoundTag saved = state.save(new CompoundTag(), registries);
        TheftState loaded = TheftState.load(saved, registries);

        helper.assertTrue(loaded.records().size() == 2, "records round-trip");
        helper.assertTrue(loaded.lastStealBetween(a, b) == 1_000L, "pair timestamp round-trips");
        helper.assertTrue(loaded.lastStealBetween(b, a) == 1_000L, "lookup is direction-agnostic");
        helper.assertTrue(loaded.lastStealBetween(b, c) == 0L, "unknown pair = 0");

        // The horizon prune: a record older than the horizon dies on the next write.
        state.record(a, b, 3_700_000L, 3_600_000L);
        helper.assertTrue(state.lastStealBetween(a, c) == 0L, "stale record pruned past the horizon");
        helper.assertTrue(state.lastStealBetween(a, b) == 3_700_000L, "fresh record kept");
        helper.succeed();
    }
}
