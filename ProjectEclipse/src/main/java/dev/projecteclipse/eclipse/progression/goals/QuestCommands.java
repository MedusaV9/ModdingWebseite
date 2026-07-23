package dev.projecteclipse.eclipse.progression.goals;

import java.util.List;
import java.util.Optional;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;
import com.mojang.brigadier.suggestion.SuggestionProvider;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.commands.arguments.EntityArgument;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * Admin quest root {@code /eclipse-quests} (perm 3) — plans_v3 P4 §3.3:
 * {@code tick <player> <id>}, {@code reroll <player>}, {@code list [player]},
 * {@code reload}, plus {@code revoke <player> <id>} as the reference caller for
 * {@link QuestApi#revoke} (P5-W4's {@code /dev quest revoke} bridges to the same call).
 * New root by design — the legacy {@code /eclipse goals tick} stays untouched and keeps
 * working through the {@code GoalTracker} adapter.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class QuestCommands {
    private static final SuggestionProvider<CommandSourceStack> GOAL_IDS =
            (context, builder) -> SharedSuggestionProvider.suggest(
                    QuestApi.suggestedIds(context.getSource().getServer()), builder);

    private QuestCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("eclipse-quests")
                .requires(source -> source.hasPermission(3))
                .then(Commands.literal("tick")
                        .then(Commands.argument("player", EntityArgument.player())
                                .then(Commands.argument("id", StringArgumentType.string())
                                        .suggests(GOAL_IDS)
                                        .executes(QuestCommands::tick))))
                .then(Commands.literal("revoke")
                        .then(Commands.argument("player", EntityArgument.player())
                                .then(Commands.argument("id", StringArgumentType.string())
                                        .suggests(GOAL_IDS)
                                        .executes(QuestCommands::revoke))))
                .then(Commands.literal("reroll")
                        .then(Commands.argument("player", EntityArgument.player())
                                .executes(QuestCommands::reroll)))
                .then(Commands.literal("list")
                        .executes(ctx -> list(ctx, ctx.getSource().getPlayerOrException()))
                        .then(Commands.argument("player", EntityArgument.player())
                                .executes(ctx -> list(ctx, EntityArgument.getPlayer(ctx, "player")))))
                .then(Commands.literal("reload").executes(QuestCommands::reload)));
    }

    private static int tick(CommandContext<CommandSourceStack> ctx) throws CommandSyntaxException {
        ServerPlayer target = EntityArgument.getPlayer(ctx, "player");
        String id = StringArgumentType.getString(ctx, "id");
        MinecraftServer server = ctx.getSource().getServer();
        Optional<GoalSpec> spec = QuestApi.byId(server, id);
        if (spec.isEmpty()) {
            ctx.getSource().sendFailure(Component.translatable("command.eclipse.quests.unknown", id));
            return 0;
        }
        if (!QuestApi.complete(server, target, spec.get())) {
            ctx.getSource().sendFailure(Component.translatable("command.eclipse.quests.already_done", id));
            return 0;
        }
        ctx.getSource().sendSuccess(() -> Component.translatable("command.eclipse.quests.ticked",
                id, target.getScoreboardName()), true);
        return 1;
    }

    private static int revoke(CommandContext<CommandSourceStack> ctx) throws CommandSyntaxException {
        ServerPlayer target = EntityArgument.getPlayer(ctx, "player");
        String id = StringArgumentType.getString(ctx, "id");
        MinecraftServer server = ctx.getSource().getServer();
        Optional<GoalSpec> spec = QuestApi.byId(server, id);
        if (spec.isEmpty()) {
            ctx.getSource().sendFailure(Component.translatable("command.eclipse.quests.unknown", id));
            return 0;
        }
        if (!QuestApi.revoke(server, target, spec.get())) {
            ctx.getSource().sendFailure(Component.translatable("command.eclipse.quests.nothing_to_revoke", id));
            return 0;
        }
        ctx.getSource().sendSuccess(() -> Component.translatable("command.eclipse.quests.revoked",
                id, target.getScoreboardName()), true);
        return 1;
    }

    private static int reroll(CommandContext<CommandSourceStack> ctx) throws CommandSyntaxException {
        ServerPlayer target = EntityArgument.getPlayer(ctx, "player");
        List<String> drawn = QuestApi.reroll(ctx.getSource().getServer(), target);
        ctx.getSource().sendSuccess(() -> Component.translatable("command.eclipse.quests.rerolled",
                target.getScoreboardName(), String.join(", ", drawn)), true);
        return drawn.size();
    }

    private static int list(CommandContext<CommandSourceStack> ctx, ServerPlayer target) {
        MinecraftServer server = ctx.getSource().getServer();
        List<GoalSpec> specs = QuestApi.allForPlayer(server, target);
        int day = QuestEngine.resolved(server).day;
        ctx.getSource().sendSuccess(() -> Component.translatable("command.eclipse.quests.list.header",
                day, target.getScoreboardName(), specs.size()), false);
        for (GoalSpec spec : specs) {
            long progress = Math.min(QuestApi.progress(server, target, spec), spec.target());
            boolean done = QuestApi.isDone(server, target, spec);
            ctx.getSource().sendSuccess(() -> Component.translatable("command.eclipse.quests.list.entry",
                    done ? "✔" : "•", spec.id(), spec.goalKind().id(), spec.scope().id(),
                    progress, spec.target(), spec.text().en()), false);
        }
        return specs.size();
    }

    private static int reload(CommandContext<CommandSourceStack> ctx) {
        GoalConfig.reloadNow();
        QuestApi.resyncAll(ctx.getSource().getServer());
        ctx.getSource().sendSuccess(() -> Component.translatable("command.eclipse.quests.reloaded",
                GoalConfig.personalPool().size()), true);
        return 1;
    }
}
