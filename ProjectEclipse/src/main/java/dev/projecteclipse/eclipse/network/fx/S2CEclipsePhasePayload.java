package dev.projecteclipse.eclipse.network.fx;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: eclipse phase change (P2 §3.2, FROZEN shape). {@code phase} uses the
 * {@code EclipseFxState} constants (0=NONE, 1=BUILDUP, 2=TOTAL, 3=ENDING); {@code intensity}
 * is the target eclipse amount reached over {@code rampTicks}; {@code permanentRim} latches
 * the post-intro purple sun rim (P4 re-sends it at login from its world flag).
 */
public record S2CEclipsePhasePayload(int phase, float intensity, int rampTicks, boolean permanentRim)
        implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CEclipsePhasePayload> TYPE = new CustomPacketPayload.Type<>(
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/eclipse_phase"));

    public static final StreamCodec<ByteBuf, S2CEclipsePhasePayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.VAR_INT, S2CEclipsePhasePayload::phase,
            ByteBufCodecs.FLOAT, S2CEclipsePhasePayload::intensity,
            ByteBufCodecs.VAR_INT, S2CEclipsePhasePayload::rampTicks,
            ByteBufCodecs.BOOL, S2CEclipsePhasePayload::permanentRim,
            S2CEclipsePhasePayload::new);

    @Override
    public CustomPacketPayload.Type<S2CEclipsePhasePayload> type() {
        return TYPE;
    }
}
