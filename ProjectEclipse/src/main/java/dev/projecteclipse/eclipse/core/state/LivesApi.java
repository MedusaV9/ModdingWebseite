package dev.projecteclipse.eclipse.core.state;

import dev.projecteclipse.eclipse.network.S2CLivesPayload;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Server-side API for the {@code eclipse:lives} player attachment.
 * Values are clamped to {@code >= 0}; every change is synced to the owning
 * client via {@link S2CLivesPayload}.
 */
public final class LivesApi {
    private LivesApi() {}

    /** Returns the player's current life count. */
    public static int get(ServerPlayer player) {
        return player.getData(EclipseAttachments.LIVES);
    }

    /** Sets the player's life count (clamped to {@code >= 0}), syncs it to the client, and returns the applied value. */
    public static int set(ServerPlayer player, int lives) {
        int clamped = Math.max(0, lives);
        player.setData(EclipseAttachments.LIVES, clamped);
        PacketDistributor.sendToPlayer(player, new S2CLivesPayload(clamped));
        return clamped;
    }

    /** Adds {@code delta} (may be negative) to the player's life count; result is clamped, synced, and returned. */
    public static int add(ServerPlayer player, int delta) {
        return set(player, get(player) + delta);
    }
}
