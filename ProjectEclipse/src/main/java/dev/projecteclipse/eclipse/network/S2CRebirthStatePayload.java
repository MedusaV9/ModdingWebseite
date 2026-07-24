package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: the receiver's rebirth standing (D11), consumed by W-SKILLTREE's
 * rebirth footer in the skill tree screen. Sent at login and after every completed
 * ceremony ({@code RebirthService.syncTo}).
 *
 * @param count               completed rebirths of this player
 * @param nextCostShards      personal umbral-shard price of the NEXT rebirth
 * @param levelCostMultiplier current global skill level-cost multiplier
 *                            ({@code levelCostMultiplierPerRebirth ^ count}; 1.0 = never reborn)
 */
public record S2CRebirthStatePayload(int count, int nextCostShards, float levelCostMultiplier)
        implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CRebirthStatePayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "rebirth_state"));

    public static final StreamCodec<ByteBuf, S2CRebirthStatePayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.VAR_INT, S2CRebirthStatePayload::count,
            ByteBufCodecs.VAR_INT, S2CRebirthStatePayload::nextCostShards,
            ByteBufCodecs.FLOAT, S2CRebirthStatePayload::levelCostMultiplier,
            S2CRebirthStatePayload::new);

    @Override
    public Type<S2CRebirthStatePayload> type() {
        return TYPE;
    }
}
