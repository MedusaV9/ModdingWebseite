package dev.projecteclipse.eclipse.network.collections;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: the receiving player's full item-lexicon discovered set (uipolish —
 * {@code collections.ItemLexicon}), sent on login and after every new discovery. Only the
 * DISCOVERED ids ride the wire; the roster itself is compile-time shared, so the payload
 * stays a handful of strings and undiscovered entries render as anonymized "???" rows in
 * the handbook's Items category without the server ever confirming what they are.
 *
 * <p>Registered by {@link CollectionsPayloads}; the client hooks in via
 * {@code CollectionsPayloads.setLexiconHandler}
 * ({@code client.collections.ClientCollectionsCache}).</p>
 */
public record S2CItemLexiconPayload(List<String> discovered) implements CustomPacketPayload {

    public S2CItemLexiconPayload {
        discovered = List.copyOf(discovered);
    }

    public static final CustomPacketPayload.Type<S2CItemLexiconPayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "collections/item_lexicon"));

    public static final StreamCodec<ByteBuf, S2CItemLexiconPayload> STREAM_CODEC =
            StreamCodec.composite(
                    ByteBufCodecs.STRING_UTF8.apply(ByteBufCodecs.list()), S2CItemLexiconPayload::discovered,
                    S2CItemLexiconPayload::new);

    @Override
    public CustomPacketPayload.Type<S2CItemLexiconPayload> type() {
        return TYPE;
    }
}
