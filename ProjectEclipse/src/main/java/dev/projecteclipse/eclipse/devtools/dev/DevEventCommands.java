package dev.projecteclipse.eclipse.devtools.dev;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.context.CommandContext;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.artifact.ArtifactSlotLock;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.lang.ServerLang;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev event …} — PROGFIX #3 operator toggles for the persisted intro-event flags
 * (perm 2):
 *
 * <ul>
 *   <li>{@code stormtouched on|off} — sets/clears {@link EclipseWorldState#isStormTouched}.
 *       {@code on} also runs an immediate {@link ArtifactSlotLock#grantAll} pass (the same
 *       grant the APPROACH → LIGHTNING trigger fires); {@code off} lets the next 1 s sweep
 *       purge every artifact copy again — the normal pre-storm state.</li>
 *   <li>{@code stormtouched status} — reads the flag.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevEventCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("event.stormtouched", DevCategory.EVENT,
                        "/dev event stormtouched on|off|status",
                        "dev.eclipse.doc.event.stormtouched", Danger.CAUTION, ClickAction.SUGGEST, 2));
    }

    private DevEventCommands() {}

    @SubscribeEvent
    static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("event")
                        .then(Commands.literal("stormtouched")
                                .then(Commands.literal("on")
                                        .executes(context -> set(context, true)))
                                .then(Commands.literal("off")
                                        .executes(context -> set(context, false)))
                                .then(Commands.literal("status")
                                        .executes(DevEventCommands::status)))));
    }

    private static int set(CommandContext<CommandSourceStack> context, boolean touched) {
        CommandSourceStack source = context.getSource();
        EclipseWorldState state = EclipseWorldState.get(source.getServer());
        state.setStormTouched(touched);
        if (touched) {
            // Same ceremony pass IntroSequence fires — everyone online gets the artifact now
            // instead of on the next sweep.
            ArtifactSlotLock.grantAll(source.getServer());
        }
        Component feedback = Component.translatable(touched
                ? "dev.eclipse.event.stormtouched.on" : "dev.eclipse.event.stormtouched.off");
        audit(source, feedback, "set stormTouched " + (touched ? "on" : "off"));
        return 1;
    }

    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        boolean touched = EclipseWorldState.get(source.getServer()).isStormTouched();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.event.stormtouched.status",
                touched ? "ON" : "OFF"), false);
        return touched ? 1 : 0;
    }

    /** Same operator-audit convention as the other /dev command bridges. */
    private static void audit(CommandSourceStack source, Component feedback, String logDetail) {
        source.sendSuccess(() -> feedback, false);
        for (ServerPlayer operator : source.getServer().getPlayerList().getPlayers()) {
            if (operator.hasPermissions(2) && operator != source.getEntity()) {
                operator.sendSystemMessage(ServerLang.tr(operator, "dev.eclipse.audit",
                        source.getTextName(), feedback));
            }
        }
        EclipseMod.LOGGER.info("[DEV AUDIT] {} {}", source.getTextName(), logDetail);
    }
}
