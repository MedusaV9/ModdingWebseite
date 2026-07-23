package dev.projecteclipse.eclipse.devtools.dev;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.DoubleArgumentType;
import com.mojang.brigadier.arguments.FloatArgumentType;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;
import com.mojang.brigadier.suggestion.SuggestionProvider;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.devtools.display.DevToolItems;
import dev.projecteclipse.eclipse.devtools.display.DisplayPlacerService;
import net.minecraft.ChatFormatting;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.ClickEvent;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.HoverEvent;
import net.minecraft.network.chat.Style;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/** Operator command editor for SavedData-backed vanilla block displays. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevDisplayCommands {
    private static final SuggestionProvider<CommandSourceStack> DISPLAY_SUGGESTIONS =
            (context, builder) -> SharedSuggestionProvider.suggest(
                    DisplayPlacerService.get(context.getSource().getServer()).displays().stream()
                            .map(DisplayPlacerService.DisplayInfo::id),
                    builder);

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("display.give", DevCategory.DISPLAY,
                        "/dev display give", "dev.eclipse.doc.display.give",
                        Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("display.list", DevCategory.DISPLAY,
                        "/dev display list", "dev.eclipse.doc.display.list",
                        Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("display.param", DevCategory.DISPLAY,
                        "/dev display param <id> <axis|speed|bob|period|scale|glow|pos|delete> …",
                        "dev.eclipse.doc.display.param", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("display.clear", DevCategory.DISPLAY,
                        "/dev display clear", "dev.eclipse.doc.display.clear",
                        Danger.DESTRUCTIVE, ClickAction.RUN, 3));
    }

    private DevDisplayCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("display")
                        .then(Commands.literal("give")
                                .executes(DevDisplayCommands::give))
                        .then(Commands.literal("list")
                                .executes(DevDisplayCommands::list))
                        .then(Commands.literal("clear")
                                .requires(source -> source.hasPermission(3))
                                .executes(DevDisplayCommands::clear))
                        .then(Commands.literal("orbitals_rebuild")
                                .executes(DevDisplayCommands::rebuildOrbitals))
                        .then(Commands.literal("param")
                                .then(Commands.argument("id", StringArgumentType.word())
                                        .suggests(DISPLAY_SUGGESTIONS)
                                        .then(Commands.literal("axis")
                                                .then(Commands.argument("x", FloatArgumentType.floatArg(-1.0F, 1.0F))
                                                        .then(Commands.argument("y",
                                                                FloatArgumentType.floatArg(-1.0F, 1.0F))
                                                                .then(Commands.argument("z",
                                                                        FloatArgumentType.floatArg(-1.0F, 1.0F))
                                                                        .executes(context -> updateVector(
                                                                                context, "axis"))))))
                                        .then(scalar("speed", -360.0F, 360.0F))
                                        .then(scalar("bob", 0.0F, 16.0F))
                                        .then(scalar("period", 0.1F, 3600.0F))
                                        .then(scalar("scale", 0.05F, 16.0F))
                                        .then(Commands.literal("glow")
                                                .then(Commands.literal("on")
                                                        .executes(context -> glow(context, true)))
                                                .then(Commands.literal("off")
                                                        .executes(context -> glow(context, false))))
                                        .then(Commands.literal("pos")
                                                .then(Commands.argument("x",
                                                        DoubleArgumentType.doubleArg(-30_000_000.0D, 30_000_000.0D))
                                                        .then(Commands.argument("y",
                                                                DoubleArgumentType.doubleArg(-2048.0D, 2048.0D))
                                                                .then(Commands.argument("z",
                                                                        DoubleArgumentType.doubleArg(
                                                                                -30_000_000.0D, 30_000_000.0D))
                                                                        .executes(DevDisplayCommands::position)))))
                                        .then(Commands.literal("delete")
                                                .executes(DevDisplayCommands::delete))))));
    }

    private static com.mojang.brigadier.builder.LiteralArgumentBuilder<CommandSourceStack> scalar(
            String name, float min, float max) {
        return Commands.literal(name)
                .then(Commands.argument("value", FloatArgumentType.floatArg(min, max))
                        .executes(context -> updateScalar(context, name)));
    }

    private static int give(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        ServerPlayer player = context.getSource().getPlayerOrException();
        ItemStack wand = new ItemStack(DevToolItems.DISPLAY_WAND.get());
        if (!player.getInventory().add(wand)) {
            player.drop(wand, false);
        }
        context.getSource().sendSuccess(() -> Component.translatable("dev.eclipse.display.given"), false);
        return 1;
    }

    private static int list(CommandContext<CommandSourceStack> context) {
        var displays = DisplayPlacerService.get(context.getSource().getServer()).displays();
        context.getSource().sendSuccess(() -> Component.translatable(
                "dev.eclipse.display.list.header", displays.size()), false);
        context.getSource().sendSuccess(() -> Component.translatable(
                "dev.eclipse.display.axiom").withStyle(ChatFormatting.DARK_GRAY), false);
        for (DisplayPlacerService.DisplayInfo display : displays) {
            String command = "/dev display param " + display.id() + " ";
            Component line = Component.translatable("dev.eclipse.display.list.entry",
                    display.id(), BuiltInRegistries.BLOCK.getKey(display.blockState().getBlock()).toString(),
                    display.dimension().location().toString(),
                    String.format(java.util.Locale.ROOT, "%.1f %.1f %.1f",
                            display.basePos().x, display.basePos().y, display.basePos().z),
                    display.speedDegPerSec(), display.bobAmplitude(), display.bobPeriodSec(),
                    display.scale(), display.glow())
                    .withStyle(Style.EMPTY.withColor(ChatFormatting.LIGHT_PURPLE).withUnderlined(true)
                            .withClickEvent(new ClickEvent(ClickEvent.Action.SUGGEST_COMMAND, command))
                            .withHoverEvent(new HoverEvent(HoverEvent.Action.SHOW_TEXT,
                                    Component.translatable("dev.eclipse.display.list.hover"))));
            context.getSource().sendSuccess(() -> line, false);
        }
        return displays.size();
    }

    private static int updateVector(CommandContext<CommandSourceStack> context, String parameter) {
        return update(context, parameter,
                FloatArgumentType.getFloat(context, "x"),
                FloatArgumentType.getFloat(context, "y"),
                FloatArgumentType.getFloat(context, "z"));
    }

    private static int updateScalar(CommandContext<CommandSourceStack> context, String parameter) {
        return update(context, parameter, FloatArgumentType.getFloat(context, "value"), 0.0F, 0.0F);
    }

    private static int glow(CommandContext<CommandSourceStack> context, boolean enabled) {
        return update(context, "glow", enabled ? 1.0F : 0.0F, 0.0F, 0.0F);
    }

    private static int update(CommandContext<CommandSourceStack> context, String parameter,
            float a, float b, float c) {
        String id = StringArgumentType.getString(context, "id");
        if (!DisplayPlacerService.get(context.getSource().getServer()).update(id, parameter, a, b, c)) {
            context.getSource().sendFailure(Component.translatable("dev.eclipse.display.param.failed", id, parameter));
            return 0;
        }
        context.getSource().sendSuccess(() -> Component.translatable(
                "dev.eclipse.display.param.updated", id, parameter), true);
        return 1;
    }

    private static int position(CommandContext<CommandSourceStack> context) {
        String id = StringArgumentType.getString(context, "id");
        Vec3 pos = new Vec3(
                DoubleArgumentType.getDouble(context, "x"),
                DoubleArgumentType.getDouble(context, "y"),
                DoubleArgumentType.getDouble(context, "z"));
        if (!DisplayPlacerService.get(context.getSource().getServer())
                .move(context.getSource().getServer(), id, pos)) {
            context.getSource().sendFailure(Component.translatable("dev.eclipse.display.param.failed", id, "pos"));
            return 0;
        }
        context.getSource().sendSuccess(() -> Component.translatable(
                "dev.eclipse.display.param.updated", id, "pos"), true);
        return 1;
    }

    private static int delete(CommandContext<CommandSourceStack> context) {
        String id = StringArgumentType.getString(context, "id");
        if (!DisplayPlacerService.get(context.getSource().getServer())
                .delete(context.getSource().getServer(), id)) {
            context.getSource().sendFailure(Component.translatable("dev.eclipse.display.delete.none"));
            return 0;
        }
        context.getSource().sendSuccess(() -> Component.translatable("dev.eclipse.display.deleted", id), true);
        return 1;
    }

    private static int clear(CommandContext<CommandSourceStack> context) {
        int removed = DisplayPlacerService.get(context.getSource().getServer())
                .clear(context.getSource().getServer());
        context.getSource().sendSuccess(() -> Component.translatable(
                "dev.eclipse.display.cleared", removed), true);
        return removed;
    }

    /** P6-W56 hook: wipes and respawns the sanctum orbital ring (safe no-op while grounded). */
    private static int rebuildOrbitals(CommandContext<CommandSourceStack> context) {
        dev.projecteclipse.eclipse.worldgen.structure.SanctumOrbitals
                .rebuild(context.getSource().getServer().overworld());
        context.getSource().sendSuccess(() -> Component.translatable(
                "dev.eclipse.display.orbitals_rebuilt"), true);
        return 1;
    }
}
