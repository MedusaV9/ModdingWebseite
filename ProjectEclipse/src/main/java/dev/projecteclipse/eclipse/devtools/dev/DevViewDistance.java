package dev.projecteclipse.eclipse.devtools.dev;

import java.util.Collection;
import java.util.Map;
import java.util.UUID;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.ViewDistanceService;
import dev.projecteclipse.eclipse.network.fx.S2CViewDistancePayload;
import net.minecraft.ChatFormatting;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.arguments.EntityArgument;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Persistent per-player layer over P2's transient view-distance payload. Cinematic sessions
 * take precedence; their falling edge re-applies every saved pin instead of leaving clients
 * at the vanilla setting. The client-side opt-out remains authoritative.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevViewDistance {
    private static boolean transientWasActive;

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("viewdist.pin", DevCategory.PLAYERS,
                        "/dev viewdist pin <player|@a> <chunks>",
                        "dev.eclipse.doc.viewdist.pin", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("viewdist.unpin", DevCategory.PLAYERS,
                        "/dev viewdist unpin <player|@a>",
                        "dev.eclipse.doc.viewdist.unpin", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("viewdist.status", DevCategory.PLAYERS,
                        "/dev viewdist status [player|@a]",
                        "dev.eclipse.doc.viewdist.status", Danger.SAFE, ClickAction.SUGGEST, 2));
    }

    private DevViewDistance() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("viewdist")
                        .then(Commands.literal("pin")
                                .then(Commands.argument("targets", EntityArgument.players())
                                        .then(Commands.argument("chunks",
                                                        IntegerArgumentType.integer(2, 32))
                                                .executes(DevViewDistance::pin))))
                        .then(Commands.literal("unpin")
                                .then(Commands.argument("targets", EntityArgument.players())
                                        .executes(DevViewDistance::unpin)))
                        .then(Commands.literal("status")
                                .executes(context -> status(context, null))
                                .then(Commands.argument("targets", EntityArgument.players())
                                        .executes(context -> status(context,
                                                EntityArgument.getPlayers(context, "targets")))))));
    }

    private static int pin(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        Collection<ServerPlayer> targets = EntityArgument.getPlayers(context, "targets");
        int chunks = IntegerArgumentType.getInteger(context, "chunks");
        DevViewDistanceData data = DevViewDistanceData.get(server);
        for (ServerPlayer target : targets) {
            data.setPin(target.getUUID(), chunks);
            if (!ViewDistanceService.isActive()) {
                sendPin(target, chunks);
            }
        }
        Component feedback = Component.translatable("dev.eclipse.viewdist.pin.ok",
                chunks, targets.size());
        audit(source, feedback, "pinned " + targets.size() + " player(s) to " + chunks + " chunks");
        warnServerFloor(source, chunks);
        if (ViewDistanceService.isActive()) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.viewdist.deferred")
                    .withStyle(ChatFormatting.YELLOW), false);
        }
        return targets.size();
    }

    private static int unpin(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        Collection<ServerPlayer> targets = EntityArgument.getPlayers(context, "targets");
        DevViewDistanceData data = DevViewDistanceData.get(source.getServer());
        int removed = 0;
        for (ServerPlayer target : targets) {
            if (data.removePin(target.getUUID())) {
                removed++;
                if (!ViewDistanceService.isActive()) {
                    PacketDistributor.sendToPlayer(target, new S2CViewDistancePayload(0));
                }
            }
        }
        if (removed == 0) {
            source.sendFailure(Component.translatable("dev.eclipse.viewdist.unpin.none"));
            return 0;
        }
        Component feedback = Component.translatable("dev.eclipse.viewdist.unpin.ok", removed);
        audit(source, feedback, "removed " + removed + " view-distance pin(s)");
        return removed;
    }

    private static int status(CommandContext<CommandSourceStack> context,
            Collection<ServerPlayer> selected) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        Map<UUID, Integer> pins = DevViewDistanceData.get(server).pinsSnapshot();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.viewdist.status.header",
                pins.size(), server.getPlayerList().getViewDistance(),
                Component.translatable(ViewDistanceService.isActive()
                        ? "dev.eclipse.yes" : "dev.eclipse.no")), false);
        if (selected != null) {
            for (ServerPlayer player : selected) {
                int chunks = pins.getOrDefault(player.getUUID(), 0);
                source.sendSuccess(() -> Component.translatable("dev.eclipse.viewdist.status.entry",
                        player.getScoreboardName(), chunks == 0 ? "-" : Integer.toString(chunks)), false);
            }
            return selected.size();
        }
        for (Map.Entry<UUID, Integer> entry : pins.entrySet()) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.viewdist.status.entry",
                    describe(server, entry.getKey()), entry.getValue()), false);
        }
        return pins.size();
    }

    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player) || ViewDistanceService.isActive()) {
            return;
        }
        int chunks = DevViewDistanceData.get(player.server).pin(player.getUUID());
        if (chunks > 0) {
            sendPin(player, chunks);
        }
    }

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        transientWasActive = ViewDistanceService.isActive();
        if (!transientWasActive) {
            reapplyPins(event.getServer());
        }
    }

    /**
     * P2 exposes no session-end callback. Observing the public active flag gives the same
     * precedence without touching cutscene-owned code.
     */
    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        boolean active = ViewDistanceService.isActive();
        if (transientWasActive && !active) {
            reapplyPins(event.getServer());
        }
        transientWasActive = active;
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        transientWasActive = false;
    }

    private static void reapplyPins(MinecraftServer server) {
        DevViewDistanceData data = DevViewDistanceData.get(server);
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            int chunks = data.pin(player.getUUID());
            if (chunks > 0) {
                sendPin(player, chunks);
            }
        }
    }

    private static void sendPin(ServerPlayer player, int chunks) {
        PacketDistributor.sendToPlayer(player, new S2CViewDistancePayload(chunks));
    }

    private static void warnServerFloor(CommandSourceStack source, int requested) {
        int serverDistance = source.getServer().getPlayerList().getViewDistance();
        if (serverDistance < requested) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.viewdist.server_floor",
                    serverDistance, requested).withStyle(ChatFormatting.YELLOW), false);
        }
    }

    private static String describe(MinecraftServer server, UUID uuid) {
        ServerPlayer online = server.getPlayerList().getPlayer(uuid);
        if (online != null) {
            return online.getScoreboardName();
        }
        if (server.getProfileCache() != null) {
            var cached = server.getProfileCache().get(uuid);
            if (cached.isPresent()) {
                return cached.get().getName();
            }
        }
        return uuid.toString();
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
