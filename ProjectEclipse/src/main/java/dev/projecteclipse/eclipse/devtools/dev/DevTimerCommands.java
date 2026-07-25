package dev.projecteclipse.eclipse.devtools.dev;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.time.EclipseClock;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeConfig;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeDayApi;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeDayService;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeMath;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeState;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * Operator-facing bridge for the real-time day clock. Every mutation goes through
 * {@link RealtimeDayApi}; that API broadcasts {@code S2CDayClockPayload} on every successful
 * state change, which is what drives the client spool animation.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevTimerCommands {
    /** Named {@code /dev timer color} modes; anything else must be a {@code #rgb}/{@code #rrggbb} literal. */
    private static final String[] COLOR_PRESETS = { "auto", "text", "accent", "deep" };

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("timer.pause", DevCategory.TIMER, "/dev timer pause",
                        "dev.eclipse.doc.timer.pause", Danger.CAUTION, ClickAction.RUN, 2),
                new DevCommandDoc("timer.resume", DevCategory.TIMER, "/dev timer resume",
                        "dev.eclipse.doc.timer.resume", Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("timer.add", DevCategory.TIMER, "/dev timer add <duration>",
                        "dev.eclipse.doc.timer.add", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("timer.sub", DevCategory.TIMER, "/dev timer sub <duration>",
                        "dev.eclipse.doc.timer.sub", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("timer.set", DevCategory.TIMER, "/dev timer set <time>",
                        "dev.eclipse.doc.timer.set", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("timer.color", DevCategory.TIMER, "/dev timer color <mode>",
                        "dev.eclipse.doc.timer.color", Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("timer.status", DevCategory.TIMER, "/dev timer status",
                        "dev.eclipse.doc.timer.status", Danger.SAFE, ClickAction.RUN, 2));
    }

    private DevTimerCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("timer")
                        .then(Commands.literal("pause").executes(DevTimerCommands::pause))
                        .then(Commands.literal("resume").executes(DevTimerCommands::resume))
                        .then(Commands.literal("add")
                                .then(Commands.argument("duration", StringArgumentType.word())
                                        .executes(context -> shift(context, false))))
                        .then(Commands.literal("sub")
                                .then(Commands.argument("duration", StringArgumentType.word())
                                        .executes(context -> shift(context, true))))
                        .then(Commands.literal("set")
                                .then(Commands.argument("time", StringArgumentType.greedyString())
                                        .executes(DevTimerCommands::set)))
                        .then(Commands.literal("color")
                                .then(Commands.argument("mode", StringArgumentType.word())
                                        .suggests((context, builder) -> {
                                            for (String preset : COLOR_PRESETS) {
                                                builder.suggest(preset);
                                            }
                                            return builder.buildFuture();
                                        })
                                        .executes(DevTimerCommands::color)))
                        .then(Commands.literal("status").executes(DevTimerCommands::status))));
    }

    private static int pause(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        long remaining = RealtimeDayApi.pause(source.getServer());
        if (remaining < 0L) {
            source.sendFailure(Component.translatable("dev.eclipse.timer.pause.failed"));
            return 0;
        }
        Component feedback = Component.translatable("dev.eclipse.timer.pause.ok",
                RealtimeMath.remainingText(remaining));
        audit(source, feedback, "paused timer; remaining=" + remaining + "ms");
        return 1;
    }

    private static int resume(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        long boundary = RealtimeDayApi.resume(source.getServer());
        if (boundary < 0L) {
            source.sendFailure(Component.translatable("dev.eclipse.timer.resume.failed"));
            return 0;
        }
        ZoneId zone = RealtimeConfig.get().zone();
        long remaining = boundary - EclipseClock.epochMillis();
        Component feedback = Component.translatable("dev.eclipse.timer.resume.ok",
                RealtimeDayService.formatInstant(boundary, zone), zone.getId(),
                RealtimeMath.remainingText(remaining));
        audit(source, feedback, "resumed timer; boundary=" + boundary);
        return 1;
    }

    private static int shift(CommandContext<CommandSourceStack> context, boolean subtract) {
        CommandSourceStack source = context.getSource();
        String raw = StringArgumentType.getString(context, "duration").trim();
        long magnitude;
        try {
            if (raw.startsWith("+") || raw.startsWith("-")) {
                throw new IllegalArgumentException("duration must not include a sign");
            }
            magnitude = RealtimeMath.parseSignedOffsetMillis("+" + raw);
            if (magnitude <= 0L || magnitude > 365L * 24L * 60L * 60L * 1000L) {
                throw new IllegalArgumentException("duration outside safe range");
            }
        } catch (IllegalArgumentException e) {
            source.sendFailure(Component.translatable("dev.eclipse.timer.duration.invalid", raw));
            return 0;
        }
        long delta = subtract ? -magnitude : magnitude;
        long remaining = RealtimeDayApi.addMillis(source.getServer(), delta);
        if (remaining < 0L) {
            source.sendFailure(Component.translatable("dev.eclipse.timer.shift.disarmed"));
            return 0;
        }
        Component feedback = Component.translatable(subtract
                        ? "dev.eclipse.timer.sub.ok" : "dev.eclipse.timer.add.ok",
                raw, RealtimeMath.remainingText(remaining));
        audit(source, feedback, (subtract ? "subtracted " : "added ") + magnitude + "ms");
        return 1;
    }

    private static int set(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        String raw = StringArgumentType.getString(context, "time").trim();
        ZoneId zone = RealtimeConfig.get().zone();
        String normalized;
        try {
            normalized = normalizeBoundarySpec(raw, zone);
        } catch (RuntimeException e) {
            source.sendFailure(Component.translatable("dev.eclipse.timer.time.invalid", raw));
            return 0;
        }

        long target;
        try {
            target = RealtimeDayApi.setBoundary(source.getServer(), normalized, zone);
        } catch (IllegalArgumentException e) {
            source.sendFailure(Component.translatable("dev.eclipse.timer.set.failed", e.getMessage()));
            return 0;
        }
        Component feedback = Component.translatable("dev.eclipse.timer.set.ok",
                RealtimeDayService.formatInstant(target, zone), zone.getId(),
                RealtimeMath.remainingText(target - EclipseClock.epochMillis()));
        audit(source, feedback, "set timer boundary=" + target + " from '" + raw + "'");
        return 1;
    }

    /**
     * Adds the friendly command forms missing from the frozen API parser: {@code HH:mm} means
     * the next occurrence in the configured zone, and a space in an ISO local date-time is
     * accepted in addition to the canonical {@code T}.
     */
    private static String normalizeBoundarySpec(String raw, ZoneId zone) {
        if (raw.startsWith("+")) {
            return raw;
        }
        if (raw.matches("\\d{2}:\\d{2}(?::\\d{2})?")) {
            LocalTime time = LocalTime.parse(raw);
            long nowMillis = EclipseClock.epochMillis();
            ZonedDateTime now = Instant.ofEpochMilli(nowMillis).atZone(zone);
            ZonedDateTime target = ZonedDateTime.of(now.toLocalDate(), time, zone);
            if (!target.toInstant().isAfter(now.toInstant())) {
                target = ZonedDateTime.of(now.toLocalDate().plusDays(1), time, zone);
            }
            return target.toLocalDateTime().toString();
        }
        String normalized = raw.replaceFirst("^(\\d{4}-\\d{2}-\\d{2})\\s+", "$1T");
        LocalDateTime.parse(normalized);
        return normalized;
    }

    /**
     * {@code /dev timer color <auto|text|accent|deep|#hex>}: persists the day-timer display
     * color mode in {@link RealtimeState} and re-broadcasts the clock payload (the existing
     * dev-payload sync path) so every client's {@code DayTimerLayer} applies it instantly.
     * {@code auto} restores the default urgency ramp.
     */
    private static int color(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        String raw = StringArgumentType.getString(context, "mode").trim().toLowerCase(java.util.Locale.ROOT);
        boolean preset = false;
        for (String candidate : COLOR_PRESETS) {
            if (candidate.equals(raw)) {
                preset = true;
                break;
            }
        }
        if (!preset && !raw.matches("#([0-9a-f]{3}|[0-9a-f]{6})")) {
            source.sendFailure(Component.translatable("dev.eclipse.timer.color.invalid", raw));
            return 0;
        }
        RealtimeState.get(source.getServer()).setTimerColorMode(raw);
        RealtimeDayService.broadcastClock(source.getServer());
        Component feedback = Component.translatable("dev.eclipse.timer.color.ok", raw);
        audit(source, feedback, "set timer color mode=" + raw);
        return 1;
    }

    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        RealtimeState state = RealtimeState.get(server);
        RealtimeConfig.Config config = RealtimeConfig.get();
        int day = DayScheduler.getDay(server);
        Component mode = Component.translatable(!state.isArmed()
                ? "dev.eclipse.timer.mode.disarmed"
                : state.isPaused() ? "dev.eclipse.timer.mode.paused" : "dev.eclipse.timer.mode.running");

        source.sendSuccess(() -> Component.translatable("dev.eclipse.timer.status.header",
                mode, day, EclipseConfig.maxDay()), false);
        source.sendSuccess(() -> Component.translatable("dev.eclipse.timer.status.zone",
                config.zone().getId(), config.boundaryTime().toString()), false);
        if (state.isArmed()) {
            long remaining = state.isPaused() ? state.getPauseRemainingMillis()
                    : Math.max(0L, state.getBoundaryEpochMillis() - EclipseClock.epochMillis());
            long shownBoundary = state.isPaused()
                    ? EclipseClock.epochMillis() + remaining : state.getBoundaryEpochMillis();
            source.sendSuccess(() -> Component.translatable("dev.eclipse.timer.status.boundary",
                    RealtimeDayService.formatInstant(shownBoundary, config.zone()),
                    RealtimeMath.remainingText(remaining)), false);
            source.sendSuccess(() -> Component.translatable("dev.eclipse.timer.status.flags",
                    yesNo(state.isManualOverride()), yesNo(state.isPaused())), false);
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.timer.status.catchup",
                config.catchUpMaxDays(), config.clientSyncSeconds()), false);
        return state.isArmed() ? 1 : 0;
    }

    private static Component yesNo(boolean value) {
        return Component.translatable(value ? "dev.eclipse.yes" : "dev.eclipse.no");
    }

    /** Server INFO audit plus explicit operator-only broadcast. */
    private static void audit(CommandSourceStack source, Component feedback, String logDetail) {
        source.sendSuccess(() -> feedback, false);
        for (ServerPlayer operator : source.getServer().getPlayerList().getPlayers()) {
            if (operator.hasPermissions(2) && operator != source.getEntity()) {
                operator.sendSystemMessage(ServerLang.tr(operator, "dev.eclipse.audit",
                        source.getTextName(), feedback));
            }
        }
        EclipseMod.LOGGER.info("[DEV AUDIT] {} {}", source.getTextName(), logDetail);
    }
}
