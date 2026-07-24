package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: committed world stage of one disc dimension. {@code dim} is the disc
 * profile name ({@code "overworld"} / {@code "nether"}), {@code radius} the fused-disc
 * radius of that stage and {@code animating} whether a ring-growth sweep is currently
 * materializing the new annulus. Broadcast by {@code worldgen.stage.WorldStageService} on
 * every stage commit and sweep completion, and sent per-dimension on login; cached in
 * {@link dev.projecteclipse.eclipse.client.ClientStateCache} for client UI (map framing,
 * fusion rumble visuals).
 */
public record S2CStagePayload(String dim, int stage, int radius, boolean animating)
        implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CStagePayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "stage"));

    public static final StreamCodec<ByteBuf, S2CStagePayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.STRING_UTF8, S2CStagePayload::dim,
            ByteBufCodecs.VAR_INT, S2CStagePayload::stage,
            ByteBufCodecs.VAR_INT, S2CStagePayload::radius,
            ByteBufCodecs.BOOL, S2CStagePayload::animating,
            S2CStagePayload::new);

    @Override
    public CustomPacketPayload.Type<S2CStagePayload> type() {
        return TYPE;
    }
}
