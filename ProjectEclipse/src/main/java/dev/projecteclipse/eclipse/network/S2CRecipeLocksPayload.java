package dev.projecteclipse.eclipse.network;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/** Server → client: recipe/item locks for EMI hiding (R7). */
public record S2CRecipeLocksPayload(List<String> lockedItemIds, List<String> lockedRecipeIds)
        implements CustomPacketPayload {

    public S2CRecipeLocksPayload {
        lockedItemIds = List.copyOf(lockedItemIds);
        lockedRecipeIds = List.copyOf(lockedRecipeIds);
    }

    public static final CustomPacketPayload.Type<S2CRecipeLocksPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "recipe_locks"));

    public static final StreamCodec<ByteBuf, S2CRecipeLocksPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.STRING_UTF8.apply(ByteBufCodecs.list()), S2CRecipeLocksPayload::lockedItemIds,
            ByteBufCodecs.STRING_UTF8.apply(ByteBufCodecs.list()), S2CRecipeLocksPayload::lockedRecipeIds,
            S2CRecipeLocksPayload::new);

    @Override
    public Type<S2CRecipeLocksPayload> type() {
        return TYPE;
    }
}
