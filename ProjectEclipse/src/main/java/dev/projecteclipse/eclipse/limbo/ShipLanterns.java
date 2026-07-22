package dev.projecteclipse.eclipse.limbo;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lives.BanService;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.CampfireBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * The four ghost-ship deck lanterns of the Ferryman fight (W12, spec §2.2 P2 "Crew"):
 * soul campfires at fixed deck positions (see {@link #positions}) — LIT is the lantern
 * state, so "extinguish" is a single block-state swap and everything survives restarts
 * for free.
 *
 * <p><b>Ghost-only re-lighting</b>: while a lantern is dark, a GHOST (a banned player —
 * {@link BanService#isBanned}) right-clicks it to start a {@value #CHANNEL_TICKS}-tick
 * (3 s) channel; the ghost must stay within {@value #CHANNEL_RANGE} blocks or the channel
 * breaks. Living players get an action-bar refusal — the vanilla flint-and-steel relight
 * path is also swallowed here so the mechanic cannot be bypassed. Progress feedback is
 * action bar + soul particles; completion flips LIT back on. The lantern block positions
 * double as the P3 sink-proof islands: the water pass only replaces air, so the campfires
 * never wash out.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ShipLanterns {
    /** Ghost re-light channel length: 3 s. */
    public static final int CHANNEL_TICKS = 60;
    /** Maximum distance the channeling ghost may drift from the lantern. */
    public static final double CHANNEL_RANGE = 3.0D;

    /** Deck-plan lantern spots (x, z): two per rail, clear of masts, sails and benches. */
    private static final int[][] LANTERN_XZ = {{-10, -3}, {-10, 3}, {10, -3}, {10, 3}};

    /** Active re-light channels by ghost UUID. Server-thread only. */
    private static final Map<UUID, Channel> CHANNELS = new HashMap<>();

    private record Channel(BlockPos pos, int startedTick) {}

    private ShipLanterns() {}

    /** The four lantern block positions, derived from the ship's waterline anchor. */
    public static List<BlockPos> positions(ServerLevel limbo) {
        int deckY = GhostShipBuilder.waterlineY(limbo) + 3;
        List<BlockPos> positions = new ArrayList<>(LANTERN_XZ.length);
        for (int[] xz : LANTERN_XZ) {
            positions.add(new BlockPos(xz[0], deckY + 1, xz[1]));
        }
        return positions;
    }

    /**
     * Places (lit) soul-campfire lanterns wherever the deck spot is not one already, and
     * dries out any waterlogged ones (P3 sink water waterlogs + douses them; a waterlogged
     * campfire can never burn, so it would stay broken forever). A dark-but-dry lantern is
     * left alone — that is a legitimate mid-P2 state.
     */
    public static void ensurePlaced(ServerLevel limbo) {
        int placed = 0;
        for (BlockPos pos : positions(limbo)) {
            BlockState state = limbo.getBlockState(pos);
            if (!state.is(Blocks.SOUL_CAMPFIRE)
                    || state.getValue(net.minecraft.world.level.block.state.properties.BlockStateProperties.WATERLOGGED)) {
                limbo.setBlockAndUpdate(pos, litState());
                placed++;
            }
        }
        if (placed > 0) {
            EclipseMod.LOGGER.info("Ship lanterns: placed {} soul-campfire lantern(s) on the deck", placed);
        }
    }

    /** Blows out {@code count} lanterns (P2 opener); returns how many actually went dark. */
    public static int extinguish(ServerLevel limbo, int count) {
        ensurePlaced(limbo);
        int darkened = 0;
        for (BlockPos pos : positions(limbo)) {
            if (darkened >= count) {
                break;
            }
            BlockState state = limbo.getBlockState(pos);
            if (state.is(Blocks.SOUL_CAMPFIRE) && state.getValue(CampfireBlock.LIT)) {
                limbo.setBlockAndUpdate(pos, state.setValue(CampfireBlock.LIT, false));
                limbo.playSound(null, pos, SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 1.0F, 0.6F);
                limbo.sendParticles(ParticleTypes.LARGE_SMOKE,
                        pos.getX() + 0.5D, pos.getY() + 0.6D, pos.getZ() + 0.5D, 12, 0.2D, 0.2D, 0.2D, 0.01D);
                EclipseMod.LOGGER.info("Ship lantern at {} extinguished", pos.toShortString());
                darkened++;
            }
        }
        return darkened;
    }

    /**
     * Relights everything (fight end / reset) and drops any running channels. Restores the
     * full pristine state rather than just flipping LIT: the P3 sink water waterlogs (and
     * thereby douses) the campfires, and a waterlogged campfire must lose its water too.
     */
    public static void relightAll(ServerLevel limbo) {
        CHANNELS.clear();
        int relit = 0;
        for (BlockPos pos : positions(limbo)) {
            BlockState state = limbo.getBlockState(pos);
            if (!state.equals(litState())) {
                limbo.setBlockAndUpdate(pos, litState());
                relit++;
            }
        }
        if (relit > 0) {
            EclipseMod.LOGGER.info("Ship lanterns: {} relit by the fight reset", relit);
        }
    }

    /** Whether every deck lantern currently burns (the P2 phase-end condition). */
    public static boolean allLit(ServerLevel limbo) {
        for (BlockPos pos : positions(limbo)) {
            BlockState state = limbo.getBlockState(pos);
            if (!state.is(Blocks.SOUL_CAMPFIRE) || !state.getValue(CampfireBlock.LIT)) {
                return false;
            }
        }
        return true;
    }

    /** Burning lantern count, for logs and probes. */
    public static int litCount(ServerLevel limbo) {
        int lit = 0;
        for (BlockPos pos : positions(limbo)) {
            BlockState state = limbo.getBlockState(pos);
            if (state.is(Blocks.SOUL_CAMPFIRE) && state.getValue(CampfireBlock.LIT)) {
                lit++;
            }
        }
        return lit;
    }

    // --- ghost-only interaction ---

    /**
     * Swallows every right-click on a lantern spot in limbo: living players are refused,
     * ghosts start (or keep) the 3 s re-light channel on a dark lantern.
     */
    @SubscribeEvent
    static void onRightClickBlock(PlayerInteractEvent.RightClickBlock event) {
        if (!(event.getEntity() instanceof ServerPlayer player)
                || !(event.getLevel() instanceof ServerLevel level)
                || !level.dimension().equals(LimboDimension.LIMBO)
                || !isLanternPos(level, event.getPos())) {
            return;
        }
        BlockState state = level.getBlockState(event.getPos());
        if (!state.is(Blocks.SOUL_CAMPFIRE)) {
            return;
        }
        // Ours: no vanilla campfire interaction (incl. flint-and-steel relights by the living).
        event.setCanceled(true);
        if (event.getHand() != InteractionHand.MAIN_HAND) {
            return;
        }
        if (state.getValue(CampfireBlock.LIT)) {
            return; // Nothing to tend.
        }
        if (!BanService.isBanned(player)) {
            player.displayClientMessage(Component.translatable("ritual.eclipse.lantern.ghost_only"), true);
            player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 0.8F);
            return;
        }
        Channel existing = CHANNELS.get(player.getUUID());
        if (existing != null && existing.pos().equals(event.getPos())) {
            return; // Already channeling this lantern; the tick loop drives progress.
        }
        CHANNELS.put(player.getUUID(), new Channel(event.getPos().immutable(), level.getServer().getTickCount()));
        player.displayClientMessage(Component.translatable("ritual.eclipse.lantern.channel", "0%"), true);
        level.playSound(null, event.getPos(), SoundEvents.SOUL_ESCAPE.value(), SoundSource.BLOCKS, 1.0F, 1.4F);
        EclipseMod.LOGGER.info("Ghost {} started re-lighting the lantern at {} ({}t channel)",
                player.getScoreboardName(), event.getPos().toShortString(), CHANNEL_TICKS);
    }

    /** Drives running channels: range/validity checks, progress feedback, completion. */
    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (CHANNELS.isEmpty()) {
            return;
        }
        ServerLevel limbo = event.getServer().getLevel(LimboDimension.LIMBO);
        if (limbo == null) {
            CHANNELS.clear();
            return;
        }
        int now = event.getServer().getTickCount();
        Iterator<Map.Entry<UUID, Channel>> iterator = CHANNELS.entrySet().iterator();
        while (iterator.hasNext()) {
            Map.Entry<UUID, Channel> entry = iterator.next();
            Channel channel = entry.getValue();
            ServerPlayer ghost = event.getServer().getPlayerList().getPlayer(entry.getKey());
            BlockState state = limbo.getBlockState(channel.pos());
            boolean lanternStillDark = state.is(Blocks.SOUL_CAMPFIRE) && !state.getValue(CampfireBlock.LIT);
            if (ghost == null || !ghost.isAlive() || ghost.level() != limbo || !BanService.isBanned(ghost)
                    || !lanternStillDark
                    || ghost.position().distanceTo(Vec3.atCenterOf(channel.pos())) > CHANNEL_RANGE) {
                iterator.remove();
                if (ghost != null) {
                    ghost.displayClientMessage(Component.translatable("ritual.eclipse.lantern.interrupted"), true);
                }
                EclipseMod.LOGGER.info("Lantern channel at {} broken ({})", channel.pos().toShortString(),
                        ghost == null ? "ghost gone" : "out of range or lantern state changed");
                continue;
            }
            int elapsed = now - channel.startedTick();
            if (elapsed % 10 == 0) {
                ghost.displayClientMessage(Component.translatable("ritual.eclipse.lantern.channel",
                        Math.min(100, elapsed * 100 / CHANNEL_TICKS) + "%"), true);
                limbo.sendParticles(ParticleTypes.SOUL, channel.pos().getX() + 0.5D,
                        channel.pos().getY() + 0.8D, channel.pos().getZ() + 0.5D, 4, 0.2D, 0.3D, 0.2D, 0.02D);
            }
            if (elapsed < CHANNEL_TICKS) {
                continue;
            }
            iterator.remove();
            // Pristine lit state (not just LIT=true): P3 sink water can waterlog the dark
            // campfire, and a waterlogged campfire cannot burn — tending it dries it out.
            limbo.setBlockAndUpdate(channel.pos(), litState());
            limbo.playSound(null, channel.pos(), SoundEvents.FLINTANDSTEEL_USE, SoundSource.BLOCKS, 1.0F, 0.7F);
            limbo.sendParticles(ParticleTypes.SOUL_FIRE_FLAME, channel.pos().getX() + 0.5D,
                    channel.pos().getY() + 0.7D, channel.pos().getZ() + 0.5D, 16, 0.25D, 0.25D, 0.25D, 0.02D);
            ghost.displayClientMessage(Component.translatable("ritual.eclipse.lantern.lit"), true);
            EclipseMod.LOGGER.info("Ghost {} re-lit the lantern at {} — {} lantern(s) now burning",
                    ghost.getScoreboardName(), channel.pos().toShortString(), litCount(limbo));
        }
    }

    private static boolean isLanternPos(ServerLevel limbo, BlockPos pos) {
        return positions(limbo).contains(pos);
    }

    /** A burning deck lantern (soul campfire defaults to LIT=true, no signal smoke). */
    private static BlockState litState() {
        return Blocks.SOUL_CAMPFIRE.defaultBlockState();
    }
}
