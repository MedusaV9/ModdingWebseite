package dev.projecteclipse.eclipse.devtools.dev;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;
import com.mojang.brigadier.suggestion.SuggestionProvider;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.scare.ScareIds;
import dev.projecteclipse.eclipse.scare.ScareService;
import dev.projecteclipse.eclipse.scare.ScareTripService;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.commands.arguments.EntityArgument;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev ghostscreen}, {@code /dev jumpscare}, {@code /dev backroomsscare} — operator
 * triggers of the Scare framework (F-064/F-065). All presentation lives client-side
 * ({@code client.scare.ScareDirector}); the servery bits are one payload send
 * ({@code scare.ScareService}) and, for the backrooms trip, the {@code scare.ScareTripService}
 * state machine. Nothing here messages regular players — scares are silent, personal and
 * leave no trace besides the operator audit line (the {@code DevGlitchCommands} convention).
 *
 * <ul>
 *   <li>{@code /dev ghostscreen <player>} — the ~10 s ghost arc: overlay ghost, glitch
 *       text, escalating glitch FX, ONE very loud bang.</li>
 *   <li>{@code /dev jumpscare <version> <player>} — one of the 30 distinct jumpscare
 *       scripts ({@code ScareIds.JUMPSCARES}, tab-completed).</li>
 *   <li>{@code /dev jumpscare list} — every version with its one-line description.</li>
 *   <li>{@code /dev backroomsscare <player>} — the ghost arc ending in a blackout "clip"
 *       into the backrooms dimension for 20–30 s (damage-proof, any hit bounces the player
 *       home; relog/stop safe via persisted return anchors).</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevScareCommands {
    private static final SuggestionProvider<CommandSourceStack> VERSION_SUGGESTIONS =
            (context, builder) -> SharedSuggestionProvider.suggest(ScareIds.JUMPSCARES, builder);

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("ghostscreen", DevCategory.PLAYERS, "/dev ghostscreen <player>",
                        "dev.eclipse.doc.ghostscreen", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("jumpscare", DevCategory.PLAYERS, "/dev jumpscare <version> <player>",
                        "dev.eclipse.doc.jumpscare", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("jumpscare.list", DevCategory.PLAYERS, "/dev jumpscare list",
                        "dev.eclipse.doc.jumpscare.list", Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("backroomsscare", DevCategory.PLAYERS, "/dev backroomsscare <player>",
                        "dev.eclipse.doc.backroomsscare", Danger.CAUTION, ClickAction.SUGGEST, 2));
    }

    private DevScareCommands() {}

    @SubscribeEvent
    static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(DevRoot::canUseDev)
                .then(Commands.literal("ghostscreen")
                        .then(Commands.argument("player", EntityArgument.player())
                                .executes(DevScareCommands::ghostscreen)))
                .then(Commands.literal("jumpscare")
                        // The literal is matched before the argument, so "list" stays a
                        // keyword AND tab-completes (the DevSkinCommands "reset" pattern).
                        .then(Commands.literal("list")
                                .executes(DevScareCommands::list))
                        .then(Commands.argument("version", StringArgumentType.word())
                                .suggests(VERSION_SUGGESTIONS)
                                .then(Commands.argument("player", EntityArgument.player())
                                        .executes(DevScareCommands::jumpscare))))
                .then(Commands.literal("backroomsscare")
                        .then(Commands.argument("player", EntityArgument.player())
                                .executes(DevScareCommands::backroomsScare))));
    }

    private static int ghostscreen(CommandContext<CommandSourceStack> context)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer target = EntityArgument.getPlayer(context, "player");
        ScareService.send(target, ScareIds.GHOSTSCREEN);
        audit(source, Component.translatable("dev.eclipse.scare.sent",
                        ScareIds.GHOSTSCREEN, target.getGameProfile().getName()),
                "ghostscreen " + target.getGameProfile().getName());
        return 1;
    }

    private static int jumpscare(CommandContext<CommandSourceStack> context)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        String version = StringArgumentType.getString(context, "version");
        if (!ScareIds.isJumpscare(version)) {
            source.sendFailure(Component.translatable("dev.eclipse.scare.unknown", version));
            return 0;
        }
        ServerPlayer target = EntityArgument.getPlayer(context, "player");
        ScareService.send(target, version);
        audit(source, Component.translatable("dev.eclipse.scare.sent",
                        version, target.getGameProfile().getName()),
                "jumpscare " + version + " " + target.getGameProfile().getName());
        return 1;
    }

    /** All 30 versions with their one-line descriptions (no audit — read-only). */
    private static int list(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.scare.list.header",
                ScareIds.JUMPSCARES.size()), false);
        for (String id : ScareIds.JUMPSCARES) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.scare.list.entry",
                    id, Component.translatable("dev.eclipse.scare.desc." + id)), false);
        }
        return ScareIds.JUMPSCARES.size();
    }

    private static int backroomsScare(CommandContext<CommandSourceStack> context)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer target = EntityArgument.getPlayer(context, "player");
        Component refusal = ScareTripService.begin(source.getServer(), target);
        if (refusal != null) {
            source.sendFailure(refusal);
            return 0;
        }
        audit(source, Component.translatable("dev.eclipse.scare.backrooms.started",
                        target.getGameProfile().getName()),
                "backroomsscare " + target.getGameProfile().getName());
        return 1;
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
