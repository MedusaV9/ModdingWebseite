package dev.projecteclipse.eclipse.backrooms;

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
 * {@code /backroomsleave} — the player-facing voluntary exit (verbatim
 * {@code XboxLeaveCommand} pattern, IDEAS §A5): permission 0, click-through confirmation
 * ({@code /backroomsleave} → clickable {@code /backroomsleave confirm}), voluntary exits
 * lock the current instance. Outside the backrooms it is a polite no-op.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class BackroomsLeaveCommand {

    static {
        DevCommandRegistry.register(new DevCommandDoc(
                "backroomsleave", DevCategory.EVENT, "/backroomsleave",
                "dev.eclipse.doc.backroomsleave", Danger.SAFE, ClickAction.RUN, 0));
    }

    private BackroomsLeaveCommand() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("backroomsleave")
                .executes(context -> {
                    ServerPlayer player = requirePlayer(context.getSource());
                    return player == null ? 0 : BackroomsEventService.leaveRequested(player);
                })
                .then(Commands.literal("confirm")
                        .executes(context -> {
                            ServerPlayer player = requirePlayer(context.getSource());
                            return player == null ? 0 : BackroomsEventService.leaveConfirmed(player);
                        })));
    }

    private static ServerPlayer requirePlayer(CommandSourceStack source) {
        if (source.getEntity() instanceof ServerPlayer player) {
            return player;
        }
        source.sendFailure(Component.translatable("eclipse.backrooms.leave.player_only"));
        return null;
    }
}
