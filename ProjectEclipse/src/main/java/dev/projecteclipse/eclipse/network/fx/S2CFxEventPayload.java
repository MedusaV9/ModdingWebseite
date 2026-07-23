package dev.projecteclipse.eclipse.network.fx;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.phys.Vec3;

/**
 * Server → client: generic one-shot FX event (P2 §3.2, FROZEN shape). The handler switches
 * on {@code id} — the frozen id constants and their {@code a}/{@code b} semantics live in
 * {@link FxPayloads} ({@code FX_LIGHTNING_STRIKE}, {@code FX_SHOCKWAVE}, {@code FX_RIFT_OPEN},
 * {@code FX_RIFT_CLOSE}, {@code FX_GLIDE_START}, {@code FX_GLIDE_STOP}, {@code FX_DOOR_GLOW}).
 */
public record S2CFxEventPayload(ResourceLocation id, Vec3 pos, float a, float b)
        implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CFxEventPayload> TYPE = new CustomPacketPayload.Type<>(
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/event"));

    public static final StreamCodec<ByteBuf, S2CFxEventPayload> STREAM_CODEC = StreamCodec.composite(
            ResourceLocation.STREAM_CODEC, S2CFxEventPayload::id,
            ByteBufCodecs.DOUBLE, payload -> payload.pos().x,
            ByteBufCodecs.DOUBLE, payload -> payload.pos().y,
            ByteBufCodecs.DOUBLE, payload -> payload.pos().z,
            ByteBufCodecs.FLOAT, S2CFxEventPayload::a,
            ByteBufCodecs.FLOAT, S2CFxEventPayload::b,
            (id, x, y, z, a, b) -> new S2CFxEventPayload(id, new Vec3(x, y, z), a, b));

    @Override
    public CustomPacketPayload.Type<S2CFxEventPayload> type() {
        return TYPE;
    }
}
