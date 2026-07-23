package dev.projecteclipse.eclipse.devtools.dev;

import java.util.Collection;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;
import com.mojang.brigadier.suggestion.SuggestionProvider;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.buffs.BuffConfig;
import dev.projecteclipse.eclipse.buffs.BuffMath;
import dev.projecteclipse.eclipse.buffs.BuffState;
import dev.projecteclipse.eclipse.buffs.TimedBuffApi;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeMath;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.commands.arguments.EntityArgument;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * Thin command bridge to the global timed-buff engine. The optional target is accepted for
 * operator ergonomics but must resolve to every online player because the backing service is
 * intentionally server-global; silently pretending a global buff is per-player would be unsafe.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevBuffCommands {
    private static final Map<String, String> ALIASES = Map.of(
            "doublexp", "double_skill_xp",
            "ore_drops", "double_ore_drops",
            "doubleore", "double_ore_drops",
            "shards", "double_shard_finds");

    private static final SuggestionProvider<CommandSourceStack> BUFF_IDS =
            (context, builder) -> SharedSuggestionProvider.suggest(
                    TimedBuffApi.Holder.get().knownIds(), builder);

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("buff.give", DevCategory.BUFFS,
                        "/dev buff give <buff> [duration] [target]",
                        "dev.eclipse.doc.buff.give", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("buff.clear", DevCategory.BUFFS, "/dev buff clear",
                        "dev.eclipse.doc.buff.clear", Danger.CAUTION, ClickAction.RUN, 2),
                new DevCommandDoc("buff.list", DevCategory.BUFFS, "/dev buff list",
                        "dev.eclipse.doc.buff.list", Danger.SAFE, ClickAction.RUN, 2));
    }

    private DevBuffCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("buff")
                        .then(Commands.literal("give")
                                .then(Commands.argument("buff", StringArgumentType.word())
                                        .suggests(BUFF_IDS)
                                        .executes(context -> give(context, null, null))
                                        .then(Commands.argument("duration", StringArgumentType.word())
                                                .executes(context -> give(context,
                                                        StringArgumentType.getString(context, "duration"), null))
                                                .then(Commands.argument("target", EntityArgument.players())
                                                        .executes(context -> give(context,
                                                                StringArgumentType.getString(context, "duration"),
                                                                EntityArgument.getPlayers(context, "target")))))))
                        .then(Commands.literal("clear").executes(DevBuffCommands::clear))
                        .then(Commands.literal("list").executes(DevBuffCommands::list))));
    }

    private static int give(CommandContext<CommandSourceStack> context, String duration,
            Collection<ServerPlayer> targets) throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        TimedBuffApi api = TimedBuffApi.Holder.get();
        String rawId = StringArgumentType.getString(context, "buff").toLowerCase(Locale.ROOT);
        String id = ALIASES.getOrDefault(rawId, rawId);

        if (!api.knownIds().contains(id)) {
            source.sendFailure(Component.translatable("dev.eclipse.buff.unknown", rawId));
            return 0;
        }
        if (targets != null && !isEveryOnlinePlayer(server, targets)) {
            source.sendFailure(Component.translatable("dev.eclipse.buff.target.global_only"));
            return 0;
        }

        int minutes = 0;
        if (duration != null) {
            try {
                long millis = parseDuration(duration);
                minutes = Math.toIntExact(Math.max(1L, (millis + 59_999L) / 60_000L));
                if (minutes > 10_080) {
                    source.sendFailure(Component.translatable("dev.eclipse.buff.duration.too_long"));
                    return 0;
                }
            } catch (IllegalArgumentException | ArithmeticException e) {
                source.sendFailure(Component.translatable("dev.eclipse.buff.duration.invalid", duration));
                return 0;
            }
        }

        if (!api.start(server, id, minutes, 0.0F)) {
            source.sendFailure(Component.translatable("dev.eclipse.buff.give.refused", id));
            return 0;
        }
        int finalMinutes = minutes;
        Component feedback = Component.translatable("dev.eclipse.buff.give.ok", id,
                finalMinutes > 0 ? finalMinutes : BuffConfig.get().buffs().get(id).defaultMinutes());
        audit(source, feedback, "gave global buff " + id + " for "
                + (finalMinutes > 0 ? finalMinutes : "default") + "m");
        return 1;
    }

    private static long parseDuration(String raw) {
        String duration = raw.trim();
        if (duration.startsWith("+") || duration.startsWith("-")) {
            throw new IllegalArgumentException("signed duration");
        }
        return RealtimeMath.parseSignedOffsetMillis("+" + duration);
    }

    private static boolean isEveryOnlinePlayer(MinecraftServer server, Collection<ServerPlayer> targets) {
        Set<java.util.UUID> selected = targets.stream().map(ServerPlayer::getUUID).collect(Collectors.toSet());
        Set<java.util.UUID> online = server.getPlayerList().getPlayers().stream()
                .map(ServerPlayer::getUUID).collect(Collectors.toSet());
        return selected.equals(online);
    }

    private static int clear(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        TimedBuffApi api = TimedBuffApi.Holder.get();
        var active = api.active(source.getServer());
        int stopped = 0;
        for (String id : active) {
            if (api.stop(source.getServer(), id)) {
                stopped++;
            }
        }
        if (stopped == 0) {
            source.sendFailure(Component.translatable("dev.eclipse.buff.clear.empty"));
            return 0;
        }
        Component feedback = Component.translatable("dev.eclipse.buff.clear.ok", stopped);
        audit(source, feedback, "cleared " + stopped + " global buff(s)");
        return stopped;
    }

    private static int list(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        long now = System.currentTimeMillis();
        var active = BuffMath.pruneExpired(BuffState.get(source.getServer()).active(), now);
        if (active.isEmpty()) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.buff.list.empty"), false);
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.buff.list.header", active.size()), false);
        for (BuffMath.ActiveBuff buff : active) {
            BuffConfig.BuffDefinition definition = BuffConfig.get().buffs().get(buff.id());
            float magnitude = buff.magnitude();
            if (magnitude <= 0.0F && definition != null
                    && definition.effect() instanceof BuffConfig.MultiplierEffect multiplier) {
                magnitude = multiplier.value();
            }
            float shownMagnitude = magnitude;
            source.sendSuccess(() -> Component.translatable("dev.eclipse.buff.list.entry",
                    buff.id(), RealtimeMath.remainingText(buff.endsAtEpochMillis() - now),
                    shownMagnitude), false);
        }
        return active.size();
    }

    private static void audit(CommandSourceStack source, Component feedback, String logDetail) {
        source.sendSuccess(() -> feedback, false);
        for (ServerPlayer operator : source.getServer().getPlayerList().getPlayers()) {
            if (operator.hasPermissions(2) && operator != source.getEntity()) {
                operator.sendSystemMessage(Component.translatable("dev.eclipse.audit",
                        source.getTextName(), feedback));
            }
        }
        EclipseMod.LOGGER.info("[DEV AUDIT] {} {}", source.getTextName(), logDetail);
    }
}
