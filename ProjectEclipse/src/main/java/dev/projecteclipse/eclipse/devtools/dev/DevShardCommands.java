package dev.projecteclipse.eclipse.devtools.dev;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.context.CommandContext;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.economy.ShardEconomy;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.network.chat.Component;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev shards} ops tree (B14 §4 playtest verification tool), registered through
 * {@link DevCommandRegistry} from the static initializer (freeze-before-boot rule) in the
 * {@code DevContractCommands} style. Brigadier merges the {@code /dev} roots across files,
 * so no shared command file is touched. Balance MUTATION stays on the legacy
 * {@code /eclipse shards set|add|pool set} tree — this tree is diagnostics only.
 *
 * <p>{@code trace on|off} flips {@link ShardEconomy#setTraceEnabled}: every personal
 * addShards/setShards, team-pool bank, physical delivery and ground pickup is logged with
 * its calling source frame, so "who credited what" is answerable during a playtest.
 * {@code status} prints the team pool + trace state at a glance.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevShardCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("shards.trace", DevCategory.ANALYTICS,
                        "/dev shards trace on|off",
                        "dev.eclipse.doc.shards.trace", Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("shards.status", DevCategory.ANALYTICS,
                        "/dev shards status",
                        "dev.eclipse.doc.shards.status", Danger.SAFE, ClickAction.RUN, 2));
    }

    private DevShardCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("shards")
                        .then(Commands.literal("trace")
                                .then(Commands.literal("on")
                                        .executes(context -> trace(context, true)))
                                .then(Commands.literal("off")
                                        .executes(context -> trace(context, false))))
                        .then(Commands.literal("status")
                                .executes(DevShardCommands::status))));
    }

    private static int trace(CommandContext<CommandSourceStack> context, boolean enabled) {
        ShardEconomy.setTraceEnabled(enabled);
        context.getSource().sendSuccess(() -> Component.translatable(
                enabled ? "dev.eclipse.shards.trace.on" : "dev.eclipse.shards.trace.off"), true);
        return 1;
    }

    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        int pool = EclipseWorldState.get(source.getServer()).getShardPool();
        boolean tracing = ShardEconomy.isTraceEnabled();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.shards.status", pool,
                Component.translatable(tracing ? "dev.eclipse.yes" : "dev.eclipse.no")), false);
        return pool;
    }
}
