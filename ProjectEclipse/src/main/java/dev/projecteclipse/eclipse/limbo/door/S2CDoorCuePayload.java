package dev.projecteclipse.eclipse.limbo.door;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.core.BlockPos;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → ONE client: personal Respawn Door pose cue (plans_v3 §2.5). The global
 * {@link DoorState} rides plain BE data; this tiny payload exists solely so P3/P4 can
 * play a private open sequence during a revive — the targeted client alone animates the
 * door while everyone else keeps their own view. Sent via
 * {@link RespawnDoorApi#playOpenFor} / {@link RespawnDoorApi#playCloseFor} /
 * {@link RespawnDoorApi#clearCueFor}; handled in
 * {@code client.entity.door.DoorRenderers.handleCue} → 
 * {@link RespawnDoorBlockEntity#applyClientCue}.
 *
 * <p>{@code pos} is the multiblock CONTROLLER cell ({@code RespawnDoorApi.controllerPos});
 * {@code pose} is one of the {@code POSE_*} constants. A cue OVERRIDES the receiving
 * viewer's ghost-sees-closed rule (explicit server instruction) until {@link #POSE_CLEAR}
 * or a level change drops the client BE.</p>
 */
public record S2CDoorCuePayload(BlockPos pos, int pose) implements CustomPacketPayload {
    /** Drop the personal override; fall back to ghost rule + global state. */
    public static final int POSE_CLEAR = 0;
    /** Play {@code open} and hold the leaves wide (for this viewer only). */
    public static final int POSE_OPEN = 1;
    /** Play the {@code close} slam and settle back into the closed idle. */
    public static final int POSE_CLOSE = 2;
    /** One-shot {@code locked_shudder} on top of the current pose (no override). */
    public static final int POSE_SHUDDER = 3;

    public static final CustomPacketPayload.Type<S2CDoorCuePayload> TYPE = new CustomPacketPayload.Type<>(
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "door/cue"));

    public static final StreamCodec<ByteBuf, S2CDoorCuePayload> STREAM_CODEC = StreamCodec.composite(
            BlockPos.STREAM_CODEC, S2CDoorCuePayload::pos,
            ByteBufCodecs.VAR_INT, S2CDoorCuePayload::pose,
            S2CDoorCuePayload::new);

    @Override
    public CustomPacketPayload.Type<S2CDoorCuePayload> type() {
        return TYPE;
    }
}
