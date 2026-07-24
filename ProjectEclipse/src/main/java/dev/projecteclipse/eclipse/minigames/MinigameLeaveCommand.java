package dev.projecteclipse.eclipse.minigames;

import com.mojang.brigadier.CommandDispatcher;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.devtools.dev.ClickAction;
import dev.projecteclipse.eclipse.devtools.dev.Danger;
import dev.projecteclipse.eclipse.devtools.dev.DevCategory;
import dev.projecteclipse.eclipse.devtools.dev.DevCommandDoc;
import dev.projecteclipse.eclipse.devtools.dev.DevCommandRegistry;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /minigameleave} — permission-0 player surface mirroring {@code /xboxleave}
 * (plan §1.1 audit exception pattern): voluntary exit from a minigame dimension with a
 * confirmation click-through ({@code /minigameleave} → clickable
 * {@code /minigameleave confirm}). Outside the minigame dimensions it is a polite no-op.
 * The literal is NOT in {@code CommandBlocker.BLOCKED_COMMANDS}, so it passes the
 * anonymity filter; leaving never locks re-entry (minigames have no lockouts).
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class MinigameLeaveCommand {

    static {
        DevCommandRegistry.register(new DevCommandDoc(
                "minigameleave", DevCategory.EVENT, "/minigameleave",
                "dev.eclipse.doc.minigameleave", Danger.SAFE, ClickAction.RUN, 0));
    }

    private MinigameLeaveCommand() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("minigameleave")
                .executes(context -> {
                    ServerPlayer player = requirePlayer(context.getSource());
                    return player == null ? 0 : MinigameService.leaveRequested(player);
                })
                .then(Commands.literal("confirm")
                        .executes(context -> {
                            ServerPlayer player = requirePlayer(context.getSource());
                            return player == null ? 0 : MinigameService.leaveConfirmed(player);
                        })));
    }

    private static ServerPlayer requirePlayer(CommandSourceStack source) {
        if (source.getEntity() instanceof ServerPlayer player) {
            return player;
        }
        source.sendFailure(Component.translatable("eclipse.minigame.leave.player_only"));
        return null;
    }
}
