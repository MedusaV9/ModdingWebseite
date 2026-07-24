package dev.projecteclipse.eclipse.network.collections;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: one collection tier-up moment ({@code tier} is the 1-based tier just
 * reached). The client renders a {@code SkillProcToast}-style card — "✦ Iron Collection
 * II — +100 XP · Shield unlocked" — with {@code EclipseSounds.UI_UNLOCK_STING} (the
 * discovery sting, distinct from {@code SKILL_PROC}). Recipe-bearing tiers land in the
 * same server tick as the {@code S2CRecipeLocksPayload} resync, so EMI un-hides the
 * moment the toast plays. Suppressed entirely when {@code collections.json}
 * {@code toastsEnabled} is false.
 */
public record S2CCollectionTierPayload(String collectionId, int tier, int xp, int points,
        List<String> unlockedItemIds) implements CustomPacketPayload {

    public S2CCollectionTierPayload {
        unlockedItemIds = List.copyOf(unlockedItemIds);
    }

    public static final CustomPacketPayload.Type<S2CCollectionTierPayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "collections/tier"));

    public static final StreamCodec<ByteBuf, S2CCollectionTierPayload> STREAM_CODEC =
            StreamCodec.composite(
                    ByteBufCodecs.STRING_UTF8, S2CCollectionTierPayload::collectionId,
                    ByteBufCodecs.VAR_INT, S2CCollectionTierPayload::tier,
                    ByteBufCodecs.VAR_INT, S2CCollectionTierPayload::xp,
                    ByteBufCodecs.VAR_INT, S2CCollectionTierPayload::points,
                    ByteBufCodecs.STRING_UTF8.apply(ByteBufCodecs.list()),
                    S2CCollectionTierPayload::unlockedItemIds,
                    S2CCollectionTierPayload::new);

    @Override
    public CustomPacketPayload.Type<S2CCollectionTierPayload> type() {
        return TYPE;
    }
}
