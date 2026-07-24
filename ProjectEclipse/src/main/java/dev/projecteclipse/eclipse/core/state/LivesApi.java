package dev.projecteclipse.eclipse.core.state;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.hearts.HeartsService;
import dev.projecteclipse.eclipse.lives.BanService;
import dev.projecteclipse.eclipse.lives.DeathFlowHooks;
import dev.projecteclipse.eclipse.network.S2CLivesPayload;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Server-side API for the {@code eclipse:lives} player attachment, whose value
 * is the player's permanent heart count.
 * Values are clamped to {@code >= 0}; every change is synced to the owning
 * client via {@link S2CLivesPayload} and immediately projected onto real max
 * health by {@link HeartsService}.
 *
 * <p><b>Ghost-state refresh (PLAN-C C4, item 8):</b> mutations used to change only the
 * heart count and never consulted {@link BanService} — a ghost (BANNED) who gained a
 * heart (vitae shard, admin {@code /eclipse lives}, kill transfer) stayed a ghost with
 * hearts in the bank. {@link #set} now hooks the 0 → &gt;0 transition: a banned player
 * whose hearts come back is immediately unbanned through the standard revive path
 * ({@link BanService#unban} — survival mode, ghost team/name color off, effects
 * cleared — then {@link DeathFlowHooks#onRevived} for the same-tick celebration,
 * exactly like {@code ReviveRitual}; the unban watch de-duplicates). Any future
 * OFFLINE heart-grant path must mirror {@code FinaleRitual.beginVictory}'s offline
 * branch instead: clear the persistent ban set
 * ({@code EclipseWorldState.removeBanned}) so {@code ReviveRitual.onPlayerLoggedIn}
 * finishes the unban on the ghost's next login.</p>
 */
public final class LivesApi {
    private LivesApi() {}

    /** Returns the player's current permanent heart count. */
    public static int get(ServerPlayer player) {
        return player.getData(EclipseAttachments.LIVES);
    }

    /** Sets the heart count (clamped to {@code >= 0}), applies max health, syncs it, and returns the applied value. */
    public static int set(ServerPlayer player, int lives) {
        int previous = get(player);
        int clamped = Math.max(0, lives);
        player.setData(EclipseAttachments.LIVES, clamped);
        HeartsService.apply(player);
        PacketDistributor.sendToPlayer(player, new S2CLivesPayload(clamped));
        // C4 item 8 post-mutation hook: hearts back from 0 while event-banned = revive.
        if (previous <= 0 && clamped > 0 && BanService.isBanned(player)) {
            EclipseMod.LOGGER.info("{} regained hearts (0 -> {}) while event-banned — unbanning through the "
                    + "standard revive path", player.getScoreboardName(), clamped);
            // unban() clears BANNED first, so its own LivesApi.set(player, 1) cannot
            // re-enter this hook; re-apply the granted count over unban's default 1.
            BanService.unban(player);
            if (get(player) != clamped) {
                set(player, clamped);
            }
            DeathFlowHooks.onRevived(player);
        }
        return clamped;
    }

    /** Adds {@code delta} (may be negative) to the heart count; result is clamped, applied, synced, and returned. */
    public static int add(ServerPlayer player, int delta) {
        return set(player, get(player) + delta);
    }
}
