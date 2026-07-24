package dev.projecteclipse.eclipse.drama;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.analytics.AnalyticsApi;
import dev.projecteclipse.eclipse.analytics.AnalyticsKeys;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.skills.SkillPerks;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.ore.OreConfig;
import dev.projecteclipse.eclipse.worldgen.ore.VeinTracker;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.tags.BlockTags;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.Vec3;

/**
 * Mining dopamine layer (W4-FEEL, IDEA-03 top 3). Pure feel additions riding existing
 * seams — no new persistence, no new payload shapes:
 *
 * <ul>
 *   <li><b>First-ore fanfare (#1):</b> the first time a player naturally mines each
 *       configured ore id (stone + deepslate variants combined), a private
 *       {@code UI_UNLOCK_STING} plays over the {@code ore_first_<oreId>} proc toast.
 *       Detection is the analytics {@code mine:<block_id>} lifetime sum {@code == 1}
 *       right after the increment (the signal fires post-count) — zero new state.</li>
 *   <li><b>Vein reveal + vein-complete chime (#2):</b> {@link VeinTracker} re-derives
 *       the deterministic vein at break time; an intact first break shows the actionbar
 *       size reveal ("Iron Ore vein · 7 blocks") and the last remaining block plays a
 *       two-note chime (amethyst + the proc chime) with a "Vein cleared ×7" toast.</li>
 *   <li><b>Ore-proc sparkle (#3/#4):</b> {@link #sendOreProcSparkle} ships the
 *       {@code eclipse:fx/ore_proc} id on the sanctioned {@code S2CFxEventPayload} seam
 *       ({@code a} = magnitude, {@code b} = packed 24-bit ore RGB — exact in a float).
 *       {@code FxPayloads} is FROZEN/shared: the client dispatch branch is delivered as
 *       an exact diff in {@code docs/plans_v3/wiring/W4-FEEL_wiring.md}; the handler
 *       body ships ready in {@code client/drama/OreProcFxClient}. Until the integrator
 *       lands that branch the payload falls into the debug-log arm — silent no-op.</li>
 * </ul>
 *
 * <p>Called from the tail of {@code SkillPerks.onNaturalOreMined} (already natural-only
 * and placed-block re-checked) and from {@code BuffEffects.onBlockDrops} (sparkle only).
 * Stateless — nothing to reset on ServerStopped.</p>
 */
public final class MiningFeelService {
    /** New id on the frozen FX seam — see the W4-FEEL wiring doc for the client branch. */
    public static final net.minecraft.resources.ResourceLocation FX_ORE_PROC =
            net.minecraft.resources.ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/ore_proc");

    /** Sparkle broadcast radius — bystanders see the jackpot glint too (it is at a block). */
    private static final double SPARKLE_RANGE = 32.0D;
    /** Quiet-Eclipse accent, the fallback sparkle color (matches {@code EclipseUiTheme.ACCENT}). */
    private static final int ACCENT_RGB = 0xB98CFF;
    /** Actionbar reveal tint (the containment HINT_COLOR purple — reads as "system whisper"). */
    private static final int REVEAL_COLOR = 0xB98CFF;

    private MiningFeelService() {}

    /**
     * Feel hook for one natural ore break; fanfare first (the rarer, bigger beat), then
     * the vein feel. Cheap early-outs: non-disc dimensions and non-configured blocks
     * leave before any work happens.
     */
    public static void onNaturalOreMined(ServerPlayer player, BlockState state, BlockPos pos) {
        ServerLevel level = player.serverLevel();
        DiscProfile profile = VeinTracker.profileOf(level);
        if (profile == null) {
            return;
        }
        OreConfig.ResolvedOre ore = VeinTracker.oreFor(profile, state);
        if (ore == null) {
            return;
        }

        // --- #1 first-ore-of-tier fanfare ---
        if (lifetimeMined(player, ore) == 1L) {
            player.playNotifySound(EclipseSounds.UI_UNLOCK_STING.get(), SoundSource.PLAYERS, 0.9F, 1.0F);
            SkillPerks.sendProcFeedback(player, "ore_first_" + ore.id(), 0.0F);
        }

        // --- #2 vein reveal + completion ---
        VeinTracker.Scan scan = VeinTracker.scan(level, pos, profile, ore);
        if (scan == null || scan.total() <= 1) {
            return; // no derivable vein / single-block vein: no progress bar to celebrate
        }
        if (scan.present() == scan.total()) {
            // First break of an intact vein: size reveal, actionbar only (no sound — the
            // payoff note is saved for completion; Quiet-Eclipse anticipation).
            player.displayClientMessage(Component.translatable("message.eclipse.vein.reveal",
                    state.getBlock().getName(), scan.total()).withColor(REVEAL_COLOR), true);
        }
        if (scan.present() == 1) {
            // This break clears the vein: bright note over the proc chime = two-note payoff.
            player.playNotifySound(SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.PLAYERS, 0.6F, 1.4F);
            SkillPerks.sendProcFeedback(player, "vein_clear", scan.total());
        }
    }

    /**
     * Lifetime natural mines of this ore, BOTH variants combined — so mining a deepslate
     * variant after the stone variant (or vice versa) never re-fires the fanfare. The
     * analytics increment for the current break lands before the signal fires, so the
     * very first break reads exactly 1. Dynamic-key-cap overflow under-counts → the
     * fanfare fails silent (never double-fires).
     */
    private static long lifetimeMined(ServerPlayer player, OreConfig.ResolvedOre ore) {
        String stoneId = BuiltInRegistries.BLOCK.getKey(ore.stoneOre()).toString();
        long sum = AnalyticsApi.sumAcrossDays(player.server, player.getUUID(),
                AnalyticsKeys.PREFIX_MINE + stoneId);
        if (ore.deepOre() != ore.stoneOre()) {
            String deepId = BuiltInRegistries.BLOCK.getKey(ore.deepOre()).toString();
            sum += AnalyticsApi.sumAcrossDays(player.server, player.getUUID(),
                    AnalyticsKeys.PREFIX_MINE + deepId);
        }
        return sum;
    }

    /**
     * Ore-proc sparkle (#3/#4): one-shot burst at the block that just paid out extra
     * drops. {@code magnitude} scales the client burst slightly (extra copies minted);
     * {@code state} picks the ore tint, {@code null} → accent purple. Client side is
     * {@code reducedFx}-gated in {@code OreProcFxClient}.
     */
    public static void sendOreProcSparkle(ServerLevel level, BlockPos pos, float magnitude,
            @Nullable BlockState state) {
        FxPayloads.sendFxEvent(level, FX_ORE_PROC, Vec3.atCenterOf(pos),
                magnitude, oreColor(state), SPARKLE_RANGE);
    }

    /** Packed 24-bit RGB per ore family (exact as a float — 0xFFFFFF < 2²⁴). */
    private static float oreColor(@Nullable BlockState state) {
        if (state == null) {
            return ACCENT_RGB;
        }
        if (state.is(BlockTags.COAL_ORES)) {
            return 0x4A4A52;
        }
        if (state.is(BlockTags.COPPER_ORES)) {
            return 0xC26B44;
        }
        if (state.is(BlockTags.IRON_ORES)) {
            return 0xD8AF93;
        }
        if (state.is(BlockTags.GOLD_ORES)) {
            return 0xFCEE4B;
        }
        if (state.is(BlockTags.REDSTONE_ORES)) {
            return 0xFF4040;
        }
        if (state.is(BlockTags.LAPIS_ORES)) {
            return 0x3E64C8;
        }
        if (state.is(BlockTags.DIAMOND_ORES)) {
            return 0x4AEDD9;
        }
        if (state.is(BlockTags.EMERALD_ORES)) {
            return 0x17DD62;
        }
        return ACCENT_RGB;
    }
}
