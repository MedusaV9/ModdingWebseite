package dev.projecteclipse.eclipse.network.gate;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client snapshot of the progression unlock state (P3 §3.12 / §7.3, owner W11).
 * Sent by {@code progression.UnlockSync} on login and whenever the derived
 * {@code UnlockState} key set changes (day change, altar level, boss kill, config reload).
 * Cached client-side in {@code client.progression.ClientUnlockCache}; the EMI plugin
 * consults that cache to hide items/recipes of still-locked mod namespaces.
 *
 * @param keys             all currently-unlocked {@code UnlockState} gate keys
 * @param lockedNamespaces registry namespaces currently locked by {@code ModGate}
 *                         (pre-resolved server-side so the client needs no config knowledge)
 */
public record S2CUnlockedKeysPayload(List<String> keys, List<String> lockedNamespaces)
        implements CustomPacketPayload {

    public S2CUnlockedKeysPayload {
        keys = List.copyOf(keys);
        lockedNamespaces = List.copyOf(lockedNamespaces);
    }

    public static final CustomPacketPayload.Type<S2CUnlockedKeysPayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "gate/unlocked_keys"));

    public static final StreamCodec<ByteBuf, S2CUnlockedKeysPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.STRING_UTF8.apply(ByteBufCodecs.list()), S2CUnlockedKeysPayload::keys,
            ByteBufCodecs.STRING_UTF8.apply(ByteBufCodecs.list()), S2CUnlockedKeysPayload::lockedNamespaces,
            S2CUnlockedKeysPayload::new);

    @Override
    public Type<S2CUnlockedKeysPayload> type() {
        return TYPE;
    }
}
