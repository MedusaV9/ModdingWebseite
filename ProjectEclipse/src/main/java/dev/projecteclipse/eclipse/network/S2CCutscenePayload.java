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
    /** Cutscene phases; TILT…EMERGE broadcast in order by {@code limbo.StartEventCutscene}. */
    public enum Phase {
        TILT,
        SUBMERGE,
        WAVES,
        EMERGE,
        /**
         * One camera-shake impulse (~2 s), pulsed repeatedly by
         * {@code worldgen.stage.FusionSequence} while the intro fusion sweep runs.
         * Unlike the ordered phases it can arrive many times; treat each receipt as a
         * fresh impulse rather than a latched state.
         */
        SHAKE
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
