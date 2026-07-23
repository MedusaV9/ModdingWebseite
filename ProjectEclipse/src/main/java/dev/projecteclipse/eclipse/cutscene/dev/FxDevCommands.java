package dev.projecteclipse.eclipse.cutscene.dev;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.FloatArgumentType;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;
import com.mojang.brigadier.suggestion.SuggestionProvider;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.CutscenePath;
import dev.projecteclipse.eclipse.cutscene.CutscenePaths;
import dev.projecteclipse.eclipse.cutscene.CutsceneService;
import dev.projecteclipse.eclipse.cutscene.PathSampler;
import dev.projecteclipse.eclipse.cutscene.SequenceReplayable;
import dev.projecteclipse.eclipse.cutscene.ViewDistanceService;
import dev.projecteclipse.eclipse.devtools.dev.ClickAction;
import dev.projecteclipse.eclipse.devtools.dev.Danger;
import dev.projecteclipse.eclipse.devtools.dev.DevCategory;
import dev.projecteclipse.eclipse.devtools.dev.DevCommandDoc;
import dev.projecteclipse.eclipse.devtools.dev.DevCommandRegistry;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.network.fx.S2CStormStatePayload;
import dev.projecteclipse.eclipse.network.fx.S2CSupplyMarkerPayload;
import dev.projecteclipse.eclipse.network.fx.S2CViewDistancePayload;
import net.minecraft.ChatFormatting;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.commands.arguments.coordinates.Vec3Argument;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.phys.HitResult;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * {@code /eclipsefx} — the P2 dev/QA command tree (R12, permission 3). These are the replay
 * hooks P5 surfaces in the handbook (§6.4); docs register into {@code DevCommandRegistry}
 * from static init, the Brigadier root registers via an own {@link RegisterCommandsEvent}
 * subscriber ({@code EclipseCommands} and {@code DevRoot} stay untouched).
 *
 * <p>Leaves: {@code post <id> on|off|clear / post list} (Veil pipeline overrides),
 * {@code uniform <pipeline> <name> <float>}, {@code emitter <id> [x y z]},
 * {@code cutscene play|stop|preview <id>} ({@code play} = full GLOBAL_TELEPORT group play
 * with view-distance bump — the W2 acceptance path; {@code preview} = particle-traced
 * flight path, no camera), {@code sequence <id> <phase>} ({@link SequenceReplayable}
 * FX-only replays), {@code storm add|remove|bolt}, {@code rift <x y z> <width> / rift close},
 * {@code supplybeam test} (toggle), {@code sun debug} (HUD cross), {@code viewdist <n|reset>},
 * {@code caption <style> <key> [ticks]}. Client-only actions travel via
 * {@link FxDevPayloads}.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class FxDevCommands {
    /** View distance pushed by the global {@code cutscene play} test (R12 default). */
    private static final int PLAY_VIEW_DISTANCE_CHUNKS = 12;
    /** Storm id used by {@code storm add|remove} so repeated calls address the same storm. */
    private static final int DEV_STORM_ID = 990_001;
    /** Path-preview trace: one particle roughly every this many blocks of arc length. */
    private static final double PREVIEW_PARTICLES_PER_BLOCK = 2.0D;
    private static final int PREVIEW_MAX_POINTS = 600;

    /** Last {@code storm add} center per dimension (for {@code storm remove}). */
    private static final Map<ServerLevel, Vec3> DEV_STORM_CENTERS = new HashMap<>();
    /** Active {@code supplybeam test} marker per operator (toggle semantics). */
    private static final Map<UUID, BlockPos> TEST_BEAMS = new HashMap<>();
    /** Last {@code rift} open position per operator (for {@code rift close}). */
    private static final Map<UUID, Vec3> LAST_RIFTS = new HashMap<>();

    private static final SuggestionProvider<CommandSourceStack> PIPELINE_SUGGESTIONS =
            (context, builder) -> SharedSuggestionProvider.suggest(List.of(
                    "eclipse:world_grade", "eclipse:sun_halo", "eclipse:limbo", "eclipse:border_glitch",
                    "eclipse:shockwave", "eclipse:altar_aberration", "eclipse:storm_interior",
                    "eclipse:rift_glitch", "eclipse:ghost_grade"), builder);

    private static final SuggestionProvider<CommandSourceStack> EMITTER_SUGGESTIONS =
            (context, builder) -> SharedSuggestionProvider.suggest(List.of(
                    "eclipse:cutscene_veil", "eclipse:unlock_burst", "eclipse:heart_burst",
                    "eclipse:altar_beam", "eclipse:limbo_motes", "eclipse:map_expand_materialize",
                    "eclipse:border_glitch"), builder);

    private static final SuggestionProvider<CommandSourceStack> PATH_SUGGESTIONS =
            (context, builder) -> SharedSuggestionProvider.suggest(
                    CutscenePaths.rawJsonById().keySet(), builder);

    private static final SuggestionProvider<CommandSourceStack> SEQUENCE_SUGGESTIONS =
            (context, builder) -> SharedSuggestionProvider.suggest(
                    SequenceReplayable.Registry.ids(), builder);

    private static final SuggestionProvider<CommandSourceStack> PHASE_SUGGESTIONS =
            (context, builder) -> {
                String sequenceId = StringArgumentType.getString(context, "sequence");
                return SharedSuggestionProvider.suggest(
                        SequenceReplayable.Registry.byId(sequenceId)
                                .map(SequenceReplayable::phaseIds).orElse(List.of()), builder);
            };

    private static final SuggestionProvider<CommandSourceStack> CAPTION_KEY_SUGGESTIONS =
            (context, builder) -> SharedSuggestionProvider.suggest(List.of(
                    "eclipse.caption.finale.dawn", "eclipse.caption.finale.home",
                    "eclipse.caption.demo.title", "eclipse.caption.demo.whisper"), builder);

    static {
        registerDocs();
    }

    private FxDevCommands() {}

    // ------------------------------------------------------------------ registration

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("eclipsefx")
                .requires(source -> source.hasPermission(3))
                .then(Commands.literal("post")
                        .then(Commands.literal("list").executes(FxDevCommands::postList))
                        .then(Commands.argument("pipeline", StringArgumentType.string())
                                .suggests(PIPELINE_SUGGESTIONS)
                                .then(Commands.literal("on").executes(ctx -> post(ctx, FxDevPayloads.ACTION_POST_ON)))
                                .then(Commands.literal("off").executes(ctx -> post(ctx, FxDevPayloads.ACTION_POST_OFF)))
                                .then(Commands.literal("clear").executes(ctx -> post(ctx, FxDevPayloads.ACTION_POST_CLEAR)))))
                .then(Commands.literal("uniform")
                        .then(Commands.argument("pipeline", StringArgumentType.string())
                                .suggests(PIPELINE_SUGGESTIONS)
                                .then(Commands.argument("name", StringArgumentType.string())
                                        .then(Commands.argument("value", FloatArgumentType.floatArg())
                                                .executes(FxDevCommands::uniform)))))
                .then(Commands.literal("emitter")
                        .then(Commands.argument("id", StringArgumentType.string())
                                .suggests(EMITTER_SUGGESTIONS)
                                .executes(ctx -> emitter(ctx, null))
                                .then(Commands.argument("pos", Vec3Argument.vec3())
                                        .executes(ctx -> emitter(ctx, Vec3Argument.getVec3(ctx, "pos"))))))
                .then(Commands.literal("cutscene")
                        .then(Commands.literal("play")
                                .then(Commands.argument("id", StringArgumentType.string())
                                        .suggests(PATH_SUGGESTIONS)
                                        .executes(FxDevCommands::cutscenePlay)))
                        .then(Commands.literal("stop").executes(FxDevCommands::cutsceneStop))
                        .then(Commands.literal("preview")
                                .then(Commands.argument("id", StringArgumentType.string())
                                        .suggests(PATH_SUGGESTIONS)
                                        .executes(FxDevCommands::cutscenePreview))))
                .then(Commands.literal("sequence")
                        .then(Commands.argument("sequence", StringArgumentType.string())
                                .suggests(SEQUENCE_SUGGESTIONS)
                                .then(Commands.argument("phase", StringArgumentType.string())
                                        .suggests(PHASE_SUGGESTIONS)
                                        .executes(FxDevCommands::sequenceReplay))))
                .then(Commands.literal("storm")
                        .then(Commands.literal("add")
                                .executes(ctx -> stormAdd(ctx, 22.0F, 48.0F, S2CStormStatePayload.TYPE_VORTEX))
                                .then(Commands.argument("radius", FloatArgumentType.floatArg(4.0F, 128.0F))
                                        .then(Commands.argument("height", FloatArgumentType.floatArg(8.0F, 256.0F))
                                                .then(Commands.literal("wall").executes(ctx -> stormAdd(ctx,
                                                        FloatArgumentType.getFloat(ctx, "radius"),
                                                        FloatArgumentType.getFloat(ctx, "height"),
                                                        S2CStormStatePayload.TYPE_WALL)))
                                                .then(Commands.literal("vortex").executes(ctx -> stormAdd(ctx,
                                                        FloatArgumentType.getFloat(ctx, "radius"),
                                                        FloatArgumentType.getFloat(ctx, "height"),
                                                        S2CStormStatePayload.TYPE_VORTEX))))))
                        .then(Commands.literal("remove").executes(FxDevCommands::stormRemove))
                        .then(Commands.literal("bolt")
                                .executes(ctx -> stormBolt(ctx, 1.0F))
                                .then(Commands.argument("intensity", FloatArgumentType.floatArg(0.0F, 1.0F))
                                        .executes(ctx -> stormBolt(ctx, FloatArgumentType.getFloat(ctx, "intensity"))))))
                .then(Commands.literal("rift")
                        .then(Commands.literal("close").executes(FxDevCommands::riftClose))
                        .then(Commands.argument("pos", Vec3Argument.vec3())
                                .then(Commands.argument("width", FloatArgumentType.floatArg(0.5F, 64.0F))
                                        .executes(FxDevCommands::riftOpen))))
                .then(Commands.literal("supplybeam")
                        .then(Commands.literal("test").executes(FxDevCommands::supplyBeamTest)))
                .then(Commands.literal("sun")
                        .then(Commands.literal("debug").executes(FxDevCommands::sunDebug)))
                .then(Commands.literal("viewdist")
                        .then(Commands.literal("reset").executes(FxDevCommands::viewDistReset))
                        .then(Commands.argument("chunks", IntegerArgumentType.integer(2, 32))
                                .executes(FxDevCommands::viewDistSet)))
                .then(Commands.literal("caption")
                        .then(captionStyle("subtitle", S2CCaptionPayload.STYLE_SUBTITLE))
                        .then(captionStyle("title", S2CCaptionPayload.STYLE_TITLE))
                        .then(captionStyle("whisper", S2CCaptionPayload.STYLE_WHISPER))));
    }

    private static com.mojang.brigadier.builder.LiteralArgumentBuilder<CommandSourceStack> captionStyle(
            String literal, int style) {
        return Commands.literal(literal)
                .then(Commands.argument("key", StringArgumentType.string())
                        .suggests(CAPTION_KEY_SUGGESTIONS)
                        .executes(ctx -> caption(ctx, style, 80))
                        .then(Commands.argument("ticks", IntegerArgumentType.integer(10, 1200))
                                .executes(ctx -> caption(ctx, style,
                                        IntegerArgumentType.getInteger(ctx, "ticks")))));
    }

    // ------------------------------------------------------------------ client-bridged leaves

    private static int post(CommandContext<CommandSourceStack> ctx, int action) throws CommandSyntaxException {
        ServerPlayer player = ctx.getSource().getPlayerOrException();
        String pipeline = StringArgumentType.getString(ctx, "pipeline");
        FxDevPayloads.sendAction(player, action, pipeline, Vec3.ZERO, 0.0F);
        reply(ctx, "post " + pipeline + " → sent to your client (feedback in chat)");
        return 1;
    }

    private static int postList(CommandContext<CommandSourceStack> ctx) throws CommandSyntaxException {
        ServerPlayer player = ctx.getSource().getPlayerOrException();
        FxDevPayloads.sendAction(player, FxDevPayloads.ACTION_POST_LIST, "", Vec3.ZERO, 0.0F);
        return 1;
    }

    private static int uniform(CommandContext<CommandSourceStack> ctx) throws CommandSyntaxException {
        ServerPlayer player = ctx.getSource().getPlayerOrException();
        String pipeline = StringArgumentType.getString(ctx, "pipeline");
        String name = StringArgumentType.getString(ctx, "name");
        float value = FloatArgumentType.getFloat(ctx, "value");
        FxDevPayloads.sendAction(player, FxDevPayloads.ACTION_UNIFORM, pipeline + "|" + name, Vec3.ZERO, value);
        reply(ctx, "uniform " + pipeline + " " + name + " = " + value + " → sent to your client");
        return 1;
    }

    private static int emitter(CommandContext<CommandSourceStack> ctx, Vec3 posOrNull) throws CommandSyntaxException {
        ServerPlayer player = ctx.getSource().getPlayerOrException();
        String id = StringArgumentType.getString(ctx, "id");
        Vec3 pos = posOrNull != null ? posOrNull : player.position();
        FxDevPayloads.sendAction(player, FxDevPayloads.ACTION_EMITTER, id, pos, 0.0F);
        reply(ctx, "emitter " + id + " → spawning on your client at "
                + String.format(Locale.ROOT, "%.1f %.1f %.1f", pos.x, pos.y, pos.z));
        return 1;
    }

    private static int sunDebug(CommandContext<CommandSourceStack> ctx) throws CommandSyntaxException {
        ServerPlayer player = ctx.getSource().getPlayerOrException();
        FxDevPayloads.sendAction(player, FxDevPayloads.ACTION_SUN_DEBUG, "", Vec3.ZERO, 0.0F);
        reply(ctx, "sun debug HUD toggled on your client");
        return 1;
    }

    // ------------------------------------------------------------------ cutscene leaves

    private static int cutscenePlay(CommandContext<CommandSourceStack> ctx) {
        String id = StringArgumentType.getString(ctx, "id");
        List<ServerPlayer> players = new ArrayList<>(ctx.getSource().getServer().getPlayerList().getPlayers());
        int started = CutsceneService.play(id, players, null, null,
                CutsceneService.PlayOptions.global(PLAY_VIEW_DISTANCE_CHUNKS));
        if (started == 0) {
            ctx.getSource().sendFailure(Component.literal("Cutscene '" + id + "' did not start (unknown/disabled/no players)"));
            return 0;
        }
        reply(ctx, "playing '" + id + "' for " + started
                + " player(s) — GLOBAL_TELEPORT, view distance " + PLAY_VIEW_DISTANCE_CHUNKS + ", return after");
        return started;
    }

    private static int cutsceneStop(CommandContext<CommandSourceStack> ctx) {
        int aborted = CutsceneService.abort(ctx.getSource().getServer().getPlayerList().getPlayers());
        reply(ctx, "aborted " + aborted + " active cutscene session(s)");
        return aborted;
    }

    /**
     * Particle-traced flight path: END_ROD dust along the arc-length-uniform spline (so
     * clustering would reveal a reparameterization bug), soul-fire markers at keyframes.
     * Player-anchored paths trace relative to the operator.
     */
    private static int cutscenePreview(CommandContext<CommandSourceStack> ctx) throws CommandSyntaxException {
        ServerPlayer player = ctx.getSource().getPlayerOrException();
        String id = StringArgumentType.getString(ctx, "id");
        CutscenePath path = CutscenePaths.get(id);
        if (path == null) {
            ctx.getSource().sendFailure(Component.literal("Unknown cutscene path '" + id + "'"));
            return 0;
        }
        if (path.keyframes().size() < 2) {
            ctx.getSource().sendFailure(Component.literal("Path '" + id + "' has fewer than 2 keyframes"));
            return 0;
        }
        ServerLevel level = player.serverLevel();
        boolean playerAnchored = path.isPlayerAnchored();
        Vec3 anchorPos = playerAnchored ? player.position() : Vec3.ZERO;
        float anchorYaw = playerAnchored ? player.getYRot() : 0.0F;

        PathSampler sampler = PathSampler.of(path);
        int points = (int) Math.min(PREVIEW_MAX_POINTS,
                Math.max(64, Math.round(sampler.totalLength() * PREVIEW_PARTICLES_PER_BLOCK)));
        for (int i = 0; i <= points; i++) {
            Vec3 local = sampler.positionAtPathFraction(i / (double) points);
            Vec3 world = PathSampler.toWorld(local, anchorPos, anchorYaw);
            level.sendParticles(player, ParticleTypes.END_ROD, true,
                    world.x, world.y, world.z, 1, 0.0D, 0.0D, 0.0D, 0.0D);
        }
        for (CutscenePath.Keyframe kf : path.keyframes()) {
            Vec3 world = PathSampler.toWorld(new Vec3(kf.x(), kf.y(), kf.z()), anchorPos, anchorYaw);
            level.sendParticles(player, ParticleTypes.SOUL_FIRE_FLAME, true,
                    world.x, world.y, world.z, 5, 0.05D, 0.05D, 0.05D, 0.0D);
        }
        reply(ctx, "traced '" + id + "' — " + (points + 1) + " points over "
                + String.format(Locale.ROOT, "%.1f", sampler.totalLength()) + " blocks ("
                + path.keyframes().size() + " keyframes, "
                + (playerAnchored ? "relative to you" : "world coordinates") + ")");
        return 1;
    }

    private static int sequenceReplay(CommandContext<CommandSourceStack> ctx) {
        String sequenceId = StringArgumentType.getString(ctx, "sequence");
        String phaseId = StringArgumentType.getString(ctx, "phase").toUpperCase(Locale.ROOT);
        var sequence = SequenceReplayable.Registry.byId(sequenceId).orElse(null);
        if (sequence == null) {
            ctx.getSource().sendFailure(Component.literal("No replayable sequence '" + sequenceId
                    + "' registered (available: " + String.join(", ", SequenceReplayable.Registry.ids())
                    + ") — W6/W7 register theirs at merge"));
            return 0;
        }
        List<ServerPlayer> players = new ArrayList<>(ctx.getSource().getServer().getPlayerList().getPlayers());
        boolean ok = sequence.replay(ctx.getSource().getServer(), phaseId, players);
        if (!ok) {
            ctx.getSource().sendFailure(Component.literal("Replay '" + sequenceId + " " + phaseId
                    + "' refused (phases: " + String.join(", ", sequence.phaseIds()) + ")"));
            return 0;
        }
        reply(ctx, "replaying " + sequenceId + " " + phaseId + " (FX-only) for " + players.size() + " player(s)");
        return 1;
    }

    // ------------------------------------------------------------------ payload-driven leaves

    private static int stormAdd(CommandContext<CommandSourceStack> ctx, float radius, float height,
            int stormType) throws CommandSyntaxException {
        ServerPlayer player = ctx.getSource().getPlayerOrException();
        ServerLevel level = player.serverLevel();
        Vec3 center = player.position();
        DEV_STORM_CENTERS.put(level, center);
        PacketDistributor.sendToPlayersInDimension(level, new S2CStormStatePayload(
                DEV_STORM_ID, center, radius, height, stormType, S2CStormStatePayload.STATE_SPAWN, 80));
        reply(ctx, "dev storm " + (stormType == S2CStormStatePayload.TYPE_VORTEX ? "VORTEX" : "WALL")
                + " r=" + radius + " h=" + height + " spawning at your position (id " + DEV_STORM_ID + ")");
        return 1;
    }

    private static int stormRemove(CommandContext<CommandSourceStack> ctx) throws CommandSyntaxException {
        ServerPlayer player = ctx.getSource().getPlayerOrException();
        ServerLevel level = player.serverLevel();
        Vec3 center = DEV_STORM_CENTERS.getOrDefault(level, player.position());
        PacketDistributor.sendToPlayersInDimension(level, new S2CStormStatePayload(
                DEV_STORM_ID, center, 22.0F, 48.0F, S2CStormStatePayload.TYPE_VORTEX,
                S2CStormStatePayload.STATE_DISSIPATE, 60));
        reply(ctx, "dev storm dissipating (id " + DEV_STORM_ID + ")");
        return 1;
    }

    private static int stormBolt(CommandContext<CommandSourceStack> ctx, float intensity) throws CommandSyntaxException {
        ServerPlayer player = ctx.getSource().getPlayerOrException();
        HitResult hit = player.pick(96.0D, 1.0F, false);
        Vec3 target = hit.getType() != HitResult.Type.MISS ? hit.getLocation()
                : player.position().add(player.getLookAngle().scale(24.0D));
        FxPayloads.sendFxEvent(player.serverLevel(), FxPayloads.FX_LIGHTNING_STRIKE, target,
                intensity, intensity >= 0.99F ? 1.0F : 0.0F, -1.0D);
        reply(ctx, String.format(Locale.ROOT, "bolt → %.1f %.1f %.1f (intensity %.2f%s)",
                target.x, target.y, target.z, intensity, intensity >= 0.99F ? ", GIANT" : ""));
        return 1;
    }

    private static int riftOpen(CommandContext<CommandSourceStack> ctx) throws CommandSyntaxException {
        ServerPlayer player = ctx.getSource().getPlayerOrException();
        Vec3 pos = Vec3Argument.getVec3(ctx, "pos");
        float width = FloatArgumentType.getFloat(ctx, "width");
        LAST_RIFTS.put(player.getUUID(), pos);
        FxPayloads.sendFxEvent(player.serverLevel(), FxPayloads.FX_RIFT_OPEN, pos, width, 0.0F, -1.0D);
        reply(ctx, String.format(Locale.ROOT, "rift open at %.1f %.1f %.1f, width %.1f — '/eclipsefx rift close' closes it",
                pos.x, pos.y, pos.z, width));
        return 1;
    }

    private static int riftClose(CommandContext<CommandSourceStack> ctx) throws CommandSyntaxException {
        ServerPlayer player = ctx.getSource().getPlayerOrException();
        Vec3 pos = LAST_RIFTS.remove(player.getUUID());
        if (pos == null) {
            ctx.getSource().sendFailure(Component.literal("No rift opened by you to close"));
            return 0;
        }
        FxPayloads.sendFxEvent(player.serverLevel(), FxPayloads.FX_RIFT_CLOSE, pos, 0.0F, 0.0F, -1.0D);
        reply(ctx, "rift closing");
        return 1;
    }

    private static int supplyBeamTest(CommandContext<CommandSourceStack> ctx) throws CommandSyntaxException {
        ServerPlayer player = ctx.getSource().getPlayerOrException();
        BlockPos existing = TEST_BEAMS.remove(player.getUUID());
        if (existing != null) {
            PacketDistributor.sendToPlayersInDimension(player.serverLevel(),
                    new S2CSupplyMarkerPayload(false, existing, 30));
            reply(ctx, "test supply beam at " + existing.toShortString() + " removed (30-tick fade)");
            return 1;
        }
        BlockPos pos = player.blockPosition();
        TEST_BEAMS.put(player.getUUID(), pos);
        PacketDistributor.sendToPlayersInDimension(player.serverLevel(),
                new S2CSupplyMarkerPayload(true, pos, 0));
        reply(ctx, "test supply beam ADD at " + pos.toShortString() + " — run again to remove");
        return 1;
    }

    private static int viewDistSet(CommandContext<CommandSourceStack> ctx) throws CommandSyntaxException {
        ServerPlayer player = ctx.getSource().getPlayerOrException();
        int chunks = IntegerArgumentType.getInteger(ctx, "chunks");
        PacketDistributor.sendToPlayer(player, new S2CViewDistancePayload(chunks));
        reply(ctx, "pushed view distance " + chunks
                + " to your client (honored only while cinematicViewDistance is ON)");
        return 1;
    }

    private static int viewDistReset(CommandContext<CommandSourceStack> ctx) throws CommandSyntaxException {
        ServerPlayer player = ctx.getSource().getPlayerOrException();
        ViewDistanceService.reset(ctx.getSource().getServer());
        PacketDistributor.sendToPlayer(player, new S2CViewDistancePayload(0));
        reply(ctx, "view distance reset (server bump + your client restore)");
        return 1;
    }

    private static int caption(CommandContext<CommandSourceStack> ctx, int style, int ticks)
            throws CommandSyntaxException {
        ServerPlayer player = ctx.getSource().getPlayerOrException();
        String key = StringArgumentType.getString(ctx, "key");
        PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(key, ticks, style));
        reply(ctx, "caption style " + style + " '" + key + "' for " + ticks + " ticks");
        return 1;
    }

    private static void reply(CommandContext<CommandSourceStack> ctx, String message) {
        ctx.getSource().sendSuccess(() -> Component.literal("[eclipsefx] ")
                .withStyle(ChatFormatting.DARK_PURPLE)
                .append(Component.literal(message).withStyle(ChatFormatting.GRAY)), false);
    }

    // ------------------------------------------------------------------ handbook docs

    private static void registerDocs() {
        DevCommandRegistry.register(
                doc("fx.post", "/eclipsefx post", "dev.eclipse.doc.fx.post", Danger.SAFE, ClickAction.SUGGEST),
                doc("fx.uniform", "/eclipsefx uniform", "dev.eclipse.doc.fx.uniform", Danger.SAFE, ClickAction.SUGGEST),
                doc("fx.emitter", "/eclipsefx emitter", "dev.eclipse.doc.fx.emitter", Danger.SAFE, ClickAction.SUGGEST),
                doc("fx.cutscene.play", "/eclipsefx cutscene play", "dev.eclipse.doc.fx.cutscene.play",
                        Danger.CAUTION, ClickAction.SUGGEST),
                doc("fx.cutscene.stop", "/eclipsefx cutscene stop", "dev.eclipse.doc.fx.cutscene.stop",
                        Danger.SAFE, ClickAction.RUN),
                doc("fx.cutscene.preview", "/eclipsefx cutscene preview", "dev.eclipse.doc.fx.cutscene.preview",
                        Danger.SAFE, ClickAction.SUGGEST),
                doc("fx.sequence", "/eclipsefx sequence", "dev.eclipse.doc.fx.sequence", Danger.CAUTION,
                        ClickAction.SUGGEST),
                doc("fx.storm", "/eclipsefx storm", "dev.eclipse.doc.fx.storm", Danger.SAFE, ClickAction.SUGGEST),
                doc("fx.rift", "/eclipsefx rift", "dev.eclipse.doc.fx.rift", Danger.SAFE, ClickAction.SUGGEST),
                doc("fx.supplybeam", "/eclipsefx supplybeam test", "dev.eclipse.doc.fx.supplybeam",
                        Danger.SAFE, ClickAction.RUN),
                doc("fx.sun.debug", "/eclipsefx sun debug", "dev.eclipse.doc.fx.sun.debug",
                        Danger.SAFE, ClickAction.RUN),
                doc("fx.viewdist", "/eclipsefx viewdist", "dev.eclipse.doc.fx.viewdist",
                        Danger.CAUTION, ClickAction.SUGGEST),
                doc("fx.caption", "/eclipsefx caption", "dev.eclipse.doc.fx.caption",
                        Danger.SAFE, ClickAction.SUGGEST));
    }

    private static DevCommandDoc doc(String id, String syntax, String descKey, Danger danger, ClickAction click) {
        return new DevCommandDoc(id, DevCategory.CUTSCENE, syntax, descKey, danger, click, 3);
    }
}
