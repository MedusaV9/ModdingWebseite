package dev.projecteclipse.eclipse.devtools.dev;

import java.util.function.Consumer;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.wand.EclipseWandItem;
import dev.projecteclipse.eclipse.wand.WandConfig;
import dev.projecteclipse.eclipse.wand.WandItems;
import dev.projecteclipse.eclipse.wand.WandPath;
import dev.projecteclipse.eclipse.wand.WandSoulbind;
import dev.projecteclipse.eclipse.wand.WandStore;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.arguments.EntityArgument;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.Mth;
import net.minecraft.world.item.ItemStack;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev wand …} — event-ops controls for the Zauberstab (W4-WAND spec §7, all
 * permission 2):
 *
 * <ul>
 *   <li>{@code disable <minutes>} / {@code enable} — global cast kill-switch (wands stay
 *       holdable; every cast is refused with a countdown message).</li>
 *   <li>{@code trading on|off} — suppresses soulbind conversion so wands can be handed
 *       over deliberately (non-owners still cannot cast).</li>
 *   <li>{@code mode player|item} — flips between per-PLAYER progression (default; the
 *       {@code WandStore} table is the truth) and per-ITEM progression (the stack keeps
 *       its own levels; stealing a leveled wand keeps it leveled).</li>
 *   <li>{@code set <player> path|level|xp|charge …} / {@code reset <player>} — test
 *       hooks; edits apply to the store row (PLAYER mode) AND all wands the target
 *       currently owns in their inventory, so changes are visible instantly.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevWandCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("wand.disable", DevCategory.PLAYERS,
                        "/dev wand disable <minutes>",
                        "dev.eclipse.doc.wand.disable", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("wand.enable", DevCategory.PLAYERS,
                        "/dev wand enable",
                        "dev.eclipse.doc.wand.enable", Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("wand.trading", DevCategory.PLAYERS,
                        "/dev wand trading on|off",
                        "dev.eclipse.doc.wand.trading", Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("wand.mode", DevCategory.PLAYERS,
                        "/dev wand mode player|item",
                        "dev.eclipse.doc.wand.mode", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("wand.set", DevCategory.PLAYERS,
                        "/dev wand set <player> path|level|xp|charge <value>",
                        "dev.eclipse.doc.wand.set", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("wand.reset", DevCategory.PLAYERS,
                        "/dev wand reset <player>",
                        "dev.eclipse.doc.wand.reset", Danger.DESTRUCTIVE, ClickAction.SUGGEST, 2));
    }

    private DevWandCommands() {}

    @SubscribeEvent
    static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("wand")
                        .requires(source -> source.hasPermission(2))
                        .then(Commands.literal("disable")
                                .then(Commands.argument("minutes", IntegerArgumentType.integer(1, 10_080))
                                        .executes(context -> disable(context.getSource(),
                                                IntegerArgumentType.getInteger(context, "minutes")))))
                        .then(Commands.literal("enable")
                                .executes(context -> enable(context.getSource())))
                        .then(Commands.literal("trading")
                                .then(Commands.literal("on")
                                        .executes(context -> trading(context.getSource(), true)))
                                .then(Commands.literal("off")
                                        .executes(context -> trading(context.getSource(), false))))
                        .then(Commands.literal("mode")
                                .then(Commands.literal("player")
                                        .executes(context -> mode(context.getSource(), false)))
                                .then(Commands.literal("item")
                                        .executes(context -> mode(context.getSource(), true))))
                        .then(Commands.literal("set")
                                .then(Commands.argument("player", EntityArgument.player())
                                        .then(Commands.literal("path")
                                                .then(pathLiteral("none", WandPath.NONE))
                                                .then(pathLiteral("riss", WandPath.RISS))
                                                .then(pathLiteral("glut", WandPath.GLUT))
                                                .then(pathLiteral("stern", WandPath.STERN)))
                                        .then(Commands.literal("level")
                                                .then(Commands.argument("value",
                                                                IntegerArgumentType.integer(1, WandPath.MAX_LEVEL))
                                                        .executes(context -> setLevel(context.getSource(),
                                                                EntityArgument.getPlayer(context, "player"),
                                                                IntegerArgumentType.getInteger(context, "value")))))
                                        .then(Commands.literal("xp")
                                                .then(Commands.argument("value",
                                                                IntegerArgumentType.integer(0))
                                                        .executes(context -> setXp(context.getSource(),
                                                                EntityArgument.getPlayer(context, "player"),
                                                                IntegerArgumentType.getInteger(context, "value")))))
                                        .then(Commands.literal("charge")
                                                .then(Commands.argument("value",
                                                                IntegerArgumentType.integer(0))
                                                        .executes(context -> setCharge(context.getSource(),
                                                                EntityArgument.getPlayer(context, "player"),
                                                                IntegerArgumentType.getInteger(context, "value")))))))
                        .then(Commands.literal("reset")
                                .then(Commands.argument("player", EntityArgument.player())
                                        .executes(context -> reset(context.getSource(),
                                                EntityArgument.getPlayer(context, "player")))))));
    }

    private static com.mojang.brigadier.builder.LiteralArgumentBuilder<CommandSourceStack> pathLiteral(
            String name, WandPath path) {
        return Commands.literal(name).executes(context -> setPath(context.getSource(),
                EntityArgument.getPlayer(context, "player"), path));
    }

    // ------------------------------------------------------------------ globals

    private static int disable(CommandSourceStack source, int minutes) {
        WandStore.get(source.getServer()).disableForMinutes(minutes);
        source.sendSuccess(() -> Component.translatable("dev.eclipse.wand.disabled", minutes), true);
        return 1;
    }

    private static int enable(CommandSourceStack source) {
        WandStore.get(source.getServer()).enable();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.wand.enabled"), true);
        return 1;
    }

    private static int trading(CommandSourceStack source, boolean on) {
        WandStore.get(source.getServer()).setTradingEnabled(on);
        source.sendSuccess(() -> Component.translatable(
                on ? "dev.eclipse.wand.trading.on" : "dev.eclipse.wand.trading.off"), true);
        return 1;
    }

    private static int mode(CommandSourceStack source, boolean perItem) {
        WandStore.get(source.getServer()).setPerItemMode(perItem);
        source.sendSuccess(() -> Component.translatable(
                perItem ? "dev.eclipse.wand.mode.item" : "dev.eclipse.wand.mode.player"), true);
        return 1;
    }

    // ------------------------------------------------------------------ per-player edits

    private static int setPath(CommandSourceStack source, ServerPlayer target, WandPath path)
            throws CommandSyntaxException {
        WandStore store = WandStore.get(source.getServer());
        if (!store.perItemMode()) {
            WandStore.Progress row = store.progress(target.getUUID());
            row.pathId = path.id();
            if (path == WandPath.NONE) {
                row.level = 1;
                row.xp = 0;
            }
            store.setDirty();
        }
        int touched = forEachOwnedWand(target, stack -> {
            stack.set(WandItems.WAND_PATH.get(), path.id());
            if (path == WandPath.NONE) {
                stack.set(WandItems.WAND_LEVEL.get(), 1);
                stack.set(WandItems.WAND_XP.get(), 0);
            }
            WandSoulbind.clampSelected(stack);
        });
        sendEditFeedback(source, target, touched,
                Component.translatable("dev.eclipse.wand.set.path", target.getDisplayName(),
                        Component.translatable(path == WandPath.NONE
                                ? "wand.eclipse.path.none" : path.langKey())));
        return 1;
    }

    private static int setLevel(CommandSourceStack source, ServerPlayer target, int level) {
        WandStore store = WandStore.get(source.getServer());
        if (!store.perItemMode()) {
            WandStore.Progress row = store.progress(target.getUUID());
            row.level = level;
            row.xp = 0;
            store.setDirty();
        }
        int touched = forEachOwnedWand(target, stack -> {
            stack.set(WandItems.WAND_LEVEL.get(), level);
            stack.set(WandItems.WAND_XP.get(), 0);
            WandSoulbind.clampSelected(stack);
        });
        sendEditFeedback(source, target, touched,
                Component.translatable("dev.eclipse.wand.set.level", target.getDisplayName(), level));
        return 1;
    }

    private static int setXp(CommandSourceStack source, ServerPlayer target, int xp) {
        WandStore store = WandStore.get(source.getServer());
        if (!store.perItemMode()) {
            store.progress(target.getUUID()).xp = xp;
            store.setDirty();
        }
        int touched = forEachOwnedWand(target,
                stack -> stack.set(WandItems.WAND_XP.get(), xp));
        sendEditFeedback(source, target, touched,
                Component.translatable("dev.eclipse.wand.set.xp", target.getDisplayName(), xp));
        return 1;
    }

    private static int setCharge(CommandSourceStack source, ServerPlayer target, int charge) {
        int max = WandConfig.get().charge().max();
        int clamped = Mth.clamp(charge, 0, max);
        int touched = forEachOwnedWand(target,
                stack -> stack.set(WandItems.WAND_CHARGE.get(), clamped));
        if (touched == 0) {
            source.sendFailure(Component.translatable("dev.eclipse.wand.no_wand",
                    target.getDisplayName()));
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.wand.set.charge",
                target.getDisplayName(), clamped, max), true);
        return 1;
    }

    private static int reset(CommandSourceStack source, ServerPlayer target) {
        WandStore.get(source.getServer()).reset(target.getUUID());
        int touched = forEachOwnedWand(target, stack -> {
            stack.set(WandItems.WAND_PATH.get(), WandPath.NONE.id());
            stack.set(WandItems.WAND_LEVEL.get(), 1);
            stack.set(WandItems.WAND_XP.get(), 0);
            stack.set(WandItems.WAND_SELECTED.get(), 0);
        });
        final int count = touched;
        source.sendSuccess(() -> Component.translatable("dev.eclipse.wand.reset",
                target.getDisplayName(), count), true);
        return 1;
    }

    // ------------------------------------------------------------------ helpers

    /** Applies {@code edit} to every wand in the target's inventory that the target OWNS. */
    private static int forEachOwnedWand(ServerPlayer target, Consumer<ItemStack> edit) {
        int touched = 0;
        for (int slot = 0; slot < target.getInventory().getContainerSize(); slot++) {
            ItemStack stack = target.getInventory().getItem(slot);
            if (stack.getItem() instanceof EclipseWandItem && WandSoulbind.isOwner(target, stack)) {
                edit.accept(stack);
                touched++;
            }
        }
        return touched;
    }

    private static void sendEditFeedback(CommandSourceStack source, ServerPlayer target,
            int touchedStacks, Component message) {
        boolean perItem = WandStore.get(source.getServer()).perItemMode();
        if (perItem && touchedStacks == 0) {
            // ITEM mode has no store row to edit — no held wand means nothing changed.
            source.sendFailure(Component.translatable("dev.eclipse.wand.no_wand",
                    target.getDisplayName()));
            return;
        }
        source.sendSuccess(() -> message, true);
    }
}
