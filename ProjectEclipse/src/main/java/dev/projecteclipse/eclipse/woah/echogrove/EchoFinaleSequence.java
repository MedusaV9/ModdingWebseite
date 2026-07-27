package dev.projecteclipse.eclipse.woah.echogrove;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.ExperienceOrb;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * WOAH-05 finale (plan §7.3) — the 600t "the grove remembers" beat, started once
 * per world when the fifth memory mote is deposited:
 *
 * <pre>
 * t0    deposit chime already played (MemoryOrbEntity); 20t of held breath
 * t20   forced flood (hold 600t, afterglow cue variant); every scene switches to
 *       GATHER — actors walk/run star-shaped to a ring around the tree
 * t80   finale blossom set grows in (60t) + CUE_ECHO_BLOOM_RAIN + motif ×2
 * t580  reward materializes at the tree foot (item drops + XP ring) + AWARD_STING
 *       + TITLE caption "Der Hain erinnert sich."
 * t620  flood tail ends into the persistent afterglow: finaleDone=true, scenes
 *       return to their loops, 15% crowns + froglights stay half-grown forever
 * </pre>
 *
 * <p>Reward drops are spawned in code (this repo has no programmatic loot-table
 * seam); {@code data/eclipse/loot_table/event/echo_grove_finale.json} ships as the
 * datapack-facing reference of the same content (plan §7.4).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EchoFinaleSequence {
    /** Timeline beats (offsets from start; the flood is forced at t20 with 600t hold). */
    private static final int T_FLOOD = 20;
    private static final int T_BLOOM = 80;
    private static final int T_REWARD = 580;
    private static final int T_END = 620;
    private static final int REWARD_XP = 500;
    private static final int XP_ORBS = 10;

    private static int tick = -1;

    private EchoFinaleSequence() {}

    /** Entry (MemoryOrbEntity deposit #5 or {@code /dev woah echo finale}). Once per world. */
    public static void start(ServerLevel level, @Nullable ServerPlayer trigger) {
        EchoGroveState state = EchoGroveState.get(level.getServer());
        if (state.finaleDone() || tick >= 0 || state.treeCenter() == null) {
            return;
        }
        tick = 0;
        EclipseMod.LOGGER.info("EchoFinaleSequence: started");
    }

    public static boolean running() {
        return tick >= 0;
    }

    /** Dev reset: abort a running finale (state handled by the caller). */
    public static void abort() {
        tick = -1;
        EchoSceneService.endGather();
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (tick < 0) {
            return;
        }
        ServerLevel level = event.getServer().overworld();
        EchoGroveState state = EchoGroveState.get(event.getServer());
        BlockPos tree = state.treeCenter();
        if (tree == null) {
            tick = -1;
            return;
        }
        int t = tick++;
        if (t == T_FLOOD) {
            MemoryFloodService.start(level, tree, 600, true);
            EchoSceneService.startGather(level, tree);
        }
        if (t == T_BLOOM) {
            EchoOverlayBuilder.spawnFinaleBloom(level, tree);
            FxPayloads.sendFxEvent(level, EchoGroveCues.CUE_ECHO_BLOOM_RAIN,
                    Vec3.atCenterOf(tree.above(EchoGroveLayout.TREE_HEIGHT)), 600.0F, 0.0F, 256.0D);
        }
        if (t == T_REWARD) {
            dropReward(level, tree);
            level.playSound(null, tree.getX() + 0.5D, tree.getY() + 2.0D, tree.getZ() + 0.5D,
                    EclipseSounds.AWARD_STING.get(), SoundSource.RECORDS, 0.9F, 1.0F);
            // The title goes to everyone near enough to have witnessed it.
            for (ServerPlayer player : level.players()) {
                if (player.position().distanceToSqr(Vec3.atCenterOf(tree)) <= 96.0D * 96.0D) {
                    PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(
                            "echo.eclipse.finale.title", 100, S2CCaptionPayload.STYLE_TITLE));
                }
            }
        }
        if (t >= T_END) {
            tick = -1;
            state.setFinaleDone();
            EchoGrovePayloads.syncAll(event.getServer());
            EchoSceneService.endGather();
            EchoOverlayBuilder.settleFinaleBloom();
            // Re-park the pool onto its afterglow floors (15% crowns stay at 0.8).
            EchoOverlayBuilder.reparkAll(true);
            EclipseMod.LOGGER.info("EchoFinaleSequence: done — afterglow persisted");
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        tick = -1;
    }

    /**
     * The reward at the tree foot (plan §7.4): the echo blossom, 3 diamonds, a
     * 16-stack of pale-oak leaves as a build souvenir, and 500 XP in a small orb
     * ring. Mirrored by {@code data/eclipse/loot_table/event/echo_grove_finale.json}.
     */
    private static void dropReward(ServerLevel level, BlockPos tree) {
        Vec3 foot = new Vec3(tree.getX() + 0.5D, tree.getY() + 1.2D, tree.getZ() + 0.5D);
        dropStack(level, foot, new ItemStack(EchoGroveItems.ECHO_BLOSSOM.get()));
        dropStack(level, foot, new ItemStack(Items.DIAMOND, 3));
        dropStack(level, foot, new ItemStack(
                dev.projecteclipse.eclipse.registry.PaleGardenBlocks.PALE_OAK_LEAVES.get(), 16));
        for (int i = 0; i < XP_ORBS; i++) {
            double angle = (i / (double) XP_ORBS) * Math.PI * 2.0D;
            ExperienceOrb.award(level, foot.add(Math.cos(angle) * 1.8D, 0.4D,
                    Math.sin(angle) * 1.8D), REWARD_XP / XP_ORBS);
        }
    }

    private static void dropStack(ServerLevel level, Vec3 pos, ItemStack stack) {
        ItemEntity item = new ItemEntity(level, pos.x, pos.y, pos.z, stack);
        item.setDefaultPickUpDelay();
        item.setDeltaMovement(0.0D, 0.15D, 0.0D);
        level.addFreshEntity(item);
    }
}
