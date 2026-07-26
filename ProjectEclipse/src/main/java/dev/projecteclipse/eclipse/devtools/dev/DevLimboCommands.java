package dev.projecteclipse.eclipse.devtools.dev;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.context.CommandContext;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.protection.LimboProtection;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * Command bridge for the {@link LimboProtection} house rules (perm 2, {@code /dev} tier):
 * <ul>
 *   <li>{@code /dev limbo pvp (on|off)} — the persisted PvP override. OFF (the default)
 *       blocks player-vs-player damage in {@code eclipse:limbo}; an active boss fight
 *       lifts the block on its own, no toggle needed.</li>
 *   <li>{@code /dev limbo status} — the effective rules, including whether a boss fight
 *       is currently lifting the PvP block.</li>
 * </ul>
 * Building in limbo has no toggle by design: {@code /devmode} is the only bypass.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevLimboCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("limbo.pvp", DevCategory.PLAYERS,
                        "/dev limbo pvp (on|off)",
                        "dev.eclipse.doc.limbo.pvp", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("limbo.status", DevCategory.PLAYERS,
                        "/dev limbo status",
                        "dev.eclipse.doc.limbo.status", Danger.SAFE, ClickAction.RUN, 2));
    }

    private DevLimboCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(DevRoot::canUseDev)
                .then(Commands.literal("limbo")
                        .then(Commands.literal("pvp")
                                .then(Commands.literal("on")
                                        .executes(context -> setPvp(context, true)))
                                .then(Commands.literal("off")
                                        .executes(context -> setPvp(context, false))))
                        .then(Commands.literal("status")
                                .executes(DevLimboCommands::status))));
    }

    private static int setPvp(CommandContext<CommandSourceStack> context, boolean allowed) {
        CommandSourceStack source = context.getSource();
        LimboProtection.setPvpAllowed(source.getServer(), allowed);
        String key = allowed ? "dev.eclipse.limbo.pvp.on" : "dev.eclipse.limbo.pvp.off";
        source.sendSuccess(() -> ServerLang.tr(source.getPlayer(), key), false);
        audit(source, key, "set limbo pvp " + (allowed ? "on" : "off"));
        return allowed ? 1 : 0;
    }

    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerPlayer viewer = source.getPlayer();
        boolean pvpAllowed = LimboProtection.isPvpAllowed(source.getServer());
        ServerLevel limbo = source.getServer().getLevel(LimboDimension.LIMBO);
        boolean bossFight = limbo != null && LimboProtection.bossFightActive(limbo);
        source.sendSuccess(() -> ServerLang.tr(viewer, "dev.eclipse.limbo.status.header"), false);
        source.sendSuccess(() -> ServerLang.tr(viewer, "dev.eclipse.limbo.status.build"), false);
        source.sendSuccess(() -> ServerLang.tr(viewer, "dev.eclipse.limbo.status.pvp",
                onOff(pvpAllowed), onOff(bossFight)), false);
        return pvpAllowed || bossFight ? 1 : 0;
    }

    private static String onOff(boolean value) {
        return value ? "ON" : "OFF";
    }

    /**
     * Same operator-audit convention as {@code DevMode} and the other {@code /dev}
     * bridges — the feedback line is re-baked per recipient so every operator reads it
     * in their own locale.
     */
    private static void audit(CommandSourceStack source, String feedbackKey, String logDetail) {
        for (ServerPlayer operator : source.getServer().getPlayerList().getPlayers()) {
            if (operator.hasPermissions(2) && operator != source.getEntity()) {
                Component feedback = ServerLang.tr(operator, feedbackKey);
                operator.sendSystemMessage(ServerLang.tr(operator, "dev.eclipse.audit",
                        source.getTextName(), feedback));
            }
        }
        EclipseMod.LOGGER.info("[DEV AUDIT] {} {}", source.getTextName(), logDetail);
    }
}
