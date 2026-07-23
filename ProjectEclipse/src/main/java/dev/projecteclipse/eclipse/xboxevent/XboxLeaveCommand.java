package dev.projecteclipse.eclipse.xboxevent;

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
 * {@code /xboxleave} — the ONLY permission-0 surface of the dev tree (plan §1.1 audit
 * exception, §2.13.6): player-facing voluntary exit from a tutorial world with a
 * confirmation click-through ({@code /xboxleave} → clickable {@code /xboxleave confirm}).
 * Outside the Xbox dimensions it is a polite no-op. The literal is NOT in
 * {@code CommandBlocker.BLOCKED_COMMANDS}, so it passes the anonymity filter.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class XboxLeaveCommand {

    static {
        DevCommandRegistry.register(new DevCommandDoc(
                "xboxleave", DevCategory.XBOX, "/xboxleave",
                "dev.eclipse.doc.xboxleave", Danger.SAFE, ClickAction.RUN, 0));
    }

    private XboxLeaveCommand() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("xboxleave")
                .executes(context -> {
                    ServerPlayer player = requirePlayer(context.getSource());
                    return player == null ? 0 : XboxEventService.leaveRequested(player);
                })
                .then(Commands.literal("confirm")
                        .executes(context -> {
                            ServerPlayer player = requirePlayer(context.getSource());
                            return player == null ? 0 : XboxEventService.leaveConfirmed(player);
                        })));
    }

    private static ServerPlayer requirePlayer(CommandSourceStack source) {
        if (source.getEntity() instanceof ServerPlayer player) {
            return player;
        }
        source.sendFailure(Component.translatable("eclipse.xbox.leave.player_only"));
        return null;
    }
}
