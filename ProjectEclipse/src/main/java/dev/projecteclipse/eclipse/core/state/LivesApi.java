package dev.projecteclipse.eclipse.core.state;

import dev.projecteclipse.eclipse.hearts.HeartsService;
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
 */
public final class LivesApi {
    private LivesApi() {}

    /** Returns the player's current permanent heart count. */
    public static int get(ServerPlayer player) {
        return player.getData(EclipseAttachments.LIVES);
    }

    /** Sets the heart count (clamped to {@code >= 0}), applies max health, syncs it, and returns the applied value. */
    public static int set(ServerPlayer player, int lives) {
        int clamped = Math.max(0, lives);
        player.setData(EclipseAttachments.LIVES, clamped);
        HeartsService.apply(player);
        PacketDistributor.sendToPlayer(player, new S2CLivesPayload(clamped));
        return clamped;
    }

    /** Adds {@code delta} (may be negative) to the heart count; result is clamped, applied, synced, and returned. */
    public static int add(ServerPlayer player, int delta) {
        return set(player, get(player) + delta);
    }
}
