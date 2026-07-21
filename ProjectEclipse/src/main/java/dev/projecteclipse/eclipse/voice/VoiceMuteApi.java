package dev.projecteclipse.eclipse.voice;

import java.util.UUID;

import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;

/**
 * Server-side API for the temporary entry mute and persistent administrative voice mute.
 */
public final class VoiceMuteApi {
    static final long ENTRY_MUTE_DURATION_MILLIS = 10L * 60L * 1000L;

    private VoiceMuteApi() {}

    /** Returns whether the player's ten-minute entry mute is still active. */
    public static boolean isEntryMuted(ServerPlayer player) {
        long firstOverworldJoin = player.getData(EclipseAttachments.FIRST_OVERWORLD_JOIN);
        return firstOverworldJoin > 0L
                && System.currentTimeMillis() - firstOverworldJoin < ENTRY_MUTE_DURATION_MILLIS;
    }

    /** Adds or removes the player's persistent administrative voice mute. */
    public static void setForceMuted(MinecraftServer server, UUID playerId, boolean muted) {
        EclipseWorldState state = EclipseWorldState.get(server);
        if (muted) {
            state.addForceVoiceMuted(playerId);
        } else {
            state.removeForceVoiceMuted(playerId);
        }
    }

    /** Returns whether either the entry mute or administrative mute is active. */
    public static boolean isMuted(MinecraftServer server, ServerPlayer player) {
        return isEntryMuted(player) || EclipseWorldState.get(server).isForceVoiceMuted(player.getUUID());
    }

    static long entryMuteRemainingMillis(ServerPlayer player) {
        long firstOverworldJoin = player.getData(EclipseAttachments.FIRST_OVERWORLD_JOIN);
        if (firstOverworldJoin <= 0L) {
            return 0L;
        }
        return Math.max(0L,
                ENTRY_MUTE_DURATION_MILLIS - (System.currentTimeMillis() - firstOverworldJoin));
    }
}
