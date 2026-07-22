package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: opens the W14 goal editor GUI ({@code devtools.client.GoalEditorScreen})
 * with the CURRENT {@code days.json} content as raw JSON (server-authoritative — the client
 * never reads its own config folder). Sent by {@code /eclipse goals edit} via
 * {@code devtools.ConfigEditor.openFor}; the edited result comes back as
 * {@link C2SConfigEditPayload}. String bound matches the {@code ConfigEditor} 64 KB limit.
 */
public record S2COpenGoalEditorPayload(String daysJson) implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<S2COpenGoalEditorPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "open_goal_editor"));

    public static final StreamCodec<ByteBuf, S2COpenGoalEditorPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.stringUtf8(C2SConfigEditPayload.MAX_JSON_BYTES), S2COpenGoalEditorPayload::daysJson,
            S2COpenGoalEditorPayload::new);

    @Override
    public CustomPacketPayload.Type<S2COpenGoalEditorPayload> type() {
        return TYPE;
    }
}
