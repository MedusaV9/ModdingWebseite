package dev.projecteclipse.eclipse.network.fx;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.core.BlockPos;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: supply-drop beam marker add/remove (P2 §3.2, FROZEN shape). Dispatched to
 * W5's {@code veilfx.SupplyBeamClient#handle}. Replaces the v1 END_ROD particle-column
 * broadcast; {@code fadeTicks} softens the remove (0 snaps).
 */
public record S2CSupplyMarkerPayload(boolean add, BlockPos pos, int fadeTicks)
        implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CSupplyMarkerPayload> TYPE = new CustomPacketPayload.Type<>(
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/supply_marker"));

    public static final StreamCodec<ByteBuf, S2CSupplyMarkerPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.BOOL, S2CSupplyMarkerPayload::add,
            BlockPos.STREAM_CODEC, S2CSupplyMarkerPayload::pos,
            ByteBufCodecs.VAR_INT, S2CSupplyMarkerPayload::fadeTicks,
            S2CSupplyMarkerPayload::new);

    @Override
    public CustomPacketPayload.Type<S2CSupplyMarkerPayload> type() {
        return TYPE;
    }
}
