package dev.projecteclipse.eclipse.network.collections;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: the receiving player's FULL collections snapshot — definitions AND
 * progress in one payload, sent on login, after every tier grant and after a config
 * reload sweep. Definitions ride the wire (instead of a client-side roster) because
 * {@code collections.json} is data-driven and hot-reloadable: the handbook tab always
 * renders exactly what the server enforces. 17 collections × ~6 tiers ≈ 2 KB, only on
 * rare events — per-credit updates use {@link S2CCollectionDeltaPayload}.
 *
 * <p>Registered by {@link CollectionsPayloads} (own registrar — NOT
 * {@code EclipsePayloads}); the client hooks in via
 * {@code CollectionsPayloads.setSnapshotHandler} ({@code client.collections.ClientCollectionsCache}).</p>
 */
public record S2CCollectionsPayload(List<Entry> entries) implements CustomPacketPayload {

    /** One collection: definition (category/icon/tiers) + this player's progress. */
    public record Entry(String id, String category, String icon, List<Tier> tiers,
            long count, int grantedTier) {
        public Entry {
            tiers = List.copyOf(tiers);
        }
    }

    /** One reward tier (thresholds ascending; {@code unlockItems} ids or {@code #tags}). */
    public record Tier(long threshold, int xp, int points, List<String> unlockItems) {
        public Tier {
            unlockItems = List.copyOf(unlockItems);
        }
    }

    public S2CCollectionsPayload {
        entries = List.copyOf(entries);
    }

    public static final CustomPacketPayload.Type<S2CCollectionsPayload> TYPE =
            new CustomPacketPayload.Type<>(
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "collections/sync"));

    public static final StreamCodec<ByteBuf, S2CCollectionsPayload> STREAM_CODEC =
            StreamCodec.of(S2CCollectionsPayload::write, S2CCollectionsPayload::read);

    private static void write(ByteBuf buf, S2CCollectionsPayload payload) {
        ByteBufCodecs.VAR_INT.encode(buf, payload.entries.size());
        for (Entry entry : payload.entries) {
            ByteBufCodecs.STRING_UTF8.encode(buf, entry.id());
            ByteBufCodecs.STRING_UTF8.encode(buf, entry.category());
            ByteBufCodecs.STRING_UTF8.encode(buf, entry.icon());
            ByteBufCodecs.VAR_INT.encode(buf, entry.tiers().size());
            for (Tier tier : entry.tiers()) {
                ByteBufCodecs.VAR_LONG.encode(buf, tier.threshold());
                ByteBufCodecs.VAR_INT.encode(buf, tier.xp());
                ByteBufCodecs.VAR_INT.encode(buf, tier.points());
                ByteBufCodecs.VAR_INT.encode(buf, tier.unlockItems().size());
                for (String item : tier.unlockItems()) {
                    ByteBufCodecs.STRING_UTF8.encode(buf, item);
                }
            }
            ByteBufCodecs.VAR_LONG.encode(buf, entry.count());
            ByteBufCodecs.VAR_INT.encode(buf, entry.grantedTier());
        }
    }

    private static S2CCollectionsPayload read(ByteBuf buf) {
        int size = ByteBufCodecs.VAR_INT.decode(buf);
        List<Entry> entries = new ArrayList<>(size);
        for (int i = 0; i < size; i++) {
            String id = ByteBufCodecs.STRING_UTF8.decode(buf);
            String category = ByteBufCodecs.STRING_UTF8.decode(buf);
            String icon = ByteBufCodecs.STRING_UTF8.decode(buf);
            int tierCount = ByteBufCodecs.VAR_INT.decode(buf);
            List<Tier> tiers = new ArrayList<>(tierCount);
            for (int t = 0; t < tierCount; t++) {
                long threshold = ByteBufCodecs.VAR_LONG.decode(buf);
                int xp = ByteBufCodecs.VAR_INT.decode(buf);
                int points = ByteBufCodecs.VAR_INT.decode(buf);
                int unlockCount = ByteBufCodecs.VAR_INT.decode(buf);
                List<String> unlocks = new ArrayList<>(unlockCount);
                for (int u = 0; u < unlockCount; u++) {
                    unlocks.add(ByteBufCodecs.STRING_UTF8.decode(buf));
                }
                tiers.add(new Tier(threshold, xp, points, unlocks));
            }
            long count = ByteBufCodecs.VAR_LONG.decode(buf);
            int grantedTier = ByteBufCodecs.VAR_INT.decode(buf);
            entries.add(new Entry(id, category, icon, tiers, count, grantedTier));
        }
        return new S2CCollectionsPayload(entries);
    }

    @Override
    public CustomPacketPayload.Type<S2CCollectionsPayload> type() {
        return TYPE;
    }
}
