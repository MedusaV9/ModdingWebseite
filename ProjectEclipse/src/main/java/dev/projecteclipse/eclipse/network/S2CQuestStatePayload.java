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
 *
 * <p>PAYLOADFIX (F-001): quest texts come straight from operator-edited {@code goals.json};
 * plain {@code STRING_UTF8} would kick every joining player once one text crosses 32,767
 * chars. Ids and texts now ride {@link NetCodecs#clampedUtf8(int)}, which truncates with a
 * WARN log instead of throwing in the encoder — a cut-off HUD line is recoverable, a kicked
 * player is not.</p>
 */
public record S2CQuestStatePayload(int day, List<QuestEntry> entries) implements CustomPacketPayload {
    /**
     * One quest row on the client HUD.
     *
     * @param kind {@code 0} main, {@code 1} side, {@code 2} personal
     * @param rewardShards personal shards paid on completion (FIX-ECON: rendered as a
     *        "◆N" chip on sidebar/TAB rows so the rebirth income is advertised BEFORE
     *        the materialize ceremony; {@code 0} = no chip)
     * @param rewardXp skill XP paid on completion (EVAL-DOPA-F: rendered as a dim "+N XP"
     *        chip half next to the shard chip; {@code 0} = no chip)
     */
    public record QuestEntry(
            String id,
            byte kind,
            String textEn,
            String textDe,
            int progress,
            int target,
            boolean done,
            boolean teamScope,
            int rewardShards,
            int rewardXp) {

        /** Quest ids are config keys — 256 chars is already pathological. */
        private static final StreamCodec<ByteBuf, String> ID_CODEC = NetCodecs.clampedUtf8(256);
        /** One localized HUD line; 4,096 chars survives even essay-length operator texts. */
        private static final StreamCodec<ByteBuf, String> TEXT_CODEC = NetCodecs.clampedUtf8(4096);

        public static final StreamCodec<ByteBuf, QuestEntry> STREAM_CODEC = StreamCodec.of(
                QuestEntry::encode,
                QuestEntry::decode);

        private static void encode(ByteBuf buf, QuestEntry value) {
            ID_CODEC.encode(buf, value.id());
            ByteBufCodecs.BYTE.encode(buf, value.kind());
            TEXT_CODEC.encode(buf, value.textEn());
            TEXT_CODEC.encode(buf, value.textDe());
            ByteBufCodecs.VAR_INT.encode(buf, value.progress());
            ByteBufCodecs.VAR_INT.encode(buf, value.target());
            ByteBufCodecs.BOOL.encode(buf, value.done());
            ByteBufCodecs.BOOL.encode(buf, value.teamScope());
            ByteBufCodecs.VAR_INT.encode(buf, value.rewardShards());
            ByteBufCodecs.VAR_INT.encode(buf, value.rewardXp());
        }

        private static QuestEntry decode(ByteBuf buf) {
            return new QuestEntry(
                    ID_CODEC.decode(buf),
                    ByteBufCodecs.BYTE.decode(buf),
                    TEXT_CODEC.decode(buf),
                    TEXT_CODEC.decode(buf),
                    ByteBufCodecs.VAR_INT.decode(buf),
                    ByteBufCodecs.VAR_INT.decode(buf),
                    ByteBufCodecs.BOOL.decode(buf),
                    ByteBufCodecs.BOOL.decode(buf),
                    ByteBufCodecs.VAR_INT.decode(buf),
                    ByteBufCodecs.VAR_INT.decode(buf));
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
