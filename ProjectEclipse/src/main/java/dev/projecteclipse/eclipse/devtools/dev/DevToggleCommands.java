package dev.projecteclipse.eclipse.devtools.dev;

import java.util.Map;
import java.util.UUID;

import javax.annotation.Nullable;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.builder.LiteralArgumentBuilder;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.admin.ActionTogglesService;
import dev.projecteclipse.eclipse.admin.ToggleAction;
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
 * W4-TOGGLES command bridge to {@link ActionTogglesService} (perm 2):
 * <ul>
 *   <li>{@code /dev toggle <action> global (on|off)} — on = action allowed;</li>
 *   <li>{@code /dev toggle <action> player <player> (allow|deny|clear)} — tri-state override;</li>
 *   <li>{@code /dev toggle status [player]} — global flags (+ override counts) or one
 *       player's effective per-action permissions;</li>
 *   <li>{@code /dev toggle clearall} — reset everything to allowed.</li>
 * </ul>
 * Actions are Brigadier literals (tab completion + no unknown-id error path).
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevToggleCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("toggle.global", DevCategory.PLAYERS,
                        "/dev toggle <action> global (on|off)",
                        "dev.eclipse.doc.toggle.global", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("toggle.player", DevCategory.PLAYERS,
                        "/dev toggle <action> player <player> (allow|deny|clear)",
                        "dev.eclipse.doc.toggle.player", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("toggle.status", DevCategory.PLAYERS,
                        "/dev toggle status [player]",
                        "dev.eclipse.doc.toggle.status", Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("toggle.clearall", DevCategory.PLAYERS,
                        "/dev toggle clearall",
                        "dev.eclipse.doc.toggle.clearall", Danger.CAUTION, ClickAction.RUN, 2));
    }

    private DevToggleCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        LiteralArgumentBuilder<CommandSourceStack> toggle = Commands.literal("toggle")
                .then(Commands.literal("status")
                        .executes(context -> status(context, null))
                        .then(Commands.argument("player", EntityArgument.player())
                                .executes(context -> status(context,
                                        EntityArgument.getPlayer(context, "player")))))
                .then(Commands.literal("clearall").executes(DevToggleCommands::clearAll));
        for (ToggleAction action : ToggleAction.values()) {
            toggle.then(Commands.literal(action.id())
                    .then(Commands.literal("global")
                            .then(Commands.literal("on")
                                    .executes(context -> setGlobal(context, action, true)))
                            .then(Commands.literal("off")
                                    .executes(context -> setGlobal(context, action, false))))
                    .then(Commands.literal("player")
                            .then(Commands.argument("player", EntityArgument.player())
                                    .then(Commands.literal("allow")
                                            .executes(context -> setOverride(context, action, Boolean.TRUE)))
                                    .then(Commands.literal("deny")
                                            .executes(context -> setOverride(context, action, Boolean.FALSE)))
                                    .then(Commands.literal("clear")
                                            .executes(context -> setOverride(context, action, null))))));
        }
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(toggle));
    }

    private static int setGlobal(CommandContext<CommandSourceStack> context, ToggleAction action,
            boolean allowed) {
        CommandSourceStack source = context.getSource();
        ActionTogglesService.setGlobal(source.getServer(), action, allowed);
        Component feedback = Component.translatable(
                allowed ? "dev.eclipse.toggle.global.on" : "dev.eclipse.toggle.global.off", action.id());
        audit(source, feedback, "set toggle " + action.id() + " globally "
                + (allowed ? "on" : "off"));
        return 1;
    }

    private static int setOverride(CommandContext<CommandSourceStack> context, ToggleAction action,
            @Nullable Boolean allow) throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer target = EntityArgument.getPlayer(context, "player");
        ActionTogglesService.setOverride(source.getServer(), action, target.getUUID(), allow);
        String key = allow == null ? "dev.eclipse.toggle.player.clear"
                : (allow ? "dev.eclipse.toggle.player.allow" : "dev.eclipse.toggle.player.deny");
        Component feedback = Component.translatable(key, action.id(), target.getScoreboardName());
        audit(source, feedback, "toggle " + action.id() + " for " + target.getScoreboardName()
                + " -> " + (allow == null ? "clear" : (allow ? "allow" : "deny")));
        return 1;
    }

    private static int status(CommandContext<CommandSourceStack> context, @Nullable ServerPlayer player) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        if (player == null) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.toggle.status.header"), false);
            for (ToggleAction action : ToggleAction.values()) {
                boolean allowed = ActionTogglesService.isGlobalAllowed(server, action);
                Map<UUID, Boolean> overrides = ActionTogglesService.overridesFor(server, action);
                long allows = overrides.values().stream().filter(Boolean::booleanValue).count();
                long denies = overrides.size() - allows;
                source.sendSuccess(() -> Component.translatable("dev.eclipse.toggle.status.line",
                        action.id(), onOff(allowed), allows, denies), false);
            }
        } else {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.toggle.status.player.header",
                    player.getScoreboardName()), false);
            for (ToggleAction action : ToggleAction.values()) {
                boolean effective = ActionTogglesService.isAllowed(server, action, player.getUUID());
                Boolean override = ActionTogglesService.playerOverride(server, action, player.getUUID());
                String overrideText = override == null ? "-" : (override ? "ALLOW" : "DENY");
                source.sendSuccess(() -> Component.translatable("dev.eclipse.toggle.status.player.line",
                        action.id(), onOff(effective), overrideText), false);
            }
        }
        return 1;
    }

    private static int clearAll(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ActionTogglesService.clearAll(source.getServer());
        Component feedback = Component.translatable("dev.eclipse.toggle.clearall.ok");
        audit(source, feedback, "cleared all action toggles");
        return 1;
    }

    private static String onOff(boolean allowed) {
        return allowed ? "ON" : "OFF";
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
