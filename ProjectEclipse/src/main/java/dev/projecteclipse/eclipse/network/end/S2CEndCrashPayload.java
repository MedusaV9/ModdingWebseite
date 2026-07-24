package dev.projecteclipse.eclipse.network.end;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.core.BlockPos;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server-to-client cue for the End disc crashing into the overworld sky.
 *
 * @param center disc center at surface height
 * @param radius materialized disc radius
 * @param timelineTicks suggested P2 crash-sequence duration
 * @param shakeStrength camera-shake/shockwave intensity hint
 */
public record S2CEndCrashPayload(
        BlockPos center, int radius, int timelineTicks, float shakeStrength)
        implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CEndCrashPayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "end/crash"));

    public static final StreamCodec<ByteBuf, S2CEndCrashPayload> STREAM_CODEC =
            StreamCodec.composite(
                    BlockPos.STREAM_CODEC, S2CEndCrashPayload::center,
                    ByteBufCodecs.VAR_INT, S2CEndCrashPayload::radius,
                    ByteBufCodecs.VAR_INT, S2CEndCrashPayload::timelineTicks,
                    ByteBufCodecs.FLOAT, S2CEndCrashPayload::shakeStrength,
                    S2CEndCrashPayload::new);

    @Override
    public CustomPacketPayload.Type<S2CEndCrashPayload> type() {
        return TYPE;
    }
}
