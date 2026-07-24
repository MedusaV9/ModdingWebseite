package dev.projecteclipse.eclipse.devtools.dev;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.contracts.ContractConfig;
import dev.projecteclipse.eclipse.contracts.ContractModifierService;
import dev.projecteclipse.eclipse.contracts.ContractService;
import dev.projecteclipse.eclipse.contracts.ContractState;
import dev.projecteclipse.eclipse.core.time.EclipseClock;
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
 * {@code /dev contract} ops tree (IDEA-20 #12, trimmed to the W4 build scope), registered
 * through {@link DevCommandRegistry} from the static initializer (freeze-before-boot rule)
 * in the {@code DevBuffCommands} style. Brigadier merges the {@code /dev} roots across
 * files, so no shared command file is touched.
 *
 * <p>{@code status} is the only place pair identities are ever readable — ops eyes only,
 * permission 2, never broadcast. {@code odds}/{@code window} tune the LIVE config snapshot
 * (transient until {@code /dev reload} or restart).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevContractCommands {
    /** Short dev omen so forced windows open quickly but the ceremony still reads. */
    private static final int DEV_OMEN_SECONDS = 5;

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("contract.start", DevCategory.EVENT,
                        "/dev contract start [hunter] [target]",
                        "dev.eclipse.doc.contract.start", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("contract.prank", DevCategory.EVENT,
                        "/dev contract prank",
                        "dev.eclipse.doc.contract.prank", Danger.CAUTION, ClickAction.RUN, 2),
                new DevCommandDoc("contract.stop", DevCategory.EVENT,
                        "/dev contract stop",
                        "dev.eclipse.doc.contract.stop", Danger.CAUTION, ClickAction.RUN, 2),
                new DevCommandDoc("contract.status", DevCategory.EVENT,
                        "/dev contract status",
                        "dev.eclipse.doc.contract.status", Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("contract.odds", DevCategory.EVENT,
                        "/dev contract odds <pct>",
                        "dev.eclipse.doc.contract.odds", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("contract.window", DevCategory.EVENT,
                        "/dev contract window <minutes>",
                        "dev.eclipse.doc.contract.window", Danger.CAUTION, ClickAction.SUGGEST, 2));
    }

    private DevContractCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("contract")
                        .then(Commands.literal("start")
                                .executes(context -> start(context, null, null))
                                .then(Commands.argument("hunter", EntityArgument.player())
                                        .then(Commands.argument("target", EntityArgument.player())
                                                .executes(context -> start(context,
                                                        EntityArgument.getPlayer(context, "hunter"),
                                                        EntityArgument.getPlayer(context, "target"))))))
                        .then(Commands.literal("prank").executes(DevContractCommands::prank))
                        .then(Commands.literal("stop").executes(DevContractCommands::stop))
                        .then(Commands.literal("status").executes(DevContractCommands::status))
                        .then(Commands.literal("odds")
                                .then(Commands.argument("pct", IntegerArgumentType.integer(0, 100))
                                        .executes(DevContractCommands::odds)))
                        .then(Commands.literal("window")
                                .then(Commands.argument("minutes", IntegerArgumentType.integer(1, 1440))
                                        .executes(DevContractCommands::window)))));
    }

    private static int start(CommandContext<CommandSourceStack> context,
            ServerPlayer hunter, ServerPlayer target) throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        Component failure = ContractService.forceStart(source.getServer(),
                ContractState.Mode.REAL, hunter, target, DEV_OMEN_SECONDS);
        if (failure != null) {
            source.sendFailure(failure);
            return 0;
        }
        audit(source, Component.translatable("dev.eclipse.contract.start.ok"),
                "force-started a REAL kill contract"
                        + (hunter != null && target != null ? " (forced pair)" : " (auto draw)"));
        return 1;
    }

    private static int prank(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        Component failure = ContractService.forceStart(source.getServer(),
                ContractState.Mode.PRANK, null, null, DEV_OMEN_SECONDS);
        if (failure != null) {
            source.sendFailure(failure);
            return 0;
        }
        audit(source, Component.translatable("dev.eclipse.contract.prank.ok"),
                "force-started a PRANK contract round");
        return 1;
    }

    private static int stop(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        Component failure = ContractService.forceStop(source.getServer());
        if (failure != null) {
            source.sendFailure(failure);
            return 0;
        }
        audit(source, Component.translatable("dev.eclipse.contract.stop.ok"),
                "force-stopped the running contract window");
        return 1;
    }

    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        ContractState state = ContractService.stateOf(server);
        ContractConfig.Values config = ContractConfig.get();
        long now = EclipseClock.epochMillis();

        source.sendSuccess(() -> Component.translatable("dev.eclipse.contract.status.header",
                state.phase().name(), state.mode().name()), false);
        if (state.phase() == ContractState.Phase.SCHEDULED
                || state.phase() == ContractState.Phase.ANNOUNCED) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.contract.status.starts",
                    mmss(state.windowStartsAtEpochMillis() - now)), false);
        }
        if (state.phase() == ContractState.Phase.ACTIVE) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.contract.status.remaining",
                    mmss(state.endsAtEpochMillis() - now)), false);
        }
        if (state.mode() == ContractState.Mode.REAL && state.hunter() != null) {
            // Ops-eyes only: names resolve here and nowhere else.
            String hunterName = nameOf(server, state.hunter());
            String targetName = nameOf(server, state.target());
            source.sendSuccess(() -> Component.translatable("dev.eclipse.contract.status.pair",
                    hunterName, targetName,
                    state.targetLoggedOut() ? " [target offline → ghost, " + state.ghostHits()
                            + " hit(s)]" : ""), false);
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.contract.status.odds",
                config.autoDaily(), config.realChancePct(), config.prankChancePct(),
                config.windowMinutes()), false);
        source.sendSuccess(() -> Component.translatable("dev.eclipse.contract.status.tallies",
                state.tallyLine(), ContractModifierService.entryCount(server)), false);
        return 1;
    }

    private static int odds(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        int pct = IntegerArgumentType.getInteger(context, "pct");
        ContractConfig.setRealChancePct(pct);
        audit(source, Component.translatable("dev.eclipse.contract.odds.ok", pct),
                "set contract REAL odds to " + pct + "% (transient)");
        return 1;
    }

    private static int window(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        int minutes = IntegerArgumentType.getInteger(context, "minutes");
        ContractConfig.setWindowMinutes(minutes);
        audit(source, Component.translatable("dev.eclipse.contract.window.ok", minutes),
                "set contract window to " + minutes + " min (transient)");
        return 1;
    }

    // ------------------------------------------------------------------ helpers

    private static String nameOf(MinecraftServer server, java.util.UUID uuid) {
        if (uuid == null) {
            return "-";
        }
        ServerPlayer online = server.getPlayerList().getPlayer(uuid);
        if (online != null) {
            return online.getScoreboardName();
        }
        var cached = server.getProfileCache() != null
                ? server.getProfileCache().get(uuid).orElse(null) : null;
        return cached != null ? cached.getName() : uuid.toString();
    }

    private static String mmss(long millis) {
        long totalSeconds = Math.max(0L, millis / 1000L);
        return String.format(java.util.Locale.ROOT, "%02d:%02d",
                totalSeconds / 60L, totalSeconds % 60L);
    }

    /** The DevBuffCommands audit convention: feedback + ops echo + log line. */
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
