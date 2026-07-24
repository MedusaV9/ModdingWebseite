package dev.projecteclipse.eclipse.network.fx;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.phys.Vec3;

/**
 * Server → client: named FX anchor sync (P2 §3.2, FROZEN shape). Feeds the
 * {@code veilfx.FxAnchors} client cache; {@code set == false} removes the anchor
 * ({@code pos} is then ignored). Frozen anchor ids: {@code eclipse:ship_door},
 * {@code eclipse:altar_center}, {@code eclipse:ship_deck}.
 */
public record S2CAnchorPayload(ResourceLocation id, boolean set, Vec3 pos)
        implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CAnchorPayload> TYPE = new CustomPacketPayload.Type<>(
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/anchor"));

    public static final StreamCodec<ByteBuf, S2CAnchorPayload> STREAM_CODEC = StreamCodec.composite(
            ResourceLocation.STREAM_CODEC, S2CAnchorPayload::id,
            ByteBufCodecs.BOOL, S2CAnchorPayload::set,
            ByteBufCodecs.DOUBLE, payload -> payload.pos().x,
            ByteBufCodecs.DOUBLE, payload -> payload.pos().y,
            ByteBufCodecs.DOUBLE, payload -> payload.pos().z,
            (id, set, x, y, z) -> new S2CAnchorPayload(id, set, new Vec3(x, y, z)));

    @Override
    public CustomPacketPayload.Type<S2CAnchorPayload> type() {
        return TYPE;
    }
}
