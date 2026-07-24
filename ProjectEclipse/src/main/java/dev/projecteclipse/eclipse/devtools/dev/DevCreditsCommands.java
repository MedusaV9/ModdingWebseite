package dev.projecteclipse.eclipse.devtools.dev;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.context.CommandContext;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.ritual.CreditsSequence;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.network.chat.Component;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev credits …} (C15): runs the REAL final credits sequence, unlike
 * {@code /dev replay play credits <phase>} which fires FX-only phase replays through
 * {@link dev.projecteclipse.eclipse.cutscene.SequenceReplayable}.
 *
 * <ul>
 *   <li>{@code start} — begins the full sequence for everyone online: helm shot →
 *       whiteout teleport to {@code eclipse:epilogue} → sunrise auto-run + credits roll →
 *       lightning/debris → title cards → fade out → trip home → close broadcast. On a
 *       DEDICATED server an un-skipped run ends with clients closing and the server
 *       halting (the intended live ending) — hence DESTRUCTIVE. Integrated servers and
 *       singleplayer never close/halt.</li>
 *   <li>{@code skip} — jumps a running sequence to the outro AND permanently disarms the
 *       close/halt for that run (the QA escape hatch).</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevCreditsCommands {

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("credits.start", DevCategory.CUTSCENE,
                        "/dev credits start",
                        "dev.eclipse.doc.credits.start", Danger.DESTRUCTIVE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("credits.skip", DevCategory.CUTSCENE,
                        "/dev credits skip",
                        "dev.eclipse.doc.credits.skip", Danger.CAUTION, ClickAction.RUN, 2));
    }

    private DevCreditsCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("credits")
                        .then(Commands.literal("start")
                                .executes(DevCreditsCommands::start))
                        .then(Commands.literal("skip")
                                .executes(DevCreditsCommands::skip))));
    }

    private static int start(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        if (CreditsSequence.isRunning()) {
            source.sendFailure(Component.translatable("dev.eclipse.credits.already_running"));
            return 0;
        }
        if (!CreditsSequence.begin(source.getServer())) {
            source.sendFailure(Component.translatable("dev.eclipse.credits.start_blocked"));
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.credits.started"), true);
        return 1;
    }

    private static int skip(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        if (!CreditsSequence.skip(source.getServer())) {
            source.sendFailure(Component.translatable("dev.eclipse.credits.skip_idle"));
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.credits.skipped"), true);
        return 1;
    }
}
