package dev.projecteclipse.eclipse.admin;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

import javax.annotation.Nullable;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.DoubleArgumentType;
import com.mojang.brigadier.arguments.FloatArgumentType;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;
import com.mojang.brigadier.suggestion.SuggestionProvider;

import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.snapshot.SnapshotService;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import dev.projecteclipse.eclipse.cutscene.CutscenePath;
import dev.projecteclipse.eclipse.cutscene.CutscenePaths;
import dev.projecteclipse.eclipse.cutscene.CutsceneService;
import dev.projecteclipse.eclipse.entity.EclipseSpawner;
import dev.projecteclipse.eclipse.limbo.GhostShipBuilder;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.limbo.StartEventCutscene;
import dev.projecteclipse.eclipse.lives.BanService;
import dev.projecteclipse.eclipse.network.S2CDayStatePayload;
import dev.projecteclipse.eclipse.network.S2CMilestonesPayload;
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
 * /eclipse event set &lt;pale|umbral|none&gt;
 * /eclipse lives set|add &lt;player&gt; &lt;n&gt;
 * /eclipse altar set &lt;level&gt;
 * /eclipse ban &lt;player&gt; | revive &lt;player&gt;
 * /eclipse restore &lt;player&gt; [index]          (no index = list snapshots)
 * /eclipse border set &lt;size&gt; [seconds]        (legacy: ring radius = size/2)
 * /eclipse border ring set &lt;radius&gt; [seconds] | border fx range &lt;blocks&gt;
 * /eclipse modgate lock|unlock &lt;namespace&gt;
 * /eclipse stage get | set &lt;overworld|nether&gt; &lt;n&gt; [instant|animate] | rebuild &lt;dim&gt; &lt;n&gt;
 * /eclipse voicemute &lt;player&gt; on|off
 * /eclipse tp_limbo [player]
 * /eclipse cutscene play &lt;id&gt; [players] | abort [players] | list | enable|disable &lt;id&gt;
 *   | skip allow|deny &lt;id&gt; | preview &lt;id&gt; | reloadpaths | export &lt;id&gt;
 *   | edit &lt;id&gt; addkeyframe [t] | edit &lt;id&gt; set roll|fov &lt;v&gt; | edit &lt;id&gt; removekeyframe &lt;i&gt;
 * /eclipse reload
 * /eclipse status
 * </pre>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EclipseCommands {
    private static final DateTimeFormatter SNAPSHOT_TIME_FORMAT =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").withZone(ZoneId.systemDefault());

    /** Tab completion with the loaded cutscene path ids. */
    private static final SuggestionProvider<CommandSourceStack> CUTSCENE_IDS =
            (context, builder) -> net.minecraft.commands.SharedSuggestionProvider.suggest(
                    CutscenePaths.all().stream().map(CutscenePath::id), builder);

    /** Tab completion for {@code /eclipse event set}. */
    private static final SuggestionProvider<CommandSourceStack> NIGHT_EVENTS =
            (context, builder) -> net.minecraft.commands.SharedSuggestionProvider.suggest(
                    List.of(EclipseWorldState.NIGHT_EVENT_PALE, EclipseWorldState.NIGHT_EVENT_UMBRAL,
                            EclipseWorldState.NIGHT_EVENT_NONE), builder);

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
                .then(Commands.literal("event")
                        .then(Commands.literal("set")
                                .then(Commands.argument("event", StringArgumentType.word())
                                        .suggests(NIGHT_EVENTS)
                                        .executes(EclipseCommands::eventSet))))
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
                                                        IntegerArgumentType.getInteger(context, "seconds"))))))
                        .then(Commands.literal("ring")
                                .then(Commands.literal("set")
                                        .then(Commands.argument("radius", DoubleArgumentType.doubleArg(1.0D))
                                                .executes(context -> borderRingSet(context, 0))
                                                .then(Commands.argument("seconds", IntegerArgumentType.integer(0))
                                                        .executes(context -> borderRingSet(context,
                                                                IntegerArgumentType.getInteger(context, "seconds")))))))
                        .then(Commands.literal("fx")
                                .then(Commands.literal("range")
                                        .then(Commands.argument("blocks", DoubleArgumentType.doubleArg(1.0D))
                                                .executes(EclipseCommands::borderFxRange)))))
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
                .then(Commands.literal("cutscene")
                        .then(Commands.literal("play")
                                .then(Commands.argument("id", StringArgumentType.word())
                                        .suggests(CUTSCENE_IDS)
                                        .executes(context -> cutscenePlay(context, null))
                                        .then(Commands.argument("players", EntityArgument.players())
                                                .executes(context -> cutscenePlay(context,
                                                        EntityArgument.getPlayers(context, "players"))))))
                        .then(Commands.literal("abort")
                                .executes(context -> cutsceneAbort(context, null))
                                .then(Commands.argument("players", EntityArgument.players())
                                        .executes(context -> cutsceneAbort(context,
                                                EntityArgument.getPlayers(context, "players")))))
                        .then(Commands.literal("list")
                                .executes(EclipseCommands::cutsceneList))
                        .then(Commands.literal("enable")
                                .then(Commands.argument("id", StringArgumentType.word())
                                        .suggests(CUTSCENE_IDS)
                                        .executes(context -> cutsceneSetDisabled(context, false))))
                        .then(Commands.literal("disable")
                                .then(Commands.argument("id", StringArgumentType.word())
                                        .suggests(CUTSCENE_IDS)
                                        .executes(context -> cutsceneSetDisabled(context, true))))
                        .then(Commands.literal("skip")
                                .then(Commands.literal("allow")
                                        .then(Commands.argument("id", StringArgumentType.word())
                                                .suggests(CUTSCENE_IDS)
                                                .executes(context -> cutsceneSkipPolicy(context, true))))
                                .then(Commands.literal("deny")
                                        .then(Commands.argument("id", StringArgumentType.word())
                                                .suggests(CUTSCENE_IDS)
                                                .executes(context -> cutsceneSkipPolicy(context, false)))))
                        .then(Commands.literal("preview")
                                .then(Commands.argument("id", StringArgumentType.word())
                                        .suggests(CUTSCENE_IDS)
                                        .executes(EclipseCommands::cutscenePreview)))
                        .then(Commands.literal("reloadpaths")
                                .executes(EclipseCommands::cutsceneReloadPaths))
                        .then(Commands.literal("export")
                                .then(Commands.argument("id", StringArgumentType.word())
                                        .suggests(CUTSCENE_IDS)
                                        .executes(EclipseCommands::cutsceneExport)))
                        .then(Commands.literal("edit")
                                .then(Commands.argument("id", StringArgumentType.word())
                                        .suggests(CUTSCENE_IDS)
                                        .then(Commands.literal("addkeyframe")
                                                .executes(context -> cutsceneAddKeyframe(context, -1.0D))
                                                .then(Commands.argument("t", DoubleArgumentType.doubleArg(0.0D, 1.0D))
                                                        .executes(context -> cutsceneAddKeyframe(context,
                                                                DoubleArgumentType.getDouble(context, "t")))))
                                        .then(Commands.literal("removekeyframe")
                                                .then(Commands.argument("index", IntegerArgumentType.integer(0))
                                                        .executes(EclipseCommands::cutsceneRemoveKeyframe)))
                                        .then(Commands.literal("set")
                                                .then(Commands.literal("roll")
                                                        .then(Commands.argument("value", FloatArgumentType.floatArg(-180.0F, 180.0F))
                                                                .executes(context -> cutsceneSetLastKeyframe(context, "roll"))))
                                                .then(Commands.literal("fov")
                                                        .then(Commands.argument("value", FloatArgumentType.floatArg(10.0F, 140.0F))
                                                                .executes(context -> cutsceneSetLastKeyframe(context, "fov"))))))))
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

    // --- night events (W10) ---

    /** {@code /eclipse event set <pale|umbral|none>}: overrides the active night event live. */
    private static int eventSet(CommandContext<CommandSourceStack> context) {
        String event = StringArgumentType.getString(context, "event").toLowerCase(Locale.ROOT);
        CommandSourceStack source = context.getSource();
        if (!EclipseWorldState.NIGHT_EVENT_PALE.equals(event)
                && !EclipseWorldState.NIGHT_EVENT_UMBRAL.equals(event)
                && !EclipseWorldState.NIGHT_EVENT_NONE.equals(event)) {
            source.sendFailure(Component.literal("Unknown night event '" + event + "' (pale|umbral|none)"));
            return 0;
        }
        MinecraftServer server = source.getServer();
        EclipseWorldState state = EclipseWorldState.get(server);
        state.setActiveNightEvent(event, state.getDay());
        if (!EclipseWorldState.NIGHT_EVENT_NONE.equals(event)) {
            EclipseSpawner.announceNightEvent(server, event);
        }
        source.sendSuccess(() -> Component.literal("Night event set to '" + event
                + "' (day stamp " + state.getNightEventDay() + ")"), false);
        return 1;
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

    /** Legacy v1 command, repointed: a vanilla-style SIZE (diameter) becomes ring radius size/2. */
    private static int borderSet(CommandContext<CommandSourceStack> context, int seconds) {
        double size = DoubleArgumentType.getDouble(context, "size");
        CommandSourceStack source = context.getSource();
        BorderController.setBorder(source.getServer(), size, seconds * 1000L);
        source.sendSuccess(() -> Component.literal("Soft border ring set to radius " + (size / 2.0D)
                + " (from legacy size " + size + ")"
                + (seconds > 0 ? " over " + seconds + " s" : " (instant)")
                + "; vanilla failsafe follows at +" + dev.projecteclipse.eclipse.border.SoftBorder.FAILSAFE_MARGIN), false);
        return (int) size;
    }

    private static int borderRingSet(CommandContext<CommandSourceStack> context, int seconds) {
        double radius = DoubleArgumentType.getDouble(context, "radius");
        CommandSourceStack source = context.getSource();
        dev.projecteclipse.eclipse.border.SoftBorder.setRing(source.getServer(),
                DiscProfile.OVERWORLD, radius, seconds * 1000L);
        source.sendSuccess(() -> Component.literal("Soft border ring set to radius " + radius
                + (seconds > 0 ? " over " + seconds + " s" : " (instant)")
                + "; vanilla failsafe follows at +" + dev.projecteclipse.eclipse.border.SoftBorder.FAILSAFE_MARGIN), false);
        return (int) radius;
    }

    private static int borderFxRange(CommandContext<CommandSourceStack> context) {
        double blocks = DoubleArgumentType.getDouble(context, "blocks");
        CommandSourceStack source = context.getSource();
        dev.projecteclipse.eclipse.border.SoftBorder.setFxRange(source.getServer(), blocks);
        source.sendSuccess(() -> Component.literal("Border FX visibility range set to " + blocks
                + " blocks (synced to all clients)"), false);
        return (int) blocks;
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

    // --- cutscene ---

    /** {@code [players]} defaults to everyone online when the selector is omitted. */
    private static Collection<ServerPlayer> cutsceneTargets(CommandSourceStack source,
            @Nullable Collection<ServerPlayer> selected) {
        return selected != null ? selected : List.copyOf(source.getServer().getPlayerList().getPlayers());
    }

    private static int cutscenePlay(CommandContext<CommandSourceStack> context,
            @Nullable Collection<ServerPlayer> selected) {
        CommandSourceStack source = context.getSource();
        String id = StringArgumentType.getString(context, "id");
        CutscenePath path = CutscenePaths.get(id);
        if (path == null) {
            source.sendFailure(Component.literal("Unknown cutscene path '" + id
                    + "' (see /eclipse cutscene list)"));
            return 0;
        }
        if (!CutsceneService.isEnabled(source.getServer(), path)) {
            source.sendFailure(Component.literal("Cutscene '" + id
                    + "' is disabled — /eclipse cutscene enable " + id + " first"));
            return 0;
        }
        Collection<ServerPlayer> targets = cutsceneTargets(source, selected);
        if (targets.isEmpty()) {
            source.sendFailure(Component.literal("No players online to play '" + id + "' for"));
            return 0;
        }
        int started = CutsceneService.play(id, targets);
        source.sendSuccess(() -> Component.literal("Playing cutscene '" + id + "' for " + started
                + " player(s): " + path.durationTicks() + " ticks + "
                + CutsceneService.WATCHDOG_MARGIN_TICKS + " watchdog"), false);
        return started;
    }

    private static int cutsceneAbort(CommandContext<CommandSourceStack> context,
            @Nullable Collection<ServerPlayer> selected) {
        CommandSourceStack source = context.getSource();
        int aborted = CutsceneService.abort(cutsceneTargets(source, selected));
        if (aborted == 0) {
            source.sendFailure(Component.literal("No active cutscene sessions among the targeted players"));
            return 0;
        }
        source.sendSuccess(() -> Component.literal("Aborted " + aborted
                + " cutscene session(s); players unfrozen"), false);
        return aborted;
    }

    private static int cutsceneList(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        Collection<CutscenePath> paths = CutscenePaths.all();
        if (paths.isEmpty()) {
            source.sendFailure(Component.literal("No cutscene paths loaded (config/eclipse/cutscenes/)"));
            return 0;
        }
        EclipseWorldState state = EclipseWorldState.get(source.getServer());
        source.sendSuccess(() -> Component.literal(paths.size()
                + " cutscene path(s) in config/eclipse/cutscenes:"), false);
        for (CutscenePath path : paths) {
            String line = " - " + path.id() + ": " + path.durationTicks() + " ticks, "
                    + path.keyframes().size() + " keyframes, anchor " + path.anchor()
                    + ", " + path.interpolation() + ", " + path.dimension()
                    + (path.allowSkip() ? ", skippable" : "")
                    + (!path.enabled() ? " [DISABLED in json]" : "")
                    + (state.isCutsceneDisabled(path.id()) ? " [DISABLED in world]" : "");
            source.sendSuccess(() -> Component.literal(line), false);
        }
        return paths.size();
    }

    private static int cutsceneSetDisabled(CommandContext<CommandSourceStack> context, boolean disabled) {
        CommandSourceStack source = context.getSource();
        String id = StringArgumentType.getString(context, "id");
        if (CutscenePaths.get(id) == null) {
            source.sendFailure(Component.literal("Unknown cutscene path '" + id + "'"));
            return 0;
        }
        boolean changed = EclipseWorldState.get(source.getServer()).setCutsceneDisabled(id, disabled);
        source.sendSuccess(() -> Component.literal("Cutscene '" + id + "' is now "
                + (disabled ? "DISABLED for this world (plays complete instantly)" : "enabled for this world")
                + (changed ? "" : " (unchanged)")), false);
        return changed ? 1 : 0;
    }

    private static int cutsceneSkipPolicy(CommandContext<CommandSourceStack> context, boolean allow) {
        CommandSourceStack source = context.getSource();
        String id = StringArgumentType.getString(context, "id");
        CutscenePath path = CutscenePaths.get(id);
        if (path == null) {
            source.sendFailure(Component.literal("Unknown cutscene path '" + id + "'"));
            return 0;
        }
        if (!CutscenePaths.save(path.withAllowSkip(allow))) {
            source.sendFailure(Component.literal("Failed to save '" + id + "' — see the server log"));
            return 0;
        }
        CutsceneService.syncLibraryToAll(source.getServer());
        source.sendSuccess(() -> Component.literal("Cutscene '" + id + "' skipping is now "
                + (allow ? "ALLOWED" : "DENIED") + " (saved + library re-synced)"), false);
        return 1;
    }

    private static int cutscenePreview(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer player = source.getPlayerOrException();
        String id = StringArgumentType.getString(context, "id");
        if (!CutsceneService.preview(id, player)) {
            source.sendFailure(Component.literal("Unknown cutscene path '" + id + "'"));
            return 0;
        }
        source.sendSuccess(() -> Component.literal("Previewing '" + id
                + "' (no freeze; Space requests a skip)"), false);
        return 1;
    }

    private static int cutsceneReloadPaths(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        CutscenePaths.reload();
        CutsceneService.syncLibraryToAll(source.getServer());
        int count = CutscenePaths.all().size();
        source.sendSuccess(() -> Component.literal("Cutscene path library reloaded: " + count
                + " path(s), re-synced to all clients"), false);
        return count;
    }

    private static int cutsceneExport(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        String id = StringArgumentType.getString(context, "id");
        CutscenePath path = CutscenePaths.get(id);
        if (path == null) {
            source.sendFailure(Component.literal("Unknown cutscene path '" + id + "'"));
            return 0;
        }
        source.sendSuccess(() -> Component.literal("config/eclipse/cutscenes/" + id + ".json:"), false);
        for (String line : path.toJsonString().split("\n")) {
            source.sendSuccess(() -> Component.literal(line), false);
        }
        return 1;
    }

    /** Captures the operator's eye position/yaw/pitch; {@code tArg < 0} = auto (last t + 0.1). */
    private static int cutsceneAddKeyframe(CommandContext<CommandSourceStack> context, double tArg)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer player = source.getPlayerOrException();
        String id = StringArgumentType.getString(context, "id");
        CutscenePath path = CutscenePaths.get(id);
        if (path == null) {
            source.sendFailure(Component.literal("Unknown cutscene path '" + id + "'"));
            return 0;
        }
        List<CutscenePath.Keyframe> keyframes = new ArrayList<>(path.keyframes());
        double t = tArg >= 0.0D ? tArg
                : keyframes.isEmpty() ? 0.0D
                        : Math.min(1.0D, keyframes.get(keyframes.size() - 1).t() + 0.1D);
        CutscenePath.Keyframe keyframe = new CutscenePath.Keyframe(t,
                player.getX(), player.getEyeY(), player.getZ(),
                player.getYRot(), player.getXRot(), 0.0F, 70.0F, "easeInOutCubic");
        keyframes.add(keyframe);
        keyframes.sort(Comparator.comparingDouble(CutscenePath.Keyframe::t));
        if (!CutscenePaths.save(path.withKeyframes(keyframes))) {
            source.sendFailure(Component.literal("Failed to save '" + id + "' — see the server log"));
            return 0;
        }
        CutsceneService.syncLibraryToAll(source.getServer());
        String line = String.format(Locale.ROOT,
                "Added keyframe #%d to '%s': t=%.2f pos %.1f %.1f %.1f yaw %.1f pitch %.1f%s",
                keyframes.indexOf(keyframe), id, t, player.getX(), player.getEyeY(), player.getZ(),
                player.getYRot(), player.getXRot(),
                path.isPlayerAnchored()
                        ? " — NOTE: player-anchored path, playback treats these as offsets"
                        : "");
        source.sendSuccess(() -> Component.literal(line), false);
        return keyframes.size();
    }

    private static int cutsceneRemoveKeyframe(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        String id = StringArgumentType.getString(context, "id");
        int index = IntegerArgumentType.getInteger(context, "index");
        CutscenePath path = CutscenePaths.get(id);
        if (path == null) {
            source.sendFailure(Component.literal("Unknown cutscene path '" + id + "'"));
            return 0;
        }
        if (index >= path.keyframes().size()) {
            source.sendFailure(Component.literal("Keyframe index " + index + " out of range (0-"
                    + (path.keyframes().size() - 1) + ")"));
            return 0;
        }
        if (path.keyframes().size() <= 2) {
            source.sendFailure(Component.literal("A path needs at least 2 keyframes — edit "
                    + "config/eclipse/cutscenes/" + id + ".json directly to rebuild it"));
            return 0;
        }
        List<CutscenePath.Keyframe> keyframes = new ArrayList<>(path.keyframes());
        CutscenePath.Keyframe removed = keyframes.remove(index);
        if (!CutscenePaths.save(path.withKeyframes(keyframes))) {
            source.sendFailure(Component.literal("Failed to save '" + id + "' — see the server log"));
            return 0;
        }
        CutsceneService.syncLibraryToAll(source.getServer());
        String line = String.format(Locale.ROOT, "Removed keyframe #%d (t=%.2f) from '%s' (%d left)",
                index, removed.t(), id, keyframes.size());
        source.sendSuccess(() -> Component.literal(line), false);
        return keyframes.size();
    }

    /** {@code edit <id> set roll|fov <v>} applies to the LAST keyframe (idea doc §3). */
    private static int cutsceneSetLastKeyframe(CommandContext<CommandSourceStack> context, String field) {
        CommandSourceStack source = context.getSource();
        String id = StringArgumentType.getString(context, "id");
        float value = FloatArgumentType.getFloat(context, "value");
        CutscenePath path = CutscenePaths.get(id);
        if (path == null) {
            source.sendFailure(Component.literal("Unknown cutscene path '" + id + "'"));
            return 0;
        }
        if (path.keyframes().isEmpty()) {
            source.sendFailure(Component.literal("'" + id + "' has no keyframes to edit"));
            return 0;
        }
        List<CutscenePath.Keyframe> keyframes = new ArrayList<>(path.keyframes());
        CutscenePath.Keyframe last = keyframes.get(keyframes.size() - 1);
        CutscenePath.Keyframe updated = "roll".equals(field)
                ? new CutscenePath.Keyframe(last.t(), last.x(), last.y(), last.z(),
                        last.yaw(), last.pitch(), value, last.fov(), last.easing())
                : new CutscenePath.Keyframe(last.t(), last.x(), last.y(), last.z(),
                        last.yaw(), last.pitch(), last.roll(), value, last.easing());
        keyframes.set(keyframes.size() - 1, updated);
        if (!CutscenePaths.save(path.withKeyframes(keyframes))) {
            source.sendFailure(Component.literal("Failed to save '" + id + "' — see the server log"));
            return 0;
        }
        CutsceneService.syncLibraryToAll(source.getServer());
        String line = String.format(Locale.ROOT, "Set %s=%.1f on the last keyframe (t=%.2f) of '%s'",
                field, value, last.t(), id);
        source.sendSuccess(() -> Component.literal(line), false);
        return 1;
    }

    // --- reload ---

    private static int reload(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        EclipseConfig.reload();
        CutscenePaths.reload();
        // Goals/unlocks may have changed; push the fresh day state to every client.
        EclipseWorldState state = EclipseWorldState.get(server);
        PacketDistributor.sendToAllPlayers(new S2CDayStatePayload(state.getDay(), state.getAltarLevel(),
                EclipseConfig.day(state.getDay()).goals()));
        // Edited milestones.json feeds the handbook Rewards tab live.
        PacketDistributor.sendToAllPlayers(S2CMilestonesPayload.current());
        // Same for the cutscene path library (edited JSONs apply immediately).
        CutsceneService.syncLibraryToAll(server);
        source.sendSuccess(() -> Component.literal("Eclipse config reloaded: "
                + EclipseConfig.days().size() + " days, " + EclipseConfig.milestones().size() + " milestones, "
                + EclipseConfig.modGate().gatedNamespaces().size() + " gated namespaces, "
                + EclipseConfig.antiCheat().blockedModIdSubstrings().size() + " anti-cheat entries, "
                + CutscenePaths.all().size() + " cutscene paths"), false);
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
                + " | Start event done: " + state.isStartEventDone()), false);
        source.sendSuccess(() -> Component.literal("Night event: " + state.getActiveNightEvent()
                + (EclipseWorldState.NIGHT_EVENT_NONE.equals(state.getActiveNightEvent())
                        ? "" : " (day " + state.getNightEventDay() + ")")
                + " | First pale night done: " + state.isFirstPaleNightDone()), false);
        source.sendSuccess(() -> Component.literal("Soft border: overworld ring r="
                + String.format(Locale.ROOT, "%.1f", dev.projecteclipse.eclipse.border.SoftBorder
                        .radius(server, DiscProfile.OVERWORLD))
                + ", nether ring r=" + String.format(Locale.ROOT, "%.1f",
                        dev.projecteclipse.eclipse.border.SoftBorder.radius(server, DiscProfile.NETHER))
                + " (0 = inactive) | fx range "
                + dev.projecteclipse.eclipse.border.SoftBorder.fxRange(server)
                + " | vanilla failsafe " + state.getBorderSize() + " blocks"), false);
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
