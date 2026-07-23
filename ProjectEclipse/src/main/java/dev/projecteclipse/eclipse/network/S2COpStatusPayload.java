package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client on login: the receiving player's op permission level (P3-W8, plan §3.8/§7.3).
 * The client persists {@code opLevel >= 2} to {@code config/eclipse-journey-state.json} so the
 * modpack-mode title screen can restore the Singleplayer/Multiplayer buttons on the NEXT boot
 * (the title renders pre-connection, so live server state cannot help there). Cosmetic only —
 * real permissions stay enforced server-side (plan risk R-11).
 */
public record S2COpStatusPayload(int opLevel) implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<S2COpStatusPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "op_status"));

    public static final StreamCodec<ByteBuf, S2COpStatusPayload> STREAM_CODEC =
            ByteBufCodecs.VAR_INT.map(S2COpStatusPayload::new, S2COpStatusPayload::opLevel);

    @Override
    public CustomPacketPayload.Type<S2COpStatusPayload> type() {
        return TYPE;
    }
}
