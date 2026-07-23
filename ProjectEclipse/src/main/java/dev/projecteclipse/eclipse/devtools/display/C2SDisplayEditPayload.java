package dev.projecteclipse.eclipse.devtools.display;

import io.netty.buffer.ByteBuf;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Validated wand action. The self-registering registrar deliberately stays outside the
 * shared EclipsePayloads hub.
 */
public record C2SDisplayEditPayload(int action) implements CustomPacketPayload {
    public static final int SELECT_OR_PLACE = 0;
    public static final int DELETE = 1;

    public static final CustomPacketPayload.Type<C2SDisplayEditPayload> TYPE =
            new CustomPacketPayload.Type<>(
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "display/edit"));
    public static final StreamCodec<ByteBuf, C2SDisplayEditPayload> STREAM_CODEC =
            ByteBufCodecs.VAR_INT.map(C2SDisplayEditPayload::new, C2SDisplayEditPayload::action);

    @Override
    public CustomPacketPayload.Type<C2SDisplayEditPayload> type() {
        return TYPE;
    }
}
