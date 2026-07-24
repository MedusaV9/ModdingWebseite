package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/** Client → server: purchase a skill tree node (R3). Server re-validates cost and prereqs. */
public record C2SSkillNodeBuyPayload(String nodeId) implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<C2SSkillNodeBuyPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "skill_node_buy"));

    public static final StreamCodec<ByteBuf, C2SSkillNodeBuyPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.STRING_UTF8, C2SSkillNodeBuyPayload::nodeId,
            C2SSkillNodeBuyPayload::new);

    @Override
    public Type<C2SSkillNodeBuyPayload> type() {
        return TYPE;
    }
}
