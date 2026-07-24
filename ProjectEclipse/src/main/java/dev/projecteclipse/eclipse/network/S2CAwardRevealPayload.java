package dev.projecteclipse.eclipse.network;

import java.util.List;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.core.UUIDUtil;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: daily award reveal overlay (R5). Carries UUIDs only — P3 renders
 * anonymized heads. Category titles/rewards are en/de literals.
 */
public record S2CAwardRevealPayload(int day, List<Category> categories) implements CustomPacketPayload {

    public record Candidate(UUID uuid, long value) {
        public static final StreamCodec<ByteBuf, Candidate> STREAM_CODEC = StreamCodec.composite(
                UUIDUtil.STREAM_CODEC, Candidate::uuid,
                ByteBufCodecs.VAR_LONG, Candidate::value,
                Candidate::new);
    }

    public record Category(
            String id,
            String titleEn,
            String titleDe,
            String rewardTextEn,
            String rewardTextDe,
            List<Candidate> candidates,
            List<UUID> winners) {

        public static final StreamCodec<ByteBuf, Category> STREAM_CODEC = StreamCodec.of(
                Category::encode,
                Category::decode);

        private static void encode(ByteBuf buf, Category value) {
            ByteBufCodecs.STRING_UTF8.encode(buf, value.id());
            ByteBufCodecs.STRING_UTF8.encode(buf, value.titleEn());
            ByteBufCodecs.STRING_UTF8.encode(buf, value.titleDe());
            ByteBufCodecs.STRING_UTF8.encode(buf, value.rewardTextEn());
            ByteBufCodecs.STRING_UTF8.encode(buf, value.rewardTextDe());
            Candidate.STREAM_CODEC.apply(ByteBufCodecs.list()).encode(buf, value.candidates());
            UUIDUtil.STREAM_CODEC.apply(ByteBufCodecs.list()).encode(buf, value.winners());
        }

        private static Category decode(ByteBuf buf) {
            return new Category(
                    ByteBufCodecs.STRING_UTF8.decode(buf),
                    ByteBufCodecs.STRING_UTF8.decode(buf),
                    ByteBufCodecs.STRING_UTF8.decode(buf),
                    ByteBufCodecs.STRING_UTF8.decode(buf),
                    ByteBufCodecs.STRING_UTF8.decode(buf),
                    Candidate.STREAM_CODEC.apply(ByteBufCodecs.list()).decode(buf),
                    UUIDUtil.STREAM_CODEC.apply(ByteBufCodecs.list()).decode(buf));
        }
    }

    public S2CAwardRevealPayload {
        categories = List.copyOf(categories);
    }

    public static final CustomPacketPayload.Type<S2CAwardRevealPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "award_reveal"));

    public static final StreamCodec<ByteBuf, S2CAwardRevealPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.VAR_INT, S2CAwardRevealPayload::day,
            Category.STREAM_CODEC.apply(ByteBufCodecs.list()), S2CAwardRevealPayload::categories,
            S2CAwardRevealPayload::new);

    @Override
    public Type<S2CAwardRevealPayload> type() {
        return TYPE;
    }
}
