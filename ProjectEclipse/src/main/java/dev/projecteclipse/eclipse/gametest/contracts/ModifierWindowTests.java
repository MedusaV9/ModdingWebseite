package dev.projecteclipse.eclipse.gametest.contracts;

import java.util.List;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.contracts.ContractConfig;
import dev.projecteclipse.eclipse.contracts.ContractModifierService;
import dev.projecteclipse.eclipse.contracts.ContractModifierService.Entry;
import dev.projecteclipse.eclipse.contracts.ContractModifierService.Kind;
import dev.projecteclipse.eclipse.contracts.ContractModifierService.ModifierState;
import dev.projecteclipse.eclipse.contracts.ContractService;
import dev.projecteclipse.eclipse.contracts.ContractState;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.time.EclipseClock;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.skills.SkillsApi;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * D3 acceptance: contract DEBUFFS are window-scoped, not day-scoped. Covers the epoch
 * expiry sweep (purge + skills-multiplier restore, day-scoped advantages untouched), the
 * NBT round-trip of the new {@code expiresAtEpochMillis} field (including pre-D3 saves
 * loading as {@code 0} = day-scoped only), the rollover purge still clearing day-scoped
 * advantages, and the wrong-kill debuff deadline math ({@code windowEnd} floored at
 * {@code debuffMinMinutes}).
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class ModifierWindowTests {
    private ModifierWindowTests() {}

    private static ServerPlayer mockServerPlayer(GameTestHelper helper) {
        // WAVE10: central helper — configures the mock connection so tick broadcasters
        // (InvLockSync/UnlockSync) can't crash the GameTestServer on a lingering mock.
        return GameTestSupport.mockServerPlayerInLevel(helper);
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void epochSweepExpiresDebuffsAndRestores(GameTestHelper helper) {
        ServerPlayer player = mockServerPlayer(helper);
        MinecraftServer server = player.server;
        UUID id = player.getUUID();
        ContractModifierService.clearAll(server);
        long t0 = System.currentTimeMillis();
        EclipseClock.setEpochMillisSupplier(() -> t0);
        try {
            int day = EclipseWorldState.get(server).getDay();
            // Window-scoped debuffs (the wrong-kill shape) + one day-scoped advantage.
            ContractModifierService.grantSkillsMulUntil(server, id, 0.5F, t0 + 10_000L);
            ContractModifierService.grantDamageMulUntil(server, id, 0.8F, t0 + 10_000L);
            ContractModifierService.grantDamageMul(server, id, 1.1F, day);
            helper.assertTrue(SkillsApi.getSecretMultiplier(server, id) == 0.5F,
                    "skills malus applied on grant");
            List<String> rows = ContractModifierService.describe(server, id);
            helper.assertTrue(rows.size() == 3, "three ledger rows");
            helper.assertTrue(rows.stream().anyMatch(row -> row.contains("left")),
                    "epoch rows describe their remaining time");

            // Before the deadline the sweep must not touch anything.
            helper.assertTrue(ContractModifierService.sweepExpired(server).isEmpty(),
                    "nothing purged before the window ends");
            helper.assertTrue(ContractModifierService.describe(server, id).size() == 3,
                    "rows intact pre-deadline");

            // Past the deadline: exactly the two epoch rows die; the advantage survives.
            EclipseClock.setEpochMillisSupplier(() -> t0 + 10_001L);
            List<Entry> purged = ContractModifierService.sweepExpired(server);
            helper.assertTrue(purged.size() == 2, "both window-scoped rows purged, got " + purged.size());
            helper.assertTrue(SkillsApi.getSecretMultiplier(server, id) == 1.0F,
                    "skills multiplier restored to 1.0");
            List<String> remaining = ContractModifierService.describe(server, id);
            helper.assertTrue(remaining.size() == 1 && remaining.get(0).startsWith("DAMAGE_MUL=1.1"),
                    "day-scoped advantage survives the epoch sweep");
            helper.assertTrue(ContractModifierService.sweepExpired(server).isEmpty(),
                    "sweep is idempotent");
        } finally {
            EclipseClock.resetToSystem();
            ContractModifierService.clearAll(server);
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void skillsRestoreFallsBackToLiveEntry(GameTestHelper helper) {
        ServerPlayer player = mockServerPlayer(helper);
        MinecraftServer server = player.server;
        UUID id = player.getUUID();
        ContractModifierService.clearAll(server);
        long t0 = System.currentTimeMillis();
        EclipseClock.setEpochMillisSupplier(() -> t0);
        try {
            int day = EclipseWorldState.get(server).getDay();
            // A hunter who wrong-killed (0.5 window malus) and then succeeded (2.0 day
            // advantage): the malus expiring must restore the ADVANTAGE, not blanket 1.0.
            ContractModifierService.grantSkillsMulUntil(server, id, 0.5F, t0 + 5_000L);
            ContractModifierService.grantSkillsMul(server, id, 2.0F, day);
            helper.assertTrue(SkillsApi.getSecretMultiplier(server, id) == 2.0F,
                    "last grant wins while both live");

            EclipseClock.setEpochMillisSupplier(() -> t0 + 5_001L);
            ContractModifierService.sweepExpired(server);
            helper.assertTrue(SkillsApi.getSecretMultiplier(server, id) == 2.0F,
                    "surviving day-scoped skills advantage re-applied after the sweep");
        } finally {
            EclipseClock.resetToSystem();
            ContractModifierService.clearAll(server);
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void savedDataRoundTripAndLegacyLoad(GameTestHelper helper) {
        UUID holder = GameTestSupport.testUuid(31);
        UUID other = GameTestSupport.testUuid(32);
        var registries = helper.getLevel().registryAccess();

        ModifierState state = new ModifierState();
        state.add(new Entry(holder, Kind.DAMAGE_MUL, 0.8F, null, 3, 123_456L));
        state.add(new Entry(holder, Kind.GRUDGE, 1.35F, other, 3, 0L));
        state.setPauseAnchorEpochMillis(9_999L);

        CompoundTag saved = state.save(new CompoundTag(), registries);
        ModifierState loaded = ModifierState.load(saved, registries);
        List<Entry> entries = loaded.entries();
        helper.assertTrue(entries.size() == 2, "two rows round-trip");
        helper.assertTrue(entries.get(0).expiresAtEpochMillis() == 123_456L,
                "epoch deadline round-trips");
        helper.assertTrue(entries.get(1).expiresAtEpochMillis() == 0L,
                "day-scoped row stays 0");
        helper.assertTrue(other.equals(entries.get(1).other()), "grudge target round-trips");
        helper.assertTrue(loaded.pauseAnchorEpochMillis() == 9_999L, "pause anchor round-trips");

        // Pre-D3 save shape: rows without the epoch field must load as 0 (day-scoped only).
        CompoundTag legacyRow = new CompoundTag();
        legacyRow.putUUID("holder", holder);
        legacyRow.putString("kind", Kind.SKILLS_MUL.name());
        legacyRow.putFloat("value", 0.75F);
        legacyRow.putInt("expiresAfterDay", 5);
        ListTag legacyList = new ListTag();
        legacyList.add(legacyRow);
        CompoundTag legacyTag = new CompoundTag();
        legacyTag.put("entries", legacyList);
        ModifierState legacy = ModifierState.load(legacyTag, registries);
        helper.assertTrue(legacy.entries().size() == 1
                        && legacy.entries().get(0).expiresAtEpochMillis() == 0L,
                "legacy row loads as day-scoped (epoch 0)");
        helper.assertTrue(legacy.pauseAnchorEpochMillis() == 0L, "legacy anchor defaults to 0");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void rolloverStillClearsDayScopedRows(GameTestHelper helper) {
        UUID holder = GameTestSupport.testUuid(33);
        // Standalone state — no global signals fired, no other systems disturbed.
        ModifierState state = new ModifierState();
        state.add(new Entry(holder, Kind.SKILLS_MUL, 2.0F, null, 3, 0L));
        state.add(new Entry(holder, Kind.DAMAGE_MUL, 0.8F, null, 3, Long.MAX_VALUE));
        state.add(new Entry(holder, Kind.AWARD_VOID, 0.0F, null, 4, 0L));

        // Same-day: nothing expires yet.
        helper.assertTrue(state.removeExpired(3).isEmpty(), "no purge while the day runs");
        // Rollover to day 4: both day-3 rows die — the epoch row too (whichever scope
        // expires first wins; contracts never span days).
        List<Entry> purged = state.removeExpired(4);
        helper.assertTrue(purged.size() == 2, "day-3 advantage AND epoch row purged at rollover");
        helper.assertTrue(state.entries().size() == 1
                        && state.entries().get(0).kind() == Kind.AWARD_VOID,
                "day-4 award void survives");

        // Epoch sweep ignores day-scoped rows entirely.
        helper.assertTrue(state.removeEpochExpired(Long.MAX_VALUE).isEmpty(),
                "epoch purge never touches day-scoped rows");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void wrongKillDebuffDeadlineIsWindowScoped(GameTestHelper helper) {
        // The deadline every wrong-kill/target-side grant receives: window end, floored
        // at now + debuffMinMinutes (a last-second Blutschuld still stings a little).
        long floorMillis = ContractConfig.get().debuffMinMinutes() * 60_000L;
        helper.assertTrue(ContractConfig.defaults().debuffMinMinutes() == 10,
                "default debuff floor is 10 minutes");
        long now = 1_000_000L;

        ContractState state = new ContractState();
        state.setEndsAtEpochMillis(now + floorMillis * 3L);
        helper.assertTrue(ContractService.debuffExpiresAt(state, now) == now + floorMillis * 3L,
                "long window: debuff dies exactly at the window end");

        state.setEndsAtEpochMillis(now + 1_000L);
        helper.assertTrue(ContractService.debuffExpiresAt(state, now) == now + floorMillis,
                "near-expiry window: debuff floored at debuffMinMinutes");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void pauseShiftPushesEpochDeadlines(GameTestHelper helper) {
        UUID holder = GameTestSupport.testUuid(34);
        ModifierState state = new ModifierState();
        state.add(new Entry(holder, Kind.DAMAGE_MUL, 0.8F, null, 3, 50_000L));
        state.add(new Entry(holder, Kind.SKILLS_MUL, 2.0F, null, 3, 0L));

        state.shiftEpochDeadlines(7_500L);
        helper.assertTrue(state.entries().get(0).expiresAtEpochMillis() == 57_500L,
                "epoch deadline shifted by the paused span");
        helper.assertTrue(state.entries().get(1).expiresAtEpochMillis() == 0L,
                "day-scoped rows never shift");
        state.shiftEpochDeadlines(0L);
        helper.assertTrue(state.entries().get(0).expiresAtEpochMillis() == 57_500L,
                "zero/negative deltas are ignored");
        helper.succeed();
    }
}
