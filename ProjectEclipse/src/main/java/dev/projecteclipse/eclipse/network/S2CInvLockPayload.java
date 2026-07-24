package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: which player-inventory container slots are currently sealed by the
 * phase locks (WB-SLOTLOCK — the visual layer of {@code progression.PhaseInventoryLock}).
 * Sent by {@code progression.InvLockSync} on login and whenever the receiving player's
 * derived lock state changes (unlock-key change, gamemode change).
 *
 * <p>Field semantics:</p>
 * <ul>
 *   <li>{@code lockedBits} — bitset over {@code Inventory} container slot indices 0–40
 *       (bit {@code i} set = slot {@code i} sealed). The server mirrors
 *       {@code PhaseInventoryLock} truth exactly: {@code main_inventory} locked → bits
 *       9–35 <b>except 17</b> (the pinned arm-artifact slot, B16 — that slot stays a
 *       real slot and keeps its {@code InventorySlotDecor} frame); {@code armor} locked
 *       → bits 36–40. Hotbar bits 0–8 are never set. Non-survival/adventure players
 *       always receive {@code 0} (the sweeps skip them).</li>
 *   <li>{@code mainUnlockDay}/{@code armorUnlockDay} — HINT for the client tooltip: the
 *       earliest configured day plan listing the {@code main_inventory}/{@code armor}
 *       unlock key, or {@code -1} when no day plan grants it (altar-milestone-only
 *       setups). Purely informational; the bitset is the truth.</li>
 * </ul>
 *
 * <p>Registered by {@link dev.projecteclipse.eclipse.network.invlock.InvLockPayloads}
 * (its own registrar — NOT {@code EclipsePayloads}); the client cache is
 * {@code client.invlock.InvLockClientState}.</p>
 */
public record S2CInvLockPayload(long lockedBits, int mainUnlockDay, int armorUnlockDay)
        implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CInvLockPayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "invlock/state"));

    public static final StreamCodec<ByteBuf, S2CInvLockPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.VAR_LONG, S2CInvLockPayload::lockedBits,
            ByteBufCodecs.INT, S2CInvLockPayload::mainUnlockDay,
            ByteBufCodecs.INT, S2CInvLockPayload::armorUnlockDay,
            S2CInvLockPayload::new);

    /** Whether the given {@code Inventory} container slot index is sealed in this state. */
    public boolean isLocked(int containerSlot) {
        return containerSlot >= 0 && containerSlot < 64 && (lockedBits & (1L << containerSlot)) != 0L;
    }

    @Override
    public CustomPacketPayload.Type<S2CInvLockPayload> type() {
        return TYPE;
    }
}
