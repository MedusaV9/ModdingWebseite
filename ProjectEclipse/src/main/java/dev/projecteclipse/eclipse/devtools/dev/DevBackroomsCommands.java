package dev.projecteclipse.eclipse.devtools.dev;

import java.util.Locale;
import java.util.UUID;

import com.mojang.authlib.GameProfile;
import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.backrooms.BackroomsEventService;
import dev.projecteclipse.eclipse.backrooms.BackroomsMaze;
import dev.projecteclipse.eclipse.backrooms.BackroomsState;
import net.minecraft.ChatFormatting;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.arguments.GameProfileArgument;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev backrooms …} (plans_v5 PLAN-C C18 — the {@code DevXboxCommands} shape):
 * start/stop/status, timer mutation, portal placement, per-player lockout clearing.
 * Registers its own {@code /dev} root subtree — Brigadier merges it with the W1 root.
 * Durations share {@link DevXboxCommands#parseDurationMillis} ({@code 1h10m / 45m / 90s};
 * bare number = minutes).
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevBackroomsCommands {

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("backrooms.start", DevCategory.EVENT,
                        "/dev backrooms start [<minutes>]",
                        "dev.eclipse.doc.backrooms.start", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("backrooms.stop", DevCategory.EVENT,
                        "/dev backrooms stop [now]",
                        "dev.eclipse.doc.backrooms.stop", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("backrooms.status", DevCategory.EVENT,
                        "/dev backrooms status",
                        "dev.eclipse.doc.backrooms.status", Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("backrooms.time", DevCategory.EVENT,
                        "/dev backrooms time (add|sub|set) <duration>",
                        "dev.eclipse.doc.backrooms.time", Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("backrooms.portal", DevCategory.EVENT,
                        "/dev backrooms portal (here|remove)",
                        "dev.eclipse.doc.backrooms.portal", Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("backrooms.lockout.clear", DevCategory.EVENT,
                        "/dev backrooms lockout clear (<player>|all)",
                        "dev.eclipse.doc.backrooms.lockout.clear", Danger.SAFE, ClickAction.SUGGEST, 2));
    }

    private DevBackroomsCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("backrooms")
                        .then(Commands.literal("start")
                                .executes(context -> start(context, 0))
                                .then(Commands.argument("minutes", IntegerArgumentType.integer(1, 1440))
                                        .executes(context -> start(context,
                                                IntegerArgumentType.getInteger(context, "minutes")))))
                        .then(Commands.literal("stop")
                                .executes(context -> stop(context, false))
                                .then(Commands.literal("now")
                                        .executes(context -> stop(context, true))))
                        .then(Commands.literal("status")
                                .executes(DevBackroomsCommands::status))
                        .then(Commands.literal("time")
                                .then(timeLeaf("add", '+'))
                                .then(timeLeaf("sub", '-'))
                                .then(timeLeaf("set", '=')))
                        .then(Commands.literal("portal")
                                .then(Commands.literal("here")
                                        .executes(DevBackroomsCommands::portalHere))
                                .then(Commands.literal("remove")
                                        .executes(DevBackroomsCommands::portalRemove)))
                        .then(Commands.literal("lockout")
                                .then(Commands.literal("clear")
                                        .then(Commands.literal("all")
                                                .executes(DevBackroomsCommands::lockoutClearAll))
                                        .then(Commands.argument("player", GameProfileArgument.gameProfile())
                                                .executes(DevBackroomsCommands::lockoutClearPlayer))))));
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
        BackroomsEventService.StartResult result = BackroomsEventService.start(
                source.getServer(), minutes, source.getTextName());
        if (!result.started()) {
            source.sendFailure(result.message());
            return 0;
        }
        BackroomsState state = BackroomsState.get(source.getServer());
        source.sendSuccess(() -> Component.translatable("dev.eclipse.backrooms.started",
                minutes > 0 ? minutes : BackroomsEventService.DEFAULT_MINUTES,
                state.instanceId()), true);
        return 1;
    }

    private static int stop(CommandContext<CommandSourceStack> context, boolean now) {
        CommandSourceStack source = context.getSource();
        Component error = BackroomsEventService.stop(source.getServer(), now);
        if (error != null) {
            source.sendFailure(error);
            return 0;
        }
        source.sendSuccess(() -> now
                ? Component.translatable("dev.eclipse.backrooms.stop.now")
                : Component.translatable("dev.eclipse.backrooms.stop.closing", 10), true);
        return 1;
    }

    private static int time(CommandContext<CommandSourceStack> context, char mode)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        long durationMillis = DevXboxCommands.parseDurationMillis(
                StringArgumentType.getString(context, "duration"));
        Component feedback = BackroomsEventService.timeMutate(source.getServer(), mode, durationMillis);
        if (feedback == null) {
            source.sendFailure(Component.translatable("dev.eclipse.backrooms.stop.idle"));
            return 0;
        }
        source.sendSuccess(() -> feedback, true);
        return 1;
    }

    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        BackroomsState state = BackroomsState.get(source.getServer());
        long now = System.currentTimeMillis();

        source.sendSuccess(() -> Component.translatable("dev.eclipse.backrooms.status.header",
                state.phase().name().toLowerCase(Locale.ROOT)).withStyle(ChatFormatting.GOLD), false);
        if (state.phase() == BackroomsState.Phase.OPEN
                || state.phase() == BackroomsState.Phase.ANNOUNCED) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.backrooms.status.window",
                    BackroomsEventService.mmss(state.endsAtEpochMillis() - now),
                    state.instanceId()), false);
            source.sendSuccess(() -> Component.translatable("dev.eclipse.backrooms.status.stamp",
                    state.stampCursor(), BackroomsMaze.totalStampUnits()), false);
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.backrooms.status.participants",
                state.participantsSnapshot().size()), false);
        source.sendSuccess(() -> Component.translatable("dev.eclipse.backrooms.status.lockouts",
                state.lockedOutCountThisInstance()), false);
        source.sendSuccess(() -> Component.translatable("dev.eclipse.backrooms.status.portal",
                state.portalPos() == null ? "-"
                        : state.portalPos().toShortString()
                                + " @ " + (state.portalDimension() == null ? "?"
                                        : state.portalDimension().location().toString()),
                state.exitPortalPos() == null ? "-" : state.exitPortalPos().toShortString()), false);
        return 1;
    }

    private static int portalHere(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        if (!(source.getEntity() instanceof ServerPlayer operator)) {
            source.sendFailure(Component.translatable("eclipse.backrooms.leave.player_only"));
            return 0;
        }
        Component error = BackroomsEventService.portalHere(source.getServer(), operator);
        if (error != null) {
            source.sendFailure(error);
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.backrooms.portal.placed",
                operator.blockPosition().toShortString()), true);
        return 1;
    }

    private static int portalRemove(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        Component error = BackroomsEventService.portalRemove(source.getServer());
        if (error != null) {
            source.sendFailure(error);
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.backrooms.portal.removed"), true);
        return 1;
    }

    private static int lockoutClearAll(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        int cleared = BackroomsState.get(source.getServer()).clearAllLockouts();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.backrooms.lockout.cleared_all",
                cleared), true);
        return cleared;
    }

    private static int lockoutClearPlayer(CommandContext<CommandSourceStack> context)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        BackroomsState state = BackroomsState.get(source.getServer());
        int cleared = 0;
        for (GameProfile profile : GameProfileArgument.getGameProfiles(context, "player")) {
            UUID uuid = profile.getId();
            if (state.clearLockout(uuid)) {
                cleared++;
                source.sendSuccess(() -> Component.translatable("dev.eclipse.backrooms.lockout.cleared",
                        profile.getName()), true);
            } else {
                source.sendSuccess(() -> Component.translatable("dev.eclipse.backrooms.lockout.none",
                        profile.getName()), false);
            }
        }
        return cleared;
    }
}
