package dev.projecteclipse.eclipse.lives;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.snapshot.SnapshotService;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import net.minecraft.ChatFormatting;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.ServerScoreboard;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.level.GameType;
import net.minecraft.world.scores.PlayerTeam;
import net.minecraft.world.scores.Team;

/**
 * Event-ban handling: players who run out of lives become green ghosts in the
 * Limbo dimension. This is Eclipse's own ban state (attachment + world state),
 * not a vanilla server ban.
 */
public final class BanService {
    /** Scoreboard team all banned "ghost" players are put on. */
    public static final String GHOST_TEAM_NAME = "eclipse_ghosts";

    private BanService() {}

    /**
     * Bans the player: marks the BANNED attachment and world state, snapshots them
     * (reason {@code "ban"}), transfers their ender chest to spawn chests via
     * {@link InheritanceService}, and applies the limbo ghost state (adventure mode,
     * ghost team, glowing + slow falling, teleport to {@code eclipse:limbo}).
     * If called mid-death (e.g. from the death event), teleport and effects are
     * deferred to the respawn hook in {@link LifecycleEvents}.
     */
    public static void ban(ServerPlayer player) {
        if (player == null) {
            return;
        }
        player.setData(EclipseAttachments.BANNED, true);
        EclipseWorldState.get(player.server).addBanned(player.getUUID());
        SnapshotService.snapshot(player, "ban");
        InheritanceService.inherit(player);
        joinGhostTeam(player);
        player.setGameMode(GameType.ADVENTURE);
        if (player.isDeadOrDying()) {
            // Effects and position do not survive the respawn; LifecycleEvents re-applies
            // the full limbo state on PlayerRespawnEvent for banned players.
            EclipseMod.LOGGER.info("Banned dead player {}; limbo state will be applied on respawn", player.getScoreboardName());
        } else {
            applyLimboState(player);
        }
    }

    /**
     * Applies the visible ghost state: adventure mode, ghost team, infinite glowing
     * + slow falling, and teleports to the Limbo dimension (falls back to the
     * overworld shared spawn with a warning if {@code eclipse:limbo} is not loaded).
     */
    public static void applyLimboState(ServerPlayer player) {
        if (player == null) {
            return;
        }
        player.setGameMode(GameType.ADVENTURE);
        joinGhostTeam(player);
        player.addEffect(new MobEffectInstance(MobEffects.GLOWING, MobEffectInstance.INFINITE_DURATION, 0, false, false));
        player.addEffect(new MobEffectInstance(MobEffects.SLOW_FALLING, MobEffectInstance.INFINITE_DURATION, 0, false, false));

        ServerLevel limbo = player.server.getLevel(LimboDimension.LIMBO);
        if (limbo != null) {
            teleportToSharedSpawn(player, limbo);
        } else {
            EclipseMod.LOGGER.warn("Limbo dimension {} is not loaded; sending banned player {} to overworld spawn instead",
                    LimboDimension.LIMBO.location(), player.getScoreboardName());
            teleportToSharedSpawn(player, player.server.overworld());
        }
    }

    /**
     * Reverses a ban: clears the BANNED attachment and world state, leaves the
     * ghost team, removes the ghost effects, restores survival mode and 1 life,
     * and teleports the player to the overworld shared spawn.
     */
    public static void unban(ServerPlayer player) {
        if (player == null) {
            return;
        }
        player.setData(EclipseAttachments.BANNED, false);
        EclipseWorldState.get(player.server).removeBanned(player.getUUID());
        leaveGhostTeam(player);
        player.removeEffect(MobEffects.GLOWING);
        player.removeEffect(MobEffects.SLOW_FALLING);
        player.setGameMode(GameType.SURVIVAL);
        LivesApi.set(player, 1);
        teleportToSharedSpawn(player, player.server.overworld());
    }

    /** Whether the player is currently event-banned (BANNED attachment). */
    public static boolean isBanned(ServerPlayer player) {
        return player != null && player.getData(EclipseAttachments.BANNED);
    }

    private static void joinGhostTeam(ServerPlayer player) {
        ServerScoreboard scoreboard = player.server.getScoreboard();
        PlayerTeam team = scoreboard.getPlayerTeam(GHOST_TEAM_NAME);
        if (team == null) {
            team = scoreboard.addPlayerTeam(GHOST_TEAM_NAME);
            team.setColor(ChatFormatting.GREEN);
            team.setAllowFriendlyFire(false);
            team.setNameTagVisibility(Team.Visibility.NEVER);
        }
        scoreboard.addPlayerToTeam(player.getScoreboardName(), team);
    }

    private static void leaveGhostTeam(ServerPlayer player) {
        ServerScoreboard scoreboard = player.server.getScoreboard();
        PlayerTeam team = scoreboard.getPlayersTeam(player.getScoreboardName());
        if (team != null && GHOST_TEAM_NAME.equals(team.getName())) {
            scoreboard.removePlayerFromTeam(player.getScoreboardName(), team);
        }
    }

    private static void teleportToSharedSpawn(ServerPlayer player, ServerLevel level) {
        MinecraftServer server = player.server;
        if (level == null) {
            level = server.overworld();
        }
        BlockPos spawn = level.getSharedSpawnPos();
        player.teleportTo(level, spawn.getX() + 0.5D, spawn.getY(), spawn.getZ() + 0.5D,
                level.getSharedSpawnAngle(), 0.0F);
    }
}
