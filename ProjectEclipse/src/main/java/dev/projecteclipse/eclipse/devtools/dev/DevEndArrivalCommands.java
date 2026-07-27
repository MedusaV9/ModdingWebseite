package dev.projecteclipse.eclipse.devtools.dev;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.context.CommandContext;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.sequence.endarrival.EndArrivalSequence;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev event start endarrival [fxonly]} / {@code /dev event stop endarrival} —
 * F-077 operator seams for the End-arrival cinematic (perm 2), registered as its own
 * brigadier tree that merges into the shared {@code /dev event} root (the parallel-wave
 * file-lock law: {@code DevEventCommands.java} stays untouched).
 *
 * <ul>
 *   <li>{@code start endarrival} — runs {@link EndArrivalSequence} with
 *       {@code buildDisc = true}: the REAL day-12 path, including the deferred
 *       {@code EndDiscService.materialize} at the phase-3 boundary. Refused when the disc
 *       is already built/building (the sequence's phase-3 call would no-op, which would
 *       leave a show that spits out nothing — use {@code fxonly} for that).</li>
 *   <li>{@code start endarrival fxonly} — the identical ~50 s show with no block written
 *       and no state flag committed (the {@code /dev nether replay_fx} convention);
 *       replayable any number of times, before or after the disc exists.</li>
 *   <li>{@code stop endarrival} — aborts the running show: debris discarded, guided
 *       cameras released, no further beats.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevEndArrivalCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("event.start.endarrival", DevCategory.EVENT,
                        "/dev event start endarrival [fxonly]",
                        "dev.eclipse.doc.event.start.endarrival", Danger.CAUTION,
                        ClickAction.SUGGEST, 2),
                new DevCommandDoc("event.stop.endarrival", DevCategory.EVENT,
                        "/dev event stop endarrival",
                        "dev.eclipse.doc.event.stop.endarrival", Danger.SAFE,
                        ClickAction.RUN, 2));
    }

    private DevEndArrivalCommands() {}

    @SubscribeEvent
    static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("event")
                        .then(Commands.literal("start")
                                .then(Commands.literal("endarrival")
                                        .executes(context -> start(context, true))
                                        .then(Commands.literal("fxonly")
                                                .executes(context -> start(context, false)))))
                        .then(Commands.literal("stop")
                                .then(Commands.literal("endarrival")
                                        .executes(DevEndArrivalCommands::stop)))));
    }

    private static int start(CommandContext<CommandSourceStack> context, boolean buildDisc) {
        CommandSourceStack source = context.getSource();
        if (!EndArrivalSequence.begin(source.getServer(), buildDisc)) {
            source.sendFailure(Component.translatable("dev.eclipse.event.start.endarrival.busy"));
            return 0;
        }
        audit(source, Component.translatable(buildDisc
                        ? "dev.eclipse.event.start.endarrival"
                        : "dev.eclipse.event.start.endarrival.fxonly"),
                "started the End arrival cinematic (buildDisc=" + buildDisc + ")");
        return 1;
    }

    private static int stop(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        if (!EndArrivalSequence.isRunning()) {
            source.sendFailure(Component.translatable("dev.eclipse.event.stop.endarrival.idle"));
            return 0;
        }
        EndArrivalSequence.abort();
        audit(source, Component.translatable("dev.eclipse.event.stop.endarrival"),
                "stopped the End arrival cinematic");
        return 1;
    }

    /** Same operator-audit convention as the other /dev command bridges. */
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
