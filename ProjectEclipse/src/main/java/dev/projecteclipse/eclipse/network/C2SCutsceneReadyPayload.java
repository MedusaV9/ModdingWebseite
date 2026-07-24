package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Client → server: chunk-preload readiness ACK of the cutscene engine (plans_v5 C6). Sent
 * once per play, the moment the client ends its preload hold — either because the chunk
 * columns along the camera path are present client-side
 * ({@code cutscene.client.ViewDistanceClient.chunksReady}) or because the
 * {@code CutsceneService.PRELOAD_TIMEOUT_TICKS} fallback expired — i.e. "the flight is
 * starting NOW". The server logs the hold and re-arms the session watchdog from this
 * moment ({@code cutscene.CutsceneService.handleClientReady}); a missing ACK (vanilla
 * client, packet loss) costs nothing, the play-time deadline already budgets the full
 * preload timeout.
 */
public record C2SCutsceneReadyPayload(String id) implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<C2SCutsceneReadyPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "cutscene_ready"));

    public static final StreamCodec<ByteBuf, C2SCutsceneReadyPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.STRING_UTF8, C2SCutsceneReadyPayload::id,
            C2SCutsceneReadyPayload::new);

    @Override
    public CustomPacketPayload.Type<C2SCutsceneReadyPayload> type() {
        return TYPE;
    }
}
