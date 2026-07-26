package dev.projecteclipse.eclipse.devtools.dev;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.context.CommandContext;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.ferryman.ArenaFight;
import dev.projecteclipse.eclipse.ferryman.finale.FinaleState;
import dev.projecteclipse.eclipse.ferryman.finale.PortalFormation;
import dev.projecteclipse.eclipse.lang.ServerLang;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * F-045c — the FERRYMAN2 finale test bridge ({@code /dev} tier, perm 2):
 * <ul>
 *   <li>{@code /dev start_ferryman} — the WHOLE arc in the 15 s dev cut: portal
 *       formation (fast; seeds a test swarm on a young world) → key over the altar →
 *       auto key flight → gate breach → purple fade → teleport → arena fight. One
 *       command, the full show ({@code PortalFormation.begin(fast, autoKey)}).</li>
 *   <li>{@code /dev ferryman skip_to arena} — SKIPS the shore theater entirely and
 *       arms the crossing through the portal ({@code ArenaFight.armGateThroughPortal}):
 *       everyone ships to the limbo deck, countdown, transformation, fight. Direct
 *       arena/boss testing without waiting on the formation.</li>
 *   <li>{@code /dev ferryman status} — finale SavedData stage, orbit count, gate site
 *       (read-only sanity check while testing).</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevFerrymanCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("start_ferryman", DevCategory.EVENT,
                        "/dev start_ferryman",
                        "dev.eclipse.doc.start_ferryman", Danger.DESTRUCTIVE, ClickAction.RUN, 2),
                new DevCommandDoc("ferryman.skipto", DevCategory.EVENT,
                        "/dev ferryman skip_to arena",
                        "dev.eclipse.doc.ferryman.skipto", Danger.DESTRUCTIVE, ClickAction.RUN, 2),
                new DevCommandDoc("ferryman.status", DevCategory.EVENT,
                        "/dev ferryman status",
                        "dev.eclipse.doc.ferryman.status", Danger.SAFE, ClickAction.RUN, 2));
    }

    private DevFerrymanCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(DevRoot::canUseDev)
                .then(Commands.literal("start_ferryman")
                        .executes(DevFerrymanCommands::startFerryman))
                .then(Commands.literal("ferryman")
                        .then(Commands.literal("skip_to")
                                .then(Commands.literal("arena")
                                        .executes(DevFerrymanCommands::skipToArena)))
                        .then(Commands.literal("status")
                                .executes(DevFerrymanCommands::status))));
    }

    /** The full arc in the dev cut: fast formation chaining straight into the key sequence. */
    private static int startFerryman(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        if (EclipseWorldState.get(server).getSanctumAltarPos() == null) {
            source.sendFailure(ServerLang.tr(source.getPlayer(), "dev.eclipse.ferryman.noaltar"));
            return 0;
        }
        boolean started = PortalFormation.begin(server, true, true);
        if (!started) {
            source.sendFailure(ServerLang.tr(source.getPlayer(), "dev.eclipse.ferryman.start.fail",
                    stageName(FinaleState.get(server).stage())));
            return 0;
        }
        source.sendSuccess(() -> ServerLang.tr(source.getPlayer(), "dev.eclipse.ferryman.start.ok"), false);
        audit(source, "dev.eclipse.ferryman.start.ok", "started the ferryman finale (fast cut)");
        return 1;
    }

    /** Straight to the crossing: everyone ships to the limbo deck, fight machinery runs. */
    private static int skipToArena(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        boolean armed = ArenaFight.armGateThroughPortal(source.getServer());
        if (!armed) {
            source.sendFailure(ServerLang.tr(source.getPlayer(), "dev.eclipse.ferryman.skip.fail"));
            return 0;
        }
        source.sendSuccess(() -> ServerLang.tr(source.getPlayer(), "dev.eclipse.ferryman.skip.ok"), false);
        audit(source, "dev.eclipse.ferryman.skip.ok", "skipped the finale straight to the arena crossing");
        return 1;
    }

    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        FinaleState state = FinaleState.get(server);
        ServerPlayer viewer = source.getPlayer();
        BlockPos portal = state.portalPos();
        source.sendSuccess(() -> ServerLang.tr(viewer, "dev.eclipse.ferryman.status",
                stageName(state.stage()), state.orbitCount(),
                portal == null ? "-" : portal.toShortString(),
                ArenaFight.isFightRunning(server) ? "ON" : "OFF"), false);
        return state.stage();
    }

    private static String stageName(int stage) {
        return switch (stage) {
            case FinaleState.STAGE_ORBITS -> "ORBITS";
            case FinaleState.STAGE_FORMING -> "FORMING";
            case FinaleState.STAGE_PORTAL_READY -> "PORTAL_READY";
            case FinaleState.STAGE_DONE -> "DONE";
            default -> "UNKNOWN(" + stage + ")";
        };
    }

    /** Operator-audit convention (DevLimboCommands twin): per-recipient locale re-bake. */
    private static void audit(CommandSourceStack source, String feedbackKey, String logDetail) {
        for (ServerPlayer operator : source.getServer().getPlayerList().getPlayers()) {
            if (operator.hasPermissions(2) && operator != source.getEntity()) {
                Component feedback = ServerLang.tr(operator, feedbackKey);
                operator.sendSystemMessage(ServerLang.tr(operator, "dev.eclipse.audit",
                        source.getTextName(), feedback));
            }
        }
        EclipseMod.LOGGER.info("[DEV AUDIT] {} {}", source.getTextName(), logDetail);
    }
}
