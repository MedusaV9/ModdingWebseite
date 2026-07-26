package dev.projecteclipse.eclipse.devtools.inspect;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.devtools.dev.ClickAction;
import dev.projecteclipse.eclipse.devtools.dev.Danger;
import dev.projecteclipse.eclipse.devtools.dev.DevCategory;
import dev.projecteclipse.eclipse.devtools.dev.DevCommandDoc;
import dev.projecteclipse.eclipse.devtools.dev.DevCommandRegistry;
import dev.projecteclipse.eclipse.devtools.dev.DevRoot;
import dev.projecteclipse.eclipse.lang.ServerLang;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.arguments.EntityArgument;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.Container;
import net.minecraft.world.SimpleMenuProvider;
import net.minecraft.world.inventory.ChestMenu;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * F-066 operator inspection commands. Both are TOP-LEVEL roots (they are typed far too often to
 * live under {@code /dev}) but share the {@code /dev} gate exactly — {@link DevRoot#canUseDev},
 * i.e. permission 2 or a configured dev-bypass identity — and both are documented in
 * {@link DevCommandRegistry} so {@code /dev help players} and the handbook list them.
 *
 * <ul>
 *   <li>{@code /invsee <player>} — six-row LIVE view of the target's 36 inventory + 4 armor +
 *       offhand slots ({@link LivePlayerInventoryMenu}).</li>
 *   <li>{@code /enderchestsee <player>} — three-row LIVE view of the target's
 *       {@code PlayerEnderChestContainer} ({@link LiveEnderChestContainer}).</li>
 * </ul>
 *
 * <p>Both menus write straight through to the target and close themselves on the next tick when
 * the target leaves (see {@link InspectTarget}). Neither needs a client-side screen: the vanilla
 * generic chest menus render them.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class InspectCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("invsee", DevCategory.PLAYERS, "/invsee <player>",
                        "dev.eclipse.doc.invsee", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("enderchestsee", DevCategory.PLAYERS, "/enderchestsee <player>",
                        "dev.eclipse.doc.enderchestsee", Danger.CAUTION, ClickAction.SUGGEST, 2));
    }

    private InspectCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("invsee")
                .requires(DevRoot::canUseDev)
                .then(Commands.argument("player", EntityArgument.player())
                        .executes(InspectCommands::invsee)));
        dispatcher.register(Commands.literal("enderchestsee")
                .requires(DevRoot::canUseDev)
                .then(Commands.argument("player", EntityArgument.player())
                        .executes(InspectCommands::enderchestsee)));
    }

    private static int invsee(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer viewer = source.getPlayerOrException();
        ServerPlayer target = EntityArgument.getPlayer(context, "player");
        if (target == viewer) {
            // Both halves of the menu would be backed by the SAME inventory — vanilla's slot
            // sync cannot express that and the mismatch duplicates stacks. Never allow it.
            source.sendFailure(ServerLang.tr(viewer, "eclipse.invsee.self"));
            return 0;
        }
        viewer.openMenu(LivePlayerInventoryMenu.provider(viewer, target));
        audit(source, viewer, ServerLang.tr(viewer, "eclipse.invsee.opened",
                target.getGameProfile().getName()), "opened the live inventory of " + target.getScoreboardName());
        return 1;
    }

    private static int enderchestsee(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer viewer = source.getPlayerOrException();
        ServerPlayer target = EntityArgument.getPlayer(context, "player");
        Component title = ServerLang.tr(viewer, "eclipse.enderchestsee.title",
                target.getGameProfile().getName());
        Container live = new LiveEnderChestContainer(target);
        viewer.openMenu(new SimpleMenuProvider((containerId, viewerInventory, player) ->
                ChestMenu.threeRows(containerId, viewerInventory, live), title));
        audit(source, viewer, ServerLang.tr(viewer, "eclipse.enderchestsee.opened",
                target.getGameProfile().getName()),
                "opened the live ender chest of " + target.getScoreboardName());
        return 1;
    }

    /** Mirrors the {@code DevPlayerCommands} audit discipline: issuer + other operators + log. */
    private static void audit(CommandSourceStack source, ServerPlayer viewer, Component feedback,
            String logDetail) {
        source.sendSuccess(() -> feedback, false);
        for (ServerPlayer operator : source.getServer().getPlayerList().getPlayers()) {
            if (operator.hasPermissions(2) && operator != viewer) {
                operator.sendSystemMessage(ServerLang.tr(operator, "dev.eclipse.audit",
                        source.getTextName(), feedback));
            }
        }
        EclipseMod.LOGGER.info("[DEV AUDIT] {} {}", source.getTextName(), logDetail);
    }
}
