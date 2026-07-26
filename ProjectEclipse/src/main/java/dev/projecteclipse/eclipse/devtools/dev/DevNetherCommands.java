package dev.projecteclipse.eclipse.devtools.dev;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.context.CommandContext;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldgenState;
import dev.projecteclipse.eclipse.network.nether.S2CNetherOpenPayload.Phase;
import dev.projecteclipse.eclipse.sequence.NetherOpeningSequence;
import dev.projecteclipse.eclipse.sequence.NetherUpheavalFx;
import dev.projecteclipse.eclipse.worldgen.nether.BreachBuilder;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.network.chat.Component;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev nether …} — the ops surface over the day-2 nether-opening show
 * ({@code sequence.NetherOpeningSequence}):
 *
 * <ul>
 *   <li>{@code /dev nether open} — runs the FULL ~47 s sequence, crater excavation
 *       included. Exactly what the day-2 rollover does.</li>
 *   <li>{@code /dev nether replay_fx} — runs the identical show with the excavation
 *       switched off: no block is written, no state flag is committed. The FX/tuning
 *       iteration loop (and the only safe verb on a live event world).</li>
 *   <li>{@code /dev nether stop} — aborts a running show and discards every block
 *       display (an already-started excavation keeps running: it is idempotent and must
 *       not be left half-dug).</li>
 *   <li>{@code /dev nether status} — phase, elapsed ticks, live displays, breach flag.</li>
 * </ul>
 *
 * <p>Registers its own {@code /dev} root subtree (Brigadier merges roots — the
 * {@code DevPortalCommands} precedent), so the shared command hubs stay untouched.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevNetherCommands {

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("nether.open", DevCategory.EVENT,
                        "/dev nether open",
                        "dev.eclipse.doc.nether.open", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("nether.replay_fx", DevCategory.EVENT,
                        "/dev nether replay_fx",
                        "dev.eclipse.doc.nether.replay_fx", Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("nether.stop", DevCategory.EVENT,
                        "/dev nether stop",
                        "dev.eclipse.doc.nether.stop", Danger.CAUTION, ClickAction.RUN, 2),
                new DevCommandDoc("nether.status", DevCategory.EVENT,
                        "/dev nether status",
                        "dev.eclipse.doc.nether.status", Danger.SAFE, ClickAction.RUN, 2));
    }

    private DevNetherCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("nether")
                        .then(Commands.literal("open")
                                .executes(context -> start(context, true)))
                        .then(Commands.literal("replay_fx")
                                .executes(context -> start(context, false)))
                        .then(Commands.literal("stop")
                                .executes(DevNetherCommands::stop))
                        .then(Commands.literal("status")
                                .executes(DevNetherCommands::status))));
    }

    // ------------------------------------------------------------------ handlers

    private static int start(CommandContext<CommandSourceStack> context, boolean carve) {
        CommandSourceStack source = context.getSource();
        if (!NetherOpeningSequence.begin(source.getServer(), carve)) {
            source.sendFailure(Component.translatable("dev.eclipse.nether.busy"));
            return 0;
        }
        source.sendSuccess(() -> Component.translatable(
                carve ? "dev.eclipse.nether.started" : "dev.eclipse.nether.replaying",
                NetherOpeningSequence.TOTAL_TICKS / 20,
                BreachBuilder.breachCenter().toShortString()), true);
        return 1;
    }

    private static int stop(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        if (!NetherOpeningSequence.isRunning() && !NetherUpheavalFx.isActive()) {
            source.sendFailure(Component.translatable("dev.eclipse.nether.idle"));
            return 0;
        }
        NetherOpeningSequence.abort();
        NetherUpheavalFx.clearAll();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.nether.stopped"), true);
        return 1;
    }

    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        Phase phase = NetherOpeningSequence.currentPhase();
        boolean open = EclipseWorldgenState.get(source.getServer()).breachOpen();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.nether.status",
                phase == null ? "-" : phase.name(),
                NetherOpeningSequence.elapsedTicks(),
                NetherOpeningSequence.TOTAL_TICKS,
                NetherOpeningSequence.isCarving() ? "carve" : "fx",
                NetherUpheavalFx.livePieces(),
                open ? "yes" : "no",
                BreachBuilder.breachCenter().toShortString()), false);
        return 1;
    }
}
