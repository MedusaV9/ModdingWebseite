package dev.projecteclipse.eclipse.network.fx;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: 0-lives "ghost" grade toggle (P2 §3.2, FROZEN shape). Sent by P3's
 * death/respawn flow (or via {@code FxPayloads#sendGhostState}); dispatched to
 * {@code EclipseFxState#setGhost} which eases the {@code eclipse:ghost_grade} pipeline.
 */
public record S2CGhostStatePayload(boolean active) implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CGhostStatePayload> TYPE = new CustomPacketPayload.Type<>(
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/ghost_state"));

    public static final StreamCodec<ByteBuf, S2CGhostStatePayload> STREAM_CODEC =
            ByteBufCodecs.BOOL.map(S2CGhostStatePayload::new, S2CGhostStatePayload::active);

    @Override
    public CustomPacketPayload.Type<S2CGhostStatePayload> type() {
        return TYPE;
    }
}
