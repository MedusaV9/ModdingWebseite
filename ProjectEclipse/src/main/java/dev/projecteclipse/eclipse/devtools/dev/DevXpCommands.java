package dev.projecteclipse.eclipse.devtools.dev;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.IntegerArgumentType;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.skills.RebirthHooks;
import dev.projecteclipse.eclipse.skills.SkillConfig;
import dev.projecteclipse.eclipse.skills.SkillCurve;
import dev.projecteclipse.eclipse.skills.SkillsApi;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.arguments.EntityArgument;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev xp …} — PROGFIX #4 skill-tree progression grants (both permission 2,
 * player defaults to the issuing source):
 *
 * <ul>
 *   <li>{@code add <amount> [player]} — grants XP through the full admin pipeline
 *       ({@code SkillsApi.addXp}, source {@code admin}: exempt from the pre-event and
 *       event-dimension gates, level-ups + client sync handled inside).</li>
 *   <li>{@code level <level> [player]} — hard-sets lifetime XP to exactly the cumulative
 *       cost of {@code <level>} on the target's EFFECTIVE curve (rebirth multipliers
 *       included via {@code RebirthHooks.curveFor}); the level sweep grants any newly
 *       reached levels and resyncs the client.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevXpCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("xp.add", DevCategory.PLAYERS,
                        "/dev xp add <amount> [player]",
                        "dev.eclipse.doc.xp.add", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("xp.level", DevCategory.PLAYERS,
                        "/dev xp level <level> [player]",
                        "dev.eclipse.doc.xp.level", Danger.CAUTION, ClickAction.SUGGEST, 2));
    }

    private DevXpCommands() {}

    @SubscribeEvent
    static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("xp")
                        .requires(source -> source.hasPermission(2))
                        .then(Commands.literal("add")
                                .then(Commands.argument("amount", IntegerArgumentType.integer(1))
                                        .executes(context -> add(context.getSource(),
                                                context.getSource().getPlayerOrException(),
                                                IntegerArgumentType.getInteger(context, "amount")))
                                        .then(Commands.argument("player", EntityArgument.player())
                                                .executes(context -> add(context.getSource(),
                                                        EntityArgument.getPlayer(context, "player"),
                                                        IntegerArgumentType.getInteger(context, "amount"))))))
                        .then(Commands.literal("level")
                                .then(Commands.argument("level",
                                                IntegerArgumentType.integer(0, SkillCurve.MAX_LEVEL))
                                        .executes(context -> level(context.getSource(),
                                                context.getSource().getPlayerOrException(),
                                                IntegerArgumentType.getInteger(context, "level")))
                                        .then(Commands.argument("player", EntityArgument.player())
                                                .executes(context -> level(context.getSource(),
                                                        EntityArgument.getPlayer(context, "player"),
                                                        IntegerArgumentType.getInteger(context, "level"))))))));
    }

    private static int add(CommandSourceStack source, ServerPlayer target, int amount) {
        int applied = SkillsApi.addXp(target, amount);
        Component feedback = Component.translatable("dev.eclipse.xp.add.ok",
                applied, target.getScoreboardName());
        audit(source, feedback, "granted " + applied + " skill XP to " + target.getScoreboardName());
        return applied;
    }

    private static int level(CommandSourceStack source, ServerPlayer target, int level) {
        SkillCurve.Params curve = RebirthHooks.curveFor(source.getServer(), target.getUUID(),
                SkillConfig.get().curve());
        long totalXp = SkillCurve.cumulativeXp(level, curve);
        SkillsApi.setTotalXp(target, totalXp);
        Component feedback = Component.translatable("dev.eclipse.xp.level.ok",
                target.getScoreboardName(), level, totalXp);
        audit(source, feedback, "set skill level of " + target.getScoreboardName()
                + " to " + level + " (totalXp=" + totalXp + ")");
        return 1;
    }

    /** Same operator-audit convention as the other /dev command bridges. */
    private static void audit(CommandSourceStack source, Component feedback, String logDetail) {
        source.sendSuccess(() -> feedback, false);
        for (ServerPlayer operator : source.getServer().getPlayerList().getPlayers()) {
            if (operator.hasPermissions(2) && operator != source.getEntity()) {
                operator.sendSystemMessage(ServerLang.tr(operator, "dev.eclipse.audit",
                        source.getTextName(), feedback));
            }
        }
        EclipseMod.LOGGER.info("[DEV AUDIT] {} {}", source.getTextName(), logDetail);
    }
}
