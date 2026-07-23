package dev.projecteclipse.eclipse.buffs;

import java.util.Locale;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.FloatArgumentType;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.arguments.StringArgumentType;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * Reference commands for timed buffs ({@code /eclipse-buffs}, perm 3). P5 surfaces the Xbox flow.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class BuffCommands {
    private BuffCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("eclipse-buffs")
                .requires(source -> source.hasPermission(3))
                .then(Commands.literal("start")
                        .then(Commands.argument("id", StringArgumentType.word())
                                .suggests((ctx, builder) -> {
                                    TimedBuffApi api = TimedBuffApi.Holder.get();
                                    return net.minecraft.commands.SharedSuggestionProvider.suggest(
                                            api.knownIds(), builder);
                                })
                                .executes(ctx -> start(ctx.getSource(),
                                        StringArgumentType.getString(ctx, "id"), 0, 0.0F))
                                .then(Commands.argument("minutes", IntegerArgumentType.integer(1))
                                        .executes(ctx -> start(ctx.getSource(),
                                                StringArgumentType.getString(ctx, "id"),
                                                IntegerArgumentType.getInteger(ctx, "minutes"), 0.0F))
                                        .then(Commands.argument("magnitude", FloatArgumentType.floatArg(0.1F))
                                                .executes(ctx -> start(ctx.getSource(),
                                                        StringArgumentType.getString(ctx, "id"),
                                                        IntegerArgumentType.getInteger(ctx, "minutes"),
                                                        FloatArgumentType.getFloat(ctx, "magnitude")))))))
                .then(Commands.literal("stop")
                        .then(Commands.argument("id", StringArgumentType.word())
                                .suggests((ctx, builder) -> net.minecraft.commands.SharedSuggestionProvider.suggest(
                                        TimedBuffApi.Holder.get().knownIds(), builder))
                                .executes(ctx -> stop(ctx.getSource(), StringArgumentType.getString(ctx, "id")))))
                .then(Commands.literal("list")
                        .executes(ctx -> list(ctx.getSource())))
                .then(Commands.literal("reload")
                        .executes(ctx -> reload(ctx.getSource()))));
    }

    private static int start(CommandSourceStack source, String id, int minutes, float magnitude) {
        MinecraftServer server = source.getServer();
        boolean ok = TimedBuffApi.Holder.get().start(server, id, minutes, magnitude);
        if (!ok) {
            source.sendFailure(Component.translatable("command.eclipse.buffs.start.failed", id));
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("command.eclipse.buffs.start.ok", id), true);
        return 1;
    }

    private static int stop(CommandSourceStack source, String id) {
        boolean ok = TimedBuffApi.Holder.get().stop(source.getServer(), id);
        if (!ok) {
            source.sendFailure(Component.translatable("command.eclipse.buffs.stop.failed", id));
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("command.eclipse.buffs.stop.ok", id), true);
        return 1;
    }

    private static int list(CommandSourceStack source) {
        var active = TimedBuffApi.Holder.get().active(source.getServer());
        if (active.isEmpty()) {
            source.sendSuccess(() -> Component.translatable("command.eclipse.buffs.list.empty"), false);
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("command.eclipse.buffs.list.header",
                active.size()), false);
        for (String id : active) {
            source.sendSuccess(() -> Component.literal("  • " + id), false);
        }
        return active.size();
    }

    private static int reload(CommandSourceStack source) {
        BuffConfig.reload();
        source.sendSuccess(() -> Component.translatable("command.eclipse.buffs.reload.ok"), true);
        return 1;
    }
}
