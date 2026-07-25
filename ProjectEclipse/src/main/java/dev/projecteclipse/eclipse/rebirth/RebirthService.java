package dev.projecteclipse.eclipse.rebirth;

import java.util.concurrent.atomic.AtomicBoolean;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import dev.projecteclipse.eclipse.economy.ShardEconomy;
import dev.projecteclipse.eclipse.hearts.HeartsService;
import dev.projecteclipse.eclipse.network.S2CAnnouncePayload;
import dev.projecteclipse.eclipse.network.S2CRebirthStatePayload;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.skills.RebirthHooks;
import dev.projecteclipse.eclipse.skills.SkillsApi;
import dev.projecteclipse.eclipse.skills.XpGates;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The D11 rebirth transaction — all-or-nothing on the server thread. Order: validate every
 * precondition, THEN consume shards, wipe skill progression (tree refund bookkeeping via
 * {@code SkillsApi.resetTree}, full wipe via {@code RebirthHooks.resetSkillProgression}),
 * grant the permanent Leben ({@link LivesApi}), record the count and run the ceremony.
 * No partial state is ever observable: every mutation happens after the last check.
 *
 * <p>Preconditions (see {@link RebirthApi.Result}): alive, not in an event dimension
 * ({@code XpGates.isEventDimension} — a limbo/minigame/xbox rebirth would dodge the
 * respawn/inventory rules of those worlds), personal shard balance ≥ {@code costForNext},
 * Leben below {@code HeartsService.MAX_HEARTS} (a capped rebirth would silently burn the
 * +1 — refuse with a message instead) and below the optional {@code maxRebirths} cap.</p>
 *
 * <p>Explicit non-goals of the reset (config {@code keepCollections}/{@code keepWand}):
 * collection-book progress and wand path/upgrades are never touched.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class RebirthService {
    private static final AtomicBoolean RELOAD_HOOK_REGISTERED = new AtomicBoolean();

    private RebirthService() {}

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        if (RELOAD_HOOK_REGISTERED.compareAndSet(false, true)) {
            dev.projecteclipse.eclipse.core.config.ReloadHooks.register("rebirth", RebirthConfig::reload);
        }
        RebirthConfig.reload();
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        RebirthConfig.invalidate();
    }

    /** Login sync so W-SKILLTREE's rebirth UI opens with fresh count/cost/multiplier. */
    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            syncTo(player);
        }
    }

    /**
     * Server entry point for {@code C2SRebirthPayload} (W-SKILLTREE's confirm button).
     * Everything is re-validated here — the client button state is advisory only. Refusals
     * answer on the action bar; success feedback is the ceremony itself.
     */
    public static void handleRebirthRequest(ServerPlayer player) {
        RebirthApi.Result result = tryRebirth(player);
        switch (result) {
            case OK -> { /* ceremony already played */ }
            case NOT_ALIVE -> { /* dead players get no action bar; silently ignore */ }
            case EVENT_DIMENSION -> player.displayClientMessage(
                    Component.translatable("rebirth.eclipse.refuse.dimension"), true);
            case NOT_ENOUGH_SHARDS -> player.displayClientMessage(
                    Component.translatable("rebirth.eclipse.refuse.shards",
                            RebirthApi.costForNext(player.server, player.getUUID()),
                            ShardEconomy.getShards(player)), true);
            case AT_LIFE_CAP -> player.displayClientMessage(
                    Component.translatable("rebirth.eclipse.refuse.life_cap", HeartsService.MAX_HEARTS), true);
            case MAX_REBIRTHS -> player.displayClientMessage(
                    Component.translatable("rebirth.eclipse.refuse.max",
                            RebirthConfig.get().maxRebirths()), true);
        }
        if (result != RebirthApi.Result.OK) {
            player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.PLAYERS, 0.5F, 1.2F);
        }
    }

    /** The transaction (see class doc). Called through {@link RebirthApi#tryRebirth}. */
    static RebirthApi.Result tryRebirth(ServerPlayer player) {
        return transact(player, false);
    }

    /**
     * Dev/admin surface ({@code /dev rebirth <player>}): one FREE ceremony — the shard
     * precondition and the deduction are skipped, every other check + effect is identical.
     */
    public static RebirthApi.Result forceRebirth(ServerPlayer player) {
        return transact(player, true);
    }

    private static RebirthApi.Result transact(ServerPlayer player, boolean free) {
        RebirthConfig.Data config = RebirthConfig.get();
        int count = RebirthApi.count(player.server, player.getUUID());
        if (!player.isAlive() || player.hasDisconnected()) {
            return RebirthApi.Result.NOT_ALIVE;
        }
        if (XpGates.isEventDimension(player.level().dimension())) {
            return RebirthApi.Result.EVENT_DIMENSION;
        }
        if (config.maxRebirths() > 0 && count >= config.maxRebirths()) {
            return RebirthApi.Result.MAX_REBIRTHS;
        }
        if (LivesApi.get(player) >= HeartsService.MAX_HEARTS) {
            return RebirthApi.Result.AT_LIFE_CAP;
        }
        int cost = free ? 0 : config.costForCount(count);
        if (!free && ShardEconomy.getShards(player) < cost) {
            return RebirthApi.Result.NOT_ENOUGH_SHARDS;
        }

        // --- last check passed: execute; every mutation below is unconditional ---
        if (cost > 0) {
            ShardEconomy.addShards(player, -cost);
        }
        // Refund bookkeeping first (spentPoints back), then the full progression wipe.
        SkillsApi.resetTree(player);
        RebirthHooks.resetSkillProgression(player);
        int gained = HeartsService.addPermanentLife(player, config.lifeRewardPerRebirth());
        int newCount = RebirthState.get(player.server).recordRebirth(player.getUUID(),
                System.currentTimeMillis());

        EclipseMod.LOGGER.info("{} was reborn (#{}, cost {} shards, +{} Leben, level costs now x{})",
                player.getScoreboardName(), newCount, cost, gained,
                String.format(java.util.Locale.ROOT, "%.3f",
                        RebirthApi.levelCostMultiplier(player.server, player.getUUID())));
        EclipseSignals.fireRebirth(player, newCount);
        ceremony(player, newCount);
        syncTo(player);
        return RebirthApi.Result.OK;
    }

    /** Fresh {@code S2CRebirthStatePayload} (count, next cost, multiplier, aura toggle) to one client. */
    public static void syncTo(ServerPlayer player) {
        int count = RebirthApi.count(player.server, player.getUUID());
        PacketDistributor.sendToPlayer(player, new S2CRebirthStatePayload(
                count,
                RebirthConfig.get().costForCount(count),
                (float) RebirthApi.levelCostMultiplier(player.server, player.getUUID()),
                RebirthState.get(player.server).auraEnabled(player.getUUID())));
    }

    /**
     * Ceremony FX/sounds/announcement: the NEWFX-B2 Starfall Rebirth cue at the reborn
     * player, a global typewriter announcement (unlock sweep) plus one named chat line,
     * and a resonance chime for everyone online.
     */
    private static void ceremony(ServerPlayer player, int newCount) {
        ServerLevel level = player.serverLevel();
        level.playSound(null, player.blockPosition(), SoundEvents.TOTEM_USE, SoundSource.PLAYERS, 1.0F, 0.8F);
        // NEWFX-B2 Starfall Rebirth: the old vanilla TOTEM/REVERSE_PORTAL/END_ROD
        // sendParticles spam is REMOVED and replaced in place by this cue — star
        // streaks converge into the player, an indraw shell collapses to a blinding
        // seam, then a wing-shell of violet fire snaps open and rains ash-glitter
        // (eclipse:rebirth_starfall, Mode.REPLACE; photon-less/reducedFx clients get
        // the eclipse:rebirth_ring Quasar leg). Entity lane so the ceremony rides the
        // reborn player; 64-block bystanders share it; a = new rebirth count (info).
        FxPayloads.sendFxEntityEvent(level, FxCues.CUE_REBIRTH_CEREMONY, player,
                newCount, 0.0F, 64.0D);

        PacketDistributor.sendToAllPlayers(new S2CAnnouncePayload(
                "announce.eclipse.rebirth.title", "announce.eclipse.rebirth.subtitle",
                S2CAnnouncePayload.STYLE_UNLOCK));
        player.server.getPlayerList().broadcastSystemMessage(Component.translatable(
                "rebirth.eclipse.announce", player.getDisplayName(), newCount, LivesApi.get(player)), false);
        for (ServerPlayer online : player.server.getPlayerList().getPlayers()) {
            online.playNotifySound(SoundEvents.AMETHYST_BLOCK_RESONATE, SoundSource.MASTER, 0.8F, 0.7F);
        }
    }
}
