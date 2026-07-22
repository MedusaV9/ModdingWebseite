package dev.projecteclipse.eclipse.lives;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.snapshot.SnapshotService;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import dev.projecteclipse.eclipse.network.S2CHeartBurstPayload;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import dev.projecteclipse.eclipse.registry.EclipseBlocks;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.GameRules;
import net.minecraft.world.level.block.state.BlockState;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDeathEvent;
import net.neoforged.neoforge.event.entity.living.LivingDropsEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The death economy: on a player death we snapshot first, then move a life from
 * the victim to a player killer (or just take one on PvE deaths), place a grave
 * with the drops, and ban the victim once they hit 0 lives. Deaths are never
 * announced in chat ({@code showDeathMessages=false}); the only cue is a global
 * thunder sound played to every online player at their own position.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class LifecycleEvents {
    /** Server-session handoff from the death event to that player's next respawn event. */
    private static final Map<UUID, PendingHeartLoss> PENDING_HEART_LOSSES = new HashMap<>();

    private record PendingHeartLoss(int previousHearts, int heartIndex) {}

    private LifecycleEvents() {}

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        MinecraftServer server = event.getServer();
        server.getGameRules().getRule(GameRules.RULE_SHOWDEATHMESSAGES).set(false, server);
        EclipseMod.LOGGER.info("Eclipse lifecycle active: showDeathMessages=false");
    }

    @SubscribeEvent
    public static void onLivingDeath(LivingDeathEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer victim)) {
            return;
        }
        SnapshotService.snapshot(victim, "death");

        if (event.getSource().getEntity() instanceof ServerPlayer killer && killer != victim) {
            LivesApi.add(killer, +1);
        }
        int previousHearts = LivesApi.get(victim);
        int remainingHearts = LivesApi.add(victim, -1);
        if (remainingHearts < previousHearts) {
            // The first now-missing zero-based heart is exactly the new count.
            PENDING_HEART_LOSSES.put(victim.getUUID(), new PendingHeartLoss(previousHearts, remainingHearts));
        }

        playDeathCue(victim.server);

        if (LivesApi.get(victim) <= 0) {
            BanService.ban(victim);
        }
    }

    /** Plays the thunder death cue to every online player at their own position (never chat). */
    private static void playDeathCue(MinecraftServer server) {
        for (ServerPlayer online : server.getPlayerList().getPlayers()) {
            online.playNotifySound(SoundEvents.LIGHTNING_BOLT_THUNDER, SoundSource.MASTER, 0.6F, 0.7F);
        }
    }

    @SubscribeEvent
    public static void onLivingDrops(LivingDropsEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer victim) || !(victim.level() instanceof ServerLevel level)) {
            return;
        }
        List<ItemStack> stacks = new ArrayList<>();
        for (ItemEntity drop : event.getDrops()) {
            ItemStack stack = drop.getItem();
            if (!stack.isEmpty()) {
                stacks.add(stack.copy());
            }
        }
        if (stacks.isEmpty()) {
            return;
        }
        BlockPos gravePos = findGravePos(level, victim.blockPosition());
        if (gravePos == null) {
            EclipseMod.LOGGER.warn("No spot for a grave near {}'s death position {}; keeping vanilla drops",
                    victim.getScoreboardName(), victim.blockPosition());
            return;
        }
        level.setBlockAndUpdate(gravePos, EclipseBlocks.GRAVE.get().defaultBlockState());
        if (level.getBlockEntity(gravePos) instanceof GraveBlockEntity grave) {
            grave.initialize(victim.getUUID(), level.getGameTime(), stacks);
            event.setCanceled(true);
        } else {
            // Should never happen; keep vanilla drops rather than voiding items.
            level.removeBlock(gravePos, false);
            EclipseMod.LOGGER.error("Grave block entity missing at {}; keeping vanilla drops", gravePos);
        }
    }

    /**
     * Re-applies the limbo ghost state after a banned player respawns (death-time
     * bans cannot teleport a corpse), then emits the deferred shatter cues for
     * a heart actually lost by that death.
     */
    @SubscribeEvent
    public static void onPlayerRespawn(PlayerEvent.PlayerRespawnEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        if (player.getData(EclipseAttachments.BANNED)) {
            BanService.applyLimboState(player);
        }

        PendingHeartLoss loss = PENDING_HEART_LOSSES.remove(player.getUUID());
        if (loss != null && LivesApi.get(player) < loss.previousHearts()) {
            PacketDistributor.sendToPlayer(player,
                    new S2CHeartBurstPayload(loss.heartIndex()),
                    new S2CQuasarPayload(
                            S2CQuasarPayload.HEART_BURST,
                            player.position().add(0.0D, 1.0D, 0.0D)));
        }
    }

    /**
     * The death position if replaceable (Y clamped into build height for void deaths),
     * otherwise the nearest replaceable/air block within a small search box, or
     * {@code null} if there is none.
     */
    private static BlockPos findGravePos(ServerLevel level, BlockPos deathPos) {
        BlockPos base = new BlockPos(deathPos.getX(),
                Mth.clamp(deathPos.getY(), level.getMinBuildHeight(), level.getMaxBuildHeight() - 1),
                deathPos.getZ());
        if (isReplaceable(level, base)) {
            return base;
        }
        for (int radius = 1; radius <= 3; radius++) {
            for (BlockPos candidate : BlockPos.betweenClosed(
                    base.offset(-radius, -1, -radius), base.offset(radius, radius + 1, radius))) {
                if (isReplaceable(level, candidate)) {
                    return candidate.immutable();
                }
            }
        }
        return null;
    }

    private static boolean isReplaceable(ServerLevel level, BlockPos pos) {
        if (level.isOutsideBuildHeight(pos)) {
            return false;
        }
        BlockState state = level.getBlockState(pos);
        return state.isAir() || state.canBeReplaced();
    }
}
