package dev.projecteclipse.eclipse.network.wand;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * C2S "cast my selected wand power" request ({@code eclipse:wand/cast}). Carries ONLY the
 * hand — everything else (held item, ownership, path, selected index, charge, cooldown,
 * disabled state, protection zones) is read and validated server-side in
 * {@code wand/WandPowers.handleCast}; a tampering client gains nothing.
 *
 * @param mainHand true = main hand, false = off hand
 */
public record C2SWandCastPayload(boolean mainHand) implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<C2SWandCastPayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "wand/cast"));

    public static final StreamCodec<io.netty.buffer.ByteBuf, C2SWandCastPayload> STREAM_CODEC =
            StreamCodec.composite(
                    ByteBufCodecs.BOOL, C2SWandCastPayload::mainHand,
                    C2SWandCastPayload::new);

    @Override
    public CustomPacketPayload.Type<C2SWandCastPayload> type() {
        return TYPE;
    }
}
