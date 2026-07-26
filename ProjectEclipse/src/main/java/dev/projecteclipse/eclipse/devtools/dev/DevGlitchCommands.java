package dev.projecteclipse.eclipse.devtools.dev;

import java.util.Locale;
import java.util.UUID;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.DoubleArgumentType;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;
import com.mojang.brigadier.suggestion.SuggestionProvider;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.glitchzone.AltarGlitchAmbience;
import dev.projecteclipse.eclipse.glitchzone.GlitchColors;
import dev.projecteclipse.eclipse.glitchzone.GlitchZone;
import dev.projecteclipse.eclipse.glitchzone.GlitchZoneEffects;
import dev.projecteclipse.eclipse.glitchzone.GlitchZoneService;
import dev.projecteclipse.eclipse.glitchzone.GlitchZoneState;
import dev.projecteclipse.eclipse.lang.ServerLang;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.commands.arguments.UuidArgument;
import net.minecraft.commands.arguments.coordinates.Vec3Argument;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev glitch …} — operator control over GLITCHZONE areas (the silent, unannounced
 * glitch event; perm 2). Zones persist in {@code glitchzone.GlitchZoneState} and tick in
 * {@code glitchzone.GlitchZoneService}; nothing here messages regular players — the event
 * stays silent, only operators get feedback/audit lines.
 *
 * <ul>
 *   <li>{@code add <effect> <radius> <durationSeconds> [x y z] [fadeTicks] [colour]} —
 *       spawns a zone (defaults: the executing player's position + dimension, 40-tick
 *       fade-out, the effect's shipped accent colour).</li>
 *   <li>{@code remove <id>} / {@code clear} — drop one zone (ids are suggested) / all.</li>
 *   <li>{@code color <id> <colour>} — repaint a LIVE zone; the client slides the accent.</li>
 *   <li>{@code list} — id, effect, colour, dimension, centre, radius and remaining seconds.</li>
 *   <li>{@code test <effect> [seconds]} — full-strength self-test on the caller only
 *       (default {@value #DEFAULT_TEST_SECONDS}&nbsp;s), through the regular sync path.</li>
 *   <li>{@code altar [status]} — fire (or inspect the schedule of) the ambient altar glitch
 *       from F-048: a purple {@code void} zone on the sanctum altar whose sonar impulse
 *       radiates from the altar block.</li>
 * </ul>
 *
 * <p><b>Colour syntax (F-049)</b>: every {@code <effect>} argument also accepts the suffix
 * form {@code <effect>_<colour>} ({@code void_purple}, {@code outline_cyan}) — both bare ids
 * and all pairs are suggested. {@code add} additionally takes an explicit trailing
 * {@code [colour]} argument; when both are given the explicit argument wins.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevGlitchCommands {
    /** Default fade-out window of a new zone (2 s; fade-in is always client-eased). */
    private static final int DEFAULT_FADE_TICKS = 40;
    private static final int DEFAULT_TEST_SECONDS = 10;

    /** Bare effect ids plus every {@code <effect>_<colour>} pair (Brigadier prefix-filters). */
    private static final SuggestionProvider<CommandSourceStack> EFFECT_SUGGESTIONS =
            (context, builder) -> SharedSuggestionProvider.suggest(GlitchColors.effectSuggestions(), builder);

    private static final SuggestionProvider<CommandSourceStack> COLOUR_SUGGESTIONS =
            (context, builder) -> SharedSuggestionProvider.suggest(GlitchColors.IDS, builder);

    private static final SuggestionProvider<CommandSourceStack> ZONE_ID_SUGGESTIONS =
            (context, builder) -> SharedSuggestionProvider.suggest(
                    GlitchZoneState.get(context.getSource().getServer()).all().stream()
                            .map(zone -> zone.id().toString()),
                    builder);

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("glitch.add", DevCategory.EVENT,
                        "/dev glitch add <effect> <radius> <durationSeconds> [x y z] [fadeTicks] [colour]",
                        "dev.eclipse.doc.glitch.add", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("glitch.remove", DevCategory.EVENT, "/dev glitch remove <id>",
                        "dev.eclipse.doc.glitch.remove", Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("glitch.color", DevCategory.EVENT, "/dev glitch color <id> <colour>",
                        "dev.eclipse.doc.glitch.color", Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("glitch.clear", DevCategory.EVENT, "/dev glitch clear",
                        "dev.eclipse.doc.glitch.clear", Danger.CAUTION, ClickAction.RUN, 2),
                new DevCommandDoc("glitch.list", DevCategory.EVENT, "/dev glitch list",
                        "dev.eclipse.doc.glitch.list", Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("glitch.test", DevCategory.EVENT, "/dev glitch test <effect> [seconds]",
                        "dev.eclipse.doc.glitch.test", Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("glitch.altar", DevCategory.EVENT, "/dev glitch altar [status]",
                        "dev.eclipse.doc.glitch.altar", Danger.SAFE, ClickAction.RUN, 2));
    }

    private DevGlitchCommands() {}

    @SubscribeEvent
    static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(DevRoot::canUseDev)
                .then(Commands.literal("glitch")
                        .then(Commands.literal("add")
                                .then(Commands.argument("effect", StringArgumentType.word())
                                        .suggests(EFFECT_SUGGESTIONS)
                                        .then(Commands.argument("radius", DoubleArgumentType.doubleArg(1.0D, 512.0D))
                                                .then(Commands.argument("durationSeconds", IntegerArgumentType.integer(1, 86_400))
                                                        .executes(ctx -> add(ctx, null, DEFAULT_FADE_TICKS, null))
                                                        .then(Commands.argument("pos", Vec3Argument.vec3())
                                                                .executes(ctx -> add(ctx,
                                                                        Vec3Argument.getVec3(ctx, "pos"), DEFAULT_FADE_TICKS, null))
                                                                .then(Commands.argument("fadeTicks", IntegerArgumentType.integer(0, 1_200))
                                                                        .executes(ctx -> add(ctx,
                                                                                Vec3Argument.getVec3(ctx, "pos"),
                                                                                IntegerArgumentType.getInteger(ctx, "fadeTicks"), null))
                                                                        .then(Commands.argument("colour", StringArgumentType.word())
                                                                                .suggests(COLOUR_SUGGESTIONS)
                                                                                .executes(ctx -> add(ctx,
                                                                                        Vec3Argument.getVec3(ctx, "pos"),
                                                                                        IntegerArgumentType.getInteger(ctx, "fadeTicks"),
                                                                                        StringArgumentType.getString(ctx, "colour"))))))))))
                        .then(Commands.literal("remove")
                                .then(Commands.argument("id", UuidArgument.uuid())
                                        .suggests(ZONE_ID_SUGGESTIONS)
                                        .executes(DevGlitchCommands::remove)))
                        .then(Commands.literal("color")
                                .then(Commands.argument("id", UuidArgument.uuid())
                                        .suggests(ZONE_ID_SUGGESTIONS)
                                        .then(Commands.argument("colour", StringArgumentType.word())
                                                .suggests(COLOUR_SUGGESTIONS)
                                                .executes(DevGlitchCommands::color))))
                        .then(Commands.literal("clear")
                                .executes(DevGlitchCommands::clear))
                        .then(Commands.literal("list")
                                .executes(DevGlitchCommands::list))
                        .then(Commands.literal("test")
                                .then(Commands.argument("effect", StringArgumentType.word())
                                        .suggests(EFFECT_SUGGESTIONS)
                                        .executes(ctx -> test(ctx, DEFAULT_TEST_SECONDS))
                                        .then(Commands.argument("seconds", IntegerArgumentType.integer(1, 300))
                                                .executes(ctx -> test(ctx,
                                                        IntegerArgumentType.getInteger(ctx, "seconds"))))))
                        .then(Commands.literal("altar")
                                .executes(DevGlitchCommands::altarFire)
                                .then(Commands.literal("status")
                                        .executes(DevGlitchCommands::altarStatus)))));
    }

    private static int add(CommandContext<CommandSourceStack> context,
            @javax.annotation.Nullable Vec3 posOrNull, int fadeTicks,
            @javax.annotation.Nullable String colourArg) throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        String token = StringArgumentType.getString(context, "effect");
        String[] parsed = GlitchColors.split(token);
        String effect = parsed[0];
        if (!GlitchZoneEffects.isValid(effect)) {
            source.sendFailure(Component.translatable("dev.eclipse.glitch.unknown_effect",
                    token, String.join(", ", GlitchZoneEffects.IDS)));
            return 0;
        }
        // Explicit argument beats the suffix; both are normalized, so a typo degrades to the
        // effect's shipped accent rather than failing the command.
        String colour = colourArg != null ? GlitchColors.normalize(colourArg) : parsed[1];
        if (colourArg != null && colour.isEmpty()) {
            source.sendFailure(Component.translatable("dev.eclipse.glitch.unknown_colour",
                    colourArg, String.join(", ", GlitchColors.IDS)));
            return 0;
        }
        double radius = DoubleArgumentType.getDouble(context, "radius");
        int seconds = IntegerArgumentType.getInteger(context, "durationSeconds");
        // Default anchor: the executing player (console must pass explicit coordinates).
        BlockPos centre = posOrNull != null ? BlockPos.containing(posOrNull)
                : source.getPlayerOrException().blockPosition();
        long now = source.getServer().overworld().getGameTime();

        GlitchZone zone = new GlitchZone(UUID.randomUUID(), source.getLevel().dimension(),
                centre, radius, effect, colour, now, now + seconds * 20L, 0, fadeTicks, false);
        if (!GlitchZoneState.get(source.getServer()).add(zone)) {
            source.sendFailure(Component.translatable("dev.eclipse.glitch.limit",
                    GlitchZoneState.MAX_ZONES));
            return 0;
        }
        Component feedback = Component.translatable("dev.eclipse.glitch.added",
                describe(effect, colour), formatBlocks(radius), seconds,
                centre.getX(), centre.getY(), centre.getZ(), zone.id().toString());
        audit(source, feedback, String.format(Locale.ROOT,
                "glitch add %s r=%.1f %ds @ %s %s fade=%d id=%s", describe(effect, colour), radius, seconds,
                source.getLevel().dimension().location(), centre.toShortString(), fadeTicks, zone.id()));
        return 1;
    }

    private static int remove(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        UUID id = UuidArgument.getUuid(context, "id");
        if (!GlitchZoneState.get(source.getServer()).remove(id)) {
            source.sendFailure(Component.translatable("dev.eclipse.glitch.remove_missing", id.toString()));
            return 0;
        }
        audit(source, Component.translatable("dev.eclipse.glitch.removed", id.toString()),
                "glitch remove " + id);
        return 1;
    }

    /** Repaints a live zone: the accent cross-fades on every client inside it. */
    private static int color(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        UUID id = UuidArgument.getUuid(context, "id");
        String raw = StringArgumentType.getString(context, "colour");
        String colour = GlitchColors.normalize(raw);
        if (colour.isEmpty() && !raw.equalsIgnoreCase("default")) {
            source.sendFailure(Component.translatable("dev.eclipse.glitch.unknown_colour",
                    raw, String.join(", ", GlitchColors.IDS)));
            return 0;
        }
        if (!GlitchZoneState.get(source.getServer()).recolour(id, colour)) {
            source.sendFailure(Component.translatable("dev.eclipse.glitch.remove_missing", id.toString()));
            return 0;
        }
        audit(source, Component.translatable("dev.eclipse.glitch.recoloured",
                        id.toString(), colour.isEmpty() ? "default" : colour),
                "glitch color " + id + " " + (colour.isEmpty() ? "default" : colour));
        return 1;
    }

    private static int clear(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        int count = GlitchZoneState.get(source.getServer()).clear();
        audit(source, Component.translatable("dev.eclipse.glitch.cleared", count),
                "glitch clear (" + count + " zones)");
        return count;
    }

    private static int list(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        var zones = GlitchZoneState.get(source.getServer()).all();
        if (zones.isEmpty()) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.glitch.list.empty"), false);
            return 0;
        }
        long now = source.getServer().overworld().getGameTime();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.glitch.list.header", zones.size()), false);
        for (GlitchZone zone : zones) {
            long remainingSeconds = Math.max(0L, (zone.endGameTime() - now) / 20L);
            source.sendSuccess(() -> Component.translatable("dev.eclipse.glitch.list.entry",
                    describe(zone.effect(), zone.colour()), formatBlocks(zone.radius()),
                    zone.dim().location().toString(), zone.centre().toShortString(),
                    remainingSeconds, zone.id().toString()), false);
        }
        return zones.size();
    }

    /** Personal self-test through the regular service/sync path (no audit — caller-only). */
    private static int test(CommandContext<CommandSourceStack> context, int seconds)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        String token = StringArgumentType.getString(context, "effect");
        String[] parsed = GlitchColors.split(token);
        String effect = parsed[0];
        if (!GlitchZoneEffects.isValid(effect)) {
            source.sendFailure(Component.translatable("dev.eclipse.glitch.unknown_effect",
                    token, String.join(", ", GlitchZoneEffects.IDS)));
            return 0;
        }
        ServerPlayer player = source.getPlayerOrException();
        GlitchZoneService.startTest(player, effect, parsed[1], seconds);
        source.sendSuccess(() -> Component.translatable("dev.eclipse.glitch.test.started",
                describe(effect, parsed[1]), seconds), false);
        return 1;
    }

    /** F-048: fires the ambient altar glitch NOW (skips the cadence, not the world checks). */
    private static int altarFire(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        long now = source.getServer().overworld().getGameTime();
        GlitchZoneState state = GlitchZoneState.get(source.getServer());
        if (!AltarGlitchAmbience.fire(source.getServer(), state, now, true)) {
            source.sendFailure(Component.translatable("dev.eclipse.glitch.altar.unavailable"));
            return 0;
        }
        audit(source, Component.translatable("dev.eclipse.glitch.altar.fired",
                        AltarGlitchAmbience.COLOUR, AltarGlitchAmbience.EFFECT),
                "glitch altar (forced)");
        return 1;
    }

    private static int altarStatus(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        long now = source.getServer().overworld().getGameTime();
        GlitchZoneState state = GlitchZoneState.get(source.getServer());
        BlockPos altar = AltarGlitchAmbience.altarPos(source.getServer());
        if (altar == null) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.glitch.altar.no_altar"), false);
            return 0;
        }
        long seconds = AltarGlitchAmbience.ticksUntilNext(state, now) / 20L;
        source.sendSuccess(() -> Component.translatable("dev.eclipse.glitch.altar.status",
                altar.toShortString(), (int) AltarGlitchAmbience.TRIGGER_RANGE,
                seconds / 60L, seconds % 60L), false);
        return 1;
    }

    /** Operator-facing effect label: {@code void} or {@code void_purple}. */
    private static String describe(String effect, String colour) {
        return colour.isEmpty() ? effect : effect + "_" + colour;
    }

    private static String formatBlocks(double radius) {
        return String.format(Locale.ROOT, "%.1f", radius);
    }

    /** Same operator-audit convention as the other /dev command bridges. */
    private static void audit(CommandSourceStack source, Component feedback, String logDetail) {
        source.sendSuccess(() -> feedback, false);
        for (ServerPlayer operator : source.getServer().getPlayerList().getPlayers()) {
            if (operator.hasPermissions(2) && operator != source.getEntity()) {
                operator.sendSystemMessage(ServerLang.tr(operator, "dev.eclipse.audit",
                        source.getTextName(), feedback));
            }
        }
        EclipseMod.LOGGER.info("[DEV AUDIT] {} {}", source.getTextName(), logDetail);
    }
}
