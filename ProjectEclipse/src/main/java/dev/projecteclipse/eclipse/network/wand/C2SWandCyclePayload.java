package dev.projecteclipse.eclipse.network.wand;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * C2S "cycle my selected wand power" request ({@code eclipse:wand/cycle}) — WANDFIX-3
 * sneak-scroll switching. Carries ONLY the direction; which wand, which powers are
 * unlocked, ownership and the freeze/actor gates are all validated server-side in
 * {@code wand/WandPowers.handleCycle}. Sent by the client {@code WandSelectInput}
 * scroll hook (sneak + wand in either hand).
 *
 * @param forward true = next power, false = previous power
 */
public record C2SWandCyclePayload(boolean forward) implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<C2SWandCyclePayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "wand/cycle"));

    public static final StreamCodec<io.netty.buffer.ByteBuf, C2SWandCyclePayload> STREAM_CODEC =
            StreamCodec.composite(
                    ByteBufCodecs.BOOL, C2SWandCyclePayload::forward,
                    C2SWandCyclePayload::new);

    @Override
    public CustomPacketPayload.Type<C2SWandCyclePayload> type() {
        return TYPE;
    }
}
