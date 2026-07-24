package dev.projecteclipse.eclipse.devtools.dev;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.wizard.WizardData;
import dev.projecteclipse.eclipse.entity.wizard.WizardEntities;
import dev.projecteclipse.eclipse.entity.wizard.WizardOrinEntity;
import dev.projecteclipse.eclipse.entity.wizard.WizardService;
import dev.projecteclipse.eclipse.worldgen.structure.WizardObservatory;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.arguments.EntityArgument;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.item.ItemStack;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;

/**
 * {@code /dev wizard …} — operator controls of Orin the Sun-Reader (W4-WIZARD,
 * IDEA-19 §3/§4): the enable/disable switch (despawns + blocks respawn; the observatory
 * stays), a teleport to the hut, and the catalyst-quest test hooks (hand a catalyst,
 * reset a player's once-per-player ledger entry). All leaves are permission 3 per the
 * ideas doc's command table.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevWizardCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("wizard.enable", DevCategory.SPAWN,
                        "/dev wizard enable",
                        "dev.eclipse.doc.wizard.enable", Danger.SAFE, ClickAction.RUN, 3),
                new DevCommandDoc("wizard.disable", DevCategory.SPAWN,
                        "/dev wizard disable",
                        "dev.eclipse.doc.wizard.disable", Danger.CAUTION, ClickAction.RUN, 3),
                new DevCommandDoc("wizard.tp", DevCategory.SPAWN,
                        "/dev wizard tp",
                        "dev.eclipse.doc.wizard.tp", Danger.SAFE, ClickAction.RUN, 3),
                new DevCommandDoc("wizard.givecatalyst", DevCategory.SPAWN,
                        "/dev wizard givecatalyst <player>",
                        "dev.eclipse.doc.wizard.givecatalyst", Danger.CAUTION, ClickAction.SUGGEST, 3),
                new DevCommandDoc("wizard.resetquest", DevCategory.SPAWN,
                        "/dev wizard resetquest <player>",
                        "dev.eclipse.doc.wizard.resetquest", Danger.CAUTION, ClickAction.SUGGEST, 3));
    }

    private DevWizardCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("wizard")
                        .requires(source -> source.hasPermission(3))
                        .then(Commands.literal("enable")
                                .executes(context -> setEnabled(context.getSource(), true)))
                        .then(Commands.literal("disable")
                                .executes(context -> setEnabled(context.getSource(), false)))
                        .then(Commands.literal("tp")
                                .executes(context -> teleport(context.getSource())))
                        .then(Commands.literal("givecatalyst")
                                .then(Commands.argument("player", EntityArgument.player())
                                        .executes(context -> giveCatalyst(context.getSource(),
                                                EntityArgument.getPlayer(context, "player")))))
                        .then(Commands.literal("resetquest")
                                .then(Commands.argument("player", EntityArgument.player())
                                        .executes(context -> resetQuest(context.getSource(),
                                                EntityArgument.getPlayer(context, "player")))))));
    }

    /** Enable respawns Orin immediately (if his hut stands); disable despawns him. */
    private static int setEnabled(CommandSourceStack source, boolean enabled) {
        ServerLevel overworld = source.getServer().overworld();
        WizardData.get(overworld).setEnabled(enabled);
        if (enabled) {
            WizardService.ensureWizard(overworld);
        } else {
            WizardService.despawnWizard(overworld);
        }
        Component feedback = Component.translatable(
                enabled ? "dev.eclipse.wizard.enabled" : "dev.eclipse.wizard.disabled");
        source.sendSuccess(() -> feedback, true);
        EclipseMod.LOGGER.info("[DEV AUDIT] {} set wizard enabled={}", source.getTextName(), enabled);
        return 1;
    }

    /** Teleports the operator to the live Orin, else onto the observatory terrace. */
    private static int teleport(CommandSourceStack source) throws CommandSyntaxException {
        ServerPlayer player = source.getPlayerOrException();
        ServerLevel overworld = source.getServer().overworld();
        WizardOrinEntity orin = WizardService.resolve(overworld,
                WizardData.get(overworld).wizardUuid());
        if (orin != null && orin.isAlive()) {
            player.teleportTo(overworld, orin.getX(), orin.getY(), orin.getZ(),
                    player.getYRot(), player.getXRot());
            source.sendSuccess(() -> Component.translatable("dev.eclipse.wizard.tp.orin"), false);
            return 1;
        }
        BlockPos anchor = WizardObservatory.builtAnchor(overworld);
        if (anchor == null) {
            source.sendFailure(Component.translatable("dev.eclipse.wizard.tp.none"));
            return 0;
        }
        BlockPos top = WizardObservatory.surfaceProbe(overworld, anchor.offset(0, 0, 5));
        player.teleportTo(overworld, top.getX() + 0.5D, top.getY(), top.getZ() + 0.5D,
                player.getYRot(), player.getXRot());
        source.sendSuccess(() -> Component.translatable("dev.eclipse.wizard.tp.hut"), false);
        return 1;
    }

    /** Hands the target one catalyst (test hook — does NOT touch the quest ledger). */
    private static int giveCatalyst(CommandSourceStack source, ServerPlayer target) {
        if (!WizardEntities.WIZARD_CATALYST.isBound()) {
            source.sendFailure(Component.translatable("dev.eclipse.wizard.give.unbound"));
            return 0;
        }
        ItemStack catalyst = new ItemStack(WizardEntities.WIZARD_CATALYST.get());
        if (!target.getInventory().add(catalyst)) {
            target.drop(catalyst, false);
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.wizard.give.ok",
                target.getScoreboardName()), true);
        EclipseMod.LOGGER.info("[DEV AUDIT] {} gave a wizard catalyst to {}",
                source.getTextName(), target.getScoreboardName());
        return 1;
    }

    /** Re-opens the once-per-player fetch quest for the target. */
    private static int resetQuest(CommandSourceStack source, ServerPlayer target) {
        ServerLevel overworld = source.getServer().overworld();
        boolean changed = WizardData.get(overworld).resetCatalyst(target.getUUID());
        if (!changed) {
            source.sendFailure(Component.translatable("dev.eclipse.wizard.resetquest.noop",
                    target.getScoreboardName()));
            return 0;
        }
        source.sendSuccess(() -> Component.translatable("dev.eclipse.wizard.resetquest.ok",
                target.getScoreboardName()), true);
        EclipseMod.LOGGER.info("[DEV AUDIT] {} reset the wizard quest for {}",
                source.getTextName(), target.getScoreboardName());
        return 1;
    }
}
