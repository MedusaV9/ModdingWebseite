package dev.projecteclipse.eclipse.awards;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.IntegerArgumentType;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.network.chat.Component;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/** Permission-2 smoke/dev surface for the otherwise-secret award engine. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class AwardCommands {
    private AwardCommands() {}

    @SubscribeEvent
    static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("eclipse-awards")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("preview")
                        .executes(context -> preview(context.getSource(),
                                DayScheduler.getDay(context.getSource().getServer())))
                        .then(Commands.argument("day", IntegerArgumentType.integer(1))
                                .executes(context -> preview(context.getSource(),
                                        IntegerArgumentType.getInteger(context, "day")))))
                .then(Commands.literal("resolve")
                        .executes(context -> resolve(context.getSource(),
                                DayScheduler.getDay(context.getSource().getServer())))
                        .then(Commands.argument("day", IntegerArgumentType.integer(1))
                                .executes(context -> resolve(context.getSource(),
                                        IntegerArgumentType.getInteger(context, "day")))))
                .then(Commands.literal("reroll")
                        .executes(context -> reroll(context.getSource(),
                                DayScheduler.getDay(context.getSource().getServer())))
                        .then(Commands.argument("day", IntegerArgumentType.integer(1))
                                .executes(context -> reroll(context.getSource(),
                                        IntegerArgumentType.getInteger(context, "day"))))));
    }

    private static int preview(CommandSourceStack source, int day) {
        var categories = AwardService.preview(source.getServer(), day);
        source.sendSuccess(() -> Component.literal("SECRET operator preview for day " + day
                + " (do not relay to players): " + String.join(", ", categories)), false);
        return categories.size();
    }

    private static int resolve(CommandSourceStack source, int day) {
        AwardsState.ResolvedDay resolved = AwardService.resolveNow(source.getServer(), day);
        source.sendSuccess(() -> Component.literal("Awards day " + day + " resolved: "
                + resolved.categories().size() + " reveal categories (idempotent)."), false);
        return resolved.categories().size();
    }

    private static int reroll(CommandSourceStack source, int day) {
        int nonce = AwardService.reroll(source.getServer(), day);
        if (nonce == -2) {
            source.sendFailure(Component.literal("Day " + day
                    + " is already resolved; reroll refused to prevent duplicate rewards."));
            return 0;
        }
        if (nonce < 0) {
            source.sendFailure(Component.literal("Reroll cap reached for day " + day + "."));
            return 0;
        }
        source.sendSuccess(() -> Component.literal("Secret award draw for day " + day
                + " rerolled (nonce " + nonce + ")."), false);
        return nonce;
    }
}
