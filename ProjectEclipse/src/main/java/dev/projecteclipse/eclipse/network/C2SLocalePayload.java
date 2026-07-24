package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Client → server: syncs the player's Eclipse UI locale preference ({@code docs/plans_v3/P3_ui.md}
 * §3.2). {@code locale} is {@code "auto"}, {@code "en_us"} or {@code "de_de"} (aliases
 * {@code en}/{@code de} are normalized client-side before send). When {@code explicit} is
 * {@code false} the server clears any stored override and falls back to vanilla
 * {@code clientInformation().language()}.
 */
public record C2SLocalePayload(String locale, boolean explicit) implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<C2SLocalePayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "locale"));

    public static final StreamCodec<ByteBuf, C2SLocalePayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.STRING_UTF8, C2SLocalePayload::locale,
            ByteBufCodecs.BOOL, C2SLocalePayload::explicit,
            C2SLocalePayload::new);

    @Override
    public CustomPacketPayload.Type<C2SLocalePayload> type() {
        return TYPE;
    }
}
