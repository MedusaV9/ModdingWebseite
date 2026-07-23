package dev.projecteclipse.eclipse.client.lang;

import com.mojang.brigadier.Command;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.builder.LiteralArgumentBuilder;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.C2SLocalePayload;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.network.chat.Component;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.RegisterClientCommandsEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Client-side {@code /lang} and {@code /sprache} commands ({@code docs/plans_v3/P3_ui.md} §3.2).
 * Works in singleplayer/dev (client command dispatcher) and on dedicated servers (local client only).
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class LangClientCommands {
    private LangClientCommands() {}

    @SubscribeEvent
    static void onRegisterClientCommands(RegisterClientCommandsEvent event) {
        LiteralArgumentBuilder<CommandSourceStack> langRoot = LiteralArgumentBuilder
                .<CommandSourceStack>literal("lang")
                .executes(context -> showStatus(context.getSource(), false))
                .then(net.minecraft.commands.Commands.argument("mode", StringArgumentType.word())
                        .executes(context -> apply(context.getSource(),
                                StringArgumentType.getString(context, "mode"), false)));

        event.getDispatcher().register(langRoot);

        LiteralArgumentBuilder<CommandSourceStack> spracheRoot = LiteralArgumentBuilder
                .<CommandSourceStack>literal("sprache")
                .executes(context -> showStatus(context.getSource(), true))
                .then(net.minecraft.commands.Commands.argument("mode", StringArgumentType.word())
                        .executes(context -> apply(context.getSource(),
                                StringArgumentType.getString(context, "mode"), true)));

        event.getDispatcher().register(spracheRoot);
    }

    @SubscribeEvent
    static void onClientLogin(ClientPlayerNetworkEvent.LoggingIn event) {
        EclipseLang.initFromConfig();
        syncToServer();
    }

    private static int showStatus(CommandSourceStack source, boolean germanFeedback) {
        String key = switch (EclipseLang.overrideRaw()) {
            case "en_us" -> "commands.eclipse.lang.status.en";
            case "de_de" -> "commands.eclipse.lang.status.de";
            default -> "commands.eclipse.lang.status.auto";
        };
        Component line = germanFeedback
                ? EclipseLang.trForLocale("de_de", key)
                : EclipseLang.tr(key);
        source.sendSuccess(() -> line, false);
        source.sendSuccess(() -> germanFeedback
                ? EclipseLang.trForLocale("de_de", "commands.eclipse.lang.usage")
                : EclipseLang.tr("commands.eclipse.lang.usage"), false);
        return Command.SINGLE_SUCCESS;
    }

    private static int apply(CommandSourceStack source, String mode, boolean germanFeedback) {
        String normalized = EclipseLang.normalizeOverride(mode);
        boolean explicit = !"auto".equals(normalized);
        EclipseLang.setOverride(normalized);
        syncToServer();

        String key = switch (normalized) {
            case "en_us" -> "commands.eclipse.lang.set.en";
            case "de_de" -> "commands.eclipse.lang.set.de";
            default -> "commands.eclipse.lang.set.auto";
        };
        Component line = germanFeedback
                ? EclipseLang.trForLocale("de_de", key)
                : EclipseLang.tr(key);
        source.sendSuccess(() -> line, false);
        PacketDistributor.sendToServer(new C2SLocalePayload(normalized, explicit));
        return Command.SINGLE_SUCCESS;
    }

    private static void syncToServer() {
        String normalized = EclipseLang.overrideRaw();
        boolean explicit = !"auto".equals(normalized);
        PacketDistributor.sendToServer(new C2SLocalePayload(normalized, explicit));
    }
}
