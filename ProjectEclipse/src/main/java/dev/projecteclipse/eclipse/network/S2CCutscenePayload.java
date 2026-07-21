package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: phase change of the start-event cutscene. Client visuals (camera,
 * shaders, waves overlay) are driven by another worker from
 * {@link dev.projecteclipse.eclipse.client.ClientStateCache#cutscenePhase}.
 */
public record S2CCutscenePayload(Phase phase) implements CustomPacketPayload {
    /** Cutscene phases, broadcast in this order by {@code limbo.StartEventCutscene}. */
    public enum Phase {
        TILT,
        SUBMERGE,
        WAVES,
        EMERGE
    }

    public static final CustomPacketPayload.Type<S2CCutscenePayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "cutscene"));

    public static final StreamCodec<ByteBuf, S2CCutscenePayload> STREAM_CODEC =
            ByteBufCodecs.VAR_INT.map(
                    ordinal -> new S2CCutscenePayload(Phase.values()[ordinal]),
                    payload -> payload.phase().ordinal());

    @Override
    public CustomPacketPayload.Type<S2CCutscenePayload> type() {
        return TYPE;
    }
}
