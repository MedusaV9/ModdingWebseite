package dev.projecteclipse.eclipse.progression.realtime;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.StringArgumentType;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.time.EclipseClock;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * Reference smoke commands for the real-time day engine ({@code /eclipse-rt}, perm 3) —
 * a NEW root so the untouchable {@code /eclipse} tree stays intact. P5-W3 surfaces the
 * polished command UX on top of {@link RealtimeDayApi}; these call exactly that surface.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class RealtimeCommands {
    private RealtimeCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("eclipse-rt")
                .requires(source -> source.hasPermission(3))
                .then(Commands.literal("arm").executes(ctx -> arm(ctx.getSource())))
                .then(Commands.literal("disarm").executes(ctx -> disarm(ctx.getSource())))
                .then(Commands.literal("pause").executes(ctx -> pause(ctx.getSource())))
                .then(Commands.literal("resume").executes(ctx -> resume(ctx.getSource())))
                .then(Commands.literal("add")
                        .then(Commands.argument("spec", StringArgumentType.word())
                                .executes(ctx -> add(ctx.getSource(),
                                        StringArgumentType.getString(ctx, "spec")))))
                .then(Commands.literal("set")
                        .then(Commands.argument("spec", StringArgumentType.greedyString())
                                .executes(ctx -> set(ctx.getSource(),
                                        StringArgumentType.getString(ctx, "spec")))))
                .then(Commands.literal("status").executes(ctx -> status(ctx.getSource()))));
    }

    private static int arm(CommandSourceStack source) {
        MinecraftServer server = source.getServer();
        long boundary = RealtimeDayApi.arm(server);
        long now = EclipseClock.epochMillis();
        source.sendSuccess(() -> Component.translatable("command.eclipse.rt.armed",
                RealtimeDayService.formatInstant(boundary, RealtimeConfig.get().zone()),
                RealtimeMath.remainingText(boundary - now)), true);
        return 1;
    }

    private static int disarm(CommandSourceStack source) {
        RealtimeDayApi.disarm(source.getServer());
        source.sendSuccess(() -> Component.translatable("command.eclipse.rt.disarmed"), true);
        return 1;
    }

    private static int pause(CommandSourceStack source) {
        long remaining = RealtimeDayApi.pause(source.getServer());
        if (remaining < 0L) {
            source.sendFailure(Component.translatable("command.eclipse.rt.pause.failed"));
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("command.eclipse.rt.pause.ok",
                RealtimeMath.remainingText(remaining)), true);
        return 1;
    }

    private static int resume(CommandSourceStack source) {
        long boundary = RealtimeDayApi.resume(source.getServer());
        if (boundary < 0L) {
            source.sendFailure(Component.translatable("command.eclipse.rt.resume.failed"));
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("command.eclipse.rt.resume.ok",
                RealtimeDayService.formatInstant(boundary, RealtimeConfig.get().zone())), true);
        return 1;
    }

    private static int add(CommandSourceStack source, String spec) {
        long delta;
        try {
            delta = RealtimeMath.parseSignedOffsetMillis(spec);
        } catch (IllegalArgumentException e) {
            source.sendFailure(Component.literal(e.getMessage()));
            return 0;
        }
        long remaining = RealtimeDayApi.addMillis(source.getServer(), delta);
        if (remaining < 0L) {
            source.sendFailure(Component.translatable("command.eclipse.rt.add.failed"));
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("command.eclipse.rt.add.ok",
                spec, RealtimeMath.remainingText(remaining)), true);
        return 1;
    }

    private static int set(CommandSourceStack source, String spec) {
        long target;
        try {
            target = RealtimeDayApi.setBoundary(source.getServer(), spec, RealtimeConfig.get().zone());
        } catch (IllegalArgumentException e) {
            source.sendFailure(Component.literal(e.getMessage()));
            return 0;
        }
        long now = EclipseClock.epochMillis();
        source.sendSuccess(() -> Component.translatable("command.eclipse.rt.set.ok",
                RealtimeDayService.formatInstant(target, RealtimeConfig.get().zone()),
                RealtimeMath.remainingText(target - now)), true);
        return 1;
    }

    private static int status(CommandSourceStack source) {
        MinecraftServer server = source.getServer();
        source.sendSuccess(() -> Component.translatable("command.eclipse.rt.status",
                RealtimeDayApi.status(server)), false);
        return RealtimeDayApi.isArmed(server) ? 1 : 0;
    }
}
