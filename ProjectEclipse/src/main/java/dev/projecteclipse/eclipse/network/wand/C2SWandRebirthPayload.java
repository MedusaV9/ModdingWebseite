package dev.projecteclipse.eclipse.network.wand;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * C2S "rebirth my wand tree" request ({@code eclipse:wand/rebirth}, F-036 — distinct
 * from the Leben-system {@code eclipse:rebirth_request}). Carries no data on purpose:
 * {@code wand/WandTreeService.handleRebirth} re-validates the maxed tree, the Wand-XP
 * balance and the held owned wand; the client's cached cost is advisory display state
 * only. Sent by the wand tab's rebirth button.
 */
public record C2SWandRebirthPayload() implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<C2SWandRebirthPayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "wand/rebirth"));

    public static final StreamCodec<ByteBuf, C2SWandRebirthPayload> STREAM_CODEC =
            StreamCodec.unit(new C2SWandRebirthPayload());

    @Override
    public CustomPacketPayload.Type<C2SWandRebirthPayload> type() {
        return TYPE;
    }
}
