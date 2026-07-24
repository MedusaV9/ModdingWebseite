package dev.projecteclipse.eclipse.voice;

import de.maxhenkel.voicechat.api.ForgeVoicechatPlugin;
import de.maxhenkel.voicechat.api.VoicechatConnection;
import de.maxhenkel.voicechat.api.VoicechatPlugin;
import de.maxhenkel.voicechat.api.events.EntitySoundPacketEvent;
import de.maxhenkel.voicechat.api.events.EventRegistration;
import de.maxhenkel.voicechat.api.events.LocationalSoundPacketEvent;
import de.maxhenkel.voicechat.api.events.MicrophonePacketEvent;
import de.maxhenkel.voicechat.api.events.StaticSoundPacketEvent;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;

/**
 * Simple Voice Chat plugin that enforces Eclipse's server-authoritative voice mutes.
 *
 * <p>This is the only class that imports the optional Voice Chat API and nothing in Eclipse's
 * normal initialization path references it. Simple Voice Chat discovers it from the annotation
 * only when that mod is installed.</p>
 */
@ForgeVoicechatPlugin
public final class EclipseVoicePlugin implements VoicechatPlugin {
    @Override
    public String getPluginId() {
        return "eclipse";
    }

    @Override
    public void registerEvents(EventRegistration registration) {
        registration.registerEvent(MicrophonePacketEvent.class, EclipseVoicePlugin::onMicrophonePacket);
        registration.registerEvent(LocationalSoundPacketEvent.class, EclipseVoicePlugin::onLocationalSoundPacket);
        registration.registerEvent(EntitySoundPacketEvent.class, EclipseVoicePlugin::onEntitySoundPacket);
        registration.registerEvent(StaticSoundPacketEvent.class, EclipseVoicePlugin::onStaticSoundPacket);
    }

    private static void onMicrophonePacket(MicrophonePacketEvent event) {
        ServerPlayer sender = minecraftPlayer(event.getSenderConnection());
        if (sender == null) {
            return;
        }
        MinecraftServer server = sender.getServer();
        if (server != null && VoiceMuteApi.isMuted(server, sender)) {
            event.cancel();
        }
    }

    private static void onLocationalSoundPacket(LocationalSoundPacketEvent event) {
        if (isEntryMuted(event.getReceiverConnection())) {
            event.cancel();
        }
    }

    private static void onEntitySoundPacket(EntitySoundPacketEvent event) {
        if (isEntryMuted(event.getReceiverConnection())) {
            event.cancel();
        }
    }

    private static void onStaticSoundPacket(StaticSoundPacketEvent event) {
        if (isEntryMuted(event.getReceiverConnection())) {
            event.cancel();
        }
    }

    private static boolean isEntryMuted(VoicechatConnection connection) {
        ServerPlayer receiver = minecraftPlayer(connection);
        return receiver != null && VoiceMuteApi.isEntryMuted(receiver);
    }

    private static ServerPlayer minecraftPlayer(VoicechatConnection connection) {
        if (connection == null) {
            return null;
        }
        Object player = connection.getPlayer().getPlayer();
        return player instanceof ServerPlayer serverPlayer ? serverPlayer : null;
    }
}
