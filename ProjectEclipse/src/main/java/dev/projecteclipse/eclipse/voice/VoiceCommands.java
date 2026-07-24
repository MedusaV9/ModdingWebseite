package dev.projecteclipse.eclipse.voice;

import com.mojang.brigadier.CommandDispatcher;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * Reference voice moderation commands ({@code /eclipse-voice}, perm 3).
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class VoiceCommands {
    private VoiceCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("eclipse-voice")
                .requires(source -> source.hasPermission(3))
                .then(Commands.literal("global")
                        .then(Commands.literal("on")
                                .executes(ctx -> setGlobal(ctx.getSource(), true)))
                        .then(Commands.literal("off")
                                .executes(ctx -> setGlobal(ctx.getSource(), false))))
                .then(Commands.literal("list")
                        .executes(ctx -> list(ctx.getSource()))));
    }

    private static int setGlobal(CommandSourceStack source, boolean muted) {
        VoiceMuteApi.setGlobalMuted(source.getServer(), muted);
        source.sendSuccess(() -> Component.translatable(muted
                ? "command.eclipse.voice.global.on"
                : "command.eclipse.voice.global.off"), true);
        return 1;
    }

    private static int list(CommandSourceStack source) {
        var server = source.getServer();
        boolean global = VoiceMuteApi.isGlobalMuted(server);
        source.sendSuccess(() -> Component.translatable("command.eclipse.voice.list.header",
                global ? "ON" : "OFF"), false);

        var forced = EclipseWorldState.get(server).getForceVoiceMuted();
        if (forced.isEmpty()) {
            source.sendSuccess(() -> Component.translatable("command.eclipse.voice.list.none"), false);
        } else {
            for (ServerPlayer player : server.getPlayerList().getPlayers()) {
                if (forced.contains(player.getUUID())) {
                    source.sendSuccess(() -> Component.literal("  • " + player.getScoreboardName()), false);
                }
            }
        }
        return 1;
    }
}
