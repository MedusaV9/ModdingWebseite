package dev.projecteclipse.eclipse.devtools.dev;

import java.util.List;
import java.util.Optional;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;
import com.mojang.brigadier.suggestion.SuggestionProvider;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.progression.goals.GoalSpec;
import dev.projecteclipse.eclipse.progression.goals.QuestApi;
import net.minecraft.ChatFormatting;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.commands.arguments.EntityArgument;
import net.minecraft.network.chat.ClickEvent;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.HoverEvent;
import net.minecraft.network.chat.MutableComponent;
import net.minecraft.network.chat.Style;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/** Polished admin bridge over {@link QuestApi}, including every main, side and personal id. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevQuestCommands {
    private static final SuggestionProvider<CommandSourceStack> QUEST_IDS =
            (context, builder) -> SharedSuggestionProvider.suggest(
                    QuestApi.suggestedIds(context.getSource().getServer()), builder);

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("quest.complete", DevCategory.QUESTS,
                        "/dev quest complete <player> <questId>",
                        "dev.eclipse.doc.quest.complete", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("quest.revoke", DevCategory.QUESTS,
                        "/dev quest revoke <player> <questId>",
                        "dev.eclipse.doc.quest.revoke", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("quest.reroll", DevCategory.QUESTS,
                        "/dev quest reroll <player>",
                        "dev.eclipse.doc.quest.reroll", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("quest.list", DevCategory.QUESTS,
                        "/dev quest list <player>",
                        "dev.eclipse.doc.quest.list", Danger.SAFE, ClickAction.SUGGEST, 2));
    }

    private DevQuestCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("quest")
                        .then(goalMutation("complete", true))
                        .then(goalMutation("revoke", false))
                        .then(Commands.literal("reroll")
                                .then(Commands.argument("player", EntityArgument.player())
                                        .executes(DevQuestCommands::reroll)))
                        .then(Commands.literal("list")
                                .then(Commands.argument("player", EntityArgument.player())
                                        .executes(DevQuestCommands::list)))));
    }

    private static com.mojang.brigadier.builder.LiteralArgumentBuilder<CommandSourceStack> goalMutation(
            String name, boolean complete) {
        return Commands.literal(name)
                .then(Commands.argument("player", EntityArgument.player())
                        .then(Commands.argument("questId", StringArgumentType.word())
                                .suggests(QUEST_IDS)
                                .executes(context -> mutate(context, complete))));
    }

    private static int mutate(CommandContext<CommandSourceStack> context, boolean complete)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer target = EntityArgument.getPlayer(context, "player");
        String id = StringArgumentType.getString(context, "questId");
        MinecraftServer server = source.getServer();
        Optional<GoalSpec> found = QuestApi.byId(server, id);
        if (found.isEmpty()) {
            source.sendFailure(Component.translatable("dev.eclipse.quest.unknown", id));
            return 0;
        }

        boolean changed = complete
                ? QuestApi.complete(server, target, found.get())
                : QuestApi.revoke(server, target, found.get());
        if (!changed) {
            source.sendFailure(Component.translatable(complete
                            ? "dev.eclipse.quest.complete.noop" : "dev.eclipse.quest.revoke.noop",
                    id, target.getScoreboardName()));
            return 0;
        }
        Component feedback = Component.translatable(complete
                        ? "dev.eclipse.quest.complete.ok" : "dev.eclipse.quest.revoke.ok",
                id, target.getScoreboardName());
        audit(source, feedback, (complete ? "completed " : "revoked ") + "quest " + id
                + " for " + target.getScoreboardName());
        return 1;
    }

    private static int reroll(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer target = EntityArgument.getPlayer(context, "player");
        List<String> drawn = QuestApi.reroll(source.getServer(), target);
        Component feedback = Component.translatable("dev.eclipse.quest.reroll.ok",
                target.getScoreboardName(), String.join(", ", drawn));
        audit(source, feedback, "rerolled personal quests for " + target.getScoreboardName());
        return drawn.size();
    }

    private static int list(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer target = EntityArgument.getPlayer(context, "player");
        List<GoalSpec> specs = QuestApi.allForPlayer(source.getServer(), target);
        source.sendSuccess(() -> Component.translatable("dev.eclipse.quest.list.header",
                target.getScoreboardName(), specs.size()), false);
        for (GoalSpec spec : specs) {
            boolean done = QuestApi.isDone(source.getServer(), target, spec);
            long progress = Math.min(QuestApi.progress(source.getServer(), target, spec), spec.target());
            MutableComponent clickableId = Component.literal(spec.id()).withStyle(Style.EMPTY
                    .withColor(ChatFormatting.AQUA)
                    .withUnderlined(true)
                    .withClickEvent(new ClickEvent(ClickEvent.Action.SUGGEST_COMMAND,
                            "/dev quest complete " + target.getScoreboardName() + " " + spec.id()))
                    .withHoverEvent(new HoverEvent(HoverEvent.Action.SHOW_TEXT,
                            Component.translatable("dev.eclipse.quest.list.hover"))));
            source.sendSuccess(() -> Component.translatable("dev.eclipse.quest.list.entry",
                    done ? "✔" : "•", clickableId, spec.goalKind().id(), spec.scope().id(),
                    progress, spec.target(), displayText(spec)), false);
        }
        return specs.size();
    }

    private static String displayText(GoalSpec spec) {
        String german = spec.text().de();
        return german == null || german.equals(spec.text().en())
                ? spec.text().en()
                : spec.text().en() + " / " + german;
    }

    private static void audit(CommandSourceStack source, Component feedback, String logDetail) {
        source.sendSuccess(() -> feedback, false);
        for (ServerPlayer operator : source.getServer().getPlayerList().getPlayers()) {
            if (operator.hasPermissions(2) && operator != source.getEntity()) {
                operator.sendSystemMessage(Component.translatable("dev.eclipse.audit",
                        source.getTextName(), feedback));
            }
        }
        EclipseMod.LOGGER.info("[DEV AUDIT] {} {}", source.getTextName(), logDetail);
    }
}
