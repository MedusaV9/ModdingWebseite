package dev.projecteclipse.eclipse.devtools.dev;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.suggestion.SuggestionProvider;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.eventdim.PortalAutoRoll;
import dev.projecteclipse.eclipse.eventdim.PortalEventScheduler;
import dev.projecteclipse.eclipse.eventdim.PortalEventsConfig;
import net.minecraft.ChatFormatting;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev portal …} (plans_v5 PLAN-C C18 §7) — the ONE dev surface over the
 * {@link PortalEventScheduler} variant registry:
 *
 * <ul>
 *   <li>{@code /dev portal <variant> open|close} — starts/stops the named portal event
 *       ({@code xbox}, {@code backrooms}, future variants self-register into the same
 *       tree; the suggestion provider reads the live registry).</li>
 *   <li>{@code /dev portal roll} — the weighted rarity lottery
 *       (COMMON {@code 4} : RARE {@code 1}), then opens whatever it drew — the ops
 *       one-liner for "surprise portal night".</li>
 *   <li>{@code /dev portal list} — variants with rarity weights.</li>
 * </ul>
 *
 * <p>Registers its own {@code /dev} root subtree (Brigadier merges roots — the
 * {@code DevBackroomsCommands} precedent). Adding a variant is the 1-page recipe in
 * {@code docs/plans_v3/plans_v5/PORTAL_RECIPE.md}.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevPortalCommands {

    static {
        DevCommandRegistry.register(
                new DevCommandDoc("portal.open", DevCategory.EVENT,
                        "/dev portal <variant> open",
                        "dev.eclipse.doc.portal.open", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("portal.close", DevCategory.EVENT,
                        "/dev portal <variant> close",
                        "dev.eclipse.doc.portal.close", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("portal.roll", DevCategory.EVENT,
                        "/dev portal roll",
                        "dev.eclipse.doc.portal.roll", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("portal.list", DevCategory.EVENT,
                        "/dev portal list",
                        "dev.eclipse.doc.portal.list", Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("portal.auto", DevCategory.EVENT,
                        "/dev portal auto on|off",
                        "dev.eclipse.doc.portal.auto", Danger.CAUTION, ClickAction.SUGGEST, 2));
    }

    /** Live registry suggestions — future variants appear without touching this file. */
    private static final SuggestionProvider<CommandSourceStack> VARIANT_SUGGESTIONS =
            (context, builder) -> SharedSuggestionProvider.suggest(
                    PortalEventScheduler.ids(), builder);

    private DevPortalCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("portal")
                        .then(Commands.literal("list")
                                .executes(DevPortalCommands::list))
                        .then(Commands.literal("roll")
                                .executes(DevPortalCommands::roll))
                        .then(Commands.literal("auto")
                                .then(Commands.literal("on")
                                        .executes(context -> auto(context, true)))
                                .then(Commands.literal("off")
                                        .executes(context -> auto(context, false))))
                        .then(Commands.argument("variant", StringArgumentType.word())
                                .suggests(VARIANT_SUGGESTIONS)
                                .then(Commands.literal("open")
                                        .executes(context -> open(context,
                                                StringArgumentType.getString(context, "variant"))))
                                .then(Commands.literal("close")
                                        .executes(context -> close(context,
                                                StringArgumentType.getString(context, "variant")))))));
    }

    // ------------------------------------------------------------------ handlers

    private static int open(CommandContext<CommandSourceStack> context, String variantId) {
        CommandSourceStack source = context.getSource();
        ServerPlayer operator = source.getEntity() instanceof ServerPlayer player ? player : null;
        Component error = PortalEventScheduler.open(source.getServer(), variantId, operator);
        if (error != null) {
            source.sendFailure(error);
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.portal.opened", variantId), true);
        return 1;
    }

    private static int close(CommandContext<CommandSourceStack> context, String variantId) {
        CommandSourceStack source = context.getSource();
        Component error = PortalEventScheduler.close(source.getServer(), variantId);
        if (error != null) {
            source.sendFailure(error);
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.portal.closed", variantId), true);
        return 1;
    }

    /**
     * V5-FIXGUARD / EVAL-SAT-F #3: toggles the {@code portal_events.json} auto-roll gate
     * (persisted via {@link PortalEventsConfig#setAutoRoll}), then re-evaluates the
     * CURRENT day's slot immediately via {@link PortalAutoRoll#refresh}.
     */
    private static int auto(CommandContext<CommandSourceStack> context, boolean enable) {
        CommandSourceStack source = context.getSource();
        PortalEventsConfig.Values values = PortalEventsConfig.setAutoRoll(enable);
        PortalAutoRoll.refresh(source.getServer());
        source.sendSuccess(() -> Component.translatable(
                enable ? "dev.eclipse.portal.auto.on" : "dev.eclipse.portal.auto.off",
                values.minDay()), true);
        return 1;
    }

    /** Weighted lottery, then open — one verb for "run a random portal event now". */
    private static int roll(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        PortalEventScheduler.Variant variant =
                PortalEventScheduler.roll(source.getServer().overworld().getRandom());
        source.sendSuccess(() -> Component.translatable("dev.eclipse.portal.rolled",
                variant.id(), variant.rarity().name().toLowerCase(java.util.Locale.ROOT)), true);
        return open(context, variant.id());
    }

    private static int list(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.portal.list.header")
                .withStyle(ChatFormatting.GOLD), false);
        for (String id : PortalEventScheduler.ids()) {
            PortalEventScheduler.Variant variant = PortalEventScheduler.byId(id);
            if (variant == null) {
                continue;
            }
            source.sendSuccess(() -> Component.translatable("dev.eclipse.portal.list.entry",
                    id, variant.rarity().name().toLowerCase(java.util.Locale.ROOT),
                    variant.rarity().weight()), false);
        }
        return PortalEventScheduler.ids().size();
    }
}
