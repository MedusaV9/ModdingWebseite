package dev.projecteclipse.eclipse.devtools.dev;

import java.util.List;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.suggestion.SuggestionProvider;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.economy.ShardEconomy;
import dev.projecteclipse.eclipse.ritual.AltarAdminState;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.SharedSuggestionProvider;
import net.minecraft.network.chat.Component;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev altar} ops tree (ALTARUI task 9), registered through {@link DevCommandRegistry}
 * from the static initializer (freeze-before-boot rule) in the {@link DevShardCommands}
 * style — Brigadier merges the {@code /dev} roots across files, so no shared command file
 * is touched. Both toggles persist in {@link AltarAdminState} ({@code eclipse_altar_admin.dat}).
 *
 * <ul>
 *   <li>{@code /dev altar lock|unlock|status} — freezes/unfreezes the milestone LADDER:
 *       while locked, {@code AltarBlockEntity#handleMilestoneDeposit} refuses cost items
 *       before consuming anything, so the altar can never advance a stage mid-playtest.
 *       Banking, offerings, heart sacrifices and the shop keep working.</li>
 *   <li>{@code /dev altar offer disable|enable <offerId>} and {@code /dev altar offer list}
 *       — pulls individual shop offers from sale ({@code ShardEconomy.Offer#id}); disabled
 *       offers vanish from the browse cycle, the altar panel and the buy path.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevAltarCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("altar.lock", DevCategory.EVENT,
                        "/dev altar lock",
                        "dev.eclipse.doc.altar.lock", Danger.CAUTION, ClickAction.RUN, 2),
                new DevCommandDoc("altar.unlock", DevCategory.EVENT,
                        "/dev altar unlock",
                        "dev.eclipse.doc.altar.unlock", Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("altar.status", DevCategory.EVENT,
                        "/dev altar status",
                        "dev.eclipse.doc.altar.status", Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("altar.offer.disable", DevCategory.EVENT,
                        "/dev altar offer disable <offerId>",
                        "dev.eclipse.doc.altar.offer.disable", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("altar.offer.enable", DevCategory.EVENT,
                        "/dev altar offer enable <offerId>",
                        "dev.eclipse.doc.altar.offer.enable", Danger.SAFE, ClickAction.SUGGEST, 2),
                new DevCommandDoc("altar.offer.list", DevCategory.EVENT,
                        "/dev altar offer list",
                        "dev.eclipse.doc.altar.offer.list", Danger.SAFE, ClickAction.RUN, 2));
    }

    /** Tab completion: every configured offer id (including currently disabled ones). */
    private static final SuggestionProvider<CommandSourceStack> OFFER_IDS = (context, builder) ->
            SharedSuggestionProvider.suggest(
                    ShardEconomy.allOffers().stream().map(ShardEconomy.Offer::id), builder);

    private DevAltarCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("altar")
                        .then(Commands.literal("lock")
                                .executes(context -> setLocked(context, true)))
                        .then(Commands.literal("unlock")
                                .executes(context -> setLocked(context, false)))
                        .then(Commands.literal("status")
                                .executes(DevAltarCommands::status))
                        .then(Commands.literal("offer")
                                .then(Commands.literal("disable")
                                        .then(Commands.argument("offerId", StringArgumentType.word())
                                                .suggests(OFFER_IDS)
                                                .executes(context -> setOfferDisabled(context, true))))
                                .then(Commands.literal("enable")
                                        .then(Commands.argument("offerId", StringArgumentType.word())
                                                .suggests(OFFER_IDS)
                                                .executes(context -> setOfferDisabled(context, false))))
                                .then(Commands.literal("list")
                                        .executes(DevAltarCommands::listOffers)))));
    }

    private static int setLocked(CommandContext<CommandSourceStack> context, boolean locked) {
        CommandSourceStack source = context.getSource();
        AltarAdminState state = AltarAdminState.get(source.getServer());
        if (!state.setProgressionLocked(locked)) {
            source.sendSuccess(() -> Component.translatable(
                    locked ? "dev.eclipse.altar.already_locked" : "dev.eclipse.altar.already_unlocked"), false);
            return 0;
        }
        // Broadcast to ops (operator audit) like every other mutating /dev leaf.
        source.sendSuccess(() -> Component.translatable(
                locked ? "dev.eclipse.altar.locked" : "dev.eclipse.altar.unlocked"), true);
        EclipseMod.LOGGER.info("[dev] {} {} altar progression",
                source.getTextName(), locked ? "LOCKED" : "unlocked");
        return 1;
    }

    private static int status(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        AltarAdminState state = AltarAdminState.get(source.getServer());
        boolean locked = state.isProgressionLocked();
        int disabled = state.getDisabledOffers().size();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.altar.status",
                Component.translatable(locked ? "dev.eclipse.yes" : "dev.eclipse.no"), disabled), false);
        return locked ? 1 : 0;
    }

    private static int setOfferDisabled(CommandContext<CommandSourceStack> context, boolean disabled) {
        CommandSourceStack source = context.getSource();
        String offerId = StringArgumentType.getString(context, "offerId");
        if (ShardEconomy.offerById(offerId) == null) {
            source.sendFailure(Component.translatable("dev.eclipse.altar.offer.unknown", offerId));
            return 0;
        }
        AltarAdminState state = AltarAdminState.get(source.getServer());
        if (!state.setOfferDisabled(offerId, disabled)) {
            source.sendSuccess(() -> Component.translatable(disabled
                    ? "dev.eclipse.altar.offer.already_disabled"
                    : "dev.eclipse.altar.offer.already_enabled", offerId), false);
            return 0;
        }
        source.sendSuccess(() -> Component.translatable(disabled
                ? "dev.eclipse.altar.offer.disabled" : "dev.eclipse.altar.offer.enabled", offerId), true);
        EclipseMod.LOGGER.info("[dev] {} {} altar shop offer '{}'",
                source.getTextName(), disabled ? "disabled" : "enabled", offerId);
        return 1;
    }

    private static int listOffers(CommandContext<CommandSourceStack> context) {
        CommandSourceStack source = context.getSource();
        AltarAdminState state = AltarAdminState.get(source.getServer());
        List<ShardEconomy.Offer> offers = ShardEconomy.allOffers();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.altar.offer.list.header",
                offers.size()), false);
        for (ShardEconomy.Offer offer : offers) {
            Component status = state.isOfferDisabled(offer.id())
                    ? Component.translatable("dev.eclipse.altar.offer.state.disabled")
                    : ShardEconomy.isOfferUnlocked(source.getServer(), offer)
                            ? Component.translatable("dev.eclipse.altar.offer.state.available")
                            : Component.translatable("dev.eclipse.altar.offer.state.day_locked", offer.minDay());
            source.sendSuccess(() -> Component.translatable("dev.eclipse.altar.offer.list.entry",
                    offer.id(), Component.translatable(offer.nameKey()), offer.cost(), status), false);
        }
        return offers.size();
    }
}
