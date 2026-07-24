package dev.projecteclipse.eclipse.gametest.economy;

import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.economy.ShardEconomy;
import dev.projecteclipse.eclipse.economy.ShardLedger;
import dev.projecteclipse.eclipse.economy.ShardPayouts;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * FIX-ECON acceptance (EVAL-DOPA-F §4 / EVAL-SAT-S #3): the boss payout 50/50 split
 * (personal rounds UP), immediate delivery to online participants with a crash-replay
 * guard, offline queuing in the persisted {@link ShardLedger}, queue/claim idempotency
 * by stable grant id, and the SavedData NBT round-trip (including the torn-write
 * reconcile of a grant found both pending and delivered).
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class ShardLedgerTests {
    private ShardLedgerTests() {}

    @SuppressWarnings("removal")
    private static ServerPlayer mockServerPlayer(GameTestHelper helper) {
        return helper.makeMockServerPlayerInLevel();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void personalShareRoundsUp(GameTestHelper helper) {
        helper.assertTrue(ShardPayouts.personalShare(1) == 1, "share(1)=1");
        helper.assertTrue(ShardPayouts.personalShare(2) == 1, "share(2)=1");
        helper.assertTrue(ShardPayouts.personalShare(3) == 2, "share(3)=2 (rounds up)");
        helper.assertTrue(ShardPayouts.personalShare(4) == 2, "share(4)=2");
        helper.assertTrue(ShardPayouts.personalShare(5) == 3, "share(5)=3 (rounds up)");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void onlineSplitPaysOnceAndOfflineQueues(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        ServerPlayer player = mockServerPlayer(helper);
        UUID offline = UUID.randomUUID();
        String onlineId = "test:online:" + UUID.randomUUID();
        String offlineId = "test:offline:" + UUID.randomUUID();
        try {
            ShardEconomy.setShards(player, 0);
            int itemsBefore = player.getInventory().countItem(EclipseItems.UMBRAL_SHARD.get());

            // Online + alive + in-level: 3 shards split as 2 personal / 1 physical, now.
            ServerPlayer paid = ShardPayouts.deliverOrQueue(helper.getLevel(), player.getUUID(),
                    onlineId, 3);
            helper.assertTrue(paid == player, "online participant paid immediately");
            helper.assertTrue(ShardEconomy.getShards(player) == 2,
                    "2 personal shards banked, got " + ShardEconomy.getShards(player));
            helper.assertTrue(player.getInventory().countItem(EclipseItems.UMBRAL_SHARD.get())
                            == itemsBefore + 1, "1 physical shard delivered to inventory");

            // Crash-replay guard: the same payout id never pays twice.
            helper.assertTrue(ShardPayouts.deliverOrQueue(helper.getLevel(), player.getUUID(),
                    onlineId, 3) == null, "replayed payout id pays nothing");
            helper.assertTrue(ShardEconomy.getShards(player) == 2, "balance unchanged on replay");

            // Offline participant: no silent skip — the split waits in the ledger.
            helper.assertTrue(ShardPayouts.deliverOrQueue(helper.getLevel(), offline,
                    offlineId, 3) == null, "offline participant not paid now");
            ShardLedger ledger = ShardLedger.get(server);
            helper.assertTrue(ledger.pending(offline).size() == 1, "offline grant queued");
            ShardLedger.PendingGrant grant = ledger.pending(offline).get(0);
            helper.assertTrue(grant.personalShards() == 2 && grant.physicalShards() == 1,
                    "queued split is 2 personal / 1 physical");

            // Re-fire of the same ceremony never duplicates the queued grant.
            ShardPayouts.deliverOrQueue(helper.getLevel(), offline, offlineId, 3);
            helper.assertTrue(ledger.pending(offline).size() == 1, "no duplicate queue entry");
        } finally {
            // Shared-save hygiene: drain the test grant so no login ever pays it.
            ShardLedger.get(server).claim(offline, offlineId);
            server.getPlayerList().remove(player);
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void ledgerClaimIdempotencyAndNbtRoundTrip(GameTestHelper helper) {
        UUID uuid = UUID.randomUUID();
        ShardLedger ledger = new ShardLedger();

        helper.assertTrue(ledger.queue(uuid, new ShardLedger.PendingGrant("g1", 2, 1)), "g1 queued");
        helper.assertTrue(!ledger.queue(uuid, new ShardLedger.PendingGrant("g1", 2, 1)),
                "duplicate id rejected while pending");
        helper.assertTrue(ledger.queue(uuid, new ShardLedger.PendingGrant("g2", 1, 1)), "g2 queued");

        helper.assertTrue(ledger.claim(uuid, "g1"), "g1 claimed once");
        helper.assertTrue(!ledger.claim(uuid, "g1"), "double claim rejected");
        helper.assertTrue(!ledger.queue(uuid, new ShardLedger.PendingGrant("g1", 2, 1)),
                "delivered id can never re-queue");
        helper.assertTrue(ledger.pending(uuid).size() == 1
                        && ledger.pending(uuid).get(0).id().equals("g2"),
                "only g2 still pending");

        // NBT round-trip: pending grant + delivered marker both survive.
        CompoundTag tag = ledger.save(new CompoundTag(), helper.getLevel().registryAccess());
        ShardLedger loaded = ShardLedger.load(tag, helper.getLevel().registryAccess());
        helper.assertTrue(loaded.pending(uuid).size() == 1
                        && loaded.pending(uuid).get(0).personalShards() == 1
                        && loaded.pending(uuid).get(0).physicalShards() == 1,
                "pending grant survives save/load");
        helper.assertTrue(!loaded.queue(uuid, new ShardLedger.PendingGrant("g1", 2, 1)),
                "delivered marker survives save/load");

        // Torn-write reconcile: a grant both pending and delivered loads as claimed.
        ShardLedger torn = new ShardLedger();
        torn.queue(uuid, new ShardLedger.PendingGrant("g2", 1, 1));
        CompoundTag tornTag = torn.save(new CompoundTag(), helper.getLevel().registryAccess());
        ShardLedger marker = new ShardLedger();
        marker.queue(uuid, new ShardLedger.PendingGrant("g2", 1, 1));
        marker.claim(uuid, "g2");
        tornTag.put("delivered", marker.save(new CompoundTag(),
                helper.getLevel().registryAccess()).getList("delivered", Tag.TAG_COMPOUND));
        ShardLedger reconciled = ShardLedger.load(tornTag, helper.getLevel().registryAccess());
        helper.assertTrue(reconciled.pending(uuid).isEmpty(),
                "grant both pending and delivered reconciles to claimed");
        helper.succeed();
    }
}
