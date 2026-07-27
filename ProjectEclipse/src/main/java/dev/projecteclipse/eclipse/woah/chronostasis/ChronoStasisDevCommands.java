package dev.projecteclipse.eclipse.woah.chronostasis;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.context.CommandContext;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.devtools.dev.ClickAction;
import dev.projecteclipse.eclipse.devtools.dev.Danger;
import dev.projecteclipse.eclipse.devtools.dev.DevCategory;
import dev.projecteclipse.eclipse.devtools.dev.DevCommandDoc;
import dev.projecteclipse.eclipse.devtools.dev.DevCommandRegistry;
import dev.projecteclipse.eclipse.devtools.dev.DevRoot;
import dev.projecteclipse.eclipse.lang.ServerLang;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev woah chrono ...} — operator surface for the WOAH-03 Chrono-Stasis site
 * (plan §9). This class registers the {@code woah} literal for the first time; later
 * Woah features hang their own subtrees off the same literal (Brigadier merges separate
 * {@code register} calls automatically, the {@link DevRoot} convention).
 *
 * <ul>
 *   <li>{@code spawn} — materialize the site immediately, bypassing the stage gate.
 *       No-op + message when already placed.</li>
 *   <li>{@code tick [count <n>]} — one time-jolt exactly as a pad right-click would fire
 *       it (JOLT phase, sounds, cue, counter++); the optional {@code count} pins the
 *       persisted {@code joltCount} first (e.g. {@code count 4} → next click discharges).</li>
 *   <li>{@code discharge} — start DISCHARGE now, ignoring joltCount and the repeat
 *       cooldown.</li>
 *   <li>{@code reset} — FROZEN + {@code joltCount=0}, discard all tagged props, then a
 *       deterministic rebuild through the normal reconcile path + a fresh anchor/pad.</li>
 *   <li>{@code status} — placed/phase/joltCount/discharges/rewardClaimed plus the live
 *       display census (read-only, no audit).</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ChronoStasisDevCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("woah.chrono.spawn", DevCategory.EVENT,
                        "/dev woah chrono spawn", "dev.eclipse.doc.woah.chrono.spawn",
                        Danger.CAUTION, ClickAction.RUN, 2),
                new DevCommandDoc("woah.chrono.tick", DevCategory.EVENT,
                        "/dev woah chrono tick [count <n>]", "dev.eclipse.doc.woah.chrono.tick",
                        Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("woah.chrono.discharge", DevCategory.EVENT,
                        "/dev woah chrono discharge", "dev.eclipse.doc.woah.chrono.discharge",
                        Danger.CAUTION, ClickAction.RUN, 2),
                new DevCommandDoc("woah.chrono.reset", DevCategory.EVENT,
                        "/dev woah chrono reset", "dev.eclipse.doc.woah.chrono.reset",
                        Danger.CAUTION, ClickAction.RUN, 2),
                new DevCommandDoc("woah.chrono.status", DevCategory.EVENT,
                        "/dev woah chrono status", "dev.eclipse.doc.woah.chrono.status",
                        Danger.SAFE, ClickAction.RUN, 2));
    }

    private ChronoStasisDevCommands() {}

    @SubscribeEvent
    static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(DevRoot::canUseDev)
                .then(Commands.literal("woah")
                        .then(Commands.literal("chrono")
                                .then(Commands.literal("spawn")
                                        .executes(ChronoStasisDevCommands::spawn))
                                .then(Commands.literal("tick")
                                        .executes(context -> jolt(context, -1))
                                        .then(Commands.literal("count")
                                                .then(Commands.argument("n",
                                                        IntegerArgumentType.integer(0, 99))
                                                        .executes(context -> jolt(context,
                                                                IntegerArgumentType.getInteger(
                                                                        context, "n"))))))
                                .then(Commands.literal("discharge")
                                        .executes(ChronoStasisDevCommands::discharge))
                                .then(Commands.literal("reset")
                                        .executes(ChronoStasisDevCommands::reset))
                                .then(Commands.literal("status")
                                        .executes(ChronoStasisDevCommands::status)))));
    }

    /** Stage-gate bypass; async two-phase materialize, exactly one result line. */
    private static int spawn(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerLevel level = source.getServer().overworld();
        if (ChronoStasisData.get(source.getServer()).placed()) {
            source.sendSuccess(() -> ServerLang.tr(source.getPlayer(),
                    "dev.eclipse.woah.chrono.spawn.already"), false);
            return 0;
        }
        source.sendSuccess(() -> ServerLang.tr(source.getPlayer(),
                "dev.eclipse.woah.chrono.spawn.started"), true);
        ChronoStasisSite.materialize(level,
                () -> source.sendSuccess(() -> ServerLang.tr(source.getPlayer(),
                        "dev.eclipse.woah.chrono.spawn.done"), false),
                throwable -> {
                    EclipseMod.LOGGER.error("ChronoStasisDevCommands: spawn failed", throwable);
                    source.sendFailure(ServerLang.tr(source.getPlayer(),
                            "dev.eclipse.woah.chrono.spawn.failed"));
                });
        EclipseMod.LOGGER.info("[DEV AUDIT] {} spawned the chrono-stasis site",
                source.getTextName());
        return 1;
    }

    private static int jolt(CommandContext<CommandSourceStack> context, int setCountOrNegative) {
        CommandSourceStack source = context.getSource();
        ServerPlayer player = source.getPlayer();
        if (player == null) {
            source.sendFailure(ServerLang.tr(null, "dev.eclipse.woah.chrono.player_only"));
            return 0;
        }
        ServerLevel level = source.getServer().overworld();
        if (!ChronoStasisService.devJolt(level, player, setCountOrNegative)) {
            source.sendFailure(ServerLang.tr(player, "dev.eclipse.woah.chrono.not_ready",
                    ChronoStasisService.phase().name()));
            return 0;
        }
        int count = ChronoStasisData.get(source.getServer()).joltCount();
        source.sendSuccess(() -> ServerLang.tr(player, "dev.eclipse.woah.chrono.tick.ok",
                count, ChronoStasisService.JOLTS_FOR_DISCHARGE), true);
        EclipseMod.LOGGER.info("[DEV AUDIT] {} fired a chrono jolt (count now {})",
                source.getTextName(), count);
        return count;
    }

    private static int discharge(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerPlayer player = source.getPlayer();
        if (player == null) {
            source.sendFailure(ServerLang.tr(null, "dev.eclipse.woah.chrono.player_only"));
            return 0;
        }
        ServerLevel level = source.getServer().overworld();
        if (!ChronoStasisService.devDischarge(level, player)) {
            source.sendFailure(ServerLang.tr(player, "dev.eclipse.woah.chrono.not_ready",
                    ChronoStasisService.phase().name()));
            return 0;
        }
        source.sendSuccess(() -> ServerLang.tr(player,
                "dev.eclipse.woah.chrono.discharge.ok"), true);
        EclipseMod.LOGGER.info("[DEV AUDIT] {} forced a chrono discharge", source.getTextName());
        return 1;
    }

    private static int reset(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerLevel level = source.getServer().overworld();
        int props = ChronoStasisService.devReset(level);
        if (props < 0) {
            source.sendFailure(ServerLang.tr(source.getPlayer(),
                    "dev.eclipse.woah.chrono.not_placed"));
            return 0;
        }
        source.sendSuccess(() -> ServerLang.tr(source.getPlayer(),
                "dev.eclipse.woah.chrono.reset.ok", props), true);
        EclipseMod.LOGGER.info("[DEV AUDIT] {} reset the chrono-stasis scene ({} prop(s))",
                source.getTextName(), props);
        return props;
    }

    /** Read-only census — no audit line (the DevScareCommands list convention). */
    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerPlayer player = source.getPlayer();
        ChronoStasisData data = ChronoStasisData.get(source.getServer());
        source.sendSuccess(() -> ServerLang.tr(player, "dev.eclipse.woah.chrono.status.header",
                data.placed(), ChronoStasisService.phase().name()), false);
        source.sendSuccess(() -> ServerLang.tr(player, "dev.eclipse.woah.chrono.status.progress",
                data.joltCount(), ChronoStasisService.JOLTS_FOR_DISCHARGE,
                data.discharges(), data.rewardClaimed()), false);
        BlockPos center = ChronoStasisService.center();
        ChronoSceneBuilder.SceneState scene = ChronoStasisService.scene();
        if (center == null || scene == null) {
            source.sendSuccess(() -> ServerLang.tr(player,
                    "dev.eclipse.woah.chrono.status.no_scene"), false);
            return data.placed() ? 1 : 0;
        }
        int live = scene.liveCount();
        source.sendSuccess(() -> ServerLang.tr(player, "dev.eclipse.woah.chrono.status.scene",
                live, scene.props().size(), scene.pendingSpawns(), scene.reconciled()), false);
        source.sendSuccess(() -> ServerLang.tr(player, "dev.eclipse.woah.chrono.status.center",
                center.getX(), center.getY(), center.getZ()), false);
        return live;
    }
}
