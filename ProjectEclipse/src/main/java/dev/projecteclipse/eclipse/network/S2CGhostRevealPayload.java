package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: logout ghost name reveal (R12). The <strong>only</strong> payload that
 * ships a real player name to clients.
 */
public record S2CGhostRevealPayload(int ghostEntityId, String ownerName, int ticks) implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<S2CGhostRevealPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ghost_reveal"));

    public static final StreamCodec<ByteBuf, S2CGhostRevealPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.VAR_INT, S2CGhostRevealPayload::ghostEntityId,
            ByteBufCodecs.STRING_UTF8, S2CGhostRevealPayload::ownerName,
            ByteBufCodecs.VAR_INT, S2CGhostRevealPayload::ticks,
            S2CGhostRevealPayload::new);

    @Override
    public Type<S2CGhostRevealPayload> type() {
        return TYPE;
    }
}
