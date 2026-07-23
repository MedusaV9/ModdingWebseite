package dev.projecteclipse.eclipse.devtools.dev;

import java.util.List;
import java.util.Locale;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;
import com.mojang.brigadier.suggestion.SuggestionProvider;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.network.chat.ClickEvent;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.HoverEvent;
import net.minecraft.network.chat.MutableComponent;
import net.minecraft.network.chat.Style;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;
import net.neoforged.neoforge.event.server.ServerStartingEvent;

/**
 * Registers the {@code /dev} Brigadier root (permission ≥ 2). Merges with sibling workers' subtrees
 * via separate {@link RegisterCommandsEvent} subscribers — never touches {@code EclipseCommands}.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevRoot {
    private static final int PAGE_SIZE = 8;

    private static final SuggestionProvider<CommandSourceStack> CATEGORY_SUGGESTIONS =
            (context, builder) -> net.minecraft.commands.SharedSuggestionProvider.suggest(
                    DevCommandRegistry.categoryNames(), builder);

    static {
        // Force legacy + core doc seeding before any worker registers.
        LegacyCommandDocs.bootstrap();
    }

    private DevRoot() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    @SubscribeEvent
    public static void onServerStarting(ServerStartingEvent event) {
        DevCommandRegistry.freeze();
        DevCommandRegistrySelfCheck.assertVisibleToFiltersPermission();
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .executes(DevRoot::openHandbookOrHelp)
                .then(Commands.literal("help")
                        .executes(ctx -> sendHelp(ctx, null, 1))
                        .then(Commands.argument("target", StringArgumentType.word())
                                .suggests(CATEGORY_SUGGESTIONS)
                                .executes(ctx -> {
                                    String target = StringArgumentType.getString(ctx, "target");
                                    if (target.chars().allMatch(Character::isDigit)) {
                                        return sendHelp(ctx, null, Integer.parseInt(target));
                                    }
                                    return sendHelp(ctx, target, 1);
                                })
                                .then(Commands.argument("page", IntegerArgumentType.integer(1))
                                        .executes(ctx -> sendHelp(ctx,
                                                StringArgumentType.getString(ctx, "target"),
                                                IntegerArgumentType.getInteger(ctx, "page"))))))
                .then(Commands.literal("docs")
                        .then(Commands.literal("export")
                                .executes(DevRoot::exportDocs)))
                .then(Commands.literal("reload")
                        .executes(ctx -> DevReload.execute(ctx.getSource()))));
    }

    private static int openHandbookOrHelp(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        if (source.getEntity() instanceof ServerPlayer player) {
            List<DevCommandDoc> visible = DevCommandRegistry.visibleTo(player);
            if (DevHandbookBridge.tryOpenHandbook(player, visible)) {
                source.sendSuccess(() -> Component.translatable("dev.eclipse.dev.handbook.opened"), true);
                return visible.size();
            }
        }
        return sendHelp(context, null, 1);
    }

    private static int sendHelp(CommandContext<CommandSourceStack> context, @javax.annotation.Nullable String categoryName,
            int page) throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        int perm = source.hasPermission(3) ? 3 : 2;
        List<DevCommandDoc> entries;
        DevCategory category = categoryName != null ? DevCommandRegistry.parseCategory(categoryName) : null;
        if (categoryName != null && category == null) {
            source.sendFailure(Component.translatable("dev.eclipse.help.unknown_category", categoryName));
            return 0;
        }
        if (category != null) {
            entries = DevCommandRegistry.byCategory(category, perm);
            source.sendSuccess(() -> Component.translatable("dev.eclipse.help.header.category",
                    Component.translatable(category.langKey())), false);
        } else {
            entries = DevCommandRegistry.visibleTo(perm);
            source.sendSuccess(() -> Component.translatable("dev.eclipse.help.header.all"), false);
        }

        if (entries.isEmpty()) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.help.empty"), false);
            return 0;
        }

        int totalPages = (entries.size() + PAGE_SIZE - 1) / PAGE_SIZE;
        int clampedPage = Math.min(Math.max(page, 1), totalPages);
        int from = (clampedPage - 1) * PAGE_SIZE;
        int to = Math.min(from + PAGE_SIZE, entries.size());

        for (int i = from; i < to; i++) {
            DevCommandDoc doc = entries.get(i);
            source.sendSuccess(() -> formatHelpEntry(doc), false);
        }

        int finalClampedPage = clampedPage;
        int finalTotalPages = totalPages;
        MutableComponent footer = Component.translatable("dev.eclipse.help.page", finalClampedPage, finalTotalPages);
        if (finalClampedPage < finalTotalPages) {
            String nextCmd = categoryName != null
                    ? String.format(Locale.ROOT, "/dev help %s %d", categoryName.toLowerCase(Locale.ROOT),
                            finalClampedPage + 1)
                    : String.format(Locale.ROOT, "/dev help %d", finalClampedPage + 1);
            footer.append(Component.translatable("dev.eclipse.help.next").withStyle(Style.EMPTY
                    .withClickEvent(new ClickEvent(ClickEvent.Action.RUN_COMMAND, nextCmd))
                    .withUnderlined(true)));
        }
        source.sendSuccess(() -> footer, false);
        return entries.size();
    }

    private static Component formatHelpEntry(DevCommandDoc doc) {
        MutableComponent line = clickableSyntax(doc);
        line.append(Component.literal(" — ").withStyle(Style.EMPTY.withColor(0xAAAAAA)));
        line.append(Component.translatable(doc.descKey()));
        if (doc.danger() != Danger.SAFE) {
            line.append(Component.literal(" [").withStyle(Style.EMPTY.withColor(dangerColor(doc.danger()))));
            line.append(Component.translatable(doc.danger().langKey())
                    .withStyle(Style.EMPTY.withColor(dangerColor(doc.danger()))));
            line.append(Component.literal("]").withStyle(Style.EMPTY.withColor(dangerColor(doc.danger()))));
        }
        if (doc.legacy()) {
            line.append(Component.translatable("dev.eclipse.help.legacy_suffix")
                    .withStyle(Style.EMPTY.withColor(0x888888).withItalic(true)));
        }
        return line;
    }

    private static MutableComponent clickableSyntax(DevCommandDoc doc) {
        String command = runnableCommand(doc);
        ClickEvent.Action action = doc.clickAction() == ClickAction.RUN ? ClickEvent.Action.RUN_COMMAND
                : ClickEvent.Action.SUGGEST_COMMAND;
        return Component.literal(doc.syntax()).withStyle(Style.EMPTY
                .withUnderlined(true)
                .withClickEvent(new ClickEvent(action, command))
                .withHoverEvent(new HoverEvent(HoverEvent.Action.SHOW_TEXT,
                        Component.translatable(doc.clickAction() == ClickAction.RUN
                                ? "dev.eclipse.help.hover.run"
                                : "dev.eclipse.help.hover.suggest"))));
    }

    /** Strips {@code <placeholders>} for RUN clicks on partially parameterized legacy syntax. */
    private static String runnableCommand(DevCommandDoc doc) {
        if (doc.clickAction() != ClickAction.RUN) {
            return doc.syntax();
        }
        String syntax = doc.syntax();
        int placeholder = syntax.indexOf(" <");
        if (placeholder > 0) {
            return syntax.substring(0, placeholder);
        }
        int ellipsis = syntax.indexOf('…');
        if (ellipsis > 0) {
            return syntax.substring(0, ellipsis).trim();
        }
        return syntax;
    }

    private static int dangerColor(Danger danger) {
        return switch (danger) {
            case SAFE -> 0x55FF55;
            case CAUTION -> 0xFFAA00;
            case DESTRUCTIVE -> 0xFF5555;
        };
    }

    private static int exportDocs(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        try {
            var path = DevDocsExporter.export(source.getServer());
            source.sendSuccess(() -> Component.translatable("dev.eclipse.docs.exported", path.toString()), false);
            return 1;
        } catch (Exception e) {
            source.sendFailure(Component.translatable("dev.eclipse.docs.export_failed",
                    e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName()));
            return 0;
        }
    }
}
