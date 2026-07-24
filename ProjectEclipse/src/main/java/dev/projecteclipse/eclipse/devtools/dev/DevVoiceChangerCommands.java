package dev.projecteclipse.eclipse.devtools.dev;

import java.util.Map;
import java.util.UUID;

import javax.annotation.Nullable;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.builder.LiteralArgumentBuilder;
import com.mojang.brigadier.builder.RequiredArgumentBuilder;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.voice.VoiceChangerConfig;
import dev.projecteclipse.eclipse.voice.VoiceChangerService;
import dev.projecteclipse.eclipse.voice.VoicePreset;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.arguments.EntityArgument;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * Operator voice-changer controls (perm 2), merged under the existing {@code /dev voice}
 * literal next to DevPlayerCommands' mute bridge:
 * <ul>
 *   <li>{@code /dev voice changer <player> <preset>} — per-player override (any preset,
 *       ignores the {@code /voice} self-select whitelist);</li>
 *   <li>{@code /dev voice changer <player> clear} — drop the override (inherit default);</li>
 *   <li>{@code /dev voice changer default (<preset>|clear)} — global default preset;</li>
 *   <li>{@code /dev voice changer status} — default, overrides, config + kill-switch state;</li>
 *   <li>{@code /dev voice changer reset} — re-arm the DSP budget kill switch.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevVoiceChangerCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("voice.changer.player", DevCategory.PLAYERS,
                        "/dev voice changer <player> (off|deep|high|ghost|glitch|clear)",
                        "dev.eclipse.doc.voice.changer.player", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("voice.changer.default", DevCategory.PLAYERS,
                        "/dev voice changer default (off|deep|high|ghost|glitch|clear)",
                        "dev.eclipse.doc.voice.changer.default", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("voice.changer.status", DevCategory.PLAYERS,
                        "/dev voice changer status",
                        "dev.eclipse.doc.voice.changer.status", Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("voice.changer.reset", DevCategory.PLAYERS,
                        "/dev voice changer reset",
                        "dev.eclipse.doc.voice.changer.reset", Danger.CAUTION, ClickAction.RUN, 2));
    }

    private DevVoiceChangerCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        LiteralArgumentBuilder<CommandSourceStack> defaults = Commands.literal("default")
                .then(Commands.literal("clear").executes(context -> setDefault(context, VoicePreset.OFF)));
        for (VoicePreset preset : VoicePreset.values()) {
            defaults.then(Commands.literal(preset.id())
                    .executes(context -> setDefault(context, preset)));
        }
        RequiredArgumentBuilder<CommandSourceStack, ?> player = Commands.argument("player",
                        EntityArgument.player())
                .then(Commands.literal("clear").executes(context -> setPlayer(context, null)));
        for (VoicePreset preset : VoicePreset.values()) {
            player.then(Commands.literal(preset.id())
                    .executes(context -> setPlayer(context, preset)));
        }
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("voice")
                        .then(Commands.literal("changer")
                                .then(Commands.literal("status").executes(DevVoiceChangerCommands::status))
                                .then(Commands.literal("reset").executes(DevVoiceChangerCommands::reset))
                                .then(defaults)
                                .then(player))));
    }

    private static int setPlayer(CommandContext<CommandSourceStack> context, @Nullable VoicePreset preset)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer target = EntityArgument.getPlayer(context, "player");
        VoiceChangerService.setPlayerPreset(source.getServer(), target.getUUID(), preset);
        Component feedback = preset == null
                ? Component.translatable("dev.eclipse.voice.changer.clear", target.getScoreboardName())
                : Component.translatable("dev.eclipse.voice.changer.set",
                        target.getScoreboardName(), preset.id());
        audit(source, feedback, "voice changer for " + target.getScoreboardName() + " -> "
                + (preset == null ? "clear" : preset.id()));
        return 1;
    }

    private static int setDefault(CommandContext<CommandSourceStack> context, VoicePreset preset) {
        CommandSourceStack source = context.getSource();
        VoiceChangerService.setGlobalDefault(source.getServer(), preset);
        Component feedback = Component.translatable("dev.eclipse.voice.changer.default.set", preset.id());
        audit(source, feedback, "voice changer global default -> " + preset.id());
        return 1;
    }

    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        VoiceChangerConfig.Snapshot config = VoiceChangerConfig.current();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.voice.changer.status.header",
                VoiceChangerService.globalDefault(server).id(),
                config.enabled() ? "ON" : "OFF",
                config.frameBudgetMicros(),
                VoiceChangerService.worstFrameMicros()), false);
        if (VoiceChangerService.isAutoDisabled()) {
            source.sendSuccess(() -> Component.translatable(
                    "dev.eclipse.voice.changer.status.autodisabled"), false);
        }
        Map<UUID, VoicePreset> overrides = VoiceChangerService.playerPresets(server);
        if (overrides.isEmpty()) {
            source.sendSuccess(() -> Component.translatable(
                    "dev.eclipse.voice.changer.status.none"), false);
            return 1;
        }
        for (Map.Entry<UUID, VoicePreset> entry : overrides.entrySet()) {
            ServerPlayer online = server.getPlayerList().getPlayer(entry.getKey());
            String name = online != null ? online.getScoreboardName() : entry.getKey().toString();
            source.sendSuccess(() -> Component.translatable("dev.eclipse.voice.changer.status.line",
                    name, entry.getValue().id()), false);
        }
        return 1;
    }

    private static int reset(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        VoiceChangerService.resetAutoDisable();
        Component feedback = Component.translatable("dev.eclipse.voice.changer.reset.ok");
        audit(source, feedback, "re-armed voice changer budget kill switch");
        return 1;
    }

    /** Same operator-audit convention as the other /dev command bridges. */
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
