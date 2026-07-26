package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: skill tree definition JSON blob (not secret). Sent at login + reload so
 * P3 can render the tree without a separate config sync channel.
 *
 * <p>PAYLOADFIX (F-001): the blob used to ride plain {@code STRING_UTF8}, which hard-fails
 * the encoder at 32,767 chars — a grown {@code skilltree.json} (the shipped default is
 * already ~26K chars) kicked every joining player with "Failed to encode packet
 * 'clientbound/minecraft:custom_payload'". The codec now uses {@link NetCodecs#LARGE_UTF8}
 * (256K chars ≈ 768 KiB, inside the 1 MiB play-phase budget); {@code SkillService.sendTree}
 * refuses to send anything over that bound instead of letting the encoder throw.</p>
 */
public record S2CSkillTreePayload(String json) implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<S2CSkillTreePayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "skill_tree"));

    public static final StreamCodec<ByteBuf, S2CSkillTreePayload> STREAM_CODEC = StreamCodec.composite(
            NetCodecs.LARGE_UTF8, S2CSkillTreePayload::json,
            S2CSkillTreePayload::new);

    @Override
    public Type<S2CSkillTreePayload> type() {
        return TYPE;
    }
}
