package dev.projecteclipse.eclipse.devtools.dev;

import java.util.List;
import java.util.UUID;

import javax.annotation.Nullable;

import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.context.CommandContext;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.pregen.MapPregenService;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * F-091 {@code /dev preload} surface over {@link MapPregenService} (plan
 * PLAN-F091-092 §2.5). {@code everything} pushes BOTH disc dimensions to the final
 * frozen radius once so every later chunk access is a region-file load;
 * {@code start} scopes/overrides the radius; {@code status} reports cursor/%/rate/ETA
 * and disk headroom; {@code pause}/{@code resume}/{@code cancel} steer running jobs;
 * {@code unload} is the belt-and-braces manual flush-save + in-flight ticket report
 * (§2.3 item 7 — the natural completion path already flushes on its own).
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevPreloadCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("preload.everything", DevCategory.STAGE,
                        "/dev preload everything", "dev.eclipse.doc.preload.everything",
                        Danger.CAUTION, ClickAction.RUN, 3),
                new DevCommandDoc("preload.start", DevCategory.STAGE,
                        "/dev preload start <overworld|nether|all> [<radiusBlocks>]",
                        "dev.eclipse.doc.preload.start",
                        Danger.CAUTION, ClickAction.SUGGEST, 3),
                new DevCommandDoc("preload.status", DevCategory.STAGE,
                        "/dev preload status", "dev.eclipse.doc.preload.status",
                        Danger.SAFE, ClickAction.RUN, 3),
                new DevCommandDoc("preload.pause", DevCategory.STAGE,
                        "/dev preload pause", "dev.eclipse.doc.preload.pause",
                        Danger.SAFE, ClickAction.RUN, 3),
                new DevCommandDoc("preload.resume", DevCategory.STAGE,
                        "/dev preload resume", "dev.eclipse.doc.preload.resume",
                        Danger.SAFE, ClickAction.RUN, 3),
                new DevCommandDoc("preload.cancel", DevCategory.STAGE,
                        "/dev preload cancel", "dev.eclipse.doc.preload.cancel",
                        Danger.CAUTION, ClickAction.RUN, 3),
                new DevCommandDoc("preload.unload", DevCategory.STAGE,
                        "/dev preload unload", "dev.eclipse.doc.preload.unload",
                        Danger.CAUTION, ClickAction.RUN, 3));
    }

    private DevPreloadCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        event.getDispatcher().register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("preload")
                        .requires(source -> source.hasPermission(3))
                        .then(Commands.literal("everything")
                                .executes(context -> start(context, null, 0)))
                        .then(Commands.literal("start")
                                .then(Commands.literal("overworld")
                                        .executes(context -> start(context, DiscProfile.OVERWORLD, 0))
                                        .then(Commands.argument("radiusBlocks",
                                                        IntegerArgumentType.integer(16, 4096))
                                                .executes(context -> start(context, DiscProfile.OVERWORLD,
                                                        IntegerArgumentType.getInteger(context, "radiusBlocks")))))
                                .then(Commands.literal("nether")
                                        .executes(context -> start(context, DiscProfile.NETHER, 0))
                                        .then(Commands.argument("radiusBlocks",
                                                        IntegerArgumentType.integer(16, 4096))
                                                .executes(context -> start(context, DiscProfile.NETHER,
                                                        IntegerArgumentType.getInteger(context, "radiusBlocks")))))
                                .then(Commands.literal("all")
                                        .executes(context -> start(context, null, 0))
                                        .then(Commands.argument("radiusBlocks",
                                                        IntegerArgumentType.integer(16, 4096))
                                                .executes(context -> start(context, null,
                                                        IntegerArgumentType.getInteger(context, "radiusBlocks"))))))
                        .then(Commands.literal("status")
                                .executes(DevPreloadCommands::status))
                        .then(Commands.literal("pause")
                                .executes(DevPreloadCommands::pause))
                        .then(Commands.literal("resume")
                                .executes(DevPreloadCommands::resume))
                        .then(Commands.literal("cancel")
                                .executes(DevPreloadCommands::cancel))
                        .then(Commands.literal("unload")
                                .executes(DevPreloadCommands::unload))));
    }

    /** {@code profile == null} = both disc dimensions; {@code radius <= 0} = plan default. */
    private static int start(CommandContext<CommandSourceStack> context,
            @Nullable DiscProfile profile, int radius) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        ServerPlayer player = source.getPlayer();
        UUID issuerId = player != null ? player.getUUID() : null;
        DiscProfile[] targets = profile != null
                ? new DiscProfile[] {profile}
                : new DiscProfile[] {DiscProfile.OVERWORLD, DiscProfile.NETHER};
        int started = 0;
        for (DiscProfile target : targets) {
            int targetRadius = radius > 0 ? radius : MapPregenService.defaultRadius(target);
            String failure = MapPregenService.start(server, target, targetRadius, issuerId, false);
            if (failure != null) {
                source.sendFailure(Component.translatable("dev.eclipse.preload.start.failed",
                        target.name(), failure));
                continue;
            }
            int radiusForMessage = targetRadius;
            source.sendSuccess(() -> Component.translatable("dev.eclipse.preload.start.ok",
                    target.name(), radiusForMessage), true);
            started++;
        }
        if (started > 0) {
            EclipseMod.LOGGER.info("[DEV AUDIT] {} started map pregen ({} job(s))",
                    source.getTextName(), started);
        }
        return started;
    }

    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        List<String> lines = MapPregenService.statusLines(source.getServer());
        for (String line : lines) {
            source.sendSuccess(() -> Component.literal(line), false);
        }
        return lines.size();
    }

    private static int pause(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        int paused = MapPregenService.pauseAll();
        if (paused == 0) {
            source.sendFailure(Component.translatable("dev.eclipse.preload.none_running"));
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.preload.paused", paused), true);
        return paused;
    }

    private static int resume(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        int resumed = MapPregenService.resumeAll();
        if (resumed == 0) {
            source.sendFailure(Component.translatable("dev.eclipse.preload.none_paused"));
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.preload.resumed", resumed), true);
        return resumed;
    }

    private static int cancel(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        int cancelled = MapPregenService.cancelAll(source.getServer());
        if (cancelled == 0) {
            source.sendFailure(Component.translatable("dev.eclipse.preload.none_running"));
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.preload.cancelled", cancelled), true);
        EclipseMod.LOGGER.info("[DEV AUDIT] {} cancelled map pregen ({} job(s))",
                source.getTextName(), cancelled);
        return cancelled;
    }

    /** Manual flush-save + verification that no pregen requests are outstanding (§2.3-7). */
    private static int unload(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        server.saveEverything(true, true, false);
        int inFlight = MapPregenService.inFlightCount();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.preload.unloaded", inFlight), true);
        return 1;
    }
}
