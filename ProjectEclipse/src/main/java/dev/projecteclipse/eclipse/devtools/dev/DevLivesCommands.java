package dev.projecteclipse.eclipse.devtools.dev;

import java.util.List;
import java.util.Locale;

import com.mojang.brigadier.CommandDispatcher;
import com.mojang.brigadier.arguments.IntegerArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.exceptions.CommandSyntaxException;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import dev.projecteclipse.eclipse.hearts.HeartsService;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.lives.BanService;
import dev.projecteclipse.eclipse.network.S2CHeartBurstPayload;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.network.hearts.HeartsPayloads;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.arguments.EntityArgument;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.RegisterCommandsEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * {@code /dev lives} ops tree (D13, W-SHARDS): SINGLE-player Leben mutation through
 * {@link LivesApi} — deliberately distinct from team-wide grants (those stay on their
 * own systems) and from the legacy perm-3 {@code /eclipse lives set|add}. Registered
 * through {@link DevCommandRegistry} from the static initializer (freeze-before-boot
 * rule); Brigadier merges the {@code /dev} roots across files.
 *
 * <p>{@code give <player> <n>} accepts NEGATIVE deltas for removal. The result is
 * clamped to {@code [0, MAX_HEARTS]}: capping at {@link HeartsService#MAX_HEARTS} is
 * reported, and hitting the 0 floor engages the standard ghost flow (the
 * {@code EclipseCommands.banIfOutOfLives} rule — zero Leben always means the ban flow,
 * never a 0-life player walking free). The opposite direction is symmetric for free:
 * {@link LivesApi#set}'s C4 hook unbans a ghost whose Leben come back.</p>
 *
 * <p>D13's {@code /dev chunk regen} half needs nothing here: W-DEVCMD's
 * {@code DevChunkCommands} + {@code worldgen.stage.ChunkRegenApi} landed with the real
 * engine, so no shell/seam is left in this package.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DevLivesCommands {
    static {
        DevCommandRegistry.register(
                new DevCommandDoc("lives.give", DevCategory.PLAYERS,
                        "/dev lives give <player> <n>",
                        "dev.eclipse.doc.lives.give", Danger.CAUTION, ClickAction.SUGGEST, 2),
                new DevCommandDoc("lives.status", DevCategory.PLAYERS,
                        "/dev lives status [player]",
                        "dev.eclipse.doc.lives.status", Danger.SAFE, ClickAction.RUN, 2),
                new DevCommandDoc("lives.burst", DevCategory.PLAYERS,
                        "/dev lives burst <player> <slot> <loss|gain|witness>",
                        "dev.eclipse.doc.lives.burst", Danger.SAFE, ClickAction.SUGGEST, 2));
    }

    private DevLivesCommands() {}

    @SubscribeEvent
    public static void onRegisterCommands(RegisterCommandsEvent event) {
        register(event.getDispatcher());
    }

    private static void register(CommandDispatcher<CommandSourceStack> dispatcher) {
        dispatcher.register(Commands.literal("dev")
                .requires(source -> source.hasPermission(2))
                .then(Commands.literal("lives")
                        .then(Commands.literal("give")
                                .then(Commands.argument("player", EntityArgument.player())
                                        .then(Commands.argument("amount", IntegerArgumentType.integer())
                                                .executes(DevLivesCommands::give))))
                        .then(Commands.literal("status")
                                .executes(context -> status(context, null))
                                .then(Commands.argument("player", EntityArgument.player())
                                        .executes(context -> status(context,
                                                EntityArgument.getPlayer(context, "player")))))
                        .then(Commands.literal("burst")
                                .then(Commands.argument("player", EntityArgument.player())
                                        .then(Commands.argument("slot",
                                                        IntegerArgumentType.integer(0, HeartsService.MAX_HEARTS - 1))
                                                .then(Commands.literal("loss")
                                                        .executes(context -> burst(context, BurstKind.LOSS)))
                                                .then(Commands.literal("gain")
                                                        .executes(context -> burst(context, BurstKind.GAIN)))
                                                .then(Commands.literal("witness")
                                                        .executes(context -> burst(context, BurstKind.WITNESS))))))));
    }

    private static int give(CommandContext<CommandSourceStack> context) throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer player = EntityArgument.getPlayer(context, "player");
        int delta = IntegerArgumentType.getInteger(context, "amount");
        int before = LivesApi.get(player);
        int target = Math.min(HeartsService.MAX_HEARTS, Math.max(0, before + delta));
        // LivesApi.set clamps >= 0 itself, applies max health, syncs the client, and
        // (C4 hook) revives a ghost on the 0 -> >0 transition.
        int applied = LivesApi.set(player, target);
        if (target != before + delta && before + delta > HeartsService.MAX_HEARTS) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.lives.give.capped",
                    HeartsService.MAX_HEARTS), false);
        }
        boolean bannedNow = banIfOutOfLives(player, applied);
        Component feedback = Component.translatable("dev.eclipse.lives.give.ok",
                player.getScoreboardName(), before, applied);
        audit(source, feedback, "set " + player.getScoreboardName() + "'s Leben " + before
                + " -> " + applied + " (delta " + (delta >= 0 ? "+" : "") + delta + ")"
                + (bannedNow ? " — event-banned (ghost flow)" : ""));
        if (bannedNow) {
            source.sendSuccess(() -> Component.translatable("dev.eclipse.lives.give.banned",
                    player.getScoreboardName()), false);
        }
        return applied;
    }

    /** The three W4-HEARTS burst lanes reachable through {@code /dev lives burst}. */
    private enum BurstKind { LOSS, GAIN, WITNESS }

    /**
     * W4-HEARTS acceptance trigger: replays one heart-burst FX lane on ONE player
     * without touching their Leben — {@code loss} is the hotbar shatter (the R8 hush
     * variant engages automatically when that player sits at exactly 1 Leben),
     * {@code gain} the R5 kill-transfer reverse burst, {@code witness} the world-space
     * R9 anchor quasar sent to the player themselves (the exact payload bystanders
     * receive) so single-client acceptance can SEE it. Pure client FX, zero state.
     */
    private static int burst(CommandContext<CommandSourceStack> context, BurstKind kind)
            throws CommandSyntaxException {
        CommandSourceStack source = context.getSource();
        ServerPlayer player = EntityArgument.getPlayer(context, "player");
        int slot = IntegerArgumentType.getInteger(context, "slot");
        switch (kind) {
            case LOSS -> PacketDistributor.sendToPlayer(player, new S2CHeartBurstPayload(slot));
            case GAIN -> HeartsPayloads.sendHeartBurstFx(player, slot, true);
            case WITNESS -> PacketDistributor.sendToPlayer(player, new S2CQuasarPayload(
                    S2CQuasarPayload.HEART_BURST, player.position().add(0.0D, 1.0D, 0.0D)));
        }
        String kindName = kind.name().toLowerCase(Locale.ROOT);
        audit(source, Component.translatable("dev.eclipse.lives.burst.ok",
                        kindName, player.getScoreboardName(), slot),
                "sent " + kindName + " heart burst to " + player.getScoreboardName()
                        + " (slot " + slot + ")");
        return 1;
    }

    /** The {@code EclipseCommands.banIfOutOfLives} rule: 0 Leben always means the ghost flow. */
    private static boolean banIfOutOfLives(ServerPlayer player, int lives) {
        if (lives > 0 || BanService.isBanned(player)) {
            return false;
        }
        BanService.ban(player);
        return true;
    }

    private static int status(CommandContext<CommandSourceStack> context, ServerPlayer only) {
        CommandSourceStack source = context.getSource();
        List<ServerPlayer> players = only != null
                ? List.of(only)
                : source.getServer().getPlayerList().getPlayers();
        source.sendSuccess(() -> Component.translatable("dev.eclipse.lives.status.header",
                players.size()), false);
        for (ServerPlayer player : players) {
            int lives = LivesApi.get(player);
            Component ghost = BanService.isBanned(player)
                    ? Component.translatable("dev.eclipse.lives.status.ghost")
                    : Component.empty();
            source.sendSuccess(() -> Component.translatable("dev.eclipse.lives.status.entry",
                    player.getScoreboardName(), lives, ghost), false);
        }
        return players.size();
    }

    /** The DevBuffCommands audit convention: feedback + ops echo + log line. */
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
