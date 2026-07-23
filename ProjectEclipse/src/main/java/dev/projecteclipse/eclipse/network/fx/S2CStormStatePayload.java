package dev.projecteclipse.eclipse.network.fx;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.phys.Vec3;

/**
 * Server → client: storm wall/vortex lifecycle (P2 §3.2, FROZEN shape). Dispatched to
 * W9's {@code stormfx.StormFxClient#handle}. {@code stormType}: 0=WALL, 1=VORTEX ("type" in
 * the plan table — renamed because a record component named {@code type} collides with
 * {@link CustomPacketPayload#type()}; wire format unchanged); {@code state}: 0=SPAWN,
 * 1=ACTIVE, 2=DISSIPATE; {@code ticks} is the ramp length of the given state.
 */
public record S2CStormStatePayload(int stormId, Vec3 center, float radius, float height,
        int stormType, int state, int ticks) implements CustomPacketPayload {

    public static final int TYPE_WALL = 0;
    public static final int TYPE_VORTEX = 1;
    public static final int STATE_SPAWN = 0;
    public static final int STATE_ACTIVE = 1;
    public static final int STATE_DISSIPATE = 2;

    public static final CustomPacketPayload.Type<S2CStormStatePayload> TYPE = new CustomPacketPayload.Type<>(
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/storm_state"));

    // Written explicitly: StreamCodec.composite tops out at 6 components in 1.21.1.
    public static final StreamCodec<ByteBuf, S2CStormStatePayload> STREAM_CODEC = StreamCodec.of(
            (buf, payload) -> {
                ByteBufCodecs.VAR_INT.encode(buf, payload.stormId());
                buf.writeDouble(payload.center().x);
                buf.writeDouble(payload.center().y);
                buf.writeDouble(payload.center().z);
                buf.writeFloat(payload.radius());
                buf.writeFloat(payload.height());
                ByteBufCodecs.VAR_INT.encode(buf, payload.stormType());
                ByteBufCodecs.VAR_INT.encode(buf, payload.state());
                ByteBufCodecs.VAR_INT.encode(buf, payload.ticks());
            },
            buf -> new S2CStormStatePayload(
                    ByteBufCodecs.VAR_INT.decode(buf),
                    new Vec3(buf.readDouble(), buf.readDouble(), buf.readDouble()),
                    buf.readFloat(),
                    buf.readFloat(),
                    ByteBufCodecs.VAR_INT.decode(buf),
                    ByteBufCodecs.VAR_INT.decode(buf),
                    ByteBufCodecs.VAR_INT.decode(buf)));

    @Override
    public CustomPacketPayload.Type<S2CStormStatePayload> type() {
        return TYPE;
    }
}
