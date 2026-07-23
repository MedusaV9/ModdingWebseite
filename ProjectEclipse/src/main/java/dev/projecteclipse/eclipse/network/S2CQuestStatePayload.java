package dev.projecteclipse.eclipse.network;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: quest list for the current day (mains, sides, personals). Text literals
 * are shipped en/de pairs — not lang keys — to prevent datamining (R2).
 */
public record S2CQuestStatePayload(int day, List<QuestEntry> entries) implements CustomPacketPayload {
    /**
     * One quest row on the client HUD.
     *
     * @param kind {@code 0} main, {@code 1} side, {@code 2} personal
     */
    public record QuestEntry(
            String id,
            byte kind,
            String textEn,
            String textDe,
            int progress,
            int target,
            boolean done,
            boolean teamScope) {

        public static final StreamCodec<ByteBuf, QuestEntry> STREAM_CODEC = StreamCodec.of(
                QuestEntry::encode,
                QuestEntry::decode);

        private static void encode(ByteBuf buf, QuestEntry value) {
            ByteBufCodecs.STRING_UTF8.encode(buf, value.id());
            ByteBufCodecs.BYTE.encode(buf, value.kind());
            ByteBufCodecs.STRING_UTF8.encode(buf, value.textEn());
            ByteBufCodecs.STRING_UTF8.encode(buf, value.textDe());
            ByteBufCodecs.VAR_INT.encode(buf, value.progress());
            ByteBufCodecs.VAR_INT.encode(buf, value.target());
            ByteBufCodecs.BOOL.encode(buf, value.done());
            ByteBufCodecs.BOOL.encode(buf, value.teamScope());
        }

        private static QuestEntry decode(ByteBuf buf) {
            return new QuestEntry(
                    ByteBufCodecs.STRING_UTF8.decode(buf),
                    ByteBufCodecs.BYTE.decode(buf),
                    ByteBufCodecs.STRING_UTF8.decode(buf),
                    ByteBufCodecs.STRING_UTF8.decode(buf),
                    ByteBufCodecs.VAR_INT.decode(buf),
                    ByteBufCodecs.VAR_INT.decode(buf),
                    ByteBufCodecs.BOOL.decode(buf),
                    ByteBufCodecs.BOOL.decode(buf));
        }
    }

    public S2CQuestStatePayload {
        entries = List.copyOf(entries);
    }

    public static final CustomPacketPayload.Type<S2CQuestStatePayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "quest_state"));

    public static final StreamCodec<ByteBuf, S2CQuestStatePayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.VAR_INT, S2CQuestStatePayload::day,
            QuestEntry.STREAM_CODEC.apply(ByteBufCodecs.list()), S2CQuestStatePayload::entries,
            S2CQuestStatePayload::new);

    @Override
    public Type<S2CQuestStatePayload> type() {
        return TYPE;
    }
}
