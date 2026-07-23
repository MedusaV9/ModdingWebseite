package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: skill tree definition JSON blob (not secret). Sent at login + reload so
 * P3 can render the tree without a separate config sync channel.
 */
public record S2CSkillTreePayload(String json) implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<S2CSkillTreePayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "skill_tree"));

    public static final StreamCodec<ByteBuf, S2CSkillTreePayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.STRING_UTF8, S2CSkillTreePayload::json,
            S2CSkillTreePayload::new);

    @Override
    public Type<S2CSkillTreePayload> type() {
        return TYPE;
    }
}
