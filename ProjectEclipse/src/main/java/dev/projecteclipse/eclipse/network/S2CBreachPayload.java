package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.core.BlockPos;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server-to-client lifecycle cue for the Nether breach materialization (plan v3 D10).
 * P2 owns the client smoke, quake and ember presentation; W1.7 only supplies the
 * deterministic crater geometry and these three phase boundaries.
 *
 * @param phase lifecycle boundary ({@link Phase#QUAKE}, {@link Phase#OPEN}, or
 *        {@link Phase#SETTLED})
 * @param center overworld crater center at the surface lip
 * @param radius crater-mouth radius in blocks
 */
public record S2CBreachPayload(Phase phase, BlockPos center, int radius)
        implements CustomPacketPayload {

    public enum Phase {
        QUAKE,
        OPEN,
        SETTLED
    }

    public static final CustomPacketPayload.Type<S2CBreachPayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "breach/phase"));

    public static final StreamCodec<ByteBuf, S2CBreachPayload> STREAM_CODEC =
            StreamCodec.of(S2CBreachPayload::write, S2CBreachPayload::read);

    private static void write(ByteBuf buf, S2CBreachPayload payload) {
        ByteBufCodecs.VAR_INT.encode(buf, payload.phase.ordinal());
        BlockPos.STREAM_CODEC.encode(buf, payload.center);
        ByteBufCodecs.VAR_INT.encode(buf, payload.radius);
    }

    private static S2CBreachPayload read(ByteBuf buf) {
        int ordinal = ByteBufCodecs.VAR_INT.decode(buf);
        Phase[] phases = Phase.values();
        Phase phase = phases[Math.max(0, Math.min(phases.length - 1, ordinal))];
        BlockPos center = BlockPos.STREAM_CODEC.decode(buf);
        int radius = ByteBufCodecs.VAR_INT.decode(buf);
        return new S2CBreachPayload(phase, center, radius);
    }

    @Override
    public CustomPacketPayload.Type<S2CBreachPayload> type() {
        return TYPE;
    }
}
