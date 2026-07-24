package dev.projecteclipse.eclipse.devtools.dev;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.LongArgumentType;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.collections.CollectionTiers;
import dev.projecteclipse.eclipse.collections.CollectionsConfig;
import dev.projecteclipse.eclipse.collections.CollectionsService;
import dev.projecteclipse.eclipse.collections.CollectionsState;
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
 * {@code /dev collections} ops tree (D1 playtest verification), registered through
 * {@link DevCommandRegistry} from the static initializer (freeze-before-boot rule) in the
 * {@code DevShardCommands} style. Brigadier merges the {@code /dev} roots across files.
 *
 * <p>{@code set <collection> <count> [player]} hard-sets a lifetime counter through
 * {@link CollectionsService#setCount} — the SAME threshold sweep as organic play runs, so
 * newly crossed tiers pay XP/points, unlock recipes and toast exactly once (already-granted
 * tiers never re-pay or revoke: the fast way to verify the whole tier-up pipeline is
 * {@code /dev collections set iron 250}). {@code status [player]} prints every collection's
 * lifetime count and granted/total tiers from {@link CollectionsState}, including offline
 * defaults (zeros) for ids the player never touched.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevCollectionsCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("collections.set", DevCategory.ANALYTICS,
                        "/dev collections set <collection> <count> [player]",
                        "dev.eclipse.doc.collections.set", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("collections.status", DevCategory.ANALYTICS,
                        "/dev collections status [player]",
                        "dev.eclipse.doc.collections.status", Danger.SAFE, ClickAction.RUN, 2));
    }

    private DevCollectionsCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("collections")
                        .then(Commands.literal("set")
                                .then(Commands.argument("collection", StringArgumentType.word())
                                        .suggests((context, builder) -> SharedSuggestionProvider.suggest(
                                                CollectionsConfig.current().collections().stream()
                                                        .map(CollectionsConfig.Collection::id),
                                                builder))
                                        .then(Commands.argument("count", LongArgumentType.longArg(0))
                                                .executes(context -> set(context,
                                                        context.getSource().getPlayerOrException()))
                                                .then(Commands.argument("player", EntityArgument.player())
                                                        .executes(context -> set(context,
                                                                EntityArgument.getPlayer(context, "player")))))))
                        .then(Commands.literal("status")
                                .executes(context -> status(context,
                                        context.getSource().getPlayerOrException()))
                                .then(Commands.argument("player", EntityArgument.player())
                                        .executes(context -> status(context,
                                                EntityArgument.getPlayer(context, "player")))))));
    }

    private static int set(CommandContext<CommandSourceStack> context, ServerPlayer target)
            throws CommandSyntaxException {
        String collectionId = StringArgumentType.getString(context, "collection");
        long count = LongArgumentType.getLong(context, "count");
        if (!CollectionsService.setCount(target, collectionId, count)) {
            context.getSource().sendFailure(
                    Component.translatable("dev.eclipse.collections.unknown", collectionId));
            return 0;
        }
        int tier = CollectionsService.grantedTierOf(target.server, target.getUUID(), collectionId);
        context.getSource().sendSuccess(() -> Component.translatable("dev.eclipse.collections.set.ok",
                collectionId, count, target.getDisplayName(), CollectionTiers.roman(tier)), true);
        return 1;
    }

    private static int status(CommandContext<CommandSourceStack> context, ServerPlayer target) {
        CommandSourceStack source = context.getSource();
        CollectionsState.Entry entry = CollectionsState.get(target.server).entry(target.getUUID());
        var collections = CollectionsConfig.current().collections();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.collections.status.header",
                target.getDisplayName(), collections.size()), false);
        for (CollectionsConfig.Collection def : collections) {
            long count = entry.count(def.id());
            int granted = entry.grantedTier(def.id());
            source.sendSuccess(() -> Component.translatable("dev.eclipse.collections.status.line",
                    def.id(), CollectionTiers.formatCount(count), granted, def.tiers().size(),
                    def.lane()), false);
        }
        return collections.size();
    }
}
