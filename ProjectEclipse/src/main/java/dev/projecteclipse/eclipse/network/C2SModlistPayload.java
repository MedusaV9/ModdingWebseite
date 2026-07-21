package dev.projecteclipse.eclipse.network;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Client → server: the sorted list of mod ids loaded on the client, sent once on login.
 * The server-side anti-cheat ({@code admin.AntiCheatCheck}) disconnects the player if any
 * id matches the {@code anticheat.json} blocklist, or if this payload never arrives within
 * the timeout (mandatory-mod enforcement).
 */
public record C2SModlistPayload(List<String> modIds) implements CustomPacketPayload {
    public C2SModlistPayload {
        modIds = List.copyOf(modIds);
    }

    public static final CustomPacketPayload.Type<C2SModlistPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "modlist"));

    public static final StreamCodec<ByteBuf, C2SModlistPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.STRING_UTF8.apply(ByteBufCodecs.list(4096)), C2SModlistPayload::modIds,
            C2SModlistPayload::new);

    @Override
    public CustomPacketPayload.Type<C2SModlistPayload> type() {
        return TYPE;
    }
}
