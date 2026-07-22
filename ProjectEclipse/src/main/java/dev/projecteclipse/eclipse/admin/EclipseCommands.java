package dev.projecteclipse.eclipse.admin;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.DoubleArgumentType;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.snapshot.SnapshotService;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import dev.projecteclipse.eclipse.limbo.GhostShipBuilder;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.limbo.StartEventCutscene;
import dev.projecteclipse.eclipse.lives.BanService;
import dev.projecteclipse.eclipse.network.S2CDayStatePayload;
import dev.projecteclipse.eclipse.progression.BorderController;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import dev.projecteclipse.eclipse.progression.ModGate;
import dev.projecteclipse.eclipse.progression.UnlockState;
import dev.projecteclipse.eclipse.voice.VoiceMuteApi;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.StageRadii;
import dev.projecteclipse.eclipse.worldgen.stage.RingGrowthService;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.arguments.EntityArgument;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The {@code /eclipse} admin command tree (permission level 3). Every subcommand delegates to
 * the owning subsystem's public API and reports back to the <em>command source only</em> via
 * {@link CommandSourceStack#sendSuccess}/{@link CommandSourceStack#sendFailure} — nothing is
 * ever broadcast to player chat.
 *
 * <pre>
 * /eclipse start_event
 * /eclipse day set &lt;1-14&gt; | day goals
 * /eclipse lives set|add &lt;player&gt; &lt;n&gt;
 * /eclipse altar set &lt;level&gt;
 * /eclipse ban &lt;player&gt; | revive &lt;player&gt;
 * /eclipse restore &lt;player&gt; [index]          (no index = list snapshots)
 * /eclipse border set &lt;size&gt; [seconds]
 * /eclipse modgate lock|unlock &lt;namespace&gt;
 * /eclipse stage get | set &lt;overworld|nether&gt; &lt;n&gt; [instant|animate] | rebuild &lt;dim&gt; &lt;n&gt;
 * /eclipse voicemute &lt;player&gt; on|off
 * /eclipse tp_limbo [player]
 * /eclipse reload
 * /eclipse status
 * </pre>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EclipseCommands {
    private static final DateTimeFormatter SNAPSHOT_TIME_FORMAT =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").withZone(ZoneId.systemDefault());

    private EclipseCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("eclipse")
                .requires(source -> source.hasPermission(3))
                .then(Commands.literal("start_event")
                        .executes(EclipseCommands::startEvent))
                .then(Commands.literal("day")
                        .then(Commands.literal("set")
                                .then(Commands.argument("day", IntegerArgumentType.integer(1, 14))
                                        .executes(EclipseCommands::daySet)))
                        .then(Commands.literal("goals")
                                .executes(EclipseCommands::dayGoals)))
                .then(Commands.literal("lives")
                        .then(Commands.literal("set")
                                .then(Commands.argument("player", EntityArgument.player())
                                        .then(Commands.argument("lives", IntegerArgumentType.integer(0))
                                                .executes(EclipseCommands::livesSet))))
                        .then(Commands.literal("add")
                                .then(Commands.argument("player", EntityArgument.player())
                                        .then(Commands.argument("delta", IntegerArgumentType.integer())
                                                .executes(EclipseCommands::livesAdd)))))
                .then(Commands.literal("altar")
                        .then(Commands.literal("set")
                                .then(Commands.argument("level", IntegerArgumentType.integer(0))
                                        .executes(EclipseCommands::altarSet))))
                .then(Commands.literal("ban")
                        .then(Commands.argument("player", EntityArgument.player())
                                .executes(EclipseCommands::ban)))
                .then(Commands.literal("revive")
                        .then(Commands.argument("player", EntityArgument.player())
                                .executes(EclipseCommands::revive)))
                .then(Commands.literal("restore")
                        .then(Commands.argument("player", EntityArgument.player())
                                .executes(EclipseCommands::restoreList)
                                .then(Commands.argument("index", IntegerArgumentType.integer(1))
                                        .executes(EclipseCommands::restoreApply))))
                .then(Commands.literal("border")
                        .then(Commands.literal("set")
                                .then(Commands.argument("size", DoubleArgumentType.doubleArg(1.0D))
                                        .executes(context -> borderSet(context, 0))
                                        .then(Commands.argument("seconds", IntegerArgumentType.integer(0))
                                                .executes(context -> borderSet(context,
                                                        IntegerArgumentType.getInteger(context, "seconds")))))))
                .then(Commands.literal("modgate")
                        .then(Commands.literal("lock")
                                .then(Commands.argument("namespace", StringArgumentType.word())
                                        .executes(context -> modgate(context, true))))
                        .then(Commands.literal("unlock")
                                .then(Commands.argument("namespace", StringArgumentType.word())
                                        .executes(context -> modgate(context, false)))))
                .then(Commands.literal("voicemute")
                        .then(Commands.argument("player", EntityArgument.player())
                                .then(Commands.literal("on")
                                        .executes(context -> voicemute(context, true)))
                                .then(Commands.literal("off")
                                        .executes(context -> voicemute(context, false)))))
                .then(Commands.literal("stage")
                        .then(Commands.literal("get")
                                .executes(EclipseCommands::stageGet))
                        .then(Commands.literal("set")
                                .then(Commands.argument("dimension", StringArgumentType.word())
                                        .suggests((context, builder) -> net.minecraft.commands.SharedSuggestionProvider
                                                .suggest(new String[] {"overworld", "nether"}, builder))
                                        .then(Commands.argument("stage", IntegerArgumentType.integer(0))
                                                .executes(context -> stageSet(context, true))
                                                .then(Commands.literal("animate")
                                                        .executes(context -> stageSet(context, true)))
                                                .then(Commands.literal("instant")
                                                        .executes(context -> stageSet(context, false))))))
                        .then(Commands.literal("rebuild")
                                .then(Commands.argument("dimension", StringArgumentType.word())
                                        .suggests((context, builder) -> net.minecraft.commands.SharedSuggestionProvider
                                                .suggest(new String[] {"overworld", "nether"}, builder))
                                        .then(Commands.argument("stage", IntegerArgumentType.integer(0))
                                                .executes(EclipseCommands::stageRebuild)))))
                .then(Commands.literal("tp_limbo")
                        .executes(context -> tpLimbo(context.getSource(), context.getSource().getPlayerOrException()))
                        .then(Commands.argument("player", EntityArgument.player())
                                .executes(context -> tpLimbo(context.getSource(),
                                        EntityArgument.getPlayer(context, "player")))))
                .then(Commands.literal("reload")
                        .executes(EclipseCommands::reload))
                .then(Commands.literal("status")
                        .executes(EclipseCommands::status)));
    }

    // --- start_event ---

    private static int startEvent(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        if (StartEventCutscene.begin(source.getServer())) {
            source.sendSuccess(() -> Component.literal("Start-event cutscene beginning"), false);
            return 1;
        }
        source.sendFailure(Component.literal("Start-event cutscene is already running"));
        return 0;
    }

    // --- day ---

    private static int daySet(CommandContext<CommandSourceStack> context) {
        int day = IntegerArgumentType.getInteger(context, "day");
        CommandSourceStack source = context.getSource();
        DayScheduler.setDay(source.getServer(), day);
        source.sendSuccess(() -> Component.literal("Eclipse day set to " + day
                + " (unlocked keys: " + String.join(", ", UnlockState.unlockedKeys(source.getServer())) + ")"), false);
        return day;
    }

    private static int dayGoals(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        int day = DayScheduler.getDay(source.getServer());
        EclipseConfig.DayPlan plan = EclipseConfig.day(day);
        source.sendSuccess(() -> Component.literal("Day " + day + " goals:"), false);
        for (String goal : plan.goals()) {
            source.sendSuccess(() -> Component.literal(" - " + goal), false);
        }
        return day;
    }

    // --- lives ---

    private static int livesSet(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        ServerPlayer player = EntityArgument.getPlayer(context, "player");
        int lives = IntegerArgumentType.getInteger(context, "lives");
        int applied = LivesApi.set(player, lives);
        context.getSource().sendSuccess(() -> Component.literal(
                player.getScoreboardName() + " now has " + applied + " lives"), false);
        return applied;
    }

    private static int livesAdd(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        ServerPlayer player = EntityArgument.getPlayer(context, "player");
        int delta = IntegerArgumentType.getInteger(context, "delta");
        int applied = LivesApi.add(player, delta);
        context.getSource().sendSuccess(() -> Component.literal(
                player.getScoreboardName() + " now has " + applied + " lives ("
                        + (delta >= 0 ? "+" : "") + delta + ")"), false);
        return applied;
    }

    // --- altar ---

    private static int altarSet(CommandContext<CommandSourceStack> context) {
        int level = IntegerArgumentType.getInteger(context, "level");
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        EclipseWorldState state = EclipseWorldState.get(server);
        state.setAltarLevel(level);
        // Same resync the altar itself performs on a milestone completion.
        PacketDistributor.sendToAllPlayers(new S2CDayStatePayload(state.getDay(), level,
                EclipseConfig.day(state.getDay()).goals()));
        source.sendSuccess(() -> Component.literal("Altar level set to " + level
                + " (unlocked keys: " + String.join(", ", UnlockState.unlockedKeys(server)) + ")"), false);
        return level;
    }

    // --- ban / revive ---

    private static int ban(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        ServerPlayer player = EntityArgument.getPlayer(context, "player");
        CommandSourceStack source = context.getSource();
        if (BanService.isBanned(player)) {
            source.sendFailure(Component.literal(player.getScoreboardName() + " is already event-banned"));
            return 0;
        }
        BanService.ban(player);
        source.sendSuccess(() -> Component.literal(
                player.getScoreboardName() + " has been event-banned and sent to Limbo"), false);
        return 1;
    }

    private static int revive(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        ServerPlayer player = EntityArgument.getPlayer(context, "player");
        CommandSourceStack source = context.getSource();
        if (!BanService.isBanned(player)) {
            source.sendFailure(Component.literal(player.getScoreboardName() + " is not event-banned"));
            return 0;
        }
        BanService.unban(player);
        source.sendSuccess(() -> Component.literal(
                player.getScoreboardName() + " has been revived (1 life, back at overworld spawn)"), false);
        return 1;
    }

    // --- restore ---

    private static int restoreList(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        ServerPlayer player = EntityArgument.getPlayer(context, "player");
        CommandSourceStack source = context.getSource();
        List<Path> snapshots = SnapshotService.list(source.getServer(), player.getUUID());
        if (snapshots.isEmpty()) {
            source.sendFailure(Component.literal("No snapshots stored for " + player.getScoreboardName()));
            return 0;
        }
        source.sendSuccess(() -> Component.literal(snapshots.size() + " snapshot(s) for "
                + player.getScoreboardName() + " (restore with /eclipse restore "
                + player.getScoreboardName() + " <index>):"), false);
        for (int i = 0; i < snapshots.size(); i++) {
            Path file = snapshots.get(i);
            String line = String.format(Locale.ROOT, " [%d] %s%s", i + 1,
                    formatSnapshotTime(file), describeSnapshotReason(file));
            source.sendSuccess(() -> Component.literal(line), false);
        }
        return snapshots.size();
    }

    private static int restoreApply(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        ServerPlayer player = EntityArgument.getPlayer(context, "player");
        int index = IntegerArgumentType.getInteger(context, "index");
        CommandSourceStack source = context.getSource();
        List<Path> snapshots = SnapshotService.list(source.getServer(), player.getUUID());
        if (snapshots.isEmpty()) {
            source.sendFailure(Component.literal("No snapshots stored for " + player.getScoreboardName()));
            return 0;
        }
        if (index > snapshots.size()) {
            source.sendFailure(Component.literal("Snapshot index " + index + " out of range (1-"
                    + snapshots.size() + ")"));
            return 0;
        }
        Path file = snapshots.get(index - 1);
        if (!SnapshotService.restore(player, file)) {
            source.sendFailure(Component.literal("Failed to restore snapshot " + file.getFileName()
                    + " — see the server log"));
            return 0;
        }
        source.sendSuccess(() -> Component.literal("Restored snapshot [" + index + "] "
                + formatSnapshotTime(file) + " for " + player.getScoreboardName()), false);
        return 1;
    }

    /** The snapshot's capture time, derived from its {@code <epochMillis>.json} file name. */
    private static String formatSnapshotTime(Path file) {
        String name = file.getFileName().toString();
        try {
            long millis = Long.parseLong(name.substring(0, name.length() - ".json".length()));
            return SNAPSHOT_TIME_FORMAT.format(Instant.ofEpochMilli(millis));
        } catch (NumberFormatException | IndexOutOfBoundsException e) {
            return name;
        }
    }

    /** Best-effort {@code " (reason)"} suffix read from the snapshot JSON; empty on any failure. */
    private static String describeSnapshotReason(Path file) {
        try {
            JsonObject root = JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)).getAsJsonObject();
            return root.has("reason") ? " (" + root.get("reason").getAsString() + ")" : "";
        } catch (Exception e) {
            return "";
        }
    }

    // --- border ---

    private static int borderSet(CommandContext<CommandSourceStack> context, int seconds) {
        double size = DoubleArgumentType.getDouble(context, "size");
        CommandSourceStack source = context.getSource();
        BorderController.setBorder(source.getServer(), size, seconds * 1000L);
        source.sendSuccess(() -> Component.literal("World border set to " + size + " blocks"
                + (seconds > 0 ? " over " + seconds + " s" : " (instant)")), false);
        return (int) size;
    }

    // --- modgate ---

    private static int modgate(CommandContext<CommandSourceStack> context, boolean lock) {
        String namespace = StringArgumentType.getString(context, "namespace").toLowerCase(Locale.ROOT);
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        boolean changed = EclipseConfig.setNamespaceGated(namespace, lock);
        boolean effectivelyLocked = ModGate.isNamespaceLocked(server, namespace);
        StringBuilder message = new StringBuilder("Namespace '").append(namespace).append("' is now ")
                .append(lock ? "gated" : "ungated").append(changed ? "" : " (unchanged)")
                .append("; content currently ").append(effectivelyLocked ? "LOCKED" : "usable");
        if (lock && !effectivelyLocked) {
            message.append(" — its unlock key is already granted by the day plan/altar; lower the day to re-lock");
        }
        source.sendSuccess(() -> Component.literal(message.toString()), false);
        return changed ? 1 : 0;
    }

    // --- voicemute ---

    private static int voicemute(CommandContext<CommandSourceStack> context, boolean muted) throws CommandSyntaxException {
        ServerPlayer player = EntityArgument.getPlayer(context, "player");
        CommandSourceStack source = context.getSource();
        VoiceMuteApi.setForceMuted(source.getServer(), player.getUUID(), muted);
        source.sendSuccess(() -> Component.literal(player.getScoreboardName()
                + (muted ? " is now force voice-muted" : " is no longer force voice-muted")), false);
        return 1;
    }

    // --- stage ---

    /** {@code "overworld"} / {@code "nether"} → the disc profile, or {@code null}. */
    private static DiscProfile discProfileArg(CommandContext<CommandSourceStack> context) {
        String name = StringArgumentType.getString(context, "dimension").toLowerCase(Locale.ROOT);
        return switch (name) {
            case "overworld" -> DiscProfile.OVERWORLD;
            case "nether" -> DiscProfile.NETHER;
            default -> null;
        };
    }

    private static int stageGet(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        for (DiscProfile profile : new DiscProfile[] {DiscProfile.OVERWORLD, DiscProfile.NETHER}) {
            int stage = WorldStageService.stage(server, profile);
            String progress = RingGrowthService.progressLine(profile);
            String line = profile.name() + ": stage " + stage + "/" + WorldStageService.maxStage(profile)
                    + " (radius " + StageRadii.radius(profile, stage) + ")"
                    + (progress != null ? " — sweeping: " + progress : "");
            source.sendSuccess(() -> Component.literal(line), false);
        }
        return WorldStageService.stage(server, DiscProfile.OVERWORLD);
    }

    private static int stageSet(CommandContext<CommandSourceStack> context, boolean animate) {
        CommandSourceStack source = context.getSource();
        DiscProfile profile = discProfileArg(context);
        if (profile == null) {
            source.sendFailure(Component.literal("Unknown disc dimension (use overworld|nether)"));
            return 0;
        }
        int stage = IntegerArgumentType.getInteger(context, "stage");
        if (stage > WorldStageService.maxStage(profile)) {
            source.sendFailure(Component.literal("Stage out of range: " + profile.name()
                    + " is configured for stages 0-" + WorldStageService.maxStage(profile)));
            return 0;
        }
        if (!WorldStageService.setStage(source.getServer(), WorldStageService.dimensionOf(profile),
                stage, animate)) {
            source.sendFailure(Component.literal(profile.name() + " is already at stage " + stage));
            return 0;
        }
        source.sendSuccess(() -> Component.literal("World stage " + profile.name() + " set to " + stage
                + " (radius " + StageRadii.radius(profile, stage) + ", "
                + (animate ? "animated sweep" : "instant stamp") + " running — watch the log)"), false);
        return stage;
    }

    private static int stageRebuild(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        DiscProfile profile = discProfileArg(context);
        if (profile == null) {
            source.sendFailure(Component.literal("Unknown disc dimension (use overworld|nether)"));
            return 0;
        }
        int stage = IntegerArgumentType.getInteger(context, "stage");
        if (!WorldStageService.rebuildStage(source.getServer(), WorldStageService.dimensionOf(profile), stage)) {
            source.sendFailure(Component.literal("Cannot rebuild " + profile.name() + " stage " + stage
                    + " (out of range, or a sweep is already running)"));
            return 0;
        }
        source.sendSuccess(() -> Component.literal("Re-stamping " + profile.name() + " stage " + stage
                + " annulus with the committed terrain (instant sweep)"), false);
        return 1;
    }

    // --- tp_limbo ---

    private static int tpLimbo(CommandSourceStack source, ServerPlayer player) {
        ServerLevel limbo = source.getServer().getLevel(LimboDimension.LIMBO);
        if (limbo == null) {
            source.sendFailure(Component.literal("Limbo dimension " + LimboDimension.LIMBO.location()
                    + " is not loaded"));
            return 0;
        }
        // Land on the ghost ship's spawn platform — the shared world spawn X/Z sit over open ocean.
        BlockPos arrival = GhostShipBuilder.platformArrivalPos(limbo);
        player.teleportTo(limbo, arrival.getX() + 0.5D, arrival.getY(), arrival.getZ() + 0.5D, 0.0F, 0.0F);
        source.sendSuccess(() -> Component.literal("Teleported " + player.getScoreboardName()
                + " to the Limbo ghost ship platform"), false);
        return 1;
    }

    // --- reload ---

    private static int reload(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        EclipseConfig.reload();
        // Goals/unlocks may have changed; push the fresh day state to every client.
        EclipseWorldState state = EclipseWorldState.get(server);
        PacketDistributor.sendToAllPlayers(new S2CDayStatePayload(state.getDay(), state.getAltarLevel(),
                EclipseConfig.day(state.getDay()).goals()));
        source.sendSuccess(() -> Component.literal("Eclipse config reloaded: "
                + EclipseConfig.days().size() + " days, " + EclipseConfig.milestones().size() + " milestones, "
                + EclipseConfig.modGate().gatedNamespaces().size() + " gated namespaces, "
                + EclipseConfig.antiCheat().blockedModIdSubstrings().size() + " anti-cheat entries"), false);
        return 1;
    }

    // --- status ---

    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        EclipseWorldState state = EclipseWorldState.get(server);

        source.sendSuccess(() -> Component.literal("=== Eclipse status ==="), false);
        source.sendSuccess(() -> Component.literal("Day: " + state.getDay()
                + " | Altar level: " + state.getAltarLevel()
                + " | Border: " + state.getBorderSize() + " blocks"
                + " | Start event done: " + state.isStartEventDone()), false);
        source.sendSuccess(() -> Component.literal("Unlocked keys: "
                + String.join(", ", UnlockState.unlockedKeys(server))), false);

        List<UUID> banned = List.copyOf(state.getBanned());
        if (banned.isEmpty()) {
            source.sendSuccess(() -> Component.literal("Banned: none"), false);
        } else {
            StringBuilder names = new StringBuilder();
            for (UUID id : banned) {
                if (names.length() > 0) {
                    names.append(", ");
                }
                names.append(server.getProfileCache() != null
                        ? server.getProfileCache().get(id).map(profile -> profile.getName()).orElse(id.toString())
                        : id.toString());
            }
            source.sendSuccess(() -> Component.literal("Banned (" + banned.size() + "): " + names), false);
        }

        List<ServerPlayer> online = server.getPlayerList().getPlayers();
        source.sendSuccess(() -> Component.literal("Online players (" + online.size() + "):"), false);
        for (ServerPlayer player : online) {
            String line = " - " + player.getScoreboardName() + ": " + LivesApi.get(player) + " lives"
                    + (BanService.isBanned(player) ? " [BANNED]" : "")
                    + (state.isForceVoiceMuted(player.getUUID()) ? " [VOICE-MUTED]" : "");
            source.sendSuccess(() -> Component.literal(line), false);
        }
        return online.size();
    }
}
