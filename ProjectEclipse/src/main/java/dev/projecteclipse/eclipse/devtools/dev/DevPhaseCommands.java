package dev.projecteclipse.eclipse.devtools.dev;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.DoubleArgumentType;
import com.mojang.brigadier.arguments.IntegerArgumentType;
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
 * D6 operator surface for the day/phase cadence. "Phase" IS the real-time day boundary
 * chain in {@link RealtimeDayService} — these commands answer "make it 2 hours instead
 * of 4" with one persisted knob instead of hand-re-armed one-shots:
 *
 * <ul>
 *   <li>{@code /dev phase status} — mode, event day, next boundary, remaining.</li>
 *   <li>{@code /dev phase interval hours <n>} / {@code minutes <n>} — switch to the
 *       recurring interval cadence, persisted in {@code realtime.json}.</li>
 *   <li>{@code /dev phase daily} — back to the once-per-real-day {@code boundaryTime}
 *       cadence (also persisted).</li>
 *   <li>{@code /dev phase next} — skip to the next phase right now (full rollover:
 *       signals, bell, announcements; the clock re-anchors on the active cadence).</li>
 * </ul>
 *
 * <p>Cadence changes are announced to all online OPs (audit broadcast), matching the
 * {@link DevTimerCommands} convention.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevPhaseCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("phase.status", DevCategory.EVENT, "/dev phase status",
                        "dev.eclipse.doc.phase.status", Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("phase.interval", DevCategory.EVENT,
                        "/dev phase interval <hours|minutes> <n>",
                        "dev.eclipse.doc.phase.interval", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("phase.daily", DevCategory.EVENT, "/dev phase daily",
                        "dev.eclipse.doc.phase.daily", Danger.CAUTION, ClickAction.RUN, 2),
                new DevCommandDoc("phase.next", DevCategory.EVENT, "/dev phase next",
                        "dev.eclipse.doc.phase.next", Danger.CAUTION, ClickAction.RUN, 2));
    }

    private DevPhaseCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("phase")
                        .then(Commands.literal("status").executes(DevPhaseCommands::status))
                        .then(Commands.literal("interval")
                                .then(Commands.literal("hours")
                                        .then(Commands.argument("n", DoubleArgumentType.doubleArg(0.002, 168.0))
                                                .executes(context -> setInterval(context,
                                                        DoubleArgumentType.getDouble(context, "n")))))
                                .then(Commands.literal("minutes")
                                        .then(Commands.argument("n", IntegerArgumentType.integer(1, 10_080))
                                                .executes(context -> setInterval(context,
                                                        IntegerArgumentType.getInteger(context, "n") / 60.0)))))
                        .then(Commands.literal("daily").executes(DevPhaseCommands::setDaily))
                        .then(Commands.literal("next").executes(DevPhaseCommands::next))));
    }

    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        RealtimeState state = RealtimeState.get(server);
        RealtimeConfig.Config cfg = RealtimeConfig.get();
        int day = DayScheduler.getDay(server);

        source.sendSuccess(() -> Component.translatable("dev.eclipse.phase.status.header",
                modeText(cfg), day, EclipseConfig.maxDay()), false);
        if (!state.isArmed()) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.phase.status.disarmed"), false);
            return 0;
        }
        if (state.isPaused()) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.phase.status.paused",
                    RealtimeMath.remainingText(state.getPauseRemainingMillis())), false);
            return 1;
        }
        long remaining = Math.max(0L, state.getBoundaryEpochMillis() - EclipseClock.epochMillis());
        source.sendSuccess(() -> Component.translatable("dev.eclipse.phase.status.boundary",
                RealtimeDayService.formatInstant(state.getBoundaryEpochMillis(), cfg.zone()),
                cfg.zone().getId(), RealtimeMath.remainingText(remaining)), false);
        if (state.isManualOverride()) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.phase.status.oneshot"), false);
        }
        return 1;
    }

    private static int setInterval(CommandContext<CommandSourceStack> context, double hours) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        RealtimeConfig.Config cfg = RealtimeDayService.applyCadence(server,
                RealtimeConfig.CadenceMode.INTERVAL, hours);
        if (!RealtimeDayApi.isArmed(server)) {
            RealtimeDayApi.arm(server);
        }
        Component feedback = Component.translatable("dev.eclipse.phase.interval.ok",
                RealtimeMath.remainingText(cfg.intervalMillis()));
        audit(source, feedback, "set phase cadence interval=" + cfg.intervalHours() + "h");
        return 1;
    }

    private static int setDaily(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        RealtimeConfig.Config cfg = RealtimeDayService.applyCadence(server,
                RealtimeConfig.CadenceMode.DAILY, RealtimeConfig.get().intervalHours());
        Component feedback = Component.translatable("dev.eclipse.phase.daily.ok",
                cfg.boundaryTime().toString(), cfg.zone().getId());
        audit(source, feedback, "set phase cadence daily@" + cfg.boundaryTime());
        return 1;
    }

    private static int next(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        int newDay = RealtimeDayService.advancePhaseNow(server);
        if (newDay < 0) {
            source.sendFailure(Component.translatable("dev.eclipse.phase.next.final",
                    DayScheduler.getDay(server)));
            return 0;
        }
        RealtimeState state = RealtimeState.get(server);
        RealtimeConfig.Config cfg = RealtimeConfig.get();
        Component feedback = state.isArmed() && state.getBoundaryEpochMillis() > 0L
                ? Component.translatable("dev.eclipse.phase.next.ok",
                        newDay, EclipseConfig.maxDay(),
                        RealtimeDayService.formatInstant(state.getBoundaryEpochMillis(), cfg.zone()))
                : Component.translatable("dev.eclipse.phase.next.ok_disarmed",
                        newDay, EclipseConfig.maxDay());
        audit(source, feedback, "skipped to next phase; day=" + newDay);
        return 1;
    }

    private static Component modeText(RealtimeConfig.Config cfg) {
        return cfg.cadenceMode() == RealtimeConfig.CadenceMode.INTERVAL
                ? Component.translatable("dev.eclipse.phase.mode.interval",
                        RealtimeMath.remainingText(cfg.intervalMillis()))
                : Component.translatable("dev.eclipse.phase.mode.daily",
                        cfg.boundaryTime().toString(), cfg.zone().getId());
    }

    /** Server INFO audit plus explicit operator-only broadcast (DevTimerCommands pattern). */
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
