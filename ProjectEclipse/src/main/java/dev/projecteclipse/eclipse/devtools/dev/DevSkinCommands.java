package dev.projecteclipse.eclipse.devtools.dev;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.skin.SkinService;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.arguments.EntityArgument;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev skin …} (F-050) and {@code /dev adminskin …} (F-051) — operator control over
 * the player skin overrides. All heavy lifting (resolve, download, validate, persist, sync)
 * lives in {@code skin.SkinService}; this class only parses, guards and reports.
 *
 * <ul>
 *   <li>{@code /dev skin <player> <url>} — a direct PNG link (64×64 or 64×32 legacy), a
 *       NameMC profile link, a Mojang texture link, or a bare Minecraft name.</li>
 *   <li>{@code /dev skin <player> reset} — drop the override again.</li>
 *   <li>{@code /dev adminskin <player>} — apply the bundled purple admin skin.</li>
 * </ul>
 *
 * <p>The command returns instantly; a network-backed apply reports success or a localized
 * failure a moment later, from the server thread.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevSkinCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("skin.set", DevCategory.PLAYERS, "/dev skin <player> <url>",
                        "dev.eclipse.doc.skin.set", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("skin.reset", DevCategory.PLAYERS, "/dev skin <player> reset",
                        "dev.eclipse.doc.skin.reset", Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("adminskin", DevCategory.PLAYERS, "/dev adminskin <player>",
                        "dev.eclipse.doc.adminskin", Danger.CAUTION, ClickAction.SUGGEST, 2));
    }

    private DevSkinCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(DevRoot::canUseDev)
                .then(Commands.literal("skin")
                        .then(Commands.argument("player", EntityArgument.player())
                                // The literal is matched before the greedy string, so "reset"
                                // stays a keyword AND tab-completes.
                                .then(Commands.literal("reset")
                                        .executes(DevSkinCommands::reset))
                                .then(Commands.argument("url", StringArgumentType.greedyString())
                                        .executes(DevSkinCommands::apply))))
                .then(Commands.literal("adminskin")
                        .then(Commands.argument("player", EntityArgument.player())
                                .executes(DevSkinCommands::adminSkin))));
    }

    private static int apply(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        ServerPlayer target = EntityArgument.getPlayer(context, "player");
        String url = StringArgumentType.getString(context, "url").strip();
        if (url.equalsIgnoreCase("reset")) {
            return reset(context);
        }
        SkinService.applyFromInput(context.getSource(), target, url);
        return 1;
    }

    private static int adminSkin(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        ServerPlayer target = EntityArgument.getPlayer(context, "player");
        SkinService.applyAdminSkin(context.getSource(), target);
        return 1;
    }

    private static int reset(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer target = EntityArgument.getPlayer(context, "player");
        String name = target.getGameProfile().getName();
        if (!SkinService.reset(source.getServer(), target.getUUID())) {
            source.sendFailure(Component.translatable("dev.eclipse.skin.reset_missing", name));
            return 0;
        }
        SkinService.auditReset(source, Component.translatable("dev.eclipse.skin.reset_done", name),
                "skin reset " + name);
        return 1;
    }
}
