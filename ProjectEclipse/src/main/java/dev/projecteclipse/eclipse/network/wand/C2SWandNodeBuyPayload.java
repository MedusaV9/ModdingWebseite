package dev.projecteclipse.eclipse.network.wand;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * C2S "buy this wand-tree node" request ({@code eclipse:wand/node_buy}, F-036). Carries
 * ONLY the node id; the server re-validates EVERYTHING in
 * {@code wand/WandTreeService.handleNodeBuy} — actor state, a HELD owned wand (the F-037
 * server gate), node existence, parent ownership and the Wand-XP balance. Sent by the
 * skill-tree screen's wand tab ({@code client/wand/WandProgressPanel}).
 *
 * @param nodeId a {@code WandTree} node id (e.g. {@code riss_s2}, {@code glut_c1})
 */
public record C2SWandNodeBuyPayload(String nodeId) implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<C2SWandNodeBuyPayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "wand/node_buy"));

    public static final StreamCodec<io.netty.buffer.ByteBuf, C2SWandNodeBuyPayload> STREAM_CODEC =
            StreamCodec.composite(
                    ByteBufCodecs.STRING_UTF8, C2SWandNodeBuyPayload::nodeId,
                    C2SWandNodeBuyPayload::new);

    @Override
    public CustomPacketPayload.Type<C2SWandNodeBuyPayload> type() {
        return TYPE;
    }
}
