package dev.projecteclipse.eclipse.start;

import java.util.Map;
import java.util.UUID;

import com.mojang.brigadier.context.CommandContext;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/** Permission-level-2 diagnostics for persistent start-disc assignments. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class StartCommands {
    private StartCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        event.getDispatcher().register(Commands.literal("eclipse-start")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("assign").executes(StartCommands::assign))
                .then(Commands.literal("show").executes(StartCommands::show)));
    }

    private static int assign(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        if (server.getPlayerList().getPlayers().isEmpty()) {
            source.sendFailure(Component.translatable("command.eclipse.start.assign.none"));
            return 0;
        }
        Map<UUID, BlockPos> assignments = StartAssignmentService.assignAll(server);
        source.sendSuccess(() -> Component.translatable(
                "command.eclipse.start.assign.success", assignments.size()), false);
        sendEntries(source, assignments);
        return assignments.size();
    }

    private static int show(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        MinecraftServer server = source.getServer();
        StartState state = StartState.get(server);
        if (!state.isAssigned() || state.assignments().isEmpty()) {
            source.sendSuccess(() -> Component.translatable(
                    "command.eclipse.start.show.empty"), false);
            return 1;
        }

        Map<UUID, BlockPos> assignments = state.assignments().keySet().stream()
                .sorted(StartAssignmentService.UUID_ORDER)
                .collect(java.util.stream.Collectors.toMap(
                        uuid -> uuid,
                        uuid -> StartAssignmentService.getAssigned(server, uuid).orElse(BlockPos.ZERO),
                        (left, right) -> left,
                        java.util.LinkedHashMap::new));
        source.sendSuccess(() -> Component.translatable(
                "command.eclipse.start.show.header", assignments.size()), false);
        sendEntries(source, assignments);
        return assignments.size();
    }

    private static void sendEntries(CommandSourceStack source,
            Map<UUID, BlockPos> assignments) {
        MinecraftServer server = source.getServer();
        assignments.entrySet().stream()
                .sorted(Map.Entry.comparingByKey(StartAssignmentService.UUID_ORDER))
                .forEach(entry -> {
                    UUID uuid = entry.getKey();
                    BlockPos anchor = entry.getValue();
                    int index = StartState.get(server).getIndex(uuid);
                    String name = server.getProfileCache() == null
                            ? uuid.toString()
                            : server.getProfileCache().get(uuid)
                                    .map(profile -> profile.getName())
                                    .orElse(uuid.toString());
                    source.sendSuccess(() -> Component.translatable(
                            "command.eclipse.start.show.entry",
                            name, index, anchor.getX(), anchor.getZ()), false);
                });
    }
}
