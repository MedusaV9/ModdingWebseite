package dev.projecteclipse.eclipse.devtools.dev;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.music.MusicCues;
import dev.projecteclipse.eclipse.music.MusicPayloads;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/** {@code /dev music play|stop|list} and {@code /dev credits}. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevMusicCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("music.play", DevCategory.MUSIC,
                        "/dev music play <id>", "dev.eclipse.doc.music.play",
                        Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("music.stop", DevCategory.MUSIC,
                        "/dev music stop", "dev.eclipse.doc.music.stop",
                        Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("music.list", DevCategory.MUSIC,
                        "/dev music list", "dev.eclipse.doc.music.list",
                        Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("credits", DevCategory.MUSIC,
                        "/dev credits", "dev.eclipse.doc.credits",
                        Danger.SAFE, ClickAction.RUN, 2));
    }

    private DevMusicCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("music")
                        .then(Commands.literal("play")
                                .then(Commands.argument("id", StringArgumentType.word())
                                        .suggests((context, builder) ->
                                                SharedSuggestionProvider.suggest(MusicCues.ids(), builder))
                                        .executes(DevMusicCommands::play)))
                        .then(Commands.literal("stop")
                                .executes(DevMusicCommands::stop))
                        .then(Commands.literal("list")
                                .executes(DevMusicCommands::list)))
                .then(Commands.literal("credits")
                        .executes(DevMusicCommands::credits)));
    }

    private static int play(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        String id = StringArgumentType.getString(context, "id");
        if (MusicCues.fromId(id).isEmpty()) {
            source.sendFailure(Component.translatable("dev.eclipse.music.unknown", id));
            return 0;
        }
        ServerPlayer player = source.getPlayerOrException();
        MusicPayloads.sendPlay(player, id);
        source.sendSuccess(() -> Component.translatable("dev.eclipse.music.played", id), false);
        return 1;
    }

    private static int stop(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        MusicPayloads.sendStop(source.getPlayerOrException());
        source.sendSuccess(() -> Component.translatable("dev.eclipse.music.stopped"), false);
        return 1;
    }

    private static int list(CommandContext<CommandSourceStack> context) {
        String ids = String.join(", ", MusicCues.ids());
        context.getSource().sendSuccess(() -> Component.translatable("dev.eclipse.music.list", ids), false);
        return MusicCues.ids().size();
    }

    private static int credits(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        MusicPayloads.sendOpenCredits(source.getPlayerOrException());
        source.sendSuccess(() -> Component.translatable("dev.eclipse.credits.opened"), false);
        return 1;
    }
}
