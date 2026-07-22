package dev.projecteclipse.eclipse.timeline;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.network.S2CTimelinePayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Server-side timeline builder ({@code docs/ideas/03_ui_ux.md} §E). Derives the
 * {@link TimelineEntry} list from {@code days.json} (one node per day plan) +
 * {@code milestones.json} (one node per altar milestone) and the current
 * {@link EclipseWorldState} day/altar level. Anonymization happens HERE, before anything
 * leaves the server: future entries are sent hidden, without title key or icon — the
 * client never receives upcoming content, so it cannot be datamined.
 *
 * <p>{@link S2CTimelinePayload} goes out at login ({@code EclipsePayloads}) and on every
 * day change ({@code DayScheduler}) / altar level change ({@code AnnouncementService}).
 * Title keys are shared with the announcement lang entries
 * ({@code announce.eclipse.day.N.title} / {@code announce.eclipse.milestone.N}).</p>
 */
public final class TimelineService {
    /** Day title keys shipped in the lang files ({@code announce.eclipse.day.1..14.title}). */
    private static final int SHIPPED_DAY_TITLES = 14;
    /** Milestone subtitle keys shipped in the lang files ({@code announce.eclipse.milestone.1..5}). */
    private static final int SHIPPED_MILESTONE_TITLES = 5;
    /** Milestone entries start above any realistic day id to keep ids stable and unique. */
    private static final int MILESTONE_ID_BASE = 1000;

    private static final ResourceLocation DAY_ICON = ResourceLocation.fromNamespaceAndPath(
            EclipseMod.MOD_ID, "textures/gui/sidebar/icon_day.png");
    private static final ResourceLocation MILESTONE_ICON = ResourceLocation.fromNamespaceAndPath(
            EclipseMod.MOD_ID, "textures/gui/sidebar/icon_altar.png");

    private TimelineService() {}

    /** The lang key of a day's announcement/timeline title, with a generic fallback. */
    public static String dayTitleKey(int day) {
        return day >= 1 && day <= SHIPPED_DAY_TITLES
                ? "announce.eclipse.day." + day + ".title"
                : "announce.eclipse.day.generic.title";
    }

    /** The lang key of a milestone's announcement/timeline line, with a generic fallback. */
    public static String milestoneKey(int level) {
        return level >= 1 && level <= SHIPPED_MILESTONE_TITLES
                ? "announce.eclipse.milestone." + level
                : "announce.eclipse.milestone.generic";
    }

    /** Builds the current anonymized timeline (already-reached and current entries only carry data). */
    public static List<TimelineEntry> buildEntries(MinecraftServer server) {
        EclipseWorldState state = EclipseWorldState.get(server);
        int day = state.getDay();
        int altarLevel = state.getAltarLevel();

        List<TimelineEntry> entries = new ArrayList<>();
        for (EclipseConfig.DayPlan plan : EclipseConfig.days()) {
            boolean reached = plan.day() <= day;
            entries.add(reached
                    ? new TimelineEntry(plan.day(), plan.day(), dayTitleKey(plan.day()), DAY_ICON, false, true)
                    : new TimelineEntry(plan.day(), plan.day(), "", TimelineEntry.NO_ICON, true, false));
        }
        for (EclipseConfig.Milestone milestone : EclipseConfig.milestones()) {
            boolean reached = milestone.level() <= altarLevel;
            int id = MILESTONE_ID_BASE + milestone.level();
            entries.add(reached
                    ? new TimelineEntry(id, 0, milestoneKey(milestone.level()), MILESTONE_ICON, false, true)
                    : new TimelineEntry(id, 0, "", TimelineEntry.NO_ICON, true, false));
        }
        return entries;
    }

    /** Login sync: sends the timeline to one player. */
    public static void syncTo(ServerPlayer player) {
        List<TimelineEntry> entries = buildEntries(player.server);
        PacketDistributor.sendToPlayer(player, new S2CTimelinePayload(entries));
        EclipseMod.LOGGER.info("Timeline payload sent to {} ({} entries, {} revealed)",
                player.getScoreboardName(), entries.size(),
                entries.stream().filter(entry -> !entry.hidden()).count());
    }

    /** Day/altar change sync: rebroadcasts the timeline to everyone online. */
    public static void syncAll(MinecraftServer server) {
        List<TimelineEntry> entries = buildEntries(server);
        PacketDistributor.sendToAllPlayers(new S2CTimelinePayload(entries));
        EclipseMod.LOGGER.info("Timeline payload sent to all players ({} entries, {} revealed)",
                entries.size(), entries.stream().filter(entry -> !entry.hidden()).count());
    }
}
