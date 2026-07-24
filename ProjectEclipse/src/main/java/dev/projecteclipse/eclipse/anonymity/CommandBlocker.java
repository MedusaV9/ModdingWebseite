package dev.projecteclipse.eclipse.anonymity;

import java.util.List;
import java.util.Set;

import com.mojang.brigadier.context.ParsedCommandNode;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.network.chat.Component;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.CommandEvent;

/**
 * Blocks the vanilla permission-0 commands that would leak player names for anyone
 * below permission level {@link Commands#LEVEL_GAMEMASTERS}: {@code /msg}, {@code /tell},
 * {@code /w} and {@code /me} bypass the chat block and print the sender's name,
 * {@code /teammsg}/{@code /tm} do the same for teams, and {@code /list} prints every
 * online player's name (and UUID with {@code /list uuids}). Ops and the console keep
 * all of them for administration.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class CommandBlocker {
    private CommandBlocker() {}

    /** Root literals of the vanilla permission-0 commands that reveal player names. */
    private static final Set<String> BLOCKED_COMMANDS =
            Set.of("msg", "tell", "w", "me", "teammsg", "tm", "list");

    @SubscribeEvent
    public static void onCommand(CommandEvent event) {
        CommandSourceStack source = event.getParseResults().getContext().getSource();
        if (source.hasPermission(Commands.LEVEL_GAMEMASTERS)) {
            return;
        }
        List<ParsedCommandNode<CommandSourceStack>> nodes = event.getParseResults().getContext().getNodes();
        if (!nodes.isEmpty() && BLOCKED_COMMANDS.contains(nodes.get(0).getNode().getName())) {
            event.setCanceled(true);
            source.sendFailure(Component.translatable("message.eclipse.command_sealed"));
        }
    }
}
