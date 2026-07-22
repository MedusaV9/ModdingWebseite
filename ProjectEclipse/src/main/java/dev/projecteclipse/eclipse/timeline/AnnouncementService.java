package dev.projecteclipse.eclipse.timeline;

import java.util.LinkedHashSet;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.network.S2CAnnouncePayload;
import dev.projecteclipse.eclipse.progression.UnlockState;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.server.MinecraftServer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Server-side announcement dispatcher: turns progression beats into {@link S2CAnnouncePayload}s
 * (client: typewriter line + themed bossbar sweep, see {@code client.hud.AnnouncementOverlay}).
 *
 * <p>Wired triggers:</p>
 * <ul>
 *   <li><b>Day advance</b> — {@code DayScheduler.setDay} calls {@link #onDayChanged} (style
 *       {@code day}), which also diffs the unlock-key set and rebroadcasts the timeline.</li>
 *   <li><b>Unlock-key additions</b> — {@link UnlockState#unlockedKeys} is snapshotted and
 *       diffed after every day/altar change; each NEW key gets a {@code unlock}-style
 *       announcement ({@code announce.eclipse.unlock.key.<key>} lang line).</li>
 *   <li><b>Altar milestone level-ups</b> — the altar level is polled every
 *       {@value #ALTAR_POLL_TICKS} ticks (catches both {@code AltarBlockEntity} completions
 *       and {@code /eclipse altar set}), announcing each level gained.</li>
 *   <li><b>Stage growth completion</b> — a {@link WorldStageService} stage listener announces
 *       finished GROW sweeps (style {@code goal}); erase sweeps stay silent.</li>
 * </ul>
 *
 * <p>Goal completion: v1 does not track per-goal completion server-side (goals are plain
 * strings in {@code days.json}), so nothing fires automatically yet — W13 should call
 * {@link #announceGoalCompleted} when its goal tracker ticks a line.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class AnnouncementService {
    /** Altar level poll period; matches {@code WorldStageService}'s altar watcher cadence. */
    private static final int ALTAR_POLL_TICKS = 20;

    private static final AtomicBoolean STAGE_LISTENER_REGISTERED = new AtomicBoolean();
    /** Baselines for change detection; valid only while {@link #initialized} is true. */
    private static boolean initialized;
    private static int lastAltarLevel;
    private static Set<String> lastUnlockedKeys = Set.of();

    private AnnouncementService() {}

    /** Broadcasts one announcement to every online player and logs it (smoke-test hook). */
    public static void announce(MinecraftServer server, String titleKey, String subtitleKey, String style) {
        PacketDistributor.sendToAllPlayers(new S2CAnnouncePayload(titleKey, subtitleKey, style));
        EclipseMod.LOGGER.info("Announce payload sent to {} players: title={} subtitle={} style={}",
                server.getPlayerList().getPlayerCount(), titleKey, subtitleKey, style);
    }

    /**
     * Day-advance hook, called by {@code DayScheduler.setDay} AFTER the new day is persisted
     * (only when the day actually changed). Announces the day, then any unlock keys the day
     * added, then rebroadcasts the anonymized timeline.
     */
    public static void onDayChanged(MinecraftServer server, int previousDay, int newDay) {
        announce(server, TimelineService.dayTitleKey(newDay),
                daySubtitleKey(newDay), S2CAnnouncePayload.STYLE_DAY);
        announceNewUnlocks(server);
        TimelineService.syncAll(server);
    }

    /**
     * W13 hook — call when a personal/server goal line is completed. v1 has no goal
     * tracking, so this is never invoked automatically yet.
     */
    public static void announceGoalCompleted(MinecraftServer server, String subtitleKey) {
        announce(server, "announce.eclipse.goal.title", subtitleKey, S2CAnnouncePayload.STYLE_GOAL);
    }

    /** Baseline the altar level + unlock keys at boot so nothing announces on startup. */
    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        MinecraftServer server = event.getServer();
        lastAltarLevel = EclipseWorldState.get(server).getAltarLevel();
        lastUnlockedKeys = new LinkedHashSet<>(UnlockState.unlockedKeys(server));
        initialized = true;
        if (STAGE_LISTENER_REGISTERED.compareAndSet(false, true)) {
            WorldStageService.addListener(AnnouncementService::onStageTerrainComplete);
            EclipseMod.LOGGER.info("AnnouncementService registered as world-stage listener");
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        initialized = false;
    }

    /**
     * Altar level poll: {@code AltarBlockEntity} and {@code /eclipse altar set} both write
     * {@link EclipseWorldState#setAltarLevel} without any event, so change detection lives
     * here. Level gains announce each milestone + its new unlock keys; lowering re-baselines
     * silently (keys were removed, not added). Both directions refresh the timeline.
     */
    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (!initialized || server.getTickCount() % ALTAR_POLL_TICKS != 0) {
            return;
        }
        int altarLevel = EclipseWorldState.get(server).getAltarLevel();
        if (altarLevel == lastAltarLevel) {
            return;
        }
        if (altarLevel > lastAltarLevel) {
            for (int level = lastAltarLevel + 1; level <= altarLevel; level++) {
                announce(server, "announce.eclipse.milestone.title",
                        TimelineService.milestoneKey(level), S2CAnnouncePayload.STYLE_UNLOCK);
            }
            announceNewUnlocks(server);
        } else {
            lastUnlockedKeys = new LinkedHashSet<>(UnlockState.unlockedKeys(server));
        }
        lastAltarLevel = altarLevel;
        TimelineService.syncAll(server);
    }

    /** Announces every unlock key present now but missing from the last snapshot. */
    private static void announceNewUnlocks(MinecraftServer server) {
        Set<String> current = new LinkedHashSet<>(UnlockState.unlockedKeys(server));
        for (String key : current) {
            if (!lastUnlockedKeys.contains(key)) {
                announce(server, "announce.eclipse.unlock.title",
                        "announce.eclipse.unlock.key." + key, S2CAnnouncePayload.STYLE_UNLOCK);
            }
        }
        lastUnlockedKeys = current;
    }

    /** Stage listener: a finished GROW sweep gets a world-growth announcement. */
    private static void onStageTerrainComplete(net.minecraft.server.level.ServerLevel level,
            dev.projecteclipse.eclipse.worldgen.DiscProfile profile, int fromStage, int toStage) {
        if (toStage <= fromStage) {
            return;
        }
        // DiscProfile.name() is already "overworld" / "nether" — matches the lang keys.
        announce(level.getServer(), "announce.eclipse.stage.title",
                "announce.eclipse.stage." + profile.name(), S2CAnnouncePayload.STYLE_GOAL);
    }

    /** The lang key of a day's typewriter subtitle, matching {@link TimelineService#dayTitleKey}. */
    private static String daySubtitleKey(int day) {
        return day >= 1 && day <= 14
                ? "announce.eclipse.day." + day + ".sub"
                : "announce.eclipse.day.generic.sub";
    }
}
