package dev.projecteclipse.eclipse.timeline;

import java.util.LinkedHashSet;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.config.Localized;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.lang.LangService;
import dev.projecteclipse.eclipse.network.S2CAnnouncePayload;
import dev.projecteclipse.eclipse.progression.UnlockState;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
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
 * <p>Goal completion: {@code progression.GoalTracker} calls {@link #announceGoalCompleted}
 * the FIRST time each (day, goal) pair is ticked by anyone, passing the raw goal line as
 * the subtitle (the overlay renders unknown keys literally).</p>
 *
 * <p>Day titles/subtitles are the SERVER-SIDE literals from the {@code days.json} plan
 * (see {@link TimelineService#dayTitleKey}) — only the generic fallbacks remain lang keys,
 * so the anonymized arc cannot be datamined from the client jar.</p>
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
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            PacketDistributor.sendToPlayer(player, new S2CAnnouncePayload(
                    TimelineService.dayTitleKey(newDay, player),
                    daySubtitleKey(newDay, player),
                    S2CAnnouncePayload.STYLE_DAY));
        }
        EclipseMod.LOGGER.info("Localized day {} announcement sent to {} players",
                newDay, server.getPlayerList().getPlayerCount());
        announceNewUnlocks(server);
        TimelineService.syncAll(server);
    }

    /**
     * Goal-completion announce, called by {@code progression.GoalTracker} once per
     * (day, goal) pair. {@code subtitleKey} is usually the raw goal line rather than a
     * lang key — the client overlay renders unknown keys literally.
     */
    public static void announceGoalCompleted(MinecraftServer server, String subtitleKey) {
        announce(server, "announce.eclipse.goal.title", subtitleKey, S2CAnnouncePayload.STYLE_GOAL);
    }

    /** Receiver-localized goal completion announcement for server-baked quest text. */
    public static void announceGoalCompleted(MinecraftServer server, Localized subtitle) {
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            PacketDistributor.sendToPlayer(player, new S2CAnnouncePayload(
                    "announce.eclipse.goal.title",
                    LangService.pick(subtitle, player),
                    S2CAnnouncePayload.STYLE_GOAL));
        }
        EclipseMod.LOGGER.info("Localized goal announcement sent to {} players",
                server.getPlayerList().getPlayerCount());
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
        // Drop the baselines too: they pin the old world's key set until the next boot
        // re-baselines, and stale values must never bleed into a new world.
        lastAltarLevel = 0;
        lastUnlockedKeys = Set.of();
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

    /**
     * The typewriter subtitle of a day, matching {@link TimelineService#dayTitleKey}: the
     * {@code days.json} plan's literal {@code subtitle} when configured (the plan's day is
     * re-checked because {@code EclipseConfig.day} clamps out-of-range days), else the
     * generic lang-key fallback.
     */
    private static String daySubtitleKey(int day, ServerPlayer player) {
        EclipseConfig.DayPlan plan = EclipseConfig.day(day);
        return plan.day() == day && !plan.localizedSubtitle().isBlank()
                ? LangService.pick(plan.localizedSubtitle(), player)
                : "announce.eclipse.day.generic.sub";
    }
}
