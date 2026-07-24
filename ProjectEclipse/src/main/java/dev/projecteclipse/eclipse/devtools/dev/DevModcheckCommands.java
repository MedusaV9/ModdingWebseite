package dev.projecteclipse.eclipse.devtools.dev;

import java.io.IOException;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.admin.AntiCheatCheck;
import dev.projecteclipse.eclipse.admin.AntiCheatCheck.Evaluation;
import dev.projecteclipse.eclipse.admin.AntiCheatCheck.ModlistMode;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.progression.ModGateIds;
import dev.projecteclipse.eclipse.progression.UnlockState;
import net.minecraft.ChatFormatting;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.arguments.EntityArgument;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/** Operator diagnostics and maintenance for the pack allowlist and progression mod gates. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevModcheckCommands {
    private static final Map<String, String> BUNDLED_MODS = bundledMods();

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("mods.modcheck", DevCategory.MODS,
                        "/dev modcheck", "dev.eclipse.doc.modcheck",
                        Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("mods.modcheck.snapshot", DevCategory.MODS,
                        "/dev modcheck snapshot", "dev.eclipse.doc.modcheck.snapshot",
                        Danger.CAUTION, ClickAction.RUN, 3),
                new DevCommandDoc("mods.modcheck.mode", DevCategory.MODS,
                        "/dev modcheck mode <allowlist|blocklist>", "dev.eclipse.doc.modcheck.mode",
                        Danger.CAUTION, ClickAction.SUGGEST, 3),
                new DevCommandDoc("mods.modcheck.test", DevCategory.MODS,
                        "/dev modcheck test <player>", "dev.eclipse.doc.modcheck.test",
                        Danger.SAFE, ClickAction.SUGGEST, 2));
    }

    private DevModcheckCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("modcheck")
                        .executes(DevModcheckCommands::report)
                        .then(Commands.literal("status")
                                .executes(DevModcheckCommands::report))
                        .then(Commands.literal("test")
                                .then(Commands.argument("player", EntityArgument.player())
                                        .executes(DevModcheckCommands::testPlayer)))
                        .then(Commands.literal("snapshot")
                                .requires(source -> source.hasPermission(3))
                                .executes(DevModcheckCommands::snapshot))
                        .then(Commands.literal("mode")
                                .requires(source -> source.hasPermission(3))
                                .then(Commands.literal("allowlist")
                                        .executes(context -> setMode(context, ModlistMode.ALLOWLIST)))
                                .then(Commands.literal("blocklist")
                                        .executes(context -> setMode(context, ModlistMode.BLOCKLIST))))));
    }

    private static int report(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        Map<String, String> loaded = AntiCheatCheck.loadedMods();
        Evaluation evaluation = AntiCheatCheck.evaluate(loaded.keySet());
        var config = AntiCheatCheck.config();

        source.sendSuccess(() -> Component.translatable("dev.eclipse.modcheck.header",
                config.mode().configName(), loaded.size(),
                Component.translatable(evaluation.accepted()
                        ? "dev.eclipse.modcheck.state.passed"
                        : "dev.eclipse.modcheck.state.failed"))
                .withStyle(evaluation.accepted() ? ChatFormatting.GREEN : ChatFormatting.YELLOW), false);
        sendEvaluation(source, evaluation);

        for (Map.Entry<String, String> mod : loaded.entrySet()) {
            String expected = config.allowedMods().getOrDefault(mod.getKey(), "—");
            source.sendSuccess(() -> Component.translatable("dev.eclipse.modcheck.loaded",
                    mod.getKey(), mod.getValue(), expected).withStyle(ChatFormatting.GRAY), false);
        }

        source.sendSuccess(() -> Component.translatable("dev.eclipse.modcheck.gates.header")
                .withStyle(ChatFormatting.LIGHT_PURPLE), false);
        for (String namespace : EclipseConfig.modGate().gatedNamespaces()) {
            String key = EclipseConfig.modGate().unlockKeys().getOrDefault(namespace, namespace);
            boolean unlocked = UnlockState.isUnlocked(source.getServer(), key);
            source.sendSuccess(() -> Component.translatable("dev.eclipse.modcheck.gate.namespace",
                    namespace, key, Component.translatable(unlocked
                            ? "dev.eclipse.modcheck.state.unlocked"
                            : "dev.eclipse.modcheck.state.locked"))
                    .withStyle(unlocked ? ChatFormatting.GREEN : ChatFormatting.RED), false);
        }
        for (ModGateIds.GateRule rule : ModGateIds.rules()) {
            boolean unlocked = UnlockState.isUnlocked(source.getServer(), rule.unlockKey());
            source.sendSuccess(() -> Component.translatable("dev.eclipse.modcheck.gate.id",
                    rule.glob(), rule.unlockKey(), Component.translatable(unlocked
                            ? "dev.eclipse.modcheck.state.unlocked"
                            : "dev.eclipse.modcheck.state.locked"))
                    .withStyle(unlocked ? ChatFormatting.GREEN : ChatFormatting.RED), false);
        }

        source.sendSuccess(() -> Component.translatable("dev.eclipse.modcheck.bundles.header")
                .withStyle(ChatFormatting.LIGHT_PURPLE), false);
        for (Map.Entry<String, String> bundle : BUNDLED_MODS.entrySet()) {
            boolean present = loaded.containsKey(bundle.getKey());
            source.sendSuccess(() -> Component.translatable("dev.eclipse.modcheck.bundle",
                    bundle.getKey(), bundle.getValue(), Component.translatable(present
                            ? "dev.eclipse.modcheck.state.loaded"
                            : "dev.eclipse.modcheck.state.not_loaded"))
                    .withStyle(present ? ChatFormatting.GREEN : ChatFormatting.YELLOW), false);
        }
        return 1;
    }

    private static int testPlayer(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        ServerPlayer player = EntityArgument.getPlayer(context, "player");
        var report = AntiCheatCheck.lastReport(player.getUUID());
        if (report.isEmpty()) {
            context.getSource().sendFailure(Component.translatable(
                    "dev.eclipse.modcheck.test.no_report", player.getScoreboardName()));
            return 0;
        }
        Evaluation evaluation = AntiCheatCheck.evaluate(report.get());
        context.getSource().sendSuccess(() -> Component.translatable(
                "dev.eclipse.modcheck.test.result", player.getScoreboardName(),
                Component.translatable(evaluation.accepted()
                        ? "dev.eclipse.modcheck.state.passed"
                        : "dev.eclipse.modcheck.state.failed"))
                .withStyle(evaluation.accepted() ? ChatFormatting.GREEN : ChatFormatting.YELLOW), false);
        sendEvaluation(context.getSource(), evaluation);
        return 1;
    }

    private static int snapshot(CommandContext<CommandSourceStack> context) {
        try {
            var updated = AntiCheatCheck.snapshotRunningServer();
            context.getSource().sendSuccess(() -> Component.translatable(
                    "dev.eclipse.modcheck.snapshot.saved",
                    updated.allowedMods().size(), updated.requiredMods().size()), true);
            return 1;
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to snapshot running mod allowlist", e);
            context.getSource().sendFailure(Component.translatable(
                    "dev.eclipse.modcheck.write_failed", e.getMessage()));
            return 0;
        }
    }

    private static int setMode(CommandContext<CommandSourceStack> context, ModlistMode mode) {
        try {
            AntiCheatCheck.setMode(mode);
            context.getSource().sendSuccess(() -> Component.translatable(
                    "dev.eclipse.modcheck.mode.set", mode.configName()), true);
            return 1;
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to persist modcheck mode {}", mode.configName(), e);
            context.getSource().sendFailure(Component.translatable(
                    "dev.eclipse.modcheck.write_failed", e.getMessage()));
            return 0;
        }
    }

    private static Map<String, String> bundledMods() {
        Map<String, String> bundled = new LinkedHashMap<>();
        bundled.put("veil", "4.3.0");
        bundled.put("geckolib", "4.9.2");
        bundled.put("emi", "1.1.18+1.21.1");
        bundled.put("mousetweaks", "2.26.1");
        return Collections.unmodifiableMap(bundled);
    }

    private static void sendEvaluation(CommandSourceStack source, Evaluation evaluation) {
        if (!evaluation.blocked().isEmpty()) {
            source.sendFailure(Component.translatable("dev.eclipse.modcheck.issue.blocked",
                    String.join(", ", evaluation.blocked())));
        }
        if (!evaluation.missing().isEmpty()) {
            source.sendFailure(Component.translatable("dev.eclipse.modcheck.issue.missing",
                    String.join(", ", evaluation.missing())));
        }
        if (!evaluation.extra().isEmpty()) {
            source.sendFailure(Component.translatable("dev.eclipse.modcheck.issue.extra",
                    String.join(", ", evaluation.extra())));
        }
    }
}
