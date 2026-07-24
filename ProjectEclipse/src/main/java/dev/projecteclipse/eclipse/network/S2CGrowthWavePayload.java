package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: one ring-growth wavefront pulse (design D11 — the exact wavefront the
 * animated sweep just wrote), broadcast every 5 ticks to players in the growing dimension
 * while an ANIMATED stage sweep runs. P2 renders the column-rise/dissolve shaders against
 * it; the server guarantees a rewritten chunk is only resent ≥ {@code growth.revealDelayTicks}
 * after the pulse covering its columns went out, so clients never see raw chunks pop ahead
 * of the animation front.
 *
 * <p>Field semantics:</p>
 * <ul>
 *   <li>{@code dim} — disc profile name ({@code "overworld"} / {@code "nether"}).</li>
 *   <li>{@code fromStage}/{@code toStage} — the committed transition driving the sweep.</li>
 *   <li>{@code innerR}/{@code outerR} — the full rewrite band (blocks from the origin).</li>
 *   <li>{@code waveR} — current wavefront ring. For GROW sweeps this is the radius the
 *       front has reached (rings race outward, {@code innerR → outerR}); for ERASE sweeps
 *       the radius the crumble front has receded to ({@code outerR → innerR}); for the
 *       intro FUSION (overworld 0 → 1, recognisable by {@code fromStage == 0}) it is the
 *       DISTANCE TO THE NEAREST PRE-EXISTING DISC EDGE the bridges have grown to, not a
 *       radius.</li>
 *   <li>{@code waveAngleStart}/{@code waveAngleEnd} — world angles (radians, −π..π,
 *       {@code atan2(z, x)}) bounding the segment written since the previous pulse.
 *       {@code −π..π} means the pulse covered one or more full rings (also always sent
 *       for fusion ordering, whose fronts are not angular).</li>
 *   <li>{@code columnRiseTicks} — client column-rise animation duration hint
 *       ({@code worldgen_tuning.json → growth.columnRiseTicks}).</li>
 *   <li>{@code pulseIndex} — 0-based pulse counter within one sweep; resets when a new
 *       sweep starts (a restart-resumed sweep starts again at 0).</li>
 * </ul>
 *
 * <p>Registered by {@link dev.projecteclipse.eclipse.network.growth.GrowthPayloads} (its
 * own registrar — NOT {@code EclipsePayloads}); P2 hooks the client side via
 * {@code GrowthPayloads.setClientWaveHandler}.</p>
 */
public record S2CGrowthWavePayload(String dim, int fromStage, int toStage, int innerR, int outerR,
        int waveR, float waveAngleStart, float waveAngleEnd, int columnRiseTicks, int pulseIndex)
        implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CGrowthWavePayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "growth/wave"));

    /** Ten fields exceed the largest {@code StreamCodec.composite} arity — hand-rolled. */
    public static final StreamCodec<ByteBuf, S2CGrowthWavePayload> STREAM_CODEC =
            StreamCodec.of(S2CGrowthWavePayload::write, S2CGrowthWavePayload::read);

    private static void write(ByteBuf buf, S2CGrowthWavePayload payload) {
        ByteBufCodecs.STRING_UTF8.encode(buf, payload.dim);
        ByteBufCodecs.VAR_INT.encode(buf, payload.fromStage);
        ByteBufCodecs.VAR_INT.encode(buf, payload.toStage);
        ByteBufCodecs.VAR_INT.encode(buf, payload.innerR);
        ByteBufCodecs.VAR_INT.encode(buf, payload.outerR);
        ByteBufCodecs.VAR_INT.encode(buf, payload.waveR);
        buf.writeFloat(payload.waveAngleStart);
        buf.writeFloat(payload.waveAngleEnd);
        ByteBufCodecs.VAR_INT.encode(buf, payload.columnRiseTicks);
        ByteBufCodecs.VAR_INT.encode(buf, payload.pulseIndex);
    }

    private static S2CGrowthWavePayload read(ByteBuf buf) {
        String dim = ByteBufCodecs.STRING_UTF8.decode(buf);
        int fromStage = ByteBufCodecs.VAR_INT.decode(buf);
        int toStage = ByteBufCodecs.VAR_INT.decode(buf);
        int innerR = ByteBufCodecs.VAR_INT.decode(buf);
        int outerR = ByteBufCodecs.VAR_INT.decode(buf);
        int waveR = ByteBufCodecs.VAR_INT.decode(buf);
        float waveAngleStart = buf.readFloat();
        float waveAngleEnd = buf.readFloat();
        int columnRiseTicks = ByteBufCodecs.VAR_INT.decode(buf);
        int pulseIndex = ByteBufCodecs.VAR_INT.decode(buf);
        return new S2CGrowthWavePayload(dim, fromStage, toStage, innerR, outerR, waveR,
                waveAngleStart, waveAngleEnd, columnRiseTicks, pulseIndex);
    }

    @Override
    public CustomPacketPayload.Type<S2CGrowthWavePayload> type() {
        return TYPE;
    }
}
