package dev.projecteclipse.eclipse.network;

import java.util.Optional;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.phys.Vec3;

/**
 * Server → client: start playing a cutscene path from the synced library (~20 bytes).
 * {@code anchor}, when present, overrides the world-anchor origin of the path (e.g. the
 * nearest new ring edge for {@code unlock_ring}); player-anchored paths ignore it.
 *
 * <p>An EMPTY {@code id} is the stop sentinel ({@link #STOP}): the client aborts the active
 * cutscene immediately (server-side {@code abort} command or a granted skip request).</p>
 */
public record S2CCutscenePlayPayload(String id, boolean allowSkip, Optional<Vec3> anchor)
        implements CustomPacketPayload {

    /** Stop sentinel — aborts whatever cutscene is active client-side. */
    public static final S2CCutscenePlayPayload STOP =
            new S2CCutscenePlayPayload("", false, Optional.empty());

    public static final CustomPacketPayload.Type<S2CCutscenePlayPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "cutscene_play"));

    private static final StreamCodec<ByteBuf, Vec3> VEC3_CODEC = StreamCodec.composite(
            ByteBufCodecs.DOUBLE, vec -> vec.x,
            ByteBufCodecs.DOUBLE, vec -> vec.y,
            ByteBufCodecs.DOUBLE, vec -> vec.z,
            Vec3::new);

    public static final StreamCodec<ByteBuf, S2CCutscenePlayPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.STRING_UTF8, S2CCutscenePlayPayload::id,
            ByteBufCodecs.BOOL, S2CCutscenePlayPayload::allowSkip,
            ByteBufCodecs.optional(VEC3_CODEC), S2CCutscenePlayPayload::anchor,
            S2CCutscenePlayPayload::new);

    /** Whether this payload is the stop sentinel rather than a play request. */
    public boolean isStop() {
        return this.id.isEmpty();
    }

    @Override
    public CustomPacketPayload.Type<S2CCutscenePlayPayload> type() {
        return TYPE;
    }
}
