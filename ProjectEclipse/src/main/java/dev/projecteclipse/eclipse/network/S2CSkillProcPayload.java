package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/** Server → client: skill proc flash cue (R3). P3 plays sound/FX from {@code procId}. */
public record S2CSkillProcPayload(String procId, float magnitude) implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<S2CSkillProcPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "skill_proc"));

    public static final StreamCodec<ByteBuf, S2CSkillProcPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.STRING_UTF8, S2CSkillProcPayload::procId,
            ByteBufCodecs.FLOAT, S2CSkillProcPayload::magnitude,
            S2CSkillProcPayload::new);

    @Override
    public Type<S2CSkillProcPayload> type() {
        return TYPE;
    }
}
