package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.core.BlockPos;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: a structure site entered the PENDING phase of the two-phase apply
 * (design D7). Broadcast by {@code worldgen.structure.StructurePendingRegistry} the moment
 * a site is enqueued (stage terrain done, structure NOT yet placed) so P2 can open its
 * rift animation over the build site; when the rift lands, P2 calls
 * {@code StructurePendingRegistry.trigger(siteId)} (server side) to place the blocks —
 * with an automatic server-side fallback after {@code structure_phase.auto_delay_ticks}
 * ({@code config/eclipse/dungeons.json}) so sites are never lost without a client.
 *
 * <p>{@code footprint} is the full XZ extent (blocks, square-ish envelope edge length) of
 * the expected structure — P2 sizes the rift tear from it (plan R11: width = diagonal ·
 * 1.2 ≈ footprint · 1.7). {@code anchor} is the deterministic site anchor (surface for
 * plateau sites, interior center for cavity/underground sites). Client handler
 * registration lives in {@code EclipsePayloads} (orchestrator merge).</p>
 */
public record S2CStructureRiftPayload(String siteId, String structureId, BlockPos anchor, int footprint)
        implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CStructureRiftPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "structure_rift"));

    public static final StreamCodec<ByteBuf, S2CStructureRiftPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.STRING_UTF8, S2CStructureRiftPayload::siteId,
            ByteBufCodecs.STRING_UTF8, S2CStructureRiftPayload::structureId,
            BlockPos.STREAM_CODEC, S2CStructureRiftPayload::anchor,
            ByteBufCodecs.VAR_INT, S2CStructureRiftPayload::footprint,
            S2CStructureRiftPayload::new);

    @Override
    public CustomPacketPayload.Type<S2CStructureRiftPayload> type() {
        return TYPE;
    }
}
