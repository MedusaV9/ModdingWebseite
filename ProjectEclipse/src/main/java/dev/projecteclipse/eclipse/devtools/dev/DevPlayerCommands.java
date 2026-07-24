package dev.projecteclipse.eclipse.devtools.dev;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.FloatArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.skills.SkillsApi;
import dev.projecteclipse.eclipse.voice.VoiceMuteApi;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.arguments.EntityArgument;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/** Player XP/secret-perk controls plus the Simple Voice Chat moderation bridge. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevPlayerCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("player.xp.give", DevCategory.PLAYERS,
                        "/dev player xp give <player> <amount>",
                        "dev.eclipse.doc.player.xp.give", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("player.multiplier.set", DevCategory.PLAYERS,
                        "/dev player multiplier set <player> <factor>",
                        "dev.eclipse.doc.player.multiplier.set", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("player.multiplier.clear", DevCategory.PLAYERS,
                        "/dev player multiplier clear <player>",
                        "dev.eclipse.doc.player.multiplier.clear", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("player.multiplier.show", DevCategory.PLAYERS,
                        "/dev player multiplier show <player>",
                        "dev.eclipse.doc.player.multiplier.show", Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("voice.mute.global", DevCategory.PLAYERS,
                        "/dev voice mute global (on|off)",
                        "dev.eclipse.doc.voice.mute.global", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("voice.mute.player", DevCategory.PLAYERS,
                        "/dev voice mute player <player> (on|off)",
                        "dev.eclipse.doc.voice.mute.player", Danger.CAUTION, ClickAction.SUGGEST, 2));
    }

    private DevPlayerCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("player")
                        .then(Commands.literal("xp")
                                .then(Commands.literal("give")
                                        .then(Commands.argument("player", EntityArgument.player())
                                                .then(Commands.argument("amount",
                                                                FloatArgumentType.floatArg(0.0F, 10_000_000.0F))
                                                        .executes(DevPlayerCommands::giveXp)))))
                        .then(Commands.literal("multiplier")
                                .then(Commands.literal("set")
                                        .then(Commands.argument("player", EntityArgument.player())
                                                .then(Commands.argument("factor",
                                                                FloatArgumentType.floatArg(0.0F, 100.0F))
                                                        .executes(context -> setMultiplier(context, false)))))
                                .then(Commands.literal("clear")
                                        .then(Commands.argument("player", EntityArgument.player())
                                                .executes(context -> setMultiplier(context, true))))
                                .then(Commands.literal("show")
                                        .then(Commands.argument("player", EntityArgument.player())
                                                .executes(DevPlayerCommands::showMultiplier)))))
                .then(Commands.literal("voice")
                        .then(Commands.literal("mute")
                                .then(Commands.literal("global")
                                        .then(Commands.literal("on")
                                                .executes(context -> globalMute(context, true)))
                                        .then(Commands.literal("off")
                                                .executes(context -> globalMute(context, false))))
                                .then(Commands.literal("player")
                                        .then(Commands.argument("player", EntityArgument.player())
                                                .then(Commands.literal("on")
                                                        .executes(context -> playerMute(context, true)))
                                                .then(Commands.literal("off")
                                                        .executes(context -> playerMute(context, false))))))));
    }

    private static int giveXp(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer target = EntityArgument.getPlayer(context, "player");
        float amount = FloatArgumentType.getFloat(context, "amount");
        int applied = SkillsApi.addXp(target, amount);
        Component feedback = Component.translatable("dev.eclipse.player.xp.give.ok",
                amount, applied, target.getScoreboardName());
        audit(source, feedback, "granted " + amount + " base skill XP to " + target.getScoreboardName());
        return 1;
    }

    private static int setMultiplier(CommandContext<CommandSourceStack> context, boolean clear)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer target = EntityArgument.getPlayer(context, "player");
        float factor = clear ? 1.0F : FloatArgumentType.getFloat(context, "factor");
        SkillsApi.setSecretMultiplier(source.getServer(), target.getUUID(), factor);

        // Secret value discipline: issuing source only; no operator broadcast and no INFO value.
        source.sendSuccess(() -> Component.translatable(clear
                        ? "dev.eclipse.player.multiplier.clear.ok" : "dev.eclipse.player.multiplier.set.ok",
                target.getScoreboardName()), false);
        EclipseMod.LOGGER.info("[DEV AUDIT] {} {} secret skill multiplier for {} (value withheld)",
                source.getTextName(), clear ? "cleared" : "changed", target.getScoreboardName());
        return 1;
    }

    private static int showMultiplier(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer target = EntityArgument.getPlayer(context, "player");
        float factor = SkillsApi.getSecretMultiplier(source.getServer(), target.getUUID());
        source.sendSuccess(() -> Component.translatable("dev.eclipse.player.multiplier.show",
                target.getScoreboardName(), factor), false);
        return 1;
    }

    private static int globalMute(CommandContext<CommandSourceStack> context, boolean muted) {
        CommandSourceStack source = context.getSource();
        VoiceMuteApi.setGlobalMuted(source.getServer(), muted);
        Component feedback = Component.translatable(muted
                ? "dev.eclipse.voice.global.on" : "dev.eclipse.voice.global.off");
        audit(source, feedback, "set global voice mute=" + muted);
        return 1;
    }

    private static int playerMute(CommandContext<CommandSourceStack> context, boolean muted)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer target = EntityArgument.getPlayer(context, "player");
        VoiceMuteApi.setForceMuted(source.getServer(), target.getUUID(), muted);
        Component feedback = Component.translatable(muted
                        ? "dev.eclipse.voice.player.on" : "dev.eclipse.voice.player.off",
                target.getScoreboardName());
        audit(source, feedback, "set voice mute=" + muted + " for " + target.getScoreboardName());
        return 1;
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
