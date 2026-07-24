package dev.projecteclipse.eclipse.progression;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.artifact.ArtifactSlotLock;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.network.S2CInvLockPayload;
import dev.projecteclipse.eclipse.network.invlock.InvLockPayloads;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Additive server hook (WB-SLOTLOCK) that mirrors {@link PhaseInventoryLock}'s derived
 * lock state to clients as {@link S2CInvLockPayload} — {@code PhaseInventoryLock} itself
 * stays untouched. The client renders sealed slots as "absent" ({@code
 * client.invlock.InvLockOverlay}); the server sweeps remain the authority.
 *
 * <p>{@link UnlockState} is a pure derivation of day/altar/boss state with no change
 * callback, so this hook polls once per second (the same cadence as the
 * {@code PhaseInventoryLock} sweeps — the visual layer can never lag the enforcement
 * layer by more than one sweep) with per-player change detection: a payload is only sent
 * on login and when that player's computed state actually differs from the last one sent
 * (day/altar/boss unlock changes, config reloads and gamemode changes all funnel through
 * the same comparison). Slot semantics live in {@link #computeLockedBits}; the payload
 * doc is the wire contract.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class InvLockSync {
    /** Same cadence as the PhaseInventoryLock sweeps. */
    private static final int POLL_INTERVAL_TICKS = 20;
    /** Offset so the poll never lands on the PhaseInventoryLock (0) or ModGate (50) sweep ticks. */
    private static final int POLL_PHASE = 7;

    private static final int MAIN_START = 9;
    private static final int MAIN_END = 35;
    private static final int ARMOR_START = 36;
    private static final int OFFHAND_SLOT = 40;

    /** Last payload sent per player; absent = nothing sent yet. Server thread only. */
    private static final Map<UUID, S2CInvLockPayload> LAST_SENT = new HashMap<>();

    private InvLockSync() {}

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % POLL_INTERVAL_TICKS != POLL_PHASE) {
            return;
        }
        int mainDay = earliestGrantDay(PhaseInventoryLock.KEY_MAIN_INVENTORY);
        int armorDay = earliestGrantDay(PhaseInventoryLock.KEY_ARMOR);
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            sync(player, mainDay, armorDay);
        }
    }

    /** Login always sends the full state — the overlay must know it before the first screen opens. */
    @SubscribeEvent
    public static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            sync(player, earliestGrantDay(PhaseInventoryLock.KEY_MAIN_INVENTORY),
                    earliestGrantDay(PhaseInventoryLock.KEY_ARMOR));
        }
    }

    @SubscribeEvent
    public static void onPlayerLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        LAST_SENT.remove(event.getEntity().getUUID());
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        LAST_SENT.clear();
    }

    /** Sends the player's current state iff it differs from the last payload they received. */
    private static void sync(ServerPlayer player, int mainDay, int armorDay) {
        S2CInvLockPayload payload = new S2CInvLockPayload(computeLockedBits(player), mainDay, armorDay);
        if (!payload.equals(LAST_SENT.get(player.getUUID()))) {
            LAST_SENT.put(player.getUUID(), payload);
            InvLockPayloads.send(player, payload);
        }
    }

    /**
     * Mirrors {@link PhaseInventoryLock} truth for one player: {@code main_inventory}
     * locked → storage slots 9–35 except {@link ArtifactSlotLock#ARTIFACT_SLOT} (the
     * pinned artifact slot is the ONE permitted storage slot while sealed, B16);
     * {@code armor} locked → 36–40. Non-survival/adventure players are never swept,
     * so they get an all-clear.
     */
    private static long computeLockedBits(ServerPlayer player) {
        if (!player.gameMode.isSurvival()) {
            return 0L;
        }
        long bits = 0L;
        if (!UnlockState.isUnlocked(player.server, PhaseInventoryLock.KEY_MAIN_INVENTORY)) {
            for (int slot = MAIN_START; slot <= MAIN_END; slot++) {
                if (slot != ArtifactSlotLock.ARTIFACT_SLOT) {
                    bits |= 1L << slot;
                }
            }
        }
        if (!UnlockState.isUnlocked(player.server, PhaseInventoryLock.KEY_ARMOR)) {
            for (int slot = ARMOR_START; slot <= OFFHAND_SLOT; slot++) {
                bits |= 1L << slot;
            }
        }
        return bits;
    }

    /**
     * Tooltip hint: the earliest configured day plan granting {@code key}, or {@code -1}
     * when no plan lists it (altar-milestone-only setups). Deliberately ignores the
     * altar/boss gates of {@link UnlockState} — neither gated key seals the inventory,
     * and the bitset stays the only truth the client acts on.
     */
    private static int earliestGrantDay(String key) {
        int earliest = -1;
        for (EclipseConfig.DayPlan plan : EclipseConfig.days()) {
            if (plan.unlocks().contains(key) && (earliest < 0 || plan.day() < earliest)) {
                earliest = plan.day();
            }
        }
        return earliest;
    }
}
