package dev.projecteclipse.eclipse.voice;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.builder.LiteralArgumentBuilder;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * Player-facing voice changer command ({@code /voice <preset>}, perm 0, SELF ONLY). Presets
 * are Brigadier literals; each execution re-checks {@link VoiceChangerConfig} so only
 * config-whitelisted presets can be self-selected (ops set anything via
 * {@code /dev voice changer}). Selecting a preset stores a per-player override in
 * {@link VoiceChangerService} — including {@code off}, which overrides a non-OFF global
 * default; {@code /voice reset} drops the override and falls back to the global default.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class VoiceChangerCommands {
    private VoiceChangerCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        LiteralArgumentBuilder<CommandSourceStack> voice = Commands.literal("voice");
        for (VoicePreset preset : VoicePreset.values()) {
            voice.then(Commands.literal(preset.id())
                    .executes(context -> selectSelf(context, preset)));
        }
        voice.then(Commands.literal("reset").executes(VoiceChangerCommands::resetSelf));
        dispatcher.register(voice);
    }

    private static int selectSelf(CommandContext<CommandSourceStack> context, VoicePreset preset)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer player = source.getPlayerOrException();
        VoiceChangerConfig.Snapshot config = VoiceChangerConfig.current();
        if (!config.enabled()) {
            source.sendFailure(Component.translatable("command.eclipse.voice_changer.disabled"));
            return 0;
        }
        if (!config.isPlayerSelectable(preset)) {
            source.sendFailure(Component.translatable("command.eclipse.voice_changer.not_allowed",
                    preset.id()));
            return 0;
        }
        VoiceChangerService.setPlayerPreset(source.getServer(), player.getUUID(), preset);
        source.sendSuccess(() -> Component.translatable("command.eclipse.voice_changer.self.ok",
                preset.id()), false);
        return 1;
    }

    private static int resetSelf(CommandContext<CommandSourceStack> context)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer player = source.getPlayerOrException();
        VoiceChangerService.setPlayerPreset(source.getServer(), player.getUUID(), null);
        source.sendSuccess(() -> Component.translatable("command.eclipse.voice_changer.self.reset"),
                false);
        return 1;
    }
}
