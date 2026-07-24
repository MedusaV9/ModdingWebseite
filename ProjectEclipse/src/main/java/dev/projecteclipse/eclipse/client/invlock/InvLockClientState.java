package dev.projecteclipse.eclipse.client.invlock;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.network.S2CInvLockPayload;
import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;

/**
 * Client cache of the server's inventory slot-lock state (WB-SLOTLOCK).
 * {@code network.invlock.InvLockPayloads} dispatches {@link S2CInvLockPayload} here
 * (frozen entry point {@link #handle}, client main thread); {@link InvLockOverlay}
 * renders from it.
 *
 * <p>Besides the raw bitset this class owns the <b>materialize-in</b> bookkeeping: when a
 * payload clears bits that were set (a row unsealed), the moment is recorded per slot so
 * the overlay can fade/scale the void cover away, and one {@link UiSounds#unlockSting()}
 * plays. The celebration is skipped for the very first payload of a session (login sync
 * is state transfer, not an unlock) and when the local player is in creative/spectator
 * (their all-clear is the gamemode branch of {@code progression.InvLockSync}, not a
 * progression unlock).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class InvLockClientState {
    /** Player {@code Inventory} container slots 0–40 (hotbar, storage, armor, offhand). */
    public static final int SLOT_COUNT = 41;

    /** Bit {@code i} = container slot {@code i} sealed. Written on the client main thread. */
    private static volatile long lockedBits;
    private static volatile int mainUnlockDay = -1;
    private static volatile int armorUnlockDay = -1;
    /** Whether any payload arrived this session (login sync must not animate). */
    private static volatile boolean received;

    /** Per-slot materialize-in start ({@link System#currentTimeMillis()}), 0 = idle. Main thread. */
    private static final long[] ANIM_START_MILLIS = new long[SLOT_COUNT];

    private InvLockClientState() {}

    /** FROZEN entry point — called by {@code InvLockPayloads} on the client main thread. */
    public static void handle(S2CInvLockPayload payload) {
        long previous = lockedBits;
        boolean hadState = received;
        lockedBits = payload.lockedBits();
        mainUnlockDay = payload.mainUnlockDay();
        armorUnlockDay = payload.armorUnlockDay();
        received = true;

        long newlyUnlocked = previous & ~payload.lockedBits();
        long newlyLocked = payload.lockedBits() & ~previous;
        for (int slot = 0; slot < SLOT_COUNT; slot++) {
            if ((newlyLocked & (1L << slot)) != 0L) {
                ANIM_START_MILLIS[slot] = 0L; // re-sealed (day lowered / config reload): cover snaps back
            }
        }
        if (!hadState || newlyUnlocked == 0L) {
            return;
        }
        LocalPlayer player = Minecraft.getInstance().player;
        if (player != null && (player.isCreative() || player.isSpectator())) {
            return; // gamemode all-clear, not a progression unlock — no fanfare
        }
        long now = System.currentTimeMillis();
        for (int slot = 0; slot < SLOT_COUNT; slot++) {
            if ((newlyUnlocked & (1L << slot)) != 0L) {
                ANIM_START_MILLIS[slot] = now;
            }
        }
        UiSounds.unlockSting();
    }

    /** Whether the given {@code Inventory} container slot is currently sealed. */
    public static boolean isLocked(int containerSlot) {
        return containerSlot >= 0 && containerSlot < SLOT_COUNT
                && (lockedBits & (1L << containerSlot)) != 0L;
    }

    /** Whether anything at all is sealed (overlay early-out). */
    public static boolean anyLocked() {
        return lockedBits != 0L;
    }

    /** Materialize-in start millis for a just-unsealed slot, or {@code 0} when idle. */
    public static long animStartMillis(int containerSlot) {
        return containerSlot >= 0 && containerSlot < SLOT_COUNT ? ANIM_START_MILLIS[containerSlot] : 0L;
    }

    /** Marks one slot's materialize-in as finished (overlay prunes elapsed animations). */
    public static void clearAnim(int containerSlot) {
        if (containerSlot >= 0 && containerSlot < SLOT_COUNT) {
            ANIM_START_MILLIS[containerSlot] = 0L;
        }
    }

    /** Tooltip hint: the configured unlock day for the group owning this slot, or {@code -1}. */
    public static int unlockDayFor(int containerSlot) {
        return containerSlot >= 36 ? armorUnlockDay : mainUnlockDay;
    }

    /** Logout drops everything — the next server decides the state anew. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        lockedBits = 0L;
        mainUnlockDay = -1;
        armorUnlockDay = -1;
        received = false;
        java.util.Arrays.fill(ANIM_START_MILLIS, 0L);
    }
}
