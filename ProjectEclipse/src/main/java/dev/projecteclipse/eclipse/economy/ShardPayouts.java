package dev.projecteclipse.eclipse.economy;

import java.util.List;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
import net.minecraft.ChatFormatting;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;

/**
 * FIX-ECON boss shard routing (EVAL-DOPA-F §4 / DOPA-S-03 / EVAL-SAT-S #3). Boss payouts
 * (Herald / Rift Warden / Fog Tyrant) used to pay only physical shard items — team-pool
 * value that could never fund the personal rebirth balance. Every boss payout now splits
 * 50/50: half (ROUNDED UP) lands on the personal {@link ShardEconomy} balance (the rebirth
 * currency, with the D14 gain toast), the rest stays a physical direct-to-inventory
 * delivery (team-pool value, with the materialize ceremony).
 *
 * <p>Participants who are offline, dead or out of the boss dimension at ceremony time are
 * no longer silently skipped: their split is queued in the persisted {@link ShardLedger}
 * (stable kill-scoped id, claim-before-give) and paid at their next login.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ShardPayouts {
    private ShardPayouts() {}

    /** Personal-balance half of a boss payout: 50% rounded UP (EVAL-DOPA-F §4). */
    public static int personalShare(int totalShards) {
        return (totalShards + 1) / 2;
    }

    /**
     * Splits {@code totalShards} (personal rounds up, rest physical) and delivers it now
     * when the participant is online, alive and still in {@code level} — otherwise the
     * split waits in the {@link ShardLedger} for the next login. Idempotent by
     * {@code payoutId} (queue-then-claim), so a crash replay of a boss death ceremony can
     * never double-pay.
     *
     * @return the paid player when delivered immediately (callers hang their ceremony FX
     *         off this), or {@code null} when queued or already delivered
     */
    public static ServerPlayer deliverOrQueue(ServerLevel level, UUID playerId, String payoutId,
            int totalShards) {
        if (playerId == null || totalShards <= 0) {
            return null;
        }
        int personal = personalShare(totalShards);
        int physical = totalShards - personal;
        ShardLedger ledger = ShardLedger.get(level.getServer());
        ledger.queue(playerId, new ShardLedger.PendingGrant(payoutId, personal, physical));
        ServerPlayer player = level.getServer().getPlayerList().getPlayer(playerId);
        if (player == null || !player.isAlive() || player.level() != level) {
            // EVAL-SAT-S #3: no silent skip — the grant waits in the ledger for next login.
            EclipseMod.LOGGER.info("Shard payout {} ({} personal / {} physical) queued for "
                    + "offline/dead/absent participant {}", payoutId, personal, physical, playerId);
            return null;
        }
        if (!ledger.claim(playerId, payoutId)) {
            return null; // already delivered (crash replay guard)
        }
        grant(player, personal, physical, true);
        return player;
    }

    /** Login delivery of queued grants (offline boss payouts — EVAL-SAT-S #3). */
    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        ShardLedger ledger = ShardLedger.get(player.server);
        for (ShardLedger.PendingGrant grant : List.copyOf(ledger.pending(player.getUUID()))) {
            if (!ledger.claim(player.getUUID(), grant.id())) {
                continue;
            }
            // No materialize ceremony on login (the kill moment is long gone) — the gain
            // toast + a chat receipt make the late payout legible instead.
            grant(player, grant.personalShards(), grant.physicalShards(), false);
            if (grant.physicalShards() > 0) {
                player.displayClientMessage(ServerLang.tr(player,
                        "eclipse.shards.payout.late_physical",
                        grant.personalShards(), grant.physicalShards())
                        .withStyle(ChatFormatting.GOLD), false);
            } else {
                player.displayClientMessage(ServerLang.tr(player,
                        "eclipse.shards.payout.late", grant.personalShards())
                        .withStyle(ChatFormatting.GOLD), false);
            }
            EclipseMod.LOGGER.info("Delivered late shard payout {} ({} personal / {} physical) to {}",
                    grant.id(), grant.personalShards(), grant.physicalShards(),
                    player.getScoreboardName());
        }
    }

    /**
     * One split grant: personal half through {@link ShardEconomy#addShards} (rebirth
     * currency, D14 gain toast), physical half through
     * {@link ShardEconomy#deliverShardItems} (team-pool value; {@code overlay} plays the
     * materialize ceremony on immediate boss payouts, quiet on login catch-up).
     */
    private static void grant(ServerPlayer player, int personal, int physical, boolean overlay) {
        if (personal > 0) {
            ShardEconomy.addShards(player, personal, true);
        }
        if (physical > 0) {
            ShardEconomy.deliverShardItems(player, physical, overlay);
        }
    }
}
