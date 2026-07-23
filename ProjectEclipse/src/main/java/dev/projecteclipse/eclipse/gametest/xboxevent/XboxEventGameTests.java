package dev.projecteclipse.eclipse.gametest.xboxevent;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.devtools.dev.DevXboxCommands;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.xboxevent.XboxDimensions;
import dev.projecteclipse.eclipse.xboxevent.XboxEventService;
import dev.projecteclipse.eclipse.xboxevent.XboxEventState;
import dev.projecteclipse.eclipse.xboxevent.XboxPayloads;
import dev.projecteclipse.eclipse.xboxevent.XboxWorldInstaller;
import dev.projecteclipse.eclipse.xboxevent.XboxWorldsManifest;
import net.minecraft.core.BlockPos;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.item.ItemStack;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * P5-W9 gametests: state machine + NBT round-trip, instance-scoped lockouts, crash resume
 * (past {@code endsAt} boots straight into CLOSING→IDLE), payload round-trips, manifest and
 * loot decoding, duration parsing. The full E2E (portal walk-in, protected death, timeout
 * return) needs a client and is covered by the manual walkthrough in the worker report.
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class XboxEventGameTests {

    private XboxEventGameTests() {}

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void stateMachineNbtRoundTrip(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        XboxEventState state = new XboxEventState();
        long endsAt = System.currentTimeMillis() + 30L * 60_000L;
        state.beginInstance("tu12", endsAt);
        helper.assertTrue(state.phase() == XboxEventState.Phase.ANNOUNCED, "beginInstance → ANNOUNCED");
        state.setPhase(XboxEventState.Phase.OPEN);

        UUID participant = UUID.randomUUID();
        UUID quitter = UUID.randomUUID();
        state.addParticipant(participant);
        state.addParticipant(quitter);
        state.lockOut(quitter);
        state.putReturnAnchor(participant, new XboxEventState.ReturnAnchor(
                net.minecraft.world.level.Level.OVERWORLD, 1.5D, 64.0D, -7.5D, 90.0F, 10.0F));
        state.setPortal(net.minecraft.world.level.Level.OVERWORLD, new BlockPos(10, 70, -4));
        state.setRewardOverride("double_skill_xp", 45);

        CompoundTag saved = state.save(new CompoundTag(), server.registryAccess());
        XboxEventState loaded = XboxEventState.load(saved, server.registryAccess());

        helper.assertTrue(loaded.phase() == XboxEventState.Phase.OPEN, "phase survives NBT");
        helper.assertTrue("tu12".equals(loaded.worldId()), "worldId survives NBT");
        helper.assertTrue(loaded.endsAtEpochMillis() == endsAt, "endsAt survives NBT");
        helper.assertTrue(loaded.instanceId() == state.instanceId(), "instanceId survives NBT");
        helper.assertTrue(loaded.isParticipant(participant) && loaded.isParticipant(quitter),
                "participants survive NBT");
        helper.assertTrue(loaded.isLockedOut(quitter) && !loaded.isLockedOut(participant),
                "lockout survives NBT");
        XboxEventState.ReturnAnchor anchor = loaded.returnAnchor(participant);
        helper.assertTrue(anchor != null && anchor.x() == 1.5D && anchor.yaw() == 90.0F
                && anchor.dimension().equals(net.minecraft.world.level.Level.OVERWORLD),
                "return anchor survives NBT");
        helper.assertTrue(new BlockPos(10, 70, -4).equals(loaded.portalPos()), "portal pos survives NBT");
        helper.assertTrue("double_skill_xp".equals(loaded.rewardBuffIdOverride())
                && loaded.rewardMinutesOverride() == 45, "reward override survives NBT");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void lockoutScopesToInstance(GameTestHelper helper) {
        XboxEventState state = new XboxEventState();
        state.beginInstance("tu1", System.currentTimeMillis() + 60_000L);
        UUID quitter = UUID.randomUUID();
        state.lockOut(quitter);
        helper.assertTrue(state.isLockedOut(quitter), "locked out in the same instance");

        // Next instance: lockout auto-expires (per-instance scoping, §2.13.3) and is pruned.
        state.beginInstance("tu1", System.currentTimeMillis() + 60_000L);
        helper.assertTrue(!state.isLockedOut(quitter), "lockout cleared by next instance");
        helper.assertTrue(state.lockoutsSnapshot().isEmpty(), "stale lockouts pruned on new instance");

        // Manual clear path (/dev xboxevent lockout clear).
        UUID other = UUID.randomUUID();
        state.lockOut(other);
        helper.assertTrue(state.clearLockout(other), "clearLockout removes the entry");
        state.lockOut(other);
        helper.assertTrue(state.clearAllLockouts() == 1, "clearAllLockouts count");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void crashResumePastEndsAtClosesOnBoot(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        XboxEventState state = XboxEventState.get(server);
        // Simulate a crash mid-event: persisted OPEN with endsAt in the past.
        state.beginInstance("tu12", System.currentTimeMillis() - 1_000L);
        state.setPhase(XboxEventState.Phase.OPEN);

        XboxEventService.resumeOnBoot(server);

        helper.assertTrue(state.phase() == XboxEventState.Phase.IDLE,
                "boot with past endsAt resumes CLOSING and lands in IDLE");
        helper.assertTrue(XboxWorldInstaller.isResetStaged(server, "tu12"),
                "closing stages the world reset marker");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void timerPayloadRoundTrip(GameTestHelper helper) {
        GameTestSupport.assertPayloadRoundTrip(XboxPayloads.S2CXboxTimerPayload.STREAM_CODEC,
                new XboxPayloads.S2CXboxTimerPayload(1_800_000_000_000L, 1_799_999_100_000L, "tu12", true));
        GameTestSupport.assertPayloadRoundTrip(XboxPayloads.S2CXboxTimerPayload.STREAM_CODEC,
                new XboxPayloads.S2CXboxTimerPayload(0L, 0L, "", false));
        GameTestSupport.assertPayloadRoundTrip(XboxPayloads.C2SXboxAckPayload.STREAM_CODEC,
                new XboxPayloads.C2SXboxAckPayload(true));
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void manifestAndDimensionsAgree(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        Map<String, XboxWorldsManifest.WorldEntry> worlds = XboxWorldsManifest.all();
        helper.assertTrue(worlds.size() == 3, "manifest lists 3 worlds (got " + worlds.size() + ")");
        for (String worldId : List.of("tu1", "tu12", "tu14")) {
            XboxWorldsManifest.WorldEntry entry = worlds.get(worldId);
            helper.assertTrue(entry != null, "manifest has " + worldId);
            helper.assertTrue(entry.sha256().length() == 64, worldId + " sha256 present");
            helper.assertTrue(XboxDimensions.byWorldId(worldId) != null, worldId + " has a dimension key");
            // Datapack dimensions must actually load on this server.
            helper.assertTrue(server.getLevel(XboxDimensions.byWorldId(worldId)) != null,
                    "dimension eclipse:xbox_" + worldId + " is loaded");
        }
        helper.assertTrue(XboxDimensions.worldIdOf(XboxDimensions.XBOX_TU12).equals("tu12"),
                "reverse lookup");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void lootDecodesAndDiscsStayVanilla(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        Map<BlockPos, List<ItemStack>> loot = XboxWorldsManifest.loot(server, "tu12");
        helper.assertTrue(!loot.isEmpty(), "tu12 loot decodes (got " + loot.size() + " containers)");

        var xboxLevel = server.getLevel(XboxDimensions.XBOX_TU12);
        helper.assertTrue(xboxLevel != null, "xbox_tu12 level loaded");
        boolean sawDisc = false;
        int spilled = 0;
        for (Map.Entry<BlockPos, List<ItemStack>> container : loot.entrySet()) {
            List<ItemStack> stacks = XboxEventService.lootFor(xboxLevel, container.getKey());
            helper.assertTrue(stacks.size() == container.getValue().size(),
                    "lootFor spills every recorded stack at " + container.getKey());
            for (ItemStack stack : stacks) {
                helper.assertTrue(!stack.isEmpty(), "no empty spilled stacks");
                var id = net.minecraft.core.registries.BuiltInRegistries.ITEM.getKey(stack.getItem());
                if (id.getPath().startsWith("music_disc_")) {
                    sawDisc = true;
                    helper.assertTrue("minecraft".equals(id.getNamespace()),
                            "music discs stay vanilla (§2.14)");
                }
            }
            spilled += stacks.size();
        }
        helper.assertTrue(sawDisc, "tu12 disc quest loot present");
        helper.assertTrue(spilled > 0, "spilled stacks counted");
        // Outside xbox dims the provider must return nothing (chests just drop themselves).
        helper.assertTrue(XboxEventService.lootFor(helper.getLevel(),
                loot.keySet().iterator().next()).isEmpty(), "no loot outside xbox dims");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void durationParsing(GameTestHelper helper) {
        try {
            helper.assertTrue(DevXboxCommands.parseDurationMillis("5s") == 5_000L, "5s");
            helper.assertTrue(DevXboxCommands.parseDurationMillis("90s") == 90_000L, "90s");
            helper.assertTrue(DevXboxCommands.parseDurationMillis("45m") == 45L * 60_000L, "45m");
            helper.assertTrue(DevXboxCommands.parseDurationMillis("1h10m") == 70L * 60_000L, "1h10m");
            helper.assertTrue(DevXboxCommands.parseDurationMillis("5m30s") == 330_000L, "5m30s");
            helper.assertTrue(DevXboxCommands.parseDurationMillis("30") == 30L * 60_000L,
                    "bare number = minutes");
        } catch (com.mojang.brigadier.exceptions.CommandSyntaxException e) {
            helper.fail("valid duration rejected: " + e.getMessage());
            return;
        }
        boolean rejected = false;
        try {
            DevXboxCommands.parseDurationMillis("banana");
        } catch (com.mojang.brigadier.exceptions.CommandSyntaxException e) {
            rejected = true;
        }
        helper.assertTrue(rejected, "invalid duration rejected");
        helper.succeed();
    }
}
