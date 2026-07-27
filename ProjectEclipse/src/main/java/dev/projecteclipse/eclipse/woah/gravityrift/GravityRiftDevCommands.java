package dev.projecteclipse.eclipse.woah.gravityrift;

import com.mojang.brigadier.CommandDispatcher;
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
 * {@code /dev woah gravity ...} — operator surface for the WOAH-02 Gravitationsbruch
 * (plan §9). Registers its own {@code literal("dev")} tree; Brigadier merges the shared
 * {@code woah} literal across the parallel feature classes (the {@code DevRoot}
 * convention — no shared file is touched).
 *
 * <ul>
 *   <li>{@code build} — materialize the crater + islands NOW, bypassing the stage-4
 *       gate (idempotent; no-op + message when the sentinel already stands).</li>
 *   <li>{@code pulse} — fire the full pulse cue + launch beat immediately (off-raster;
 *       the regular 45 s raster is untouched).</li>
 *   <li>{@code invert} — clear the cooldown and start the 15 s inversion window as a
 *       heart hit would (player-only: the trigger needs an initiator).</li>
 *   <li>{@code orbitals} — wipe + budget-respawn all ~220 orbital displays.</li>
 *   <li>{@code tp} — teleport onto the crater rim at the walk sector (player-only).</li>
 *   <li>{@code status} — build/sentinel/pulse/inversion/low-G/display census
 *       (read-only, no audit line).</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class GravityRiftDevCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("woah.gravity.build", DevCategory.EVENT,
                        "/dev woah gravity build", "dev.eclipse.doc.woah.gravity.build",
                        Danger.CAUTION, ClickAction.RUN, 2),
                new DevCommandDoc("woah.gravity.pulse", DevCategory.EVENT,
                        "/dev woah gravity pulse", "dev.eclipse.doc.woah.gravity.pulse",
                        Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("woah.gravity.invert", DevCategory.EVENT,
                        "/dev woah gravity invert", "dev.eclipse.doc.woah.gravity.invert",
                        Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("woah.gravity.orbitals", DevCategory.EVENT,
                        "/dev woah gravity orbitals", "dev.eclipse.doc.woah.gravity.orbitals",
                        Danger.CAUTION, ClickAction.RUN, 2),
                new DevCommandDoc("woah.gravity.tp", DevCategory.EVENT,
                        "/dev woah gravity tp", "dev.eclipse.doc.woah.gravity.tp",
                        Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("woah.gravity.status", DevCategory.EVENT,
                        "/dev woah gravity status", "dev.eclipse.doc.woah.gravity.status",
                        Danger.SAFE, ClickAction.RUN, 2));
    }

    private GravityRiftDevCommands() {}

    @SubscribeEvent
    static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(DevRoot::canUseDev)
                .then(Commands.literal("woah")
                        .then(Commands.literal("gravity")
                                .then(Commands.literal("build")
                                        .executes(GravityRiftDevCommands::build))
                                .then(Commands.literal("pulse")
                                        .executes(GravityRiftDevCommands::pulse))
                                .then(Commands.literal("invert")
                                        .executes(GravityRiftDevCommands::invert))
                                .then(Commands.literal("orbitals")
                                        .executes(GravityRiftDevCommands::orbitals))
                                .then(Commands.literal("tp")
                                        .executes(GravityRiftDevCommands::teleport))
                                .then(Commands.literal("status")
                                        .executes(GravityRiftDevCommands::status)))));
    }

    /** Stage-gate bypass; async two-phase materialize, exactly one result line. */
    private static int build(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerLevel level = source.getServer().overworld();
        GravityRiftState state = GravityRiftState.get(source.getServer());
        if (state.built() && GravityRiftBuilder.isBuiltSentinel(level, state.anchor())) {
            source.sendSuccess(() -> ServerLang.tr(source.getPlayer(),
                    "dev.eclipse.woah.gravity.build.already"), false);
            return 0;
        }
        source.sendSuccess(() -> ServerLang.tr(source.getPlayer(),
                "dev.eclipse.woah.gravity.build.started"), true);
        GravityRiftBuilder.materialize(level,
                () -> source.sendSuccess(() -> ServerLang.tr(source.getPlayer(),
                        "dev.eclipse.woah.gravity.build.done"), false),
                throwable -> {
                    EclipseMod.LOGGER.error("GravityRiftDevCommands: build failed", throwable);
                    source.sendFailure(ServerLang.tr(source.getPlayer(),
                            "dev.eclipse.woah.gravity.build.failed"));
                });
        EclipseMod.LOGGER.info("[DEV AUDIT] {} built the gravity rift", source.getTextName());
        return 1;
    }

    private static int pulse(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerLevel level = source.getServer().overworld();
        if (!GravityRiftState.get(source.getServer()).built()) {
            source.sendFailure(ServerLang.tr(source.getPlayer(),
                    "dev.eclipse.woah.gravity.not_built"));
            return 0;
        }
        GravityRiftService.devPulse(level);
        source.sendSuccess(() -> ServerLang.tr(source.getPlayer(),
                "dev.eclipse.woah.gravity.pulse.ok"), true);
        EclipseMod.LOGGER.info("[DEV AUDIT] {} fired a gravity pulse", source.getTextName());
        return 1;
    }

    private static int invert(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerPlayer player = source.getPlayer();
        if (player == null) {
            source.sendFailure(ServerLang.tr(null, "dev.eclipse.woah.gravity.player_only"));
            return 0;
        }
        if (!GravityRiftState.get(source.getServer()).built()) {
            source.sendFailure(ServerLang.tr(player, "dev.eclipse.woah.gravity.not_built"));
            return 0;
        }
        GravityRiftService.devInvert(player);
        source.sendSuccess(() -> ServerLang.tr(player,
                "dev.eclipse.woah.gravity.invert.ok"), true);
        EclipseMod.LOGGER.info("[DEV AUDIT] {} forced a gravity inversion", source.getTextName());
        return 1;
    }

    private static int orbitals(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerLevel level = source.getServer().overworld();
        if (!GravityRiftState.get(source.getServer()).built()) {
            source.sendFailure(ServerLang.tr(source.getPlayer(),
                    "dev.eclipse.woah.gravity.not_built"));
            return 0;
        }
        GravityRiftOrbitals.rebuild(level);
        source.sendSuccess(() -> ServerLang.tr(source.getPlayer(),
                "dev.eclipse.woah.gravity.orbitals.ok", GravityRiftZone.pieces().size()), true);
        EclipseMod.LOGGER.info("[DEV AUDIT] {} rebuilt the gravity-rift orbitals",
                source.getTextName());
        return 1;
    }

    /** Rim drop-off: the kept-clear walk sector's outer edge, facing the heart. */
    private static int teleport(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerPlayer player = source.getPlayer();
        if (player == null) {
            source.sendFailure(ServerLang.tr(null, "dev.eclipse.woah.gravity.player_only"));
            return 0;
        }
        ServerLevel level = source.getServer().overworld();
        GravityRiftState state = GravityRiftState.get(source.getServer());
        BlockPos anchor = state.anchor();
        if (!state.built() || anchor == null) {
            // Not built yet — drop at the landmark surface for a look at the jungle site.
            BlockPos center = GravityRiftZone.surfaceCenter(level);
            player.teleportTo(level, center.getX() + 0.5D, center.getY() + 1.0D,
                    center.getZ() + 0.5D, 0.0F, 30.0F);
        } else {
            // Walk-sector bearing (unit inward direction (0.820, −0.573) → stand outside).
            double rim = GravityRiftZone.CRATER_RADIUS + 4.0D;
            double x = anchor.getX() + 0.5D + 0.820D * rim;
            double z = anchor.getZ() + 0.5D + -0.573D * rim;
            int y = anchor.getY() + GravityRiftZone.MAX_DEPTH + 2;
            float yaw = (float) Math.toDegrees(Math.atan2(-(anchor.getX() + 0.5D - x),
                    anchor.getZ() + 0.5D - z));
            player.teleportTo(level, x, y, z, yaw, 20.0F);
        }
        source.sendSuccess(() -> ServerLang.tr(player, "dev.eclipse.woah.gravity.tp.ok"), false);
        return 1;
    }

    /** Read-only census — no audit line (the DevScareCommands list convention). */
    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        ServerPlayer player = source.getPlayer();
        ServerLevel level = source.getServer().overworld();
        String snapshot = GravityRiftService.devStatus(level);
        source.sendSuccess(() -> ServerLang.tr(player, "dev.eclipse.woah.gravity.status.header",
                snapshot), false);
        int live = GravityRiftOrbitals.liveCount();
        source.sendSuccess(() -> ServerLang.tr(player, "dev.eclipse.woah.gravity.status.displays",
                live, GravityRiftZone.pieces().size()), false);
        return live;
    }
}
