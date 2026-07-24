package dev.projecteclipse.eclipse.ghosts;

import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.cutscene.FreezeService;
import dev.projecteclipse.eclipse.network.S2CGhostRevealPayload;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import net.minecraft.core.BlockPos;
import net.minecraft.core.GlobalPos;
import net.minecraft.resources.ResourceKey;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.GameType;
import net.minecraft.world.level.Level;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Logout ghost lifecycle (R12): spawn on logout, despawn on login, name reveal on hit.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class LogoutGhostService {
    private static final double REVEAL_RANGE_BLOCKS = 32.0D;
    private static final double REVEAL_RANGE_SQ = REVEAL_RANGE_BLOCKS * REVEAL_RANGE_BLOCKS;

    // statics reset on ServerStopped
    private static final Map<Integer, Long> lastRevealByEntityId = new HashMap<>();
    private static boolean missingTypeLogged;

    private LogoutGhostService() {}

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        GhostConfig.reload();
        MinecraftServer server = event.getServer();
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            clearGhostForOwner(server, player.getUUID());
        }
    }

    @SubscribeEvent
    static void onPlayerLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        GhostConfig.Settings cfg = GhostConfig.get();
        if (!cfg.enabled()) {
            return;
        }
        if (shouldSkip(player)) {
            return;
        }
        ResourceKey<Level> dim = player.level().dimension();
        if (!cfg.dimensions().contains(dim)) {
            return;
        }
        if (!(player.level() instanceof ServerLevel level)) {
            return;
        }

        clearGhostForOwner(player.server, player.getUUID());

        if (!GhostEntities.LOGOUT_GHOST.isBound()) {
            if (!missingTypeLogged) {
                EclipseMod.LOGGER.warn("Logout ghost entity type not registered yet — spawn skipped "
                        + "(apply docs/plans_v3/wiring/P4-B9_wiring.md)");
                missingTypeLogged = true;
            }
            return;
        }

        LogoutGhostEntity ghost = LogoutGhostEntity.spawnAt(level, player.getUUID(),
                player.getGameProfile().getName(),
                player.getX(), player.getY(), player.getZ(), player.getYRot());
        if (ghost == null) {
            return;
        }

        GlobalPos pos = GlobalPos.of(dim, player.blockPosition());
        GhostsState.get(player.server).put(player.getUUID(),
                new GhostsState.GhostRecord(ghost.getUUID(), pos));
        EclipseMod.LOGGER.debug("Logout ghost spawned for {} at {}", player.getUUID(), pos);
    }

    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            clearGhostForOwner(player.server, player.getUUID());
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        lastRevealByEntityId.clear();
        missingTypeLogged = false;
    }

    private static boolean shouldSkip(ServerPlayer player) {
        if (player.isSpectator()) {
            return true;
        }
        if (player.getData(EclipseAttachments.BANNED) || EclipseWorldState.get(player.server).isBanned(player.getUUID())) {
            return true;
        }
        if (player.hasPermissions(3) && player.gameMode.getGameModeForPlayer() == GameType.CREATIVE) {
            return true;
        }
        return FreezeService.isFrozen(player);
    }

    /** Called from {@link LogoutGhostEntity#hurt} (and P6's override when wired). */
    public static void onGhostHurt(LogoutGhostEntity ghost, @Nullable Entity attacker) {
        if (ghost.level().isClientSide()) {
            return;
        }
        GhostConfig.Settings cfg = GhostConfig.get();
        long now = System.currentTimeMillis();
        int entityId = ghost.getId();
        Long last = lastRevealByEntityId.get(entityId);
        if (last != null && now - last < cfg.revealCooldownSeconds() * 1000L) {
            return;
        }
        lastRevealByEntityId.put(entityId, now);

        int ticks = cfg.revealTicks();
        ghost.setRevealTicks(ticks);
        String ownerName = ghost.getOwnerName();
        S2CGhostRevealPayload payload = new S2CGhostRevealPayload(entityId, ownerName, ticks);

        if (!(ghost.level() instanceof ServerLevel level)) {
            return;
        }
        for (ServerPlayer viewer : level.players()) {
            if (viewer.distanceToSqr(ghost) <= REVEAL_RANGE_SQ) {
                PacketDistributor.sendToPlayer(viewer, payload);
            }
        }
    }

    /** Self-check hook for orphan ghost cleanup (100t cadence in entity tick). */
    public static boolean isValid(LogoutGhostEntity ghost) {
        Optional<UUID> owner = ghost.getOwnerUuid();
        if (owner.isEmpty() || !(ghost.level() instanceof ServerLevel level)) {
            return false;
        }
        GhostsState.GhostRecord record = GhostsState.get(level.getServer()).get(owner.get());
        return record != null && record.ghostEntityUuid().equals(ghost.getUUID());
    }

    private static void clearGhostForOwner(MinecraftServer server, UUID owner) {
        GhostsState state = GhostsState.get(server);
        GhostsState.GhostRecord record = state.remove(owner);
        if (record == null) {
            return;
        }
        ServerLevel level = server.getLevel(record.position().dimension());
        if (level == null) {
            return;
        }
        Entity entity = level.getEntity(record.ghostEntityUuid());
        if (entity != null) {
            entity.discard();
            return;
        }
        // Chunk may be unloaded — ticket-load once at login (acceptable per plan).
        BlockPos pos = record.position().pos();
        level.getChunk(pos.getX() >> 4, pos.getZ() >> 4);
        entity = level.getEntity(record.ghostEntityUuid());
        if (entity != null) {
            entity.discard();
        }
    }
}
