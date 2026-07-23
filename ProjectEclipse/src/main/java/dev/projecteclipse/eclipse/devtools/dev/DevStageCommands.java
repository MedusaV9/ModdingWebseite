package dev.projecteclipse.eclipse.devtools.dev;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;

import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.suggestion.SuggestionProvider;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.devtools.StageBackups;
import dev.projecteclipse.eclipse.devtools.StageIO;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.ChatFormatting;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.network.chat.ClickEvent;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.HoverEvent;
import net.minecraft.network.chat.Style;
import net.minecraft.server.level.ServerLevel;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/** Consolidated, documented {@code /dev stage} backup/snapshot surface. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevStageCommands {
    private static final DateTimeFormatter DISPLAY_TIME =
            DateTimeFormatter.ofPattern("uuuu-MM-dd HH:mm:ss 'UTC'", Locale.ROOT).withZone(ZoneOffset.UTC);

    private static final SuggestionProvider<CommandSourceStack> BACKUP_SUGGESTIONS =
            (context, builder) -> SharedSuggestionProvider.suggest(
                    backupIdsAndLabels(context.getSource().getServer()), builder);

    private static final SuggestionProvider<CommandSourceStack> RESTORE_SUGGESTIONS =
            (context, builder) -> {
                List<String> ids = new ArrayList<>(backupIdsAndLabels(context.getSource().getServer()));
                snapshots(context.getSource().getServer()).stream().map(SnapshotInfo::id).forEach(ids::add);
                return SharedSuggestionProvider.suggest(ids, builder);
            };

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("stage.save", DevCategory.STAGE,
                        "/dev stage save <name>", "dev.eclipse.doc.stage.save",
                        Danger.CAUTION, ClickAction.SUGGEST, 3),
                new DevCommandDoc("stage.load", DevCategory.STAGE,
                        "/dev stage load <name>", "dev.eclipse.doc.stage.load",
                        Danger.DESTRUCTIVE, ClickAction.SUGGEST, 3),
                new DevCommandDoc("stage.revert", DevCategory.STAGE,
                        "/dev stage revert", "dev.eclipse.doc.stage.revert",
                        Danger.DESTRUCTIVE, ClickAction.RUN, 3),
                new DevCommandDoc("stage.list", DevCategory.STAGE,
                        "/dev stage list", "dev.eclipse.doc.stage.list",
                        Danger.SAFE, ClickAction.RUN, 3),
                new DevCommandDoc("stage.prune", DevCategory.STAGE,
                        "/dev stage prune [<keep>]", "dev.eclipse.doc.stage.prune",
                        Danger.CAUTION, ClickAction.SUGGEST, 3),
                new DevCommandDoc("stage.backup.now", DevCategory.STAGE,
                        "/dev stage backup now [<label>]", "dev.eclipse.doc.stage.backup",
                        Danger.SAFE, ClickAction.SUGGEST, 3));
    }

    private DevStageCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        event.getDispatcher().register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("stage")
                        .requires(source -> source.hasPermission(3))
                        .then(Commands.literal("save")
                                .then(Commands.argument("name", StringArgumentType.word())
                                        .executes(DevStageCommands::saveNamed)))
                        .then(Commands.literal("load")
                                .then(Commands.argument("name", StringArgumentType.word())
                                        .suggests(RESTORE_SUGGESTIONS)
                                        .executes(DevStageCommands::loadNamed)))
                        .then(Commands.literal("revert")
                                .executes(DevStageCommands::revert))
                        .then(Commands.literal("list")
                                .executes(DevStageCommands::list))
                        .then(Commands.literal("prune")
                                .executes(context -> prune(context, StageBackups.retention(
                                        context.getSource().getServer())))
                                .then(Commands.argument("keep", IntegerArgumentType.integer(1, 100))
                                        .executes(context -> prune(context,
                                                IntegerArgumentType.getInteger(context, "keep")))))
                        .then(Commands.literal("backup")
                                .then(Commands.literal("now")
                                        .executes(context -> backupNow(context, ""))
                                        .then(Commands.argument("label", StringArgumentType.word())
                                                .executes(context -> backupNow(context,
                                                        StringArgumentType.getString(context, "label")))))
                                .then(Commands.literal("list")
                                        .executes(DevStageCommands::list))
                                .then(Commands.literal("restore")
                                        .then(Commands.argument("id", StringArgumentType.word())
                                                .suggests(BACKUP_SUGGESTIONS)
                                                .executes(DevStageCommands::restoreBackup)))
                                .then(Commands.literal("prune")
                                        .executes(context -> prune(context, StageBackups.retention(
                                                context.getSource().getServer())))
                                        .then(Commands.argument("keep", IntegerArgumentType.integer(1, 100))
                                                .executes(context -> prune(context,
                                                        IntegerArgumentType.getInteger(context, "keep"))))))));
    }

    private static int saveNamed(CommandContext<CommandSourceStack> context) {
        String label = StringArgumentType.getString(context, "name");
        return createBackup(context, label, "named-snapshot");
    }

    private static int backupNow(CommandContext<CommandSourceStack> context, String label) {
        return createBackup(context, label, "manual-backup");
    }

    private static int createBackup(CommandContext<CommandSourceStack> context, String label, String sourceName) {
        CommandSourceStack source = context.getSource();
        DiscProfile profile = currentProfile(source);
        if (profile == null) {
            source.sendFailure(Component.translatable("dev.eclipse.stage.disc_only"));
            return 0;
        }
        StageBackups.BackupResult result = StageBackups.backupNow(
                source.getLevel(), profile, label, sourceName, source.getTextName());
        if (!result.success()) {
            source.sendFailure(Component.translatable("dev.eclipse.stage.backup.failed"));
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.stage.backup.saved",
                result.info().id(), profile.name(), result.info().sizeBytes() / 1024L), true);
        return 1;
    }

    private static int loadNamed(CommandContext<CommandSourceStack> context) {
        String id = StringArgumentType.getString(context, "name");
        SnapshotInfo snapshot = snapshots(context.getSource().getServer()).stream()
                .filter(info -> info.id().equals(id)).findFirst().orElse(null);
        if (snapshot != null) {
            ServerLevel level = context.getSource().getServer().getLevel(WorldStageService.dimensionOf(snapshot.profile()));
            if (level == null) {
                context.getSource().sendFailure(Component.translatable("dev.eclipse.stage.dimension_missing",
                        snapshot.profile().name()));
                return 0;
            }
            return reportOperation(context.getSource(), StageIO.load(level, snapshot.profile(), snapshot.stage(),
                    "dev-stage-load", context.getSource().getTextName()));
        }
        return restoreById(context.getSource(), id);
    }

    private static int restoreBackup(CommandContext<CommandSourceStack> context) {
        return restoreById(context.getSource(), StringArgumentType.getString(context, "id"));
    }

    private static int restoreById(CommandSourceStack source, String id) {
        StageBackups.BackupInfo info = StageBackups.find(source.getServer(), id).orElse(null);
        if (info == null) {
            source.sendFailure(Component.translatable("dev.eclipse.stage.restore.unknown", id));
            return 0;
        }
        ServerLevel level = source.getServer().getLevel(WorldStageService.dimensionOf(info.profile()));
        if (level == null) {
            source.sendFailure(Component.translatable("dev.eclipse.stage.dimension_missing", info.profile().name()));
            return 0;
        }
        return reportOperation(source, StageBackups.restore(
                level, info.profile(), id, "dev-stage-restore", source.getTextName()));
    }

    private static int revert(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        DiscProfile profile = currentProfile(source);
        if (profile == null) {
            source.sendFailure(Component.translatable("dev.eclipse.stage.disc_only"));
            return 0;
        }
        return reportOperation(source, StageBackups.restoreLatest(
                source.getLevel(), profile, "dev-stage-revert", source.getTextName()));
    }

    private static int reportOperation(CommandSourceStack source, String result) {
        if (result.startsWith("ERROR:")) {
            source.sendFailure(Component.translatable("dev.eclipse.stage.operation.failed"));
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.stage.operation.started"), true);
        return 1;
    }

    private static int list(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        List<SnapshotInfo> snapshots = snapshots(source.getServer());
        List<StageBackups.BackupInfo> backups = StageBackups.list(source.getServer());
        source.sendSuccess(() -> Component.translatable("dev.eclipse.stage.list.header",
                snapshots.size(), backups.size()), false);

        for (SnapshotInfo snapshot : snapshots) {
            String command = "/dev stage load " + snapshot.id();
            Component line = Component.translatable("dev.eclipse.stage.list.snapshot",
                    snapshot.profile().name(), snapshot.stage(), DISPLAY_TIME.format(Instant.ofEpochMilli(snapshot.time())),
                    snapshot.sizeBytes() / 1024L).withStyle(clickStyle(command));
            source.sendSuccess(() -> line, false);
        }
        for (StageBackups.BackupInfo backup : backups) {
            String command = "/dev stage load " + backup.id();
            Component line = Component.translatable("dev.eclipse.stage.list.backup",
                    backup.id(), backup.profile().name(), DISPLAY_TIME.format(
                            Instant.ofEpochMilli(backup.savedAtEpochMillis())),
                    backup.source(), backup.sizeBytes() / 1024L).withStyle(clickStyle(command));
            source.sendSuccess(() -> line, false);
        }
        if (snapshots.isEmpty() && backups.isEmpty()) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.stage.list.empty"), false);
        }
        return snapshots.size() + backups.size();
    }

    private static Style clickStyle(String command) {
        return Style.EMPTY.withColor(ChatFormatting.AQUA).withUnderlined(true)
                .withClickEvent(new ClickEvent(ClickEvent.Action.RUN_COMMAND, command))
                .withHoverEvent(new HoverEvent(HoverEvent.Action.SHOW_TEXT,
                        Component.translatable("dev.eclipse.stage.list.restore_hover")));
    }

    private static int prune(CommandContext<CommandSourceStack> context, int keep) {
        int removed = StageBackups.prune(context.getSource().getServer(), DiscProfile.OVERWORLD, keep)
                + StageBackups.prune(context.getSource().getServer(), DiscProfile.NETHER, keep);
        context.getSource().sendSuccess(() -> Component.translatable(
                "dev.eclipse.stage.pruned", removed, keep), true);
        return removed;
    }

    private static DiscProfile currentProfile(CommandSourceStack source) {
        return WorldStageService.profileOf(source.getLevel().dimension());
    }

    private static List<SnapshotInfo> snapshots(net.minecraft.server.MinecraftServer server) {
        Path dir = StageIO.stagesDir(server);
        if (!Files.isDirectory(dir)) {
            return List.of();
        }
        List<SnapshotInfo> result = new ArrayList<>();
        try (var stream = Files.list(dir)) {
            stream.filter(Files::isRegularFile)
                    .map(path -> parseSnapshot(path))
                    .filter(java.util.Objects::nonNull)
                    .forEach(result::add);
        } catch (IOException e) {
            EclipseMod.LOGGER.warn("Could not list curated stage snapshots in {}", dir, e);
        }
        result.sort(Comparator.comparingLong(SnapshotInfo::time).reversed());
        return List.copyOf(result);
    }

    private static List<String> backupIdsAndLabels(net.minecraft.server.MinecraftServer server) {
        List<String> values = new ArrayList<>();
        for (StageBackups.BackupInfo backup : StageBackups.list(server)) {
            values.add(backup.id());
            if (!backup.label().isEmpty() && !values.contains(backup.label())) {
                values.add(backup.label());
            }
        }
        return values;
    }

    private static SnapshotInfo parseSnapshot(Path path) {
        String name = path.getFileName().toString();
        if (!name.endsWith(".bin")) {
            return null;
        }
        String stem = name.substring(0, name.length() - 4);
        DiscProfile profile = stem.startsWith("nether_") ? DiscProfile.NETHER : DiscProfile.OVERWORLD;
        String stagePart = profile == DiscProfile.NETHER ? stem.substring("nether_".length()) : stem;
        try {
            int stage = Integer.parseInt(stagePart);
            long time = Files.getLastModifiedTime(path).toMillis();
            return new SnapshotInfo("snapshot_" + profile.name() + "_" + stage,
                    profile, stage, time, Files.size(path));
        } catch (NumberFormatException | IOException ignored) {
            return null;
        }
    }

    private record SnapshotInfo(String id, DiscProfile profile, int stage, long time, long sizeBytes) {}
}
