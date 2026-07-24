package dev.projecteclipse.eclipse.network;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: the altar milestone ladder ({@code milestones.json} —
 * {@link EclipseConfig.Milestone}), sent at login and re-broadcast on
 * {@code /eclipse reload}. Cached in {@code ClientStateCache.milestones}; the handbook's
 * Rewards tab renders the costs with real item icons and the Status tab derives the altar
 * ring's max level from it. Milestones are progression-public information (announcements
 * already name them), so unlike the timeline this payload is NOT anonymized.
 */
public record S2CMilestonesPayload(List<Entry> entries) implements CustomPacketPayload {
    /** One item cost line, e.g. {@code minecraft:diamond} x 8. */
    public record Cost(String item, int count) {
        public static final StreamCodec<ByteBuf, Cost> STREAM_CODEC = StreamCodec.composite(
                ByteBufCodecs.STRING_UTF8, Cost::item,
                ByteBufCodecs.VAR_INT, Cost::count,
                Cost::new);
    }

    /** One milestone level: what the altar demands and which unlock keys it grants. */
    public record Entry(int level, List<Cost> costs, List<String> rewards) {
        public Entry {
            costs = List.copyOf(costs);
            rewards = List.copyOf(rewards);
        }

        public static final StreamCodec<ByteBuf, Entry> STREAM_CODEC = StreamCodec.composite(
                ByteBufCodecs.VAR_INT, Entry::level,
                Cost.STREAM_CODEC.apply(ByteBufCodecs.list()), Entry::costs,
                ByteBufCodecs.STRING_UTF8.apply(ByteBufCodecs.list()), Entry::rewards,
                Entry::new);
    }

    public S2CMilestonesPayload {
        entries = List.copyOf(entries);
    }

    public static final CustomPacketPayload.Type<S2CMilestonesPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "milestones"));

    public static final StreamCodec<ByteBuf, S2CMilestonesPayload> STREAM_CODEC = StreamCodec.composite(
            Entry.STREAM_CODEC.apply(ByteBufCodecs.list()), S2CMilestonesPayload::entries,
            S2CMilestonesPayload::new);

    /** Snapshot of the server's current milestone config. */
    public static S2CMilestonesPayload current() {
        List<Entry> entries = new ArrayList<>();
        for (EclipseConfig.Milestone milestone : EclipseConfig.milestones()) {
            List<Cost> costs = new ArrayList<>();
            for (EclipseConfig.ItemCost cost : milestone.cost()) {
                costs.add(new Cost(cost.item(), cost.count()));
            }
            entries.add(new Entry(milestone.level(), costs, milestone.rewards()));
        }
        return new S2CMilestonesPayload(entries);
    }

    @Override
    public CustomPacketPayload.Type<S2CMilestonesPayload> type() {
        return TYPE;
    }
}
