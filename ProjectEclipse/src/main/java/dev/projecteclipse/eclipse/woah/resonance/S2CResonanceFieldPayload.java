package dev.projecteclipse.eclipse.woah.resonance;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.core.BlockPos;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * WOAH-04 §3.6 server → client: resonance-field geometry + puzzle state. Sent on
 * build, on every state change and on login (the {@code S2CStormStatePayload}
 * once-not-per-tick law); the client mirror is
 * {@code woah.resonance.client.ResonanceFieldClient}. Deliberately carries NO
 * melody content — teach glows arrive as individual {@code CUE_RESONANCE_STRIKE}
 * cues, so the payload can never leak the solution.
 *
 * <p>Registered in {@code network.EclipsePayloads} (the sanctioned minimal-additive
 * exception for this feature); geometry is tiny (9 crystals + ~12 edges) and only
 * crosses the wire on events, never per tick.</p>
 *
 * @param anchor    valley anchor block position (bowl center at plateau height)
 * @param altar     altar dais center (the finale column / fail sting anchor)
 * @param crystals  the 9 monoliths in tone-graph index order
 * @param edges     neighbor-graph index pairs (light-path edges, ~12)
 * @param state     {@code ResonanceMelodyMachine.State} ordinal
 * @param cooldownRemainingTicks remaining COOLDOWN ticks at send time (0 outside it)
 */
public record S2CResonanceFieldPayload(BlockPos anchor, BlockPos altar, List<Crystal> crystals,
        List<Edge> edges, int state, int cooldownRemainingTicks) implements CustomPacketPayload {

    /** One monolith: base anchor, visual height in blocks, pentatonic tone index. */
    public record Crystal(BlockPos basePos, float height, int toneIndex) {}

    /** One neighbor-graph edge (crystal indices into {@link #crystals}). */
    public record Edge(int a, int b) {}

    public static final CustomPacketPayload.Type<S2CResonanceFieldPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(
                    EclipseMod.MOD_ID, "woah_resonance_field"));

    public static final StreamCodec<ByteBuf, S2CResonanceFieldPayload> STREAM_CODEC =
            StreamCodec.of(S2CResonanceFieldPayload::encode, S2CResonanceFieldPayload::decode);

    private static void encode(ByteBuf buf, S2CResonanceFieldPayload payload) {
        buf.writeLong(payload.anchor().asLong());
        buf.writeLong(payload.altar().asLong());
        buf.writeByte(payload.crystals().size());
        for (Crystal crystal : payload.crystals()) {
            buf.writeLong(crystal.basePos().asLong());
            buf.writeFloat(crystal.height());
            buf.writeByte(crystal.toneIndex());
        }
        buf.writeByte(payload.edges().size());
        for (Edge edge : payload.edges()) {
            buf.writeByte(edge.a());
            buf.writeByte(edge.b());
        }
        buf.writeByte(payload.state());
        buf.writeInt(payload.cooldownRemainingTicks());
    }

    private static S2CResonanceFieldPayload decode(ByteBuf buf) {
        BlockPos anchor = BlockPos.of(buf.readLong());
        BlockPos altar = BlockPos.of(buf.readLong());
        int crystalCount = buf.readUnsignedByte();
        List<Crystal> crystals = new ArrayList<>(crystalCount);
        for (int i = 0; i < crystalCount; i++) {
            crystals.add(new Crystal(BlockPos.of(buf.readLong()), buf.readFloat(),
                    buf.readUnsignedByte()));
        }
        int edgeCount = buf.readUnsignedByte();
        List<Edge> edges = new ArrayList<>(edgeCount);
        for (int i = 0; i < edgeCount; i++) {
            edges.add(new Edge(buf.readUnsignedByte(), buf.readUnsignedByte()));
        }
        int state = buf.readUnsignedByte();
        int cooldown = buf.readInt();
        return new S2CResonanceFieldPayload(anchor, altar, List.copyOf(crystals),
                List.copyOf(edges), state, cooldown);
    }

    @Override
    public CustomPacketPayload.Type<S2CResonanceFieldPayload> type() {
        return TYPE;
    }
}
