package dev.projecteclipse.eclipse.network;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/** Server → client: skill XP bar, points, owned tree nodes (R3). */
public record S2CSkillStatePayload(
        int level,
        long totalXp,
        int xpIntoLevel,
        int xpForLevel,
        int points,
        int unspent,
        List<String> ownedNodes,
        boolean procMsgEnabled,
        boolean secretMultiplierActive) implements CustomPacketPayload {

    public S2CSkillStatePayload {
        ownedNodes = List.copyOf(ownedNodes);
    }

    public static final CustomPacketPayload.Type<S2CSkillStatePayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "skill_state"));

    public static final StreamCodec<ByteBuf, S2CSkillStatePayload> STREAM_CODEC = StreamCodec.of(
            S2CSkillStatePayload::encode,
            S2CSkillStatePayload::decode);

    private static void encode(ByteBuf buf, S2CSkillStatePayload value) {
        ByteBufCodecs.VAR_INT.encode(buf, value.level());
        ByteBufCodecs.VAR_LONG.encode(buf, value.totalXp());
        ByteBufCodecs.VAR_INT.encode(buf, value.xpIntoLevel());
        ByteBufCodecs.VAR_INT.encode(buf, value.xpForLevel());
        ByteBufCodecs.VAR_INT.encode(buf, value.points());
        ByteBufCodecs.VAR_INT.encode(buf, value.unspent());
        ByteBufCodecs.STRING_UTF8.apply(ByteBufCodecs.list()).encode(buf, value.ownedNodes());
        ByteBufCodecs.BOOL.encode(buf, value.procMsgEnabled());
        ByteBufCodecs.BOOL.encode(buf, value.secretMultiplierActive());
    }

    private static S2CSkillStatePayload decode(ByteBuf buf) {
        return new S2CSkillStatePayload(
                ByteBufCodecs.VAR_INT.decode(buf),
                ByteBufCodecs.VAR_LONG.decode(buf),
                ByteBufCodecs.VAR_INT.decode(buf),
                ByteBufCodecs.VAR_INT.decode(buf),
                ByteBufCodecs.VAR_INT.decode(buf),
                ByteBufCodecs.VAR_INT.decode(buf),
                ByteBufCodecs.STRING_UTF8.apply(ByteBufCodecs.list()).decode(buf),
                ByteBufCodecs.BOOL.decode(buf),
                ByteBufCodecs.BOOL.decode(buf));
    }

    @Override
    public Type<S2CSkillStatePayload> type() {
        return TYPE;
    }
}
