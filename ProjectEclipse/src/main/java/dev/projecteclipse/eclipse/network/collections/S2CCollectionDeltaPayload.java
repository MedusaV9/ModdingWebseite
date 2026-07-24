package dev.projecteclipse.eclipse.network.collections;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: one collection counter moved ({@code CollectionsService} coalesces
 * credits and flushes dirty counters at most once per second per collection — the
 * {@code SkillService.DIRTY} pattern). Byte-lean on purpose: mining sessions credit
 * every broken block. Tier boundaries are NOT crossed by this payload alone — tier
 * grants always ride a fresh {@link S2CCollectionsPayload} plus
 * {@link S2CCollectionTierPayload}.
 */
public record S2CCollectionDeltaPayload(String collectionId, long newCount)
        implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CCollectionDeltaPayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "collections/delta"));

    public static final StreamCodec<ByteBuf, S2CCollectionDeltaPayload> STREAM_CODEC =
            StreamCodec.composite(
                    ByteBufCodecs.STRING_UTF8, S2CCollectionDeltaPayload::collectionId,
                    ByteBufCodecs.VAR_LONG, S2CCollectionDeltaPayload::newCount,
                    S2CCollectionDeltaPayload::new);

    @Override
    public CustomPacketPayload.Type<S2CCollectionDeltaPayload> type() {
        return TYPE;
    }
}
