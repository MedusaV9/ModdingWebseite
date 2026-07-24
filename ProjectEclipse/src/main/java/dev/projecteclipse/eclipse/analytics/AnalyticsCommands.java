package dev.projecteclipse.eclipse.analytics;

import java.util.Collection;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import com.mojang.authlib.GameProfile;
import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.commands.arguments.GameProfileArgument;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * Reference dump commands for analytics ({@code /eclipse-analytics}, perm 3 — P4 §2.4).
 * P5-W4 surfaces the polished command set on top of {@link AnalyticsApi}; this class stays
 * the smoke-test entry point ({@code /eclipse-analytics top 1 mine_total}). Output goes to
 * the invoking operator only (never broadcast) — player names are resolvable by ops here,
 * clients never see this data (anonymity holds: nothing is sent to non-op players).
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class AnalyticsCommands {
    private AnalyticsCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("eclipse-analytics")
                .requires(source -> source.hasPermission(3))
                .then(Commands.literal("top")
                        .then(Commands.argument("day", IntegerArgumentType.integer(1))
                                .then(Commands.argument("key", StringArgumentType.string())
                                        .suggests((ctx, builder) -> SharedSuggestionProvider.suggest(
                                                AnalyticsKeys.categories(), builder))
                                        .executes(ctx -> top(ctx.getSource(),
                                                IntegerArgumentType.getInteger(ctx, "day"),
                                                StringArgumentType.getString(ctx, "key"), 10))
                                        .then(Commands.argument("n", IntegerArgumentType.integer(1, 100))
                                                .executes(ctx -> top(ctx.getSource(),
                                                        IntegerArgumentType.getInteger(ctx, "day"),
                                                        StringArgumentType.getString(ctx, "key"),
                                                        IntegerArgumentType.getInteger(ctx, "n")))))))
                .then(Commands.literal("dump")
                        .then(Commands.argument("day", IntegerArgumentType.integer(1))
                                .then(Commands.argument("player", GameProfileArgument.gameProfile())
                                        .executes(ctx -> dump(ctx.getSource(),
                                                IntegerArgumentType.getInteger(ctx, "day"),
                                                GameProfileArgument.getGameProfiles(ctx, "player"))))))
                .then(Commands.literal("categories")
                        .executes(ctx -> categories(ctx.getSource())))
                .then(Commands.literal("reload")
                        .executes(ctx -> reload(ctx.getSource()))));
    }

    private static int top(CommandSourceStack source, int day, String key, int n) {
        List<AnalyticsApi.Entry> entries = AnalyticsApi.top(source.getServer(), day, key, n);
        if (entries.isEmpty()) {
            source.sendSuccess(() -> Component.literal("No analytics for day " + day + " / " + key), false);
            return 0;
        }
        source.sendSuccess(() -> Component.literal("Top " + entries.size() + " — day " + day
                + ", " + key + ":"), false);
        int rank = 1;
        for (AnalyticsApi.Entry entry : entries) {
            String line = "  " + rank + ". " + describe(source.getServer(), entry.uuid())
                    + " — " + entry.value();
            source.sendSuccess(() -> Component.literal(line), false);
            rank++;
        }
        return entries.size();
    }

    private static int dump(CommandSourceStack source, int day, Collection<GameProfile> profiles)
            throws CommandSyntaxException {
        MinecraftServer server = source.getServer();
        int lines = 0;
        for (GameProfile profile : profiles) {
            UUID uuid = profile.getId();
            Set<String> keys = AnalyticsApi.keys(server, day);
            source.sendSuccess(() -> Component.literal("Analytics day " + day + " — "
                    + describe(server, uuid) + ":"), false);
            int printed = 0;
            for (String key : keys.stream().sorted().toList()) {
                long value = AnalyticsApi.value(server, day, uuid, key);
                if (value != 0L) {
                    String line = "  " + key + " = " + value;
                    source.sendSuccess(() -> Component.literal(line), false);
                    printed++;
                }
            }
            if (printed == 0) {
                source.sendSuccess(() -> Component.literal("  (no data)"), false);
            }
            lines += printed;
        }
        return lines;
    }

    private static int categories(CommandSourceStack source) {
        source.sendSuccess(() -> Component.literal("Static categories: "
                + String.join(", ", AnalyticsKeys.categories())), false);
        source.sendSuccess(() -> Component.literal("Dynamic prefixes: "
                + String.join(" ", AnalyticsKeys.dynamicPrefixes())
                + " (e.g. kill:minecraft:zombie, mine:minecraft:iron_ore)"), false);
        return AnalyticsKeys.categories().size();
    }

    private static int reload(CommandSourceStack source) {
        AnalyticsConfig.reload();
        DepositValues.reload();
        source.sendSuccess(() -> Component.literal("Analytics config reloaded ("
                + AnalyticsConfig.get().craftAllowlist().size() + " craft-allowlisted ids)"), false);
        return 1;
    }

    /** Op-facing identity: cached name when known, otherwise the raw UUID. */
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
