package dev.projecteclipse.eclipse.devtools.dev;

import java.util.Collection;
import java.util.List;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.suggestion.SuggestionProvider;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.SequenceReplayable;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/** Thin aliases over SequenceReplayable.Registry; no sequence logic is duplicated here. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevReplayCommands {
    private static final SuggestionProvider<CommandSourceStack> ID_SUGGESTIONS =
            (context, builder) -> SharedSuggestionProvider.suggest(SequenceReplayable.Registry.ids(), builder);

    private static final SuggestionProvider<CommandSourceStack> PHASE_SUGGESTIONS =
            (context, builder) -> {
                String id = StringArgumentType.getString(context, "id");
                List<String> phases = SequenceReplayable.Registry.byId(id)
                        .map(SequenceReplayable::phaseIds).orElse(List.of());
                return SharedSuggestionProvider.suggest(phases, builder);
            };

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("replay.list", DevCategory.CUTSCENE,
                        "/dev replay list", "dev.eclipse.doc.replay.list",
                        Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("replay.play", DevCategory.CUTSCENE,
                        "/dev replay play <id> [<phase>]", "dev.eclipse.doc.replay.play",
                        Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("replay.revert", DevCategory.CUTSCENE,
                        "/dev replay revert <id>", "dev.eclipse.doc.replay.revert",
                        Danger.SAFE, ClickAction.SUGGEST, 2));
    }

    private DevReplayCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("replay")
                        .then(Commands.literal("list")
                                .executes(DevReplayCommands::list))
                        .then(Commands.literal("play")
                                .then(Commands.argument("id", StringArgumentType.word())
                                        .suggests(ID_SUGGESTIONS)
                                        .executes(context -> play(context, null))
                                        .then(Commands.argument("phase", StringArgumentType.word())
                                                .suggests(PHASE_SUGGESTIONS)
                                                .executes(context -> play(context,
                                                        StringArgumentType.getString(context, "phase"))))))
                        .then(Commands.literal("revert")
                                .then(Commands.argument("id", StringArgumentType.word())
                                        .suggests(ID_SUGGESTIONS)
                                        .executes(DevReplayCommands::revert)))));
    }

    private static int list(CommandContext<CommandSourceStack> context) {
        List<String> ids = SequenceReplayable.Registry.ids();
        if (ids.isEmpty()) {
            context.getSource().sendSuccess(() -> Component.translatable(
                    "dev.eclipse.replay.registry_empty"), false);
            return 0;
        }
        context.getSource().sendSuccess(() -> Component.translatable(
                "dev.eclipse.replay.list.header", ids.size()), false);
        for (String id : ids) {
            SequenceReplayable replayable = SequenceReplayable.Registry.byId(id).orElseThrow();
            context.getSource().sendSuccess(() -> Component.translatable(
                    "dev.eclipse.replay.list.entry", id, String.join(", ", replayable.phaseIds())), false);
        }
        return ids.size();
    }

    private static int play(CommandContext<CommandSourceStack> context, String requestedPhase) {
        if (SequenceReplayable.Registry.ids().isEmpty()) {
            context.getSource().sendFailure(Component.translatable("dev.eclipse.replay.registry_empty"));
            return 0;
        }
        String id = StringArgumentType.getString(context, "id");
        SequenceReplayable replayable = SequenceReplayable.Registry.byId(id).orElse(null);
        if (replayable == null) {
            context.getSource().sendFailure(Component.translatable("dev.eclipse.replay.unknown", id));
            return 0;
        }
        String phase = requestedPhase;
        if (phase == null) {
            if (replayable.phaseIds().isEmpty()) {
                context.getSource().sendFailure(Component.translatable("dev.eclipse.replay.no_phases", id));
                return 0;
            }
            phase = replayable.phaseIds().get(0);
        }
        Collection<ServerPlayer> viewers = context.getSource().getEntity() instanceof ServerPlayer player
                ? List.of(player)
                : context.getSource().getServer().getPlayerList().getPlayers();
        if (!replayable.replay(context.getSource().getServer(), phase, viewers)) {
            context.getSource().sendFailure(Component.translatable("dev.eclipse.replay.failed", id, phase));
            return 0;
        }
        String finalPhase = phase;
        context.getSource().sendSuccess(() -> Component.translatable(
                "dev.eclipse.replay.started", id, finalPhase, viewers.size()), false);
        context.getSource().sendSuccess(() -> Component.translatable(
                "dev.eclipse.replay.fx_only"), false);
        return 1;
    }

    private static int revert(CommandContext<CommandSourceStack> context) {
        if (SequenceReplayable.Registry.ids().isEmpty()) {
            context.getSource().sendFailure(Component.translatable("dev.eclipse.replay.registry_empty"));
            return 0;
        }
        String id = StringArgumentType.getString(context, "id");
        if (SequenceReplayable.Registry.byId(id).isEmpty()) {
            context.getSource().sendFailure(Component.translatable("dev.eclipse.replay.unknown", id));
            return 0;
        }
        // Registry's replay contract is FX-only: it cannot commit terrain/progression,
        // so there is deliberately no synthetic undo API to call.
        context.getSource().sendSuccess(() -> Component.translatable(
                "dev.eclipse.replay.nothing_to_revert", id), false);
        return 1;
    }
}
