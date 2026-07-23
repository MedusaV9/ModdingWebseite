package dev.projecteclipse.eclipse.devtools.dev;

import java.io.IOException;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import com.mojang.authlib.GameProfile;
import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;
import com.mojang.brigadier.exceptions.DynamicCommandExceptionType;
import com.mojang.brigadier.suggestion.SuggestionProvider;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.buffs.TimedBuffApi;
import dev.projecteclipse.eclipse.xboxevent.XboxEventConfig;
import dev.projecteclipse.eclipse.xboxevent.XboxEventService;
import dev.projecteclipse.eclipse.xboxevent.XboxEventState;
import dev.projecteclipse.eclipse.xboxevent.XboxWorldInstaller;
import net.minecraft.ChatFormatting;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.commands.arguments.GameProfileArgument;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev xboxevent …} (plan §2.1 XBOX rows, P5-W9): start/stop/status, timer
 * mutation, portal placement, per-player lockout clearing, reward override and the staged
 * per-world reset. Registers its own {@code /dev} root subtree — Brigadier merges it with
 * the W1 root; {@code EclipseCommands} and {@code DevRoot} stay untouched.
 *
 * <p>Durations accept {@code 1h10m / 45m / 90s / 5m30s}; a bare number means minutes.
 * Note (W7 wiring): {@code xboxevent bake} is an offline tool now
 * ({@code tools/xboxworlds/run_all.py}) — deliberately NOT registered here.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevXboxCommands {

    private static final Pattern DURATION = Pattern.compile("^(?:(\\d+)h)?(?:(\\d+)m)?(?:(\\d+)s)?$");

    private static final DynamicCommandExceptionType ERROR_BAD_DURATION = new DynamicCommandExceptionType(
            raw -> Component.translatable("dev.eclipse.xbox.time.bad_duration", raw));

    private static final SuggestionProvider<CommandSourceStack> WORLD_SUGGESTIONS =
            (context, builder) -> SharedSuggestionProvider.suggest(XboxEventConfig.get().worlds(), builder);

    private static final SuggestionProvider<CommandSourceStack> BUFF_SUGGESTIONS =
            (context, builder) -> SharedSuggestionProvider.suggest(
                    TimedBuffApi.Holder.get().knownIds(), builder);

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("xboxevent.start", DevCategory.XBOX,
                        "/dev xboxevent start (tu1|tu12|tu14) [<minutes>]",
                        "dev.eclipse.doc.xboxevent.start", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("xboxevent.stop", DevCategory.XBOX,
                        "/dev xboxevent stop [now]",
                        "dev.eclipse.doc.xboxevent.stop", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("xboxevent.status", DevCategory.XBOX,
                        "/dev xboxevent status",
                        "dev.eclipse.doc.xboxevent.status", Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("xboxevent.time", DevCategory.XBOX,
                        "/dev xboxevent time (add|sub|set) <duration>",
                        "dev.eclipse.doc.xboxevent.time", Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("xboxevent.portal", DevCategory.XBOX,
                        "/dev xboxevent portal (here|remove)",
                        "dev.eclipse.doc.xboxevent.portal", Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("xboxevent.lockout.clear", DevCategory.XBOX,
                        "/dev xboxevent lockout clear (<player>|all)",
                        "dev.eclipse.doc.xboxevent.lockout.clear", Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("xboxevent.reward.set", DevCategory.XBOX,
                        "/dev xboxevent reward set <buffId> <minutes>",
                        "dev.eclipse.doc.xboxevent.reward.set", Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("xboxevent.reset", DevCategory.XBOX,
                        "/dev xboxevent reset <world>",
                        "dev.eclipse.doc.xboxevent.reset", Danger.DESTRUCTIVE, ClickAction.SUGGEST, 3));
    }

    private DevXboxCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("xboxevent")
                        .then(Commands.literal("start")
                                .then(Commands.argument("world", StringArgumentType.word())
                                        .suggests(WORLD_SUGGESTIONS)
                                        .executes(context -> start(context, 0))
                                        .then(Commands.argument("minutes", IntegerArgumentType.integer(1, 1440))
                                                .executes(context -> start(context,
                                                        IntegerArgumentType.getInteger(context, "minutes"))))))
                        .then(Commands.literal("stop")
                                .executes(context -> stop(context, false))
                                .then(Commands.literal("now")
                                        .executes(context -> stop(context, true))))
                        .then(Commands.literal("status")
                                .executes(DevXboxCommands::status))
                        .then(Commands.literal("time")
                                .then(timeLeaf("add", '+'))
                                .then(timeLeaf("sub", '-'))
                                .then(timeLeaf("set", '=')))
                        .then(Commands.literal("portal")
                                .then(Commands.literal("here")
                                        .executes(DevXboxCommands::portalHere))
                                .then(Commands.literal("remove")
                                        .executes(DevXboxCommands::portalRemove)))
                        .then(Commands.literal("lockout")
                                .then(Commands.literal("clear")
                                        .then(Commands.literal("all")
                                                .executes(DevXboxCommands::lockoutClearAll))
                                        .then(Commands.argument("player", GameProfileArgument.gameProfile())
                                                .executes(DevXboxCommands::lockoutClearPlayer))))
                        .then(Commands.literal("reward")
                                .then(Commands.literal("set")
                                        .then(Commands.argument("buffId", StringArgumentType.word())
                                                .suggests(BUFF_SUGGESTIONS)
                                                .then(Commands.argument("minutes", IntegerArgumentType.integer(1, 1440))
                                                        .executes(DevXboxCommands::rewardSet)))))
                        .then(Commands.literal("reset")
                                .requires(source -> source.hasPermission(3))
                                .then(Commands.argument("world", StringArgumentType.word())
                                        .suggests(WORLD_SUGGESTIONS)
                                        .executes(DevXboxCommands::reset)))));
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
        String world = StringArgumentType.getString(context, "world").toLowerCase(Locale.ROOT);
        XboxEventService.StartResult result = XboxEventService.start(
                source.getServer(), world, minutes, source.getTextName());
        if (!result.started()) {
            source.sendFailure(result.message());
            return 0;
        }
        XboxEventState state = XboxEventState.get(source.getServer());
        source.sendSuccess(() -> Component.translatable("dev.eclipse.xbox.started",
                world, minutes > 0 ? minutes : XboxEventConfig.get().defaultMinutes(),
                state.instanceId()), true);
        if (result.message() != null) {
            source.sendSuccess(() -> result.message().copy().withStyle(ChatFormatting.YELLOW), false);
        }
        return 1;
    }

    private static int stop(CommandContext<CommandSourceStack> context, boolean now) {
        CommandSourceStack source = context.getSource();
        XboxEventState state = XboxEventState.get(source.getServer());
        String world = state.worldId();
        Component error = XboxEventService.stop(source.getServer(), now);
        if (error != null) {
            source.sendFailure(error);
            return 0;
        }
        source.sendSuccess(() -> now
                ? Component.translatable("dev.eclipse.xbox.stop.now", world)
                : Component.translatable("dev.eclipse.xbox.stop.closing", world, 10), true);
        return 1;
    }

    private static int time(CommandContext<CommandSourceStack> context, char mode)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        long durationMillis = parseDurationMillis(StringArgumentType.getString(context, "duration"));
        Component feedback = XboxEventService.timeMutate(source.getServer(), mode, durationMillis);
        if (feedback == null) {
            source.sendFailure(Component.translatable("dev.eclipse.xbox.stop.idle"));
            return 0;
        }
        source.sendSuccess(() -> feedback, true);
        return 1;
    }

    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        XboxEventState state = XboxEventState.get(server);
        long now = System.currentTimeMillis();

        source.sendSuccess(() -> Component.translatable("dev.eclipse.xbox.status.header",
                state.phase().name().toLowerCase(Locale.ROOT)).withStyle(ChatFormatting.GOLD), false);
        if (state.phase() == XboxEventState.Phase.OPEN || state.phase() == XboxEventState.Phase.ANNOUNCED) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.xbox.status.world",
                    state.worldId(), XboxEventService.mmss(state.endsAtEpochMillis() - now),
                    state.instanceId()), false);
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.xbox.status.participants",
                state.participantsSnapshot().size(),
                String.join(", ", state.debugParticipantNames(server))), false);

        long lockedThisInstance = state.lockoutsSnapshot().values().stream()
                .filter(instance -> instance == state.instanceId()).count();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.xbox.status.lockouts",
                lockedThisInstance), false);

        source.sendSuccess(() -> Component.translatable("dev.eclipse.xbox.status.portal",
                state.portalPos() == null ? "-"
                        : state.portalPos().toShortString()
                                + " @ " + (state.portalDimension() == null ? "?"
                                        : state.portalDimension().location().toString())), false);

        XboxEventConfig.Values config = XboxEventConfig.get();
        String rewardBuff = state.rewardBuffIdOverride().isEmpty()
                ? config.rewardBuffId() : state.rewardBuffIdOverride();
        int rewardMinutes = state.rewardMinutesOverride() > 0
                ? state.rewardMinutesOverride() : config.rewardMinutes();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.xbox.status.reward",
                rewardBuff, rewardMinutes), false);

        StringBuilder installed = new StringBuilder();
        for (String worldId : config.worlds()) {
            if (installed.length() > 0) {
                installed.append(", ");
            }
            installed.append(worldId)
                    .append(XboxWorldInstaller.isInstalled(server, worldId) ? "✔" : "✖");
            if (XboxWorldInstaller.isResetStaged(server, worldId)) {
                installed.append(" (reset staged)");
            }
        }
        String installedText = installed.toString();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.xbox.status.worlds", installedText), false);
        return 1;
    }

    private static int portalHere(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        if (!(source.getEntity() instanceof ServerPlayer operator)) {
            source.sendFailure(Component.translatable("eclipse.xbox.leave.player_only"));
            return 0;
        }
        Component error = XboxEventService.portalHere(source.getServer(), operator);
        if (error != null) {
            source.sendFailure(error);
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.xbox.portal.placed",
                operator.blockPosition().toShortString()), true);
        return 1;
    }

    private static int portalRemove(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        Component error = XboxEventService.portalRemove(source.getServer());
        if (error != null) {
            source.sendFailure(error);
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.xbox.portal.removed"), true);
        return 1;
    }

    private static int lockoutClearAll(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        int cleared = XboxEventState.get(source.getServer()).clearAllLockouts();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.xbox.lockout.cleared_all", cleared), true);
        return cleared;
    }

    private static int lockoutClearPlayer(CommandContext<CommandSourceStack> context)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        XboxEventState state = XboxEventState.get(source.getServer());
        int cleared = 0;
        for (GameProfile profile : GameProfileArgument.getGameProfiles(context, "player")) {
            UUID uuid = profile.getId();
            if (state.clearLockout(uuid)) {
                cleared++;
                source.sendSuccess(() -> Component.translatable("dev.eclipse.xbox.lockout.cleared",
                        profile.getName()), true);
            } else {
                source.sendSuccess(() -> Component.translatable("dev.eclipse.xbox.lockout.none",
                        profile.getName()), false);
            }
        }
        return cleared;
    }

    private static int rewardSet(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        String buffId = StringArgumentType.getString(context, "buffId");
        int minutes = IntegerArgumentType.getInteger(context, "minutes");
        XboxEventState.get(source.getServer()).setRewardOverride(buffId, minutes);
        source.sendSuccess(() -> Component.translatable("dev.eclipse.xbox.reward.set", buffId, minutes), true);
        return 1;
    }

    private static int reset(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        String world = StringArgumentType.getString(context, "world").toLowerCase(Locale.ROOT);
        if (!XboxEventConfig.get().worlds().contains(world)) {
            source.sendFailure(Component.translatable("dev.eclipse.xbox.start.unknown_world",
                    world, String.join(", ", XboxEventConfig.get().worlds())));
            return 0;
        }
        XboxEventState state = XboxEventState.get(server);
        boolean activeOnWorld = (state.phase() == XboxEventState.Phase.OPEN
                || state.phase() == XboxEventState.Phase.ANNOUNCED) && state.worldId().equals(world);
        if (activeOnWorld) {
            source.sendFailure(Component.translatable("dev.eclipse.xbox.reset.active", world));
            return 0;
        }
        try {
            XboxWorldInstaller.stageReset(server, world);
        } catch (IOException e) {
            source.sendFailure(Component.literal("reset: " + e.getMessage()));
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.xbox.reset.staged", world), true);
        return 1;
    }

    // ------------------------------------------------------------------ duration parsing

    /** {@code 1h10m / 45m / 90s / 5m30s}; bare number = minutes. Public for gametests. */
    public static long parseDurationMillis(String raw) throws CommandSyntaxException {
        String normalized = raw.strip().toLowerCase(Locale.ROOT);
        if (normalized.matches("\\d+")) {
            long minutes = Long.parseLong(normalized);
            if (minutes <= 0) {
                throw ERROR_BAD_DURATION.create(raw);
            }
            return minutes * 60_000L;
        }
        Matcher matcher = DURATION.matcher(normalized);
        if (!matcher.matches()) {
            throw ERROR_BAD_DURATION.create(raw);
        }
        long hours = matcher.group(1) == null ? 0L : Long.parseLong(matcher.group(1));
        long minutes = matcher.group(2) == null ? 0L : Long.parseLong(matcher.group(2));
        long seconds = matcher.group(3) == null ? 0L : Long.parseLong(matcher.group(3));
        long millis = ((hours * 60L + minutes) * 60L + seconds) * 1000L;
        if (millis <= 0L) {
            throw ERROR_BAD_DURATION.create(raw);
        }
        return millis;
    }

    /** Test hook: exposes the lockout map filter used by {@code status}. */
    static long lockedOutCountThisInstance(XboxEventState state) {
        Map<UUID, Integer> lockouts = state.lockoutsSnapshot();
        return lockouts.values().stream().filter(instance -> instance == state.instanceId()).count();
    }
}
