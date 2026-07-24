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
 *
 * <p>D8 additions on the same login payload (no new packet): {@code modcheckAllowContinue} is
 * the SERVER's authoritative mismatch verdict from {@code anticheat.json} and
 * {@code modcheckPolicyHash} is the server's mod-policy digest ({@code AntiCheatCheck.policyHash});
 * the client only logs drift against its baked manifest — enforcement already happened
 * server-side in {@code AntiCheatCheck.handleModlist}.</p>
 */
public record S2COpStatusPayload(int opLevel, boolean modcheckAllowContinue, String modcheckPolicyHash)
        implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<S2COpStatusPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "op_status"));

    public static final StreamCodec<ByteBuf, S2COpStatusPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.VAR_INT, S2COpStatusPayload::opLevel,
            ByteBufCodecs.BOOL, S2COpStatusPayload::modcheckAllowContinue,
            ByteBufCodecs.stringUtf8(64), S2COpStatusPayload::modcheckPolicyHash,
            S2COpStatusPayload::new);

    @Override
    public CustomPacketPayload.Type<S2COpStatusPayload> type() {
        return TYPE;
    }
}
