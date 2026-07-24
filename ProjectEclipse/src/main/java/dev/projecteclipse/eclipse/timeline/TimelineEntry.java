package dev.projecteclipse.eclipse.timeline;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.resources.ResourceLocation;

/**
 * One node of the event timeline ({@code docs/ideas/03_ui_ux.md} §E), as synced to clients by
 * {@code S2CTimelinePayload}. Entries are built server-side by {@link TimelineService} from
 * {@code days.json} + {@code milestones.json} and are ANONYMIZED before sending: a
 * {@code hidden} (future) entry carries an empty {@code titleKey} and the {@link #NO_ICON}
 * sentinel, so clients cannot datamine upcoming content — W9's handbook renders those as
 * "???" glitch nodes.
 *
 * @param id        stable entry id (day entries first, then altar milestones)
 * @param unlockDay the event day the entry belongs to; {@code 0} for altar milestones,
 *                  which unlock by offerings rather than by the calendar
 * @param titleKey  translation key of the entry title; empty when {@code hidden}
 * @param icon      icon texture; {@link #NO_ICON} when {@code hidden}
 * @param hidden    whether the entry is still in the future (anonymized)
 * @param reached   whether the entry has been reached (day passed / altar level attained)
 */
public record TimelineEntry(int id, int unlockDay, String titleKey, ResourceLocation icon,
        boolean hidden, boolean reached) {
    /** Icon sentinel of anonymized future entries (no real texture behind it). */
    public static final ResourceLocation NO_ICON =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "empty");

    public static final StreamCodec<ByteBuf, TimelineEntry> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.VAR_INT, TimelineEntry::id,
            ByteBufCodecs.VAR_INT, TimelineEntry::unlockDay,
            ByteBufCodecs.STRING_UTF8, TimelineEntry::titleKey,
            ResourceLocation.STREAM_CODEC, TimelineEntry::icon,
            ByteBufCodecs.BOOL, TimelineEntry::hidden,
            ByteBufCodecs.BOOL, TimelineEntry::reached,
            TimelineEntry::new);
}
