package dev.projecteclipse.eclipse.worldgen;

import java.nio.file.Path;
import java.util.Arrays;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.suggestion.SuggestionProvider;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldgenState;
import dev.projecteclipse.eclipse.worldgen.fog.FogStormSites;
import dev.projecteclipse.eclipse.worldgen.fog.StormLootData;
import dev.projecteclipse.eclipse.worldgen.ore.OreConfig;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.network.chat.Component;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * Operator surface for per-save worldgen configuration and event flags. The command
 * self-registers on NeoForge's command event and requires permission level two.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EclipseWorldgenCommand {
    private static final SuggestionProvider<CommandSourceStack> PENDING_SITE_SUGGESTIONS =
            (context, builder) -> SharedSuggestionProvider.suggest(
                    StructurePendingRegistry.pending().stream()
                            .map(StructurePendingRegistry.PendingSite::siteId),
                    builder);

    private EclipseWorldgenCommand() {}

    /** Registers {@code /eclipse-worldgen} on every server command dispatcher. */
    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("eclipse-worldgen")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("reload").executes(EclipseWorldgenCommand::reload))
                .then(Commands.literal("refreeze")
                        .then(refreezeLiteral("stages"))
                        .then(refreezeLiteral("ores"))
                        .then(refreezeLiteral("fog"))
                        .then(refreezeLiteral("all")))
                .then(Commands.literal("breach")
                        .then(Commands.literal("open").executes(context -> setBreach(context, true)))
                        .then(Commands.literal("close").executes(context -> setBreach(context, false))))
                .then(Commands.literal("end")
                        .then(Commands.literal("materialize").executes(EclipseWorldgenCommand::materializeEnd)))
                .then(Commands.literal("structures")
                        .then(Commands.literal("list").executes(EclipseWorldgenCommand::listStructures))
                        .then(Commands.literal("place")
                                .then(Commands.argument("id", StringArgumentType.word())
                                        .suggests(PENDING_SITE_SUGGESTIONS)
                                        .executes(EclipseWorldgenCommand::placeStructure))))
                .then(Commands.literal("freeze")
                        .then(Commands.literal("status").executes(EclipseWorldgenCommand::freezeStatus))));
    }

    private static com.mojang.brigadier.builder.LiteralArgumentBuilder<CommandSourceStack> refreezeLiteral(
            String section) {
        return Commands.literal(section).executes(context -> refreeze(context, section));
    }

    private static int reload(CommandContext<CommandSourceStack> context) {
        Path saveDir = FrozenParams.saveEclipseDir();
        if (saveDir == null) {
            context.getSource().sendFailure(Component.translatable("command.eclipse.worldgen.no_freeze"));
            return 0;
        }
        OreConfig.reload(saveDir);
        StormLootData.reload(saveDir);
        FogStormSites.reloadFromSave();
        context.getSource().sendSuccess(
                () -> Component.translatable("command.eclipse.worldgen.reload"), true);
        return 1;
    }

    private static int refreeze(CommandContext<CommandSourceStack> context, String section) {
        String frozenSection = "fog".equals(section) ? "fogstorms" : section;
        String result = FrozenParams.refreeze(context.getSource().getServer(), frozenSection);
        if (result.startsWith("ERROR:")) {
            context.getSource().sendFailure(
                    Component.translatable("command.eclipse.worldgen.refreeze_failed", result));
            return 0;
        }
        context.getSource().sendSuccess(
                () -> Component.translatable("command.eclipse.worldgen.refreeze", section), true);
        return 1;
    }

    private static int setBreach(CommandContext<CommandSourceStack> context, boolean open) {
        if (open) {
            // openNow deliberately repairs/replays even when the flag is already set
            // (W1.7 wiring); the stage listener path only fires while the flag is false.
            dev.projecteclipse.eclipse.worldgen.nether.BreachBuilder.openNow(
                    context.getSource().getServer().overworld());
        } else {
            EclipseWorldgenState.get(context.getSource().getServer()).setBreachOpen(false);
        }
        context.getSource().sendSuccess(
                () -> Component.translatable("command.eclipse.worldgen.breach", open), true);
        return 1;
    }

    private static int materializeEnd(CommandContext<CommandSourceStack> context) {
        dev.projecteclipse.eclipse.worldgen.end.EndDiscService.materialize(
                context.getSource().getServer());
        context.getSource().sendSuccess(
                () -> Component.translatable("command.eclipse.worldgen.end_materialized"), true);
        return 1;
    }

    private static int listStructures(CommandContext<CommandSourceStack> context) {
        var pending = StructurePendingRegistry.pending();
        var placed = StructurePendingRegistry.placedSiteIds();
        context.getSource().sendSuccess(() -> Component.translatable(
                "command.eclipse.worldgen.structures_header", pending.size(), placed.size(),
                BudgetedBlockWriter.queuedJobs()), false);
        for (StructurePendingRegistry.PendingSite site : pending) {
            context.getSource().sendSuccess(() -> Component.translatable(
                    "command.eclipse.worldgen.structure_pending", site.siteId(),
                    site.structureId(), site.anchor().toShortString()), false);
        }
        for (String siteId : placed) {
            context.getSource().sendSuccess(() -> Component.translatable(
                    "command.eclipse.worldgen.structure_placed", siteId), false);
        }
        return pending.size() + placed.size();
    }

    private static int placeStructure(CommandContext<CommandSourceStack> context) {
        String siteId = StringArgumentType.getString(context, "id");
        if (!StructurePendingRegistry.trigger(siteId)) {
            context.getSource().sendFailure(Component.translatable(
                    "command.eclipse.worldgen.structure_missing", siteId));
            return 0;
        }
        context.getSource().sendSuccess(() -> Component.translatable(
                "command.eclipse.worldgen.structure_triggered", siteId), true);
        return 1;
    }

    private static int freezeStatus(CommandContext<CommandSourceStack> context) {
        FrozenParams.Context frozen = FrozenParams.current();
        if (frozen == null) {
            context.getSource().sendFailure(Component.translatable("command.eclipse.worldgen.no_freeze"));
            return 0;
        }
        context.getSource().sendSuccess(() -> Component.translatable(
                "command.eclipse.worldgen.freeze_status",
                Long.toUnsignedString(frozen.mapSeed()),
                Arrays.toString(frozen.overworldRadii()),
                Arrays.toString(frozen.netherRadii()),
                String.valueOf(FrozenParams.saveEclipseDir())), false);
        return 1;
    }
}
