package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.core.BlockPos;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server-to-client lifecycle cue for the Nether breach materialization (plan v3 D10)
 * and, since IDEA-17 (W4-NETHER), the per-player glitch-drift transfer phases.
 * P2 owns the client smoke, quake and ember presentation; W1.7 only supplies the
 * deterministic crater geometry and the phase boundaries.
 *
 * <p>The {@code DRIFT_*} phases are APPEND-ONLY additions: {@link #read}'s ordinal
 * clamp tolerates unknown ordinals on old clients (they degrade to the last known
 * phase instead of crashing), so new phases must only ever be appended to the enum.
 * For drift phases the payload is player-targeted, {@code center} is the shaft anchor
 * (overworld crater / nether arrival) and {@code radius} carries the requested glitch
 * PULSE hold in ticks (short — the transition envelope also fades to black, so the
 * pulses mark capture and each dimension seam instead of covering the whole ride).</p>
 *
 * @param phase lifecycle boundary ({@link Phase#QUAKE}, {@link Phase#OPEN},
 *        {@link Phase#SETTLED}) or drift boundary ({@link Phase#DRIFT_DOWN},
 *        {@link Phase#DRIFT_UP}, {@link Phase#DRIFT_END})
 * @param center overworld crater center at the surface lip (drift: shaft anchor)
 * @param radius crater-mouth radius in blocks (drift: glitch pulse hold ticks)
 */
public record S2CBreachPayload(Phase phase, BlockPos center, int radius)
        implements CustomPacketPayload {

    public enum Phase {
        QUAKE,
        OPEN,
        SETTLED,
        /** Glitch-drift descent captured at the breach lip (player-targeted). */
        DRIFT_DOWN,
        /** Updraft tractor engaged towards the nether ceiling (player-targeted). */
        DRIFT_UP,
        /** Drift finished or aborted — force the glitch-post out ramp (player-targeted). */
        DRIFT_END
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
