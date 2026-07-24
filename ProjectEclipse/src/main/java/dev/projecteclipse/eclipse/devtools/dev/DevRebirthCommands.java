package dev.projecteclipse.eclipse.devtools.dev;

import java.util.Map;
import java.util.UUID;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.rebirth.RebirthApi;
import dev.projecteclipse.eclipse.rebirth.RebirthService;
import dev.projecteclipse.eclipse.rebirth.RebirthState;
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
 * D11 dev bridge: {@code /dev rebirth <player> [count]} performs {@code count} (default 1)
 * FREE forced ceremonies — no shard cost, but the Leben cap and event-dimension refusals
 * still apply (a forced rebirth must never silently burn the reward either).
 * {@code /dev rebirth status} dumps every persisted rebirth entry with next cost and the
 * resulting level-cost multiplier.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevRebirthCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("rebirth.force", DevCategory.PLAYERS,
                        "/dev rebirth <player> [count]",
                        "dev.eclipse.doc.rebirth.force", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("rebirth.status", DevCategory.PLAYERS, "/dev rebirth status",
                        "dev.eclipse.doc.rebirth.status", Danger.SAFE, ClickAction.RUN, 2));
    }

    private DevRebirthCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("rebirth")
                        .then(Commands.literal("status").executes(DevRebirthCommands::status))
                        .then(Commands.argument("player", EntityArgument.player())
                                .executes(context -> force(context, 1))
                                .then(Commands.argument("count", IntegerArgumentType.integer(1, 32))
                                        .executes(context -> force(context,
                                                IntegerArgumentType.getInteger(context, "count")))))));
    }

    private static int force(CommandContext<CommandSourceStack> context, int count)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer target = EntityArgument.getPlayer(context, "player");
        int done = 0;
        RebirthApi.Result lastRefusal = null;
        for (int i = 0; i < count; i++) {
            RebirthApi.Result result = RebirthService.forceRebirth(target);
            if (result != RebirthApi.Result.OK) {
                lastRefusal = result;
                break;
            }
            done++;
        }
        if (done == 0) {
            source.sendFailure(Component.translatable("dev.eclipse.rebirth.force.refused",
                    target.getDisplayName(), String.valueOf(lastRefusal)));
            return 0;
        }
        Component feedback = Component.translatable("dev.eclipse.rebirth.force.ok",
                target.getDisplayName(), done,
                RebirthApi.count(source.getServer(), target.getUUID()));
        audit(source, feedback, "forced " + done + " rebirth(s) on " + target.getScoreboardName()
                + (lastRefusal != null ? " (then refused: " + lastRefusal + ")" : ""));
        return done;
    }

    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        Map<UUID, RebirthState.Entry> entries = RebirthState.get(server).entries();
        if (entries.isEmpty()) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.rebirth.status.empty"), false);
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.rebirth.status.header",
                entries.size()), false);
        int shown = 0;
        for (Map.Entry<UUID, RebirthState.Entry> entry : entries.entrySet()) {
            UUID uuid = entry.getKey();
            ServerPlayer online = server.getPlayerList().getPlayer(uuid);
            String name = online != null ? online.getScoreboardName() : uuid.toString();
            source.sendSuccess(() -> Component.translatable("dev.eclipse.rebirth.status.entry",
                    name,
                    entry.getValue().count,
                    RebirthApi.costForNext(server, uuid),
                    String.format(java.util.Locale.ROOT, "%.3f",
                            RebirthApi.levelCostMultiplier(server, uuid))), false);
            shown++;
        }
        return shown;
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
