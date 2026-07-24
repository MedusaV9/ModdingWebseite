package dev.projecteclipse.eclipse.devtools.dev;

import java.util.Locale;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;
import com.mojang.brigadier.suggestion.SuggestionProvider;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.minigames.MinigameDimensions;
import dev.projecteclipse.eclipse.minigames.MinigameService;
import dev.projecteclipse.eclipse.minigames.MinigameState;
import net.minecraft.ChatFormatting;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev minigame …} (W4-MINIGAMES, the {@code DevXboxCommands} pattern):
 * start/stop/status, timer mutation and portal placement for the portal minigame events.
 * Registers its own {@code /dev} root subtree — Brigadier merges it with the W1 root;
 * {@code EclipseCommands} and {@code DevRoot} stay untouched.
 *
 * <p>Durations accept {@code 1h10m / 45m / 90s / 5m30s}; a bare number means minutes
 * (parsing reuses {@link DevXboxCommands#parseDurationMillis}).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevMinigameCommands {

    private static final SuggestionProvider<CommandSourceStack> GAME_SUGGESTIONS =
            (context, builder) -> SharedSuggestionProvider.suggest(
                    MinigameDimensions.gameIds(), builder);

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("minigame.start", DevCategory.EVENT,
                        "/dev minigame start (arena|race) [<minutes>]",
                        "dev.eclipse.doc.minigame.start", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("minigame.stop", DevCategory.EVENT,
                        "/dev minigame stop [now]",
                        "dev.eclipse.doc.minigame.stop", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("minigame.status", DevCategory.EVENT,
                        "/dev minigame status",
                        "dev.eclipse.doc.minigame.status", Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("minigame.time", DevCategory.EVENT,
                        "/dev minigame time (add|sub|set) <duration>",
                        "dev.eclipse.doc.minigame.time", Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("minigame.portal", DevCategory.EVENT,
                        "/dev minigame portal (here|remove)",
                        "dev.eclipse.doc.minigame.portal", Danger.SAFE, ClickAction.SUGGEST, 2));
    }

    private DevMinigameCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("minigame")
                        .then(Commands.literal("start")
                                .then(Commands.argument("game", StringArgumentType.word())
                                        .suggests(GAME_SUGGESTIONS)
                                        .executes(context -> start(context, 0))
                                        .then(Commands.argument("minutes", IntegerArgumentType.integer(1, 1440))
                                                .executes(context -> start(context,
                                                        IntegerArgumentType.getInteger(context, "minutes"))))))
                        .then(Commands.literal("stop")
                                .executes(context -> stop(context, false))
                                .then(Commands.literal("now")
                                        .executes(context -> stop(context, true))))
                        .then(Commands.literal("status")
                                .executes(DevMinigameCommands::status))
                        .then(Commands.literal("time")
                                .then(timeLeaf("add", '+'))
                                .then(timeLeaf("sub", '-'))
                                .then(timeLeaf("set", '=')))
                        .then(Commands.literal("portal")
                                .then(Commands.literal("here")
                                        .executes(DevMinigameCommands::portalHere))
                                .then(Commands.literal("remove")
                                        .executes(DevMinigameCommands::portalRemove)))));
    }

    private static com.mojang.brigadier.builder.LiteralArgumentBuilder<CommandSourceStack> timeLeaf(
            String literal, char mode) {
        return Commands.literal(literal)
                .then(Commands.argument("duration", StringArgumentType.word())
                        .executes(context -> time(context, mode)));
    }

    // ------------------------------------------------------------------ handlers

    private static int start(CommandContext<CommandSourceStack> context, int minutes) {
        CommandSourceStack source = context.getSource();
        String game = StringArgumentType.getString(context, "game").toLowerCase(Locale.ROOT);
        MinigameService.StartResult result = MinigameService.start(
                source.getServer(), game, minutes, source.getTextName());
        if (!result.started()) {
            source.sendFailure(result.message());
            return 0;
        }
        MinigameState state = MinigameState.get(source.getServer());
        int effectiveMinutes = minutes > 0 ? minutes
                : dev.projecteclipse.eclipse.minigames.MinigameConfig.get().defaultMinutes();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.minigame.started",
                game, effectiveMinutes, state.openCount()), true);
        if (result.message() != null) {
            source.sendSuccess(() -> result.message().copy().withStyle(ChatFormatting.YELLOW), false);
        }
        return 1;
    }

    private static int stop(CommandContext<CommandSourceStack> context, boolean now) {
        CommandSourceStack source = context.getSource();
        MinigameState state = MinigameState.get(source.getServer());
        String game = state.gameId();
        Component error = MinigameService.stop(source.getServer(), now);
        if (error != null) {
            source.sendFailure(error);
            return 0;
        }
        source.sendSuccess(() -> now
                ? Component.translatable("dev.eclipse.minigame.stop.now", game)
                : Component.translatable("dev.eclipse.minigame.stop.closing", game, 10), true);
        return 1;
    }

    private static int time(CommandContext<CommandSourceStack> context, char mode)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        long durationMillis = DevXboxCommands.parseDurationMillis(
                StringArgumentType.getString(context, "duration"));
        Component feedback = MinigameService.timeMutate(source.getServer(), mode, durationMillis);
        if (feedback == null) {
            source.sendFailure(Component.translatable("dev.eclipse.minigame.stop.idle"));
            return 0;
        }
        source.sendSuccess(() -> feedback, true);
        return 1;
    }

    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        MinigameState state = MinigameState.get(server);
        long now = System.currentTimeMillis();

        source.sendSuccess(() -> Component.translatable("dev.eclipse.minigame.status.header",
                state.phase().name().toLowerCase(Locale.ROOT)).withStyle(ChatFormatting.GOLD), false);
        if (state.isActive()) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.minigame.status.game",
                    state.gameId(), MinigameService.mmss(state.endsAtEpochMillis() - now),
                    state.openCount()), false);
            source.sendSuccess(() -> Component.translatable("dev.eclipse.minigame.status.course",
                    MinigameService.isCourseReady() ? "ready" : "building"), false);
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.minigame.status.participants",
                state.participantsSnapshot().size(),
                String.join(", ", state.debugParticipantNames(server))), false);
        source.sendSuccess(() -> Component.translatable("dev.eclipse.minigame.status.tickets",
                state.ticketsSnapshot().size()), false);
        source.sendSuccess(() -> Component.translatable("dev.eclipse.minigame.status.portal",
                state.portalPos() == null ? "-"
                        : state.portalPos().toShortString()
                                + " @ " + (state.portalDimension() == null ? "?"
                                        : state.portalDimension().location().toString())), false);
        return 1;
    }

    private static int portalHere(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        if (!(source.getEntity() instanceof ServerPlayer operator)) {
            source.sendFailure(Component.translatable("eclipse.minigame.leave.player_only"));
            return 0;
        }
        Component error = MinigameService.portalHere(source.getServer(), operator);
        if (error != null) {
            source.sendFailure(error);
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.minigame.portal.placed",
                operator.blockPosition().toShortString()), true);
        return 1;
    }

    private static int portalRemove(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        Component error = MinigameService.portalRemove(source.getServer());
        if (error != null) {
            source.sendFailure(error);
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.minigame.portal.removed"), true);
        return 1;
    }
}
