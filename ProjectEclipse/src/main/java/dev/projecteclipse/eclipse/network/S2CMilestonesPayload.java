package dev.projecteclipse.eclipse.network;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;

/**
 * Server → client: the ANONYMIZED altar milestone ladder ({@code milestones.json} —
 * {@link EclipseConfig.Milestone}), sent at login, on {@code /eclipse reload} and on
 * every altar level change (the {@code AnnouncementService} altar poll). Cached in
 * {@code ClientStateCache.milestones}; the handbook's Altar Offering tab renders the
 * costs with real item icons.
 *
 * <p>Wave-5 A5 anti-spoiler trim: only milestones with {@code level <= altarLevel + 1}
 * ship with data ({@code revealed}) — the reached tiers plus the tier the altar is
 * currently hungering for. One data-free stub ({@code revealed() == false}, empty
 * costs/rewards) marks the tier beyond that, so the client can tease "???" without ever
 * receiving future demands; nothing past it leaves the server.</p>
 */
public record S2CMilestonesPayload(List<Entry> entries) implements CustomPacketPayload {
    /** One item cost line, e.g. {@code minecraft:diamond} x 8. */
    public record Cost(String item, int count) {
        public static final StreamCodec<ByteBuf, Cost> STREAM_CODEC = StreamCodec.composite(
                ByteBufCodecs.STRING_UTF8, Cost::item,
                ByteBufCodecs.VAR_INT, Cost::count,
                Cost::new);
    }

    /**
     * One milestone level: what the altar demands and which unlock keys it grants.
     * {@code revealed == false} marks the anonymized teaser stub (level only, no data).
     */
    public record Entry(int level, List<Cost> costs, List<String> rewards, boolean revealed) {
        public Entry {
            costs = List.copyOf(costs);
            rewards = List.copyOf(rewards);
        }

        public static final StreamCodec<ByteBuf, Entry> STREAM_CODEC = StreamCodec.composite(
                ByteBufCodecs.VAR_INT, Entry::level,
                Cost.STREAM_CODEC.apply(ByteBufCodecs.list()), Entry::costs,
                ByteBufCodecs.STRING_UTF8.apply(ByteBufCodecs.list()), Entry::rewards,
                ByteBufCodecs.BOOL, Entry::revealed,
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

    /**
     * Snapshot of the server's current milestone config, trimmed against the world's
     * altar level (A5): levels {@code <= altarLevel + 1} are revealed with full data,
     * the single next level (when one exists) rides along as a data-free teaser stub,
     * and everything beyond is simply not sent.
     */
    public static S2CMilestonesPayload current(MinecraftServer server) {
        int altarLevel = EclipseWorldState.get(server).getAltarLevel();
        List<Entry> entries = new ArrayList<>();
        EclipseConfig.Milestone teaser = null;
        for (EclipseConfig.Milestone milestone : EclipseConfig.milestones()) {
            if (milestone.level() <= altarLevel + 1) {
                List<Cost> costs = new ArrayList<>();
                for (EclipseConfig.ItemCost cost : milestone.cost()) {
                    costs.add(new Cost(cost.item(), cost.count()));
                }
                entries.add(new Entry(milestone.level(), costs, milestone.rewards(), true));
            } else if (teaser == null || milestone.level() < teaser.level()) {
                teaser = milestone;
            }
        }
        if (teaser != null) {
            entries.add(new Entry(teaser.level(), List.of(), List.of(), false));
        }
        return new S2CMilestonesPayload(entries);
    }

    @Override
    public CustomPacketPayload.Type<S2CMilestonesPayload> type() {
        return TYPE;
    }
}
