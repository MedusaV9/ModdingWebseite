package dev.projecteclipse.eclipse.devtools.dev;

import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import com.mojang.authlib.GameProfile;
import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;
import com.mojang.brigadier.suggestion.SuggestionProvider;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.analytics.AnalyticsApi;
import dev.projecteclipse.eclipse.analytics.AnalyticsService;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.commands.arguments.GameProfileArgument;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/** Read-only operator query surface over the retained per-day analytics store. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevStatsCommands {
    private static final SuggestionProvider<CommandSourceStack> METRICS = (context, builder) -> {
        int day = AnalyticsService.currentDay(context.getSource().getServer());
        Set<String> metrics = new LinkedHashSet<>(AnalyticsApi.categories());
        metrics.addAll(AnalyticsApi.keys(context.getSource().getServer(), day).stream().sorted().toList());
        return SharedSuggestionProvider.suggest(metrics, builder);
    };

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("stats.query", DevCategory.ANALYTICS,
                        "/dev stats query <player> [metric] [day]",
                        "dev.eclipse.doc.stats.query", Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("stats.top", DevCategory.ANALYTICS,
                        "/dev stats top <metric>",
                        "dev.eclipse.doc.stats.top", Danger.SAFE, ClickAction.SUGGEST, 2));
    }

    private DevStatsCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("stats")
                        .then(Commands.literal("query")
                                .then(Commands.argument("player", GameProfileArgument.gameProfile())
                                        .executes(context -> query(context, null,
                                                AnalyticsService.currentDay(context.getSource().getServer())))
                                        .then(Commands.argument("metric", StringArgumentType.word())
                                                .suggests(METRICS)
                                                .executes(context -> query(context,
                                                        StringArgumentType.getString(context, "metric"),
                                                        AnalyticsService.currentDay(
                                                                context.getSource().getServer())))
                                                .then(Commands.argument("day",
                                                                IntegerArgumentType.integer(1))
                                                        .executes(context -> query(context,
                                                                StringArgumentType.getString(context, "metric"),
                                                                IntegerArgumentType.getInteger(context, "day")))))))
                        .then(Commands.literal("top")
                                .then(Commands.argument("metric", StringArgumentType.word())
                                        .suggests(METRICS)
                                        .executes(DevStatsCommands::top)))));
    }

    private static int query(CommandContext<CommandSourceStack> context, String metric, int day)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        Collection<GameProfile> profiles = GameProfileArgument.getGameProfiles(context, "player");
        int printed = 0;
        for (GameProfile profile : profiles) {
            UUID uuid = profile.getId();
            if (uuid == null) {
                source.sendFailure(Component.translatable("dev.eclipse.stats.profile.no_uuid", profile.getName()));
                continue;
            }
            source.sendSuccess(() -> Component.translatable("dev.eclipse.stats.query.header",
                    profile.getName(), day), false);
            if (metric != null) {
                long value = AnalyticsApi.value(server, day, uuid, metric);
                source.sendSuccess(() -> Component.translatable("dev.eclipse.stats.query.entry",
                        metric, value), false);
                printed++;
                continue;
            }
            Set<String> keys = AnalyticsApi.keys(server, day);
            int profileLines = 0;
            for (String key : keys.stream().sorted().toList()) {
                long value = AnalyticsApi.value(server, day, uuid, key);
                if (value != 0L) {
                    source.sendSuccess(() -> Component.translatable("dev.eclipse.stats.query.entry",
                            key, value), false);
                    profileLines++;
                    printed++;
                }
            }
            if (profileLines == 0) {
                source.sendSuccess(() -> Component.translatable("dev.eclipse.stats.query.empty"), false);
            }
        }
        return printed;
    }

    private static int top(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        String metric = StringArgumentType.getString(context, "metric");
        int day = AnalyticsService.currentDay(server);
        List<AnalyticsApi.Entry> rows = AnalyticsApi.top(server, day, metric, 10);
        if (rows.isEmpty()) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.stats.top.empty",
                    metric, day), false);
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.stats.top.header",
                metric, day, rows.size()), false);
        for (int index = 0; index < rows.size(); index++) {
            AnalyticsApi.Entry row = rows.get(index);
            int rank = index + 1;
            source.sendSuccess(() -> Component.translatable("dev.eclipse.stats.top.entry",
                    rank, describe(server, row.uuid()), row.value()), false);
        }
        return rows.size();
    }

    private static String describe(MinecraftServer server, UUID uuid) {
        if (server.getProfileCache() != null) {
            var cached = server.getProfileCache().get(uuid);
            if (cached.isPresent()) {
                return cached.get().getName();
            }
        }
        return uuid.toString();
    }
}
