package de.sonic0810.goobymod.gametest;

import com.mojang.authlib.GameProfile;
import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.entity.GoobyLoadedIndex;
import de.sonic0810.goobymod.event.GiftPriorityTracker;
import de.sonic0810.goobymod.event.GoobyEvents;
import de.sonic0810.goobymod.registry.ModEntities;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import net.minecraft.core.BlockPos;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.phys.Vec3;
import net.neoforged.neoforge.common.util.FakePlayer;
import net.neoforged.neoforge.common.util.FakePlayerFactory;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * Welle 6 "Cozy Home & Performance" (v5.3.0): Regressionstests fuer die beiden
 * Architektur-Audit-Fixes. (a) Das Geschenk-/Ball-Prioritaetsfenster laeuft
 * jetzt ueber den {@link GiftPriorityTracker} (Join-Registrierung + Sweep nur
 * ueber markierte Drops) statt ueber einen globalen Entity-Tick-Hook.
 * (b) Der Logout-Cleanup nutzt den bounded {@link GoobyLoadedIndex} statt
 * eines All-Entities-Scans ueber alle Level. Beide Pfade muessen sich exakt
 * wie vorher verhalten.
 */
@GameTestHolder(GoobyMod.MODID)
@PrefixGameTestTemplate(false)
public class GoobyPerformanceTests {
    private static final String ARENA = "arena";

    private static void placeFloor(GameTestHelper helper) {
        for (int x = 0; x < 5; x++) {
            for (int z = 0; z < 5; z++) {
                helper.setBlock(new BlockPos(x, 1, z), Blocks.DIRT);
            }
        }
    }

    private static FakePlayer fakePlayer(GameTestHelper helper, String name) {
        return FakePlayerFactory.get(helper.getLevel(),
                new GameProfile(UUID.nameUUIDFromBytes(name.getBytes(StandardCharsets.UTF_8)), name));
    }

    // ------------------------------------------------------------------
    // (a) Gift-Prioritaetsfenster: Registry statt globalem Entity-Tick-Hook
    // ------------------------------------------------------------------

    /** Join registriert NUR markierte Drops; das Fenster laeuft exakt wie frueher ab. */
    @GameTest(template = ARENA, timeoutTicks = 200)
    public static void gift_priority_tracker_lifecycle(GameTestHelper helper) {
        placeFloor(helper);
        ServerLevel level = helper.getLevel();
        Vec3 spot = helper.absoluteVec(new Vec3(2.5, 2.5, 2.5));
        UUID recipient = UUID.randomUUID();

        ItemEntity gift = new ItemEntity(level, spot.x, spot.y, spot.z, new ItemStack(Items.CARROT));
        gift.setTarget(recipient);
        gift.getPersistentData().putLong(GoobyEntity.GIFT_PRIORITY_UNTIL_TAG, level.getGameTime() + 30L);
        level.addFreshEntity(gift);
        helper.assertTrue(GiftPriorityTracker.isTrackedForTest(gift),
                "Join-Hook registrierte den markierten Drop nicht");

        // Unmarkierte Drops gehoeren NICHT in den Tracker …
        ItemEntity plain = new ItemEntity(level, spot.x, spot.y, spot.z + 1.0, new ItemStack(Items.STONE));
        level.addFreshEntity(plain);
        helper.assertFalse(GiftPriorityTracker.isTrackedForTest(plain),
                "Drop ohne Prioritaetsfenster landete im Tracker");
        // … auch nicht Drops mit Vanilla-Target, aber ohne Marker-Tag (deren
        // Target darf der Sweep nie anfassen — identisch zum alten Hook).
        ItemEntity targetedOnly = new ItemEntity(level, spot.x, spot.y, spot.z - 1.0,
                new ItemStack(Items.OAK_SAPLING));
        targetedOnly.setTarget(recipient);
        level.addFreshEntity(targetedOnly);
        helper.assertFalse(GiftPriorityTracker.isTrackedForTest(targetedOnly),
                "Drop ohne Marker-Tag landete im Tracker");

        helper.startSequence()
                .thenExecuteAfter(10, () -> helper.assertTrue(recipient.equals(gift.getTarget()),
                        "Prioritaetsfenster endete zu frueh"))
                .thenExecuteAfter(30, () -> {
                    helper.assertTrue(gift.getTarget() == null,
                            "Vanilla-Target ueberlebte den Fenster-Ablauf");
                    helper.assertFalse(gift.getPersistentData().contains(GoobyEntity.GIFT_PRIORITY_UNTIL_TAG),
                            "Marker-Tag ueberlebte den Fenster-Ablauf");
                    helper.assertFalse(GiftPriorityTracker.isTrackedForTest(gift),
                            "Abgelaufener Drop haengt weiter im Tracker");
                    helper.assertTrue(recipient.equals(targetedOnly.getTarget()),
                            "Sweep fasste ein fremdes Vanilla-Target an");
                    gift.discard();
                    plain.discard();
                    targetedOnly.discard();
                })
                .thenSucceed();
    }

    /** Der Produktions-Spawnpfad (Gooby-Geschenk) laeuft durch den Tracker. */
    @GameTest(template = ARENA, timeoutTicks = 200)
    public static void gift_spawn_path_registers_in_tracker(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity gooby = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(1, 2, 1));
        ServerPlayer recipient = TestPlayers.create(helper, new Vec3(4.5, 2.0, 4.5));

        ItemEntity dropped = gooby.spawnGiftForRecipient(helper.getLevel(),
                new ItemStack(Items.CARROT), recipient);
        helper.assertTrue(GiftPriorityTracker.isTrackedForTest(dropped),
                "spawnGiftForRecipient registrierte den Drop nicht im Tracker");
        helper.assertTrue(recipient.getUUID().equals(dropped.getTarget()),
                "Geschenk traegt keine Empfaenger-Prioritaet");

        // Der Sweep liest das LIVE-Tag: vorgezogener Ablauf wirkt sofort.
        dropped.getPersistentData().putLong(GoobyEntity.GIFT_PRIORITY_UNTIL_TAG,
                helper.getLevel().getGameTime() + 2L);
        helper.startSequence()
                .thenExecuteAfter(4, () -> {
                    helper.assertTrue(dropped.getTarget() == null,
                            "Fenster-Ablauf gab das Geschenk nicht fuer alle frei");
                    helper.assertFalse(GiftPriorityTracker.isTrackedForTest(dropped),
                            "Abgelaufenes Geschenk haengt im Tracker");
                    dropped.discard();
                    TestPlayers.remove(helper, recipient);
                })
                .thenSucceed();
    }

    /** Entfernte/despawnte Drops verlassen den Tracker im naechsten Sweep (bounded). */
    @GameTest(template = ARENA)
    public static void gift_tracker_drops_removed_entities(GameTestHelper helper) {
        placeFloor(helper);
        ServerLevel level = helper.getLevel();
        Vec3 spot = helper.absoluteVec(new Vec3(2.5, 2.5, 2.5));

        ItemEntity gift = new ItemEntity(level, spot.x, spot.y, spot.z, new ItemStack(Items.CARROT));
        gift.setTarget(UUID.randomUUID());
        gift.getPersistentData().putLong(GoobyEntity.GIFT_PRIORITY_UNTIL_TAG, level.getGameTime() + 600L);
        level.addFreshEntity(gift);
        helper.assertTrue(GiftPriorityTracker.isTrackedForTest(gift),
                "Testaufbau: Drop wurde nicht registriert");

        gift.discard();
        helper.startSequence()
                .thenExecuteAfter(2, () -> helper.assertFalse(GiftPriorityTracker.isTrackedForTest(gift),
                        "Entfernter Drop blieb im Tracker haengen (Leak)"))
                .thenSucceed();
    }

    // ------------------------------------------------------------------
    // (b) Logout-Cleanup: bounded Gooby-Index statt All-Entities-Scan
    // ------------------------------------------------------------------

    /** Der Index folgt dem Entity-Lifecycle und der Logout raeumt ALLE Goobys auf. */
    @GameTest(template = ARENA)
    public static void logout_cleanup_uses_bounded_index(GameTestHelper helper) {
        placeFloor(helper);
        GoobyEntity first = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(1, 2, 1));
        GoobyEntity second = helper.spawn(ModEntities.GOOBY.get(), new BlockPos(3, 2, 3));
        helper.assertTrue(GoobyLoadedIndex.containsForTest(first)
                        && GoobyLoadedIndex.containsForTest(second),
                "Frisch gespawnte Goobys fehlen im Loaded-Index");

        FakePlayer player = fakePlayer(helper, "index_logout");
        long now = helper.getLevel().getGameTime();
        first.recordSneakToggle(player, now, false);
        first.handleBareHandInteraction(player, now);
        second.recordSneakToggle(player, now, false);
        helper.assertTrue(first.transientStateSizeForTest() > 0 && second.transientStateSizeForTest() > 0,
                "Testaufbau erzeugte keine transienten Spieler-Caches");

        // Exakt der Event-Kern, den PlayerLoggedOutEvent aufruft.
        GoobyEvents.handlePlayerLogout(player.getUUID());
        helper.assertTrue(first.transientStateSizeForTest() == 0,
                "Logout ueber den Index liess Caches am ersten Gooby zurueck");
        helper.assertTrue(second.transientStateSizeForTest() == 0,
                "Logout ueber den Index liess Caches am zweiten Gooby zurueck");

        // Bounded: Discard entfernt sofort aus dem Index, der Rest bleibt.
        second.discard();
        helper.assertFalse(GoobyLoadedIndex.containsForTest(second),
                "Entfernter Gooby haengt weiter im Loaded-Index (Leak)");
        helper.assertTrue(GoobyLoadedIndex.containsForTest(first),
                "Index verlor einen weiterhin geladenen Gooby");
        helper.succeed();
    }
}
