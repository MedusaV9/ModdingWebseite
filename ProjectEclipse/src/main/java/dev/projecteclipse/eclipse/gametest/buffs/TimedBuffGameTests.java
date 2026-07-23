package dev.projecteclipse.eclipse.gametest.buffs;

import java.util.List;
import java.util.Map;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.buffs.BuffConfig;
import dev.projecteclipse.eclipse.buffs.BuffMath;
import dev.projecteclipse.eclipse.buffs.PlacedBlockCheck;
import dev.projecteclipse.eclipse.analytics.PlacedBlockData;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import dev.projecteclipse.eclipse.voice.VoiceMuteApi;
import net.minecraft.core.BlockPos;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.chunk.LevelChunk;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * P4-B9 timed buff + voice gametests (pure math + lightweight integration).
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class TimedBuffGameTests {
    private TimedBuffGameTests() {}

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void buffStartExtendRefuseCap(GameTestHelper helper) {
        Map<String, BuffConfig.BuffDefinition> defs = BuffConfig.defaultConfig().buffs();
        BuffConfig.BuffDefinition skill = defs.get("double_skill_xp");
        BuffConfig.BuffDefinition supply = defs.get("supply_rush");
        helper.assertTrue(skill != null && supply != null, "defaults loaded");

        long now = 1_000_000L;
        List<BuffMath.ActiveBuff> active = List.of();

        List<BuffMath.ActiveBuff> started = BuffMath.applyStart(active, skill, 3, 1, 0.0F, now);
        helper.assertTrue(started != null && started.size() == 1, "start ok");
        long firstEnd = started.get(0).endsAtEpochMillis();

        List<BuffMath.ActiveBuff> extended = BuffMath.applyStart(started, skill, 3, 1, 0.0F, now + 1000L);
        helper.assertTrue(extended != null && extended.get(0).endsAtEpochMillis() > firstEnd, "extend");

        List<BuffMath.ActiveBuff> supplyStarted = BuffMath.applyStart(List.of(), supply, 3, 5, 0.0F, now);
        helper.assertTrue(supplyStarted != null && supplyStarted.size() == 1, "supply start");
        List<BuffMath.ActiveBuff> refused = BuffMath.applyStart(supplyStarted, supply, 3, 5, 0.0F, now);
        helper.assertTrue(refused == null, "refuse stack");

        active = started;
        List<BuffMath.ActiveBuff> capped = BuffMath.applyStart(active, defs.get("half_hunger"), 3, 1, 0.0F, now);
        helper.assertTrue(capped != null && capped.size() == 2, "second buff");
        capped = BuffMath.applyStart(capped, defs.get("double_ore_drops"), 3, 1, 0.0F, now);
        helper.assertTrue(capped != null && capped.size() == 3, "third buff");
        List<BuffMath.ActiveBuff> overCap = BuffMath.applyStart(capped, defs.get("xp_magnet"), 3, 1, 0.0F, now);
        helper.assertTrue(overCap == null, "maxActive cap");

        List<BuffMath.ActiveBuff> expired = BuffMath.pruneExpired(capped, firstEnd + 120_000L);
        helper.assertTrue(expired.isEmpty(), "expired after restart simulation");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void multiplierProduct(GameTestHelper helper) {
        var defs = BuffConfig.defaultConfig().buffs();
        long now = 500_000L;
        List<BuffMath.ActiveBuff> active = List.of(
                new BuffMath.ActiveBuff("double_skill_xp", now + 60_000L, 2.0F),
                new BuffMath.ActiveBuff("glitch_surge", now + 60_000L, 2.0F));
        float skill = BuffMath.multiplierProduct(active, defs, "skill_xp", now);
        float glitch = BuffMath.multiplierProduct(active, defs, "glitch_spawn", now);
        helper.assertTrue(Math.abs(skill - 2.0F) < 0.01F, "skill_xp");
        helper.assertTrue(Math.abs(glitch - 2.0F) < 0.01F, "glitch_spawn");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void placedBlockNaturalCheck(GameTestHelper helper) {
        ServerLevel level = helper.getLevel();
        BlockPos pos = helper.absolutePos(new BlockPos(0, 0, 0));
        LevelChunk chunk = level.getChunkAt(pos);
        PlacedBlockData data = PlacedBlockData.empty();
        long[] bits = data.sectionBits(level.getSectionIndex(pos.getY()), true);
        bits[0] = 1L;
        chunk.setData(EclipseAttachments.PLACED_BLOCKS, data);

        helper.assertTrue(PlacedBlockCheck.isPlaced(level, pos), "marked placed");
        helper.assertFalse(PlacedBlockCheck.isNatural(level, pos), "not natural");

        BlockPos other = helper.absolutePos(new BlockPos(1, 0, 0));
        helper.assertTrue(PlacedBlockCheck.isNatural(level, other), "unset natural");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void globalVoiceMute(GameTestHelper helper) {
        ServerPlayer player = GameTestSupport.mockSurvivalPlayer(helper);
        var server = helper.getLevel().getServer();
        VoiceMuteApi.setGlobalMuted(server, true);
        helper.assertTrue(VoiceMuteApi.isGlobalMuted(server), "global on");
        helper.assertTrue(VoiceMuteApi.isMuted(server, player), "player muted by global");
        VoiceMuteApi.setGlobalMuted(server, false);
        helper.assertFalse(VoiceMuteApi.isMuted(server, player) && VoiceMuteApi.isGlobalMuted(server),
                "global off clears global leg");
        helper.succeed();
    }
}
