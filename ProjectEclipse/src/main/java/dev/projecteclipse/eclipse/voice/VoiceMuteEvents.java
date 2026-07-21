package dev.projecteclipse.eclipse.voice;

import java.util.Locale;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.Level;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/** NeoForge-side lifecycle and action-bar handling for voice mutes. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class VoiceMuteEvents {
    private static final int HINT_INTERVAL_TICKS = 30 * 20;

    private VoiceMuteEvents() {}

    @SubscribeEvent
    public static void onPlayerChangedDimension(PlayerEvent.PlayerChangedDimensionEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)
                || !Level.OVERWORLD.equals(event.getTo())
                || player.getData(EclipseAttachments.FIRST_OVERWORLD_JOIN) != 0L) {
            return;
        }
        player.setData(EclipseAttachments.FIRST_OVERWORLD_JOIN, System.currentTimeMillis());
    }

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % HINT_INTERVAL_TICKS != 0) {
            return;
        }

        EclipseWorldState state = EclipseWorldState.get(server);
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            long remainingMillis = VoiceMuteApi.entryMuteRemainingMillis(player);
            if (remainingMillis > 0L) {
                player.displayClientMessage(
                        Component.translatable("message.eclipse.voice_sealed_remaining",
                                formatDuration(remainingMillis)),
                        true);
            } else if (state.isForceVoiceMuted(player.getUUID())) {
                player.displayClientMessage(Component.translatable("message.eclipse.voice_sealed"), true);
            }
        }
    }

    private static String formatDuration(long remainingMillis) {
        long remainingSeconds = (remainingMillis + 999L) / 1000L;
        return String.format(Locale.ROOT, "%d:%02d", remainingSeconds / 60L, remainingSeconds % 60L);
    }
}
