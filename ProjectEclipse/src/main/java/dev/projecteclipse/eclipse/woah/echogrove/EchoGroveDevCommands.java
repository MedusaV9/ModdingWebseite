package dev.projecteclipse.eclipse.woah.echogrove;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.arguments.StringArgumentType;
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
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev woah echo ...} — operator surface for the WOAH-05 echo grove
 * (plan §9). Hangs its subtree off the shared {@code woah} literal (Brigadier
 * merges separate register calls — the {@code ChronoStasisDevCommands} sibling
 * convention; {@link DevRoot} holds the permission root).
 *
 * <ul>
 *   <li>{@code spawn} — materialize the grove immediately, stage-independent.</li>
 *   <li>{@code flood [ticks]} — force a memory flood now (default 160t hold).</li>
 *   <li>{@code finale} — pin {@code deposited=5} and start the finale sequence.</li>
 *   <li>{@code reset} — quest state back to zero, scenes/one-shots despawn, the
 *       overlay pool re-parks, all orbs respawn; TERRAIN STAYS (plan §9).</li>
 *   <li>{@code status} — placed/deposited/finaleDone + actor/orb/pool/loop census.</li>
 *   <li>{@code scene <id>} — one amplified playback next to the executor.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EchoGroveDevCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("woah.echo.spawn", DevCategory.EVENT,
                        "/dev woah echo spawn", "dev.eclipse.doc.woah.echo.spawn",
                        Danger.CAUTION, ClickAction.RUN, 2),
                new DevCommandDoc("woah.echo.flood", DevCategory.EVENT,
                        "/dev woah echo flood [ticks]", "dev.eclipse.doc.woah.echo.flood",
                        Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("woah.echo.finale", DevCategory.EVENT,
                        "/dev woah echo finale", "dev.eclipse.doc.woah.echo.finale",
                        Danger.CAUTION, ClickAction.RUN, 2),
                new DevCommandDoc("woah.echo.reset", DevCategory.EVENT,
                        "/dev woah echo reset", "dev.eclipse.doc.woah.echo.reset",
                        Danger.CAUTION, ClickAction.RUN, 2),
                new DevCommandDoc("woah.echo.status", DevCategory.EVENT,
                        "/dev woah echo status", "dev.eclipse.doc.woah.echo.status",
                        Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("woah.echo.scene", DevCategory.EVENT,
                        "/dev woah echo scene <id>", "dev.eclipse.doc.woah.echo.scene",
                        Danger.SAFE, ClickAction.RUN, 2));
    }

    private EchoGroveDevCommands() {}

    @SubscribeEvent
    static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(DevRoot::canUseDev)
                .then(Commands.literal("woah")
                        .then(Commands.literal("echo")
                                .then(Commands.literal("spawn")
                                        .executes(EchoGroveDevCommands::spawn))
                                .then(Commands.literal("flood")
                                        .executes(context -> flood(context,
                                                MemoryFloodService.FLOOD_TICKS))
                                        .then(Commands.argument("ticks",
                                                IntegerArgumentType.integer(80, 1200))
                                                .executes(context -> flood(context,
                                                        IntegerArgumentType.getInteger(
                                                                context, "ticks")))))
                                .then(Commands.literal("finale")
                                        .executes(EchoGroveDevCommands::finale))
                                .then(Commands.literal("reset")
                                        .executes(EchoGroveDevCommands::reset))
                                .then(Commands.literal("status")
                                        .executes(EchoGroveDevCommands::status))
                                .then(Commands.literal("scene")
                                        .then(Commands.argument("id", StringArgumentType.word())
                                                .suggests((context, builder) ->
                                                        SharedSuggestionProvider.suggest(
                                                                EchoScenes.SCENE_ORDER, builder))
                                                .executes(EchoGroveDevCommands::scene))))));
    }

    /** Stage-gate bypass; async two-phase materialize, exactly one result line. */
    private static int spawn(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerLevel level = source.getServer().overworld();
        if (EchoGroveState.get(source.getServer()).placed()) {
            source.sendSuccess(() -> ServerLang.tr(source.getPlayer(),
                    "dev.eclipse.woah.echo.spawn.already"), false);
            return 0;
        }
        source.sendSuccess(() -> ServerLang.tr(source.getPlayer(),
                "dev.eclipse.woah.echo.spawn.started"), true);
        EchoGroveSites.materializeNow(level,
                () -> source.sendSuccess(() -> ServerLang.tr(source.getPlayer(),
                        "dev.eclipse.woah.echo.spawn.done"), false),
                throwable -> {
                    EclipseMod.LOGGER.error("EchoGroveDevCommands: spawn failed", throwable);
                    source.sendFailure(ServerLang.tr(source.getPlayer(),
                            "dev.eclipse.woah.echo.spawn.failed"));
                });
        EclipseMod.LOGGER.info("[DEV AUDIT] {} spawned the echo grove", source.getTextName());
        return 1;
    }

    private static int flood(CommandContext<CommandSourceStack> context, int holdTicks) {
        CommandSourceStack source = context.getSource();
        EchoGroveState state = EchoGroveState.get(source.getServer());
        BlockPos tree = state.treeCenter();
        if (!state.placed() || tree == null) {
            source.sendFailure(ServerLang.tr(source.getPlayer(),
                    "dev.eclipse.woah.echo.not_placed"));
            return 0;
        }
        MemoryFloodService.start(source.getServer().overworld(), tree, holdTicks,
                state.finaleDone());
        source.sendSuccess(() -> ServerLang.tr(source.getPlayer(),
                "dev.eclipse.woah.echo.flood.ok", holdTicks), true);
        EclipseMod.LOGGER.info("[DEV AUDIT] {} forced a memory flood ({}t)",
                source.getTextName(), holdTicks);
        return 1;
    }

    private static int finale(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerLevel level = source.getServer().overworld();
        EchoGroveState state = EchoGroveState.get(source.getServer());
        if (!state.placed() || state.treeCenter() == null) {
            source.sendFailure(ServerLang.tr(source.getPlayer(),
                    "dev.eclipse.woah.echo.not_placed"));
            return 0;
        }
        if (state.finaleDone()) {
            source.sendFailure(ServerLang.tr(source.getPlayer(),
                    "dev.eclipse.woah.echo.finale.done_already"));
            return 0;
        }
        while (state.deposited() < 5) {
            state.deposit();
        }
        EchoGrovePayloads.syncAll(source.getServer());
        EchoFinaleSequence.start(level, source.getPlayer());
        source.sendSuccess(() -> ServerLang.tr(source.getPlayer(),
                "dev.eclipse.woah.echo.finale.ok"), true);
        EclipseMod.LOGGER.info("[DEV AUDIT] {} started the echo grove finale",
                source.getTextName());
        return 1;
    }

    /** Quest + scene reset; terrain and static glimmer stay (plan §9). */
    private static int reset(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerLevel level = source.getServer().overworld();
        EchoGroveState state = EchoGroveState.get(source.getServer());
        if (!state.placed()) {
            source.sendFailure(ServerLang.tr(source.getPlayer(),
                    "dev.eclipse.woah.echo.not_placed"));
            return 0;
        }
        EchoFinaleSequence.abort();
        MemoryFloodService.cancelFlood();
        EchoSceneService.discardAll();
        state.resetQuest();
        int orbs = EchoGroveTerraformer.respawnOrbs(level);
        EchoOverlayBuilder.reparkAll(false);
        EchoGrovePayloads.syncAll(source.getServer());
        source.sendSuccess(() -> ServerLang.tr(source.getPlayer(),
                "dev.eclipse.woah.echo.reset.ok", orbs), true);
        EclipseMod.LOGGER.info("[DEV AUDIT] {} reset the echo grove quest ({} orb(s) recycled)",
                source.getTextName(), orbs);
        return 1;
    }

    /** Read-only census — no audit line (the DevScareCommands list convention). */
    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerPlayer player = source.getPlayer();
        ServerLevel level = source.getServer().overworld();
        EchoGroveState state = EchoGroveState.get(source.getServer());
        source.sendSuccess(() -> ServerLang.tr(player, "dev.eclipse.woah.echo.status.header",
                state.placed(), Integer.toBinaryString(state.collectedOrbs()),
                state.deposited(), state.finaleDone()), false);
        int liveOrbs = 0;
        for (java.util.UUID uuid : state.orbUuids()) {
            if (level.getEntity(uuid) != null) {
                liveOrbs++;
            }
        }
        int finalLiveOrbs = liveOrbs;
        source.sendSuccess(() -> ServerLang.tr(player, "dev.eclipse.woah.echo.status.census",
                EchoSceneService.actorCount(), EchoSceneService.loopInstanceCount(),
                EchoSceneService.oneShotCount(), finalLiveOrbs), false);
        source.sendSuccess(() -> ServerLang.tr(player, "dev.eclipse.woah.echo.status.pool",
                EchoOverlayBuilder.poolSize(), EchoOverlayBuilder.poolTarget(),
                MemoryFloodService.floodActive(), MemoryFloodService.ticksUntilFlood()), false);
        return EchoSceneService.actorCount();
    }

    private static int scene(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerPlayer player = source.getPlayer();
        if (player == null) {
            source.sendFailure(ServerLang.tr(null, "dev.eclipse.woah.echo.player_only"));
            return 0;
        }
        String id = StringArgumentType.getString(context, "id");
        if (EchoScenes.scene(id) == null) {
            source.sendFailure(ServerLang.tr(player, "dev.eclipse.woah.echo.scene.unknown", id));
            return 0;
        }
        EchoSceneService.playOnce(source.getServer().overworld(), id, player, 0.6F);
        source.sendSuccess(() -> ServerLang.tr(player,
                "dev.eclipse.woah.echo.scene.ok", id), true);
        return 1;
    }
}
