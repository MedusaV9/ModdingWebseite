package dev.projecteclipse.eclipse.devtools.dev;

import java.util.Collection;
import java.util.Locale;
import java.util.UUID;

import com.mojang.authlib.GameProfile;
import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.DoubleArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.anticheat.AntiXrayConfig;
import dev.projecteclipse.eclipse.anticheat.OreExposureRules;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.arguments.GameProfileArgument;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/** Operator queries and threshold tuning for behavioral ore-exposure detection. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevAnticheatCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("anticheat.status", DevCategory.ANALYTICS,
                        "/dev anticheat status", "dev.eclipse.doc.anticheat.status",
                        Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("anticheat.player", DevCategory.ANALYTICS,
                        "/dev anticheat player <player>", "dev.eclipse.doc.anticheat.player",
                        Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("anticheat.threshold.show", DevCategory.ANALYTICS,
                        "/dev anticheat threshold",
                        "dev.eclipse.doc.anticheat.threshold",
                        Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("anticheat.threshold.soft", DevCategory.ANALYTICS,
                        "/dev anticheat threshold soft <score>",
                        "dev.eclipse.doc.anticheat.threshold.set",
                        Danger.CAUTION, ClickAction.SUGGEST, 3),
                new DevCommandDoc("anticheat.threshold.hard", DevCategory.ANALYTICS,
                        "/dev anticheat threshold hard <score>",
                        "dev.eclipse.doc.anticheat.threshold.set",
                        Danger.CAUTION, ClickAction.SUGGEST, 3));
    }

    private DevAnticheatCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("anticheat")
                        .then(Commands.literal("status")
                                .executes(DevAnticheatCommands::status))
                        .then(Commands.literal("player")
                                .then(Commands.argument("player", GameProfileArgument.gameProfile())
                                        .executes(DevAnticheatCommands::player)))
                        .then(Commands.literal("threshold")
                                .executes(DevAnticheatCommands::thresholds)
                                .then(Commands.literal("soft")
                                        .requires(source -> source.hasPermission(3))
                                        .then(Commands.argument("score",
                                                        DoubleArgumentType.doubleArg(0.0D, 100.0D))
                                                .executes(context -> setThreshold(context, true))))
                                .then(Commands.literal("hard")
                                        .requires(source -> source.hasPermission(3))
                                        .then(Commands.argument("score",
                                                        DoubleArgumentType.doubleArg(0.0D, 100.0D))
                                                .executes(context -> setThreshold(context, false)))))));
    }

    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        AntiXrayConfig.Data config = AntiXrayConfig.get();
        OreExposureRules.Status status = OreExposureRules.status();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.anticheat.status",
                yesNo(config.enabled()), actionName(config.actionMode()),
                status.trackedPlayers(), status.softPlayers(), status.hardPlayers()), false);
        source.sendSuccess(() -> Component.translatable("dev.eclipse.anticheat.thresholds",
                config.softThreshold(), config.hardThreshold(),
                config.minimumSamples(), config.windowSize()), false);
        for (OreExposureRules.PlayerScore row : OreExposureRules.playerScores()) {
            if (row.snapshot().level() != OreExposureRules.SuspicionLevel.CLEAR) {
                source.sendSuccess(() -> playerLine(
                        describe(source.getServer(), row.playerId()), row.snapshot()), false);
            }
        }
        return status.softPlayers() + status.hardPlayers();
    }

    private static int player(CommandContext<CommandSourceStack> context)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        Collection<GameProfile> profiles = GameProfileArgument.getGameProfiles(context, "player");
        int printed = 0;
        for (GameProfile profile : profiles) {
            UUID playerId = profile.getId();
            if (playerId == null) {
                source.sendFailure(Component.translatable(
                        "dev.eclipse.anticheat.player.no_uuid", profile.getName()));
                continue;
            }
            OreExposureRules.PlayerSnapshot snapshot = OreExposureRules.playerScore(playerId);
            source.sendSuccess(() -> playerLine(profile.getName(), snapshot), false);
            printed++;
        }
        return printed;
    }

    private static Component playerLine(String playerName,
            OreExposureRules.PlayerSnapshot snapshot) {
        return Component.translatable("dev.eclipse.anticheat.player",
                playerName,
                levelName(snapshot.level()),
                formatScore(snapshot.score()),
                snapshot.unexposedSamples(),
                snapshot.samples(),
                snapshot.exposedSamples());
    }

    private static int thresholds(CommandContext<CommandSourceStack> context) {
        AntiXrayConfig.Data config = AntiXrayConfig.get();
        context.getSource().sendSuccess(() -> Component.translatable(
                "dev.eclipse.anticheat.thresholds",
                config.softThreshold(), config.hardThreshold(),
                config.minimumSamples(), config.windowSize()), false);
        return 1;
    }

    private static int setThreshold(CommandContext<CommandSourceStack> context, boolean soft) {
        CommandSourceStack source = context.getSource();
        AntiXrayConfig.Data old = AntiXrayConfig.get();
        double value = DoubleArgumentType.getDouble(context, "score");
        double newSoft = soft ? value : old.softThreshold();
        double newHard = soft ? old.hardThreshold() : value;
        if (!AntiXrayConfig.updateThresholds(newSoft, newHard)) {
            source.sendFailure(Component.translatable("dev.eclipse.anticheat.threshold.invalid",
                    newSoft, newHard));
            return 0;
        }

        // Existing samples are not silently reinterpreted under a newly chosen policy.
        OreExposureRules.clearTracking();
        String kind = soft ? "soft" : "hard";
        Component feedback = Component.translatable("dev.eclipse.anticheat.threshold.updated",
                Component.translatable("dev.eclipse.anticheat.threshold." + kind), value);
        audit(source, feedback, "set behavioral anti-xray " + kind + " threshold to " + value);
        return 1;
    }

    private static Component yesNo(boolean value) {
        return Component.translatable(value ? "dev.eclipse.yes" : "dev.eclipse.no");
    }

    private static Component levelName(OreExposureRules.SuspicionLevel level) {
        return Component.translatable("dev.eclipse.anticheat.level."
                + level.name().toLowerCase(Locale.ROOT));
    }

    private static Component actionName(AntiXrayConfig.ActionMode action) {
        return Component.translatable("dev.eclipse.anticheat.action."
                + action.name().toLowerCase(Locale.ROOT));
    }

    private static String formatScore(double score) {
        return String.format(Locale.ROOT, "%.1f", score);
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

    private static void audit(CommandSourceStack source, Component feedback, String detail) {
        source.sendSuccess(() -> feedback, false);
        for (ServerPlayer operator : source.getServer().getPlayerList().getPlayers()) {
            if (operator.hasPermissions(2) && operator != source.getEntity()) {
                operator.sendSystemMessage(Component.translatable("dev.eclipse.audit",
                        source.getTextName(), feedback));
            }
        }
        EclipseMod.LOGGER.info("[DEV AUDIT] {} {}", source.getTextName(), detail);
    }
}
