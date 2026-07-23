package dev.projecteclipse.eclipse.skills;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.FloatArgumentType;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.arguments.LongArgumentType;
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
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * Skill command roots (R3). Player-facing {@code /skills} (perm 0): {@code info},
 * {@code procmsg on|off}, {@code buy <node>} (server-validated fallback until P3's GUI).
 * Admin {@code /eclipse-skills} (perm 3) is the reference implementation P5 will surface:
 * {@code xp add|set}, {@code mult set} (secret — feedback to the issuing source only, no
 * admin broadcast, DEBUG log), {@code points add}, {@code tree reset}, {@code reload}.
 * New roots by design — the existing {@code /eclipse} tree is untouched (plan rule 1).
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class SkillCommands {
    private static final SuggestionProvider<CommandSourceStack> NODE_SUGGESTIONS =
            (context, builder) -> SharedSuggestionProvider.suggest(
                    SkillTreeConfig.get().nodes().keySet(), builder);

    private SkillCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("skills")
                .executes(SkillCommands::info)
                .then(Commands.literal("info").executes(SkillCommands::info))
                .then(Commands.literal("procmsg")
                        .then(Commands.literal("on").executes(ctx -> procMsg(ctx, true)))
                        .then(Commands.literal("off").executes(ctx -> procMsg(ctx, false))))
                .then(Commands.literal("buy")
                        .then(Commands.argument("node", StringArgumentType.word())
                                .suggests(NODE_SUGGESTIONS)
                                .executes(SkillCommands::buy))));

        dispatcher.register(Commands.literal("eclipse-skills")
                .requires(source -> source.hasPermission(3))
                .then(Commands.literal("xp")
                        .then(Commands.literal("add")
                                .then(Commands.argument("player", EntityArgument.player())
                                        .then(Commands.argument("amount", IntegerArgumentType.integer())
                                                .executes(SkillCommands::xpAdd))))
                        .then(Commands.literal("set")
                                .then(Commands.argument("player", EntityArgument.player())
                                        .then(Commands.argument("amount", LongArgumentType.longArg(0))
                                                .executes(SkillCommands::xpSet)))))
                .then(Commands.literal("mult")
                        .then(Commands.literal("set")
                                .then(Commands.argument("player", EntityArgument.player())
                                        .then(Commands.argument("factor",
                                                        FloatArgumentType.floatArg(0.0F, 100.0F))
                                                .executes(SkillCommands::multSet)))))
                .then(Commands.literal("points")
                        .then(Commands.literal("add")
                                .then(Commands.argument("player", EntityArgument.player())
                                        .then(Commands.argument("amount", IntegerArgumentType.integer(1))
                                                .executes(SkillCommands::pointsAdd)))))
                .then(Commands.literal("tree")
                        .then(Commands.literal("reset")
                                .then(Commands.argument("player", EntityArgument.player())
                                        .executes(SkillCommands::treeReset))))
                .then(Commands.literal("reload").executes(SkillCommands::reload)));
    }

    // ------------------------------------------------------------------
    // /skills (perm 0)
    // ------------------------------------------------------------------

    private static int info(CommandContext<CommandSourceStack> ctx) throws CommandSyntaxException {
        ServerPlayer player = ctx.getSource().getPlayerOrException();
        SkillState.Entry entry = SkillState.get(player.server).entry(player.getUUID());
        SkillCurve.Params curve = SkillConfig.get().curve();
        int level = SkillCurve.levelForXp(entry.totalXp, curve);
        // Action-bar dump (feedback rule: action bar, never chat). Secret multiplier is
        // deliberately absent — nothing here may reveal it.
        player.displayClientMessage(Component.translatable("message.eclipse.skill.info",
                level,
                SkillCurve.xpIntoLevel(entry.totalXp, level, curve),
                SkillCurve.xpForLevel(level + 1, curve),
                entry.unspentPoints()), true);
        SkillService.syncTo(player);
        return level;
    }

    private static int procMsg(CommandContext<CommandSourceStack> ctx, boolean enabled)
            throws CommandSyntaxException {
        ServerPlayer player = ctx.getSource().getPlayerOrException();
        SkillsApi.setProcMessagesEnabled(player, enabled);
        player.displayClientMessage(Component.translatable(enabled
                ? "message.eclipse.skill.procmsg.on"
                : "message.eclipse.skill.procmsg.off"), true);
        return 1;
    }

    private static int buy(CommandContext<CommandSourceStack> ctx) throws CommandSyntaxException {
        ServerPlayer player = ctx.getSource().getPlayerOrException();
        String nodeId = StringArgumentType.getString(ctx, "node");
        return SkillService.buyNode(player, nodeId) == SkillTree.BuyResult.OK ? 1 : 0;
    }

    // ------------------------------------------------------------------
    // /eclipse-skills (perm 3)
    // ------------------------------------------------------------------

    private static int xpAdd(CommandContext<CommandSourceStack> ctx) throws CommandSyntaxException {
        ServerPlayer target = EntityArgument.getPlayer(ctx, "player");
        int amount = IntegerArgumentType.getInteger(ctx, "amount");
        int applied = SkillsApi.addXp(target, SkillService.SOURCE_ADMIN, amount);
        ctx.getSource().sendSuccess(() -> Component.translatable("command.eclipse.skills.xp_added",
                applied, target.getScoreboardName()), true);
        return applied;
    }

    private static int xpSet(CommandContext<CommandSourceStack> ctx) throws CommandSyntaxException {
        ServerPlayer target = EntityArgument.getPlayer(ctx, "player");
        long amount = LongArgumentType.getLong(ctx, "amount");
        SkillsApi.setTotalXp(target, amount);
        ctx.getSource().sendSuccess(() -> Component.translatable("command.eclipse.skills.xp_set",
                amount, target.getScoreboardName()), true);
        return 1;
    }

    private static int multSet(CommandContext<CommandSourceStack> ctx) throws CommandSyntaxException {
        ServerPlayer target = EntityArgument.getPlayer(ctx, "player");
        float factor = FloatArgumentType.getFloat(ctx, "factor");
        SkillsApi.setSecretMultiplier(ctx.getSource().getServer(), target.getUUID(), factor);
        // Secrecy: feedback to the issuing source ONLY (no admin-chat broadcast), value is
        // logged at DEBUG inside SkillsApi and never surfaces in /skills info or payloads.
        ctx.getSource().sendSuccess(() -> Component.translatable("command.eclipse.skills.mult_set",
                target.getScoreboardName()), false);
        return 1;
    }

    private static int pointsAdd(CommandContext<CommandSourceStack> ctx) throws CommandSyntaxException {
        ServerPlayer target = EntityArgument.getPlayer(ctx, "player");
        int amount = IntegerArgumentType.getInteger(ctx, "amount");
        SkillsApi.addPoints(target, amount);
        ctx.getSource().sendSuccess(() -> Component.translatable("command.eclipse.skills.points_added",
                amount, target.getScoreboardName()), true);
        return amount;
    }

    private static int treeReset(CommandContext<CommandSourceStack> ctx) throws CommandSyntaxException {
        ServerPlayer target = EntityArgument.getPlayer(ctx, "player");
        SkillsApi.resetTree(target);
        ctx.getSource().sendSuccess(() -> Component.translatable("command.eclipse.skills.tree_reset",
                target.getScoreboardName()), true);
        return 1;
    }

    private static int reload(CommandContext<CommandSourceStack> ctx) {
        SkillConfig.reload();
        SkillTreeConfig.reload();
        for (ServerPlayer player : ctx.getSource().getServer().getPlayerList().getPlayers()) {
            SkillService.sendTree(player);
            SkillService.syncTo(player);
        }
        ctx.getSource().sendSuccess(() -> Component.translatable("command.eclipse.skills.reloaded"), true);
        return 1;
    }
}
