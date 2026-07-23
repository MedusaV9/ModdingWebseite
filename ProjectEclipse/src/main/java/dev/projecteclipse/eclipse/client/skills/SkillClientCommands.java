package dev.projecteclipse.eclipse.client.skills;

import com.mojang.brigadier.Command;
import com.mojang.brigadier.builder.LiteralArgumentBuilder;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RegisterClientCommandsEvent;

/**
 * Client-side {@code /eclipse-ui procs [on|off]} (WB-SKILLS; plan §3.9's proc click-off
 * target — the {@code LangClientCommands} registration pattern). Flips the
 * {@code procMessages} CLIENT config through the typed handle with {@code set()+save()}
 * (the sanctioned B13 write path, like {@code SettingsPanel}) — purely local, the
 * server-side {@code /skills procmsg} flag is a separate, untouched opt-out. Bare
 * {@code /eclipse-ui procs} reports the current state. The proc chat line's [hide]
 * suffix runs {@code /eclipse-ui procs off} via RUN_COMMAND, which NeoForge routes
 * through the client dispatcher first.
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class SkillClientCommands {
    private SkillClientCommands() {}

    @SubscribeEvent
    static void onRegisterClientCommands(RegisterClientCommandsEvent event) {
        LiteralArgumentBuilder<CommandSourceStack> root = LiteralArgumentBuilder
                .<CommandSourceStack>literal("eclipse-ui")
                .then(Commands.literal("procs")
                        .executes(context -> status(context.getSource()))
                        .then(Commands.literal("on")
                                .executes(context -> apply(context.getSource(), true)))
                        .then(Commands.literal("off")
                                .executes(context -> apply(context.getSource(), false))));
        event.getDispatcher().register(root);
    }

    private static int status(CommandSourceStack source) {
        boolean enabled = EclipseClientConfig.procMessages();
        source.sendSuccess(() -> EclipseLang.tr(enabled
                ? "commands.eclipse.procs.status.on"
                : "commands.eclipse.procs.status.off"), false);
        return Command.SINGLE_SUCCESS;
    }

    private static int apply(CommandSourceStack source, boolean enabled) {
        if (EclipseClientConfig.SPEC.isLoaded()
                && EclipseClientConfig.PROC_MESSAGES.get() != enabled) {
            EclipseClientConfig.PROC_MESSAGES.set(enabled);
            EclipseClientConfig.PROC_MESSAGES.save();
        }
        source.sendSuccess(() -> EclipseLang.tr(enabled
                ? "commands.eclipse.procs.on"
                : "commands.eclipse.procs.off"), false);
        return Command.SINGLE_SUCCESS;
    }
}
