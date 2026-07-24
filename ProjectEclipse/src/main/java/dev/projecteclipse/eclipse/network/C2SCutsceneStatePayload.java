package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Client → server: cutscene playback ACKs. {@code STARTED}/{@code FINISHED}/{@code SKIPPED}
 * feed the server session tracker (and later the W14 inspector); {@code SKIP_REQUEST} asks
 * the server to end the cutscene early — the server validates it against the path's
 * {@code allowSkip} and the per-world disabled set before granting (a granted skip is
 * answered with the {@link S2CCutscenePlayPayload#STOP} sentinel + an unfreeze).
 */
public record C2SCutsceneStatePayload(String id, State state) implements CustomPacketPayload {
    /** Client playback states. Order is wire format — append only. */
    public enum State {
        STARTED,
        FINISHED,
        SKIP_REQUEST,
        SKIPPED
    }

    public static final CustomPacketPayload.Type<C2SCutsceneStatePayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "cutscene_state"));

    public static final StreamCodec<ByteBuf, C2SCutsceneStatePayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.STRING_UTF8, C2SCutsceneStatePayload::id,
            ByteBufCodecs.VAR_INT.map(ordinal -> State.values()[ordinal], State::ordinal),
            C2SCutsceneStatePayload::state,
            C2SCutsceneStatePayload::new);

    @Override
    public CustomPacketPayload.Type<C2SCutsceneStatePayload> type() {
        return TYPE;
    }
}
