package dev.projecteclipse.eclipse.network.nether;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.core.BlockPos;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client beat of the day-2 NETHER OPENING sequence
 * ({@code sequence.NetherOpeningSequence}). One broadcast per beat to every player in the
 * overworld; the client scales everything by ITS OWN distance to {@code center}, so a
 * single packet drives a proximity-correct show for the whole server.
 *
 * <p>The payload deliberately carries no timings: phase lengths live server-side only and
 * every client-visible beat is pushed (the {@link Phase#RUMBLE} pulse cadence included).
 * A client that joins mid-sequence simply picks the show up at the next beat, and one that
 * misses the end still gets the permanent plume — that window is driven by
 * {@code client.nether.NetherPitPlume}'s physical probe, not by this payload.</p>
 *
 * <p>Like {@code S2CBreachPayload}, {@link Phase} is APPEND-ONLY: {@link #read} clamps
 * unknown ordinals to the last known phase so an old client degrades instead of crashing.</p>
 *
 * @param phase     which beat fired
 * @param center    crater centre at the surface lip plane ({@code BreachGeometry})
 * @param intensity 0..1 beat strength — {@link Phase#RUMBLE} shake amplitude before the
 *                  client's own distance falloff; unused (0) by the other phases
 */
public record S2CNetherOpenPayload(Phase phase, BlockPos center, float intensity)
        implements CustomPacketPayload {

    public enum Phase {
        /** Phase 1: the ground starts breathing (ash + glints + the first faint rumble). */
        OMEN,
        /** Phase 2: quake — fissure stamps around the rim, hopping ground, harder shake. */
        TREMOR,
        /** Phase 3: the pit is torn open (eruption FX + the block-display fountain). */
        RUPTURE,
        /** Phase 4: the show is over; the permanent plume takes the anchor from here. */
        AFTERMATH,
        /** Ground-rumble pulse: {@code intensity} = amplitude before the distance falloff. */
        RUMBLE
    }

    public static final CustomPacketPayload.Type<S2CNetherOpenPayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "nether/open"));

    public static final StreamCodec<ByteBuf, S2CNetherOpenPayload> STREAM_CODEC =
            StreamCodec.of(S2CNetherOpenPayload::write, S2CNetherOpenPayload::read);

    private static void write(ByteBuf buf, S2CNetherOpenPayload payload) {
        ByteBufCodecs.VAR_INT.encode(buf, payload.phase.ordinal());
        BlockPos.STREAM_CODEC.encode(buf, payload.center);
        ByteBufCodecs.FLOAT.encode(buf, payload.intensity);
    }

    private static S2CNetherOpenPayload read(ByteBuf buf) {
        int ordinal = ByteBufCodecs.VAR_INT.decode(buf);
        Phase[] phases = Phase.values();
        Phase phase = phases[Math.max(0, Math.min(phases.length - 1, ordinal))];
        BlockPos center = BlockPos.STREAM_CODEC.decode(buf);
        float intensity = ByteBufCodecs.FLOAT.decode(buf);
        return new S2CNetherOpenPayload(phase, center, intensity);
    }

    @Override
    public CustomPacketPayload.Type<S2CNetherOpenPayload> type() {
        return TYPE;
    }
}
