package dev.projecteclipse.eclipse.timeline;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.config.Localized;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.lang.LangService;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.network.S2CAnnouncePayload;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.progression.UnlockState;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeDayService;
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
    /** SKYDAY: the quiet-dawn whisper caption (lang key; en+de via langdrop skyday.json). */
    private static final String QUIET_DAY_CAPTION = "eclipse.caption.dawn.quietday";
    private static final int QUIET_DAY_CAPTION_TICKS = 80;

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
     *
     * <p>SKYDAY: days whose plan is marked quiet ({@code DayPlan.announce() == false} —
     * the mid-arc unlock-package days whose only news is keys that get their own unlock
     * sweeps anyway) skip the full-screen day card and send a short whisper caption
     * instead. The dawn toll (DawnCeremony) plays either way, the unlock sweeps and the
     * timeline rebroadcast below are never skipped, and out-of-plan days keep the loud
     * generic card (unchanged behavior).</p>
     */
    public static void onDayChanged(MinecraftServer server, int previousDay, int newDay) {
        EclipseConfig.DayPlan plan = EclipseConfig.day(newDay);
        boolean loud = plan.day() != newDay || plan.announce();
        if (loud) {
            for (ServerPlayer player : server.getPlayerList().getPlayers()) {
                PacketDistributor.sendToPlayer(player, new S2CAnnouncePayload(
                        TimelineService.dayTitleKey(newDay, player),
                        daySubtitleKey(newDay, player),
                        S2CAnnouncePayload.STYLE_DAY));
            }
            EclipseMod.LOGGER.info("Localized day {} announcement sent to {} players",
                    newDay, server.getPlayerList().getPlayerCount());
        } else {
            for (ServerPlayer player : server.getPlayerList().getPlayers()) {
                PacketDistributor.sendToPlayer(player, new S2CCaptionPayload(
                        QUIET_DAY_CAPTION, QUIET_DAY_CAPTION_TICKS,
                        S2CCaptionPayload.STYLE_SUBTITLE));
            }
            EclipseMod.LOGGER.info("Quiet day {} rollover — whisper caption sent to {} players",
                    newDay, server.getPlayerList().getPlayerCount());
        }
        // WAVE6 (F-106 C) — C4: a multi-day catch-up burst (server was down) accumulates
        // its quiet days' unlock keys in one diff at THIS final loud beat. ≥2 replayed
        // days would flood the sweep queue with a per-key parade — digest instead: ONE
        // sweep + the full key list once in chat. Single-day mornings stay untouched.
        RealtimeDayService.CatchUpWindow window = RealtimeDayService.consumeCatchUpWindow();
        if (window != null && window.days() >= 2) {
            announceCatchUpDigest(server, window);
        } else {
            announceNewUnlocks(server);
        }
        TimelineService.syncAll(server);
    }

    /**
     * WAVE6 (F-106 C) — C4 catch-up digest: one {@code unlock}-themed sweep ("days X–Y
     * passed … N seals opened") replacing the per-key parade, plus the full resolved key
     * list ONCE in chat ({@code ServerLang}-baked per player; keys without a lang line
     * humanize like the client renderer). Also advances the unlock baseline exactly like
     * {@link #announceNewUnlocks}. Probe: {@code [w6c-digest] days=<x>..<y> unlocks=<n>}.
     */
    private static void announceCatchUpDigest(MinecraftServer server,
            RealtimeDayService.CatchUpWindow window) {
        Set<String> current = new LinkedHashSet<>(UnlockState.unlockedKeys(server));
        List<String> newKeys = new ArrayList<>();
        for (String key : current) {
            if (!lastUnlockedKeys.contains(key)) {
                newKeys.add(key);
            }
        }
        lastUnlockedKeys = current;
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            PacketDistributor.sendToPlayer(player, new S2CAnnouncePayload(
                    "announce.eclipse.digest.title",
                    ServerLang.tr(player, "announce.eclipse.digest.sub",
                            window.fromDay(), window.toDay(), newKeys.size()).getString(),
                    S2CAnnouncePayload.STYLE_UNLOCK));
            if (!newKeys.isEmpty()) {
                List<String> names = new ArrayList<>(newKeys.size());
                for (String key : newKeys) {
                    names.add(resolvedUnlockName(player, key));
                }
                player.sendSystemMessage(ServerLang.tr(player, "announce.eclipse.digest.chat",
                        window.fromDay(), window.toDay(), String.join(", ", names)));
            }
        }
        EclipseMod.LOGGER.info("Catch-up digest sent to {} players: days {}..{}, {} new unlocks",
                server.getPlayerList().getPlayerCount(), window.fromDay(), window.toDay(),
                newKeys.size());
        EclipseMod.LOGGER.debug("[w6c-digest] days={}..{} unlocks={}",
                window.fromDay(), window.toDay(), newKeys.size());
    }

    /**
     * The chat-facing name of one unlock key: its {@code announce.eclipse.unlock.key.<key>}
     * lang line when merged, else the humanized key (underscores → spaces — matching the
     * client overlay's literal-render fallback).
     */
    private static String resolvedUnlockName(ServerPlayer player, String key) {
        String langKey = "announce.eclipse.unlock.key." + key;
        String resolved = ServerLang.tr(player, langKey).getString();
        return resolved.equals(langKey) ? key.replace('_', ' ') : resolved;
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
     * silently (keys were removed, not added). Both directions refresh the timeline AND the
     * trimmed milestone ladder (A5: {@code S2CMilestonesPayload} only carries levels up to
     * {@code altarLevel + 1}, so every level change must re-send it).
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
        PacketDistributor.sendToAllPlayers(
                dev.projecteclipse.eclipse.network.S2CMilestonesPayload.current(server));
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
     * generic lang-key fallback. A5-extra: swaps to the plan's {@code subtitleDone} once
     * {@link DayTextConditions#isDone} holds — beaten content is not re-advertised.
     */
    private static String daySubtitleKey(int day, ServerPlayer player) {
        EclipseConfig.DayPlan plan = EclipseConfig.day(day);
        if (plan.day() != day) {
            return "announce.eclipse.day.generic.sub";
        }
        Localized subtitle = !plan.localizedSubtitleDone().isBlank()
                && DayTextConditions.isDone(player.server, day)
                ? plan.localizedSubtitleDone()
                : plan.localizedSubtitle();
        return !subtitle.isBlank()
                ? LangService.pick(subtitle, player)
                : "announce.eclipse.day.generic.sub";
    }
}
