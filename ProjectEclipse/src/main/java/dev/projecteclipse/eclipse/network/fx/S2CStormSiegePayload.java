package dev.projecteclipse.eclipse.network.fx;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: the SIEGE overlay state of one storm (F-031/F-032 — the Fog-Tyrant
 * boss fight raging INSIDE a standing site storm). Orthogonal to
 * {@link S2CStormStatePayload} on purpose: the base lifecycle payload stays FROZEN, and
 * the siege only modulates how the client renders an ACTIVE storm. Sent by
 * {@code stormfx.StormSiege} on fight start/end, re-sent as a keepalive and on login
 * resync (handling is idempotent — see {@code StormFxClient.handleSiege}).
 *
 * <p>{@code active=true}: the client eases the storm's visual radius/height toward
 * {@code radiusScale}× over {@code growTicks} (F-031a), dissolves the opaque occluder
 * core over ~3 s for free combat sight (F-032), and drops one volumetric quality tier +
 * caps raymarch steps (F-031b). {@code active=false} (fight abandoned, storm still
 * standing): everything eases back — a WON fight instead rides the EXPLODE state, where
 * the occluder never returns because the storm bursts.</p>
 */
public record S2CStormSiegePayload(int stormId, boolean active, int growTicks,
        float radiusScale) implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CStormSiegePayload> TYPE = new CustomPacketPayload.Type<>(
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/storm_siege"));

    public static final StreamCodec<ByteBuf, S2CStormSiegePayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.VAR_INT, S2CStormSiegePayload::stormId,
            ByteBufCodecs.BOOL, S2CStormSiegePayload::active,
            ByteBufCodecs.VAR_INT, S2CStormSiegePayload::growTicks,
            ByteBufCodecs.FLOAT, S2CStormSiegePayload::radiusScale,
            S2CStormSiegePayload::new);

    @Override
    public CustomPacketPayload.Type<S2CStormSiegePayload> type() {
        return TYPE;
    }
}
