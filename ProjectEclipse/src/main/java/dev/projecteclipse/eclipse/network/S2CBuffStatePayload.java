package dev.projecteclipse.eclipse.network;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/** Server → client: active timed buff rows for sidebar / overlay (R16). */
public record S2CBuffStatePayload(List<Buff> active) implements CustomPacketPayload {

    public record Buff(String id, String titleEn, String titleDe, long endsAtEpochMillis, float magnitude) {
        public static final StreamCodec<ByteBuf, Buff> STREAM_CODEC = StreamCodec.composite(
                ByteBufCodecs.STRING_UTF8, Buff::id,
                ByteBufCodecs.STRING_UTF8, Buff::titleEn,
                ByteBufCodecs.STRING_UTF8, Buff::titleDe,
                ByteBufCodecs.VAR_LONG, Buff::endsAtEpochMillis,
                ByteBufCodecs.FLOAT, Buff::magnitude,
                Buff::new);
    }

    public S2CBuffStatePayload {
        active = List.copyOf(active);
    }

    public static final CustomPacketPayload.Type<S2CBuffStatePayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "buff_state"));

    public static final StreamCodec<ByteBuf, S2CBuffStatePayload> STREAM_CODEC = StreamCodec.composite(
            Buff.STREAM_CODEC.apply(ByteBufCodecs.list()), S2CBuffStatePayload::active,
            S2CBuffStatePayload::new);

    @Override
    public Type<S2CBuffStatePayload> type() {
        return TYPE;
    }
}
