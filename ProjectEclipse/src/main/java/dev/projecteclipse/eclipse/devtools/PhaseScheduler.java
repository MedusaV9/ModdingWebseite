package dev.projecteclipse.eclipse.devtools;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.network.S2CBossbarStylePayload;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerBossEvent;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.Mth;
import net.minecraft.world.BossEvent;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStoppingEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Real-time phase scheduler (W14, {@code docs/ideas/05_systems.md} §3): schedules the NEXT
 * event-day advance at an absolute wall-clock instant, persisted as
 * {@link EclipseWorldState#getNextPhaseEpochMillis} so it survives restarts.
 *
 * <ul>
 *   <li>{@code /eclipse schedule next <ISO8601|+NhNNm>} accepts a relative offset
 *       ({@code +2h30m}, {@code +45m}, {@code +90s}) or a server-local ISO date-time
 *       ({@code 2026-08-01T18:00}); {@code list} prints, {@code clear} cancels.</li>
 *   <li>While a schedule is set, ONE lazy global {@link ServerBossEvent} shows the countdown
 *       ("Next phase: 2h 14m", purple, progress = remaining/total, W8 {@code day} skin via
 *       {@link S2CBossbarStylePayload}); it is hidden/removed whenever idle. Late joiners are
 *       added and re-tagged, mirroring {@code ritual.ReviveRitual}.</li>
 *   <li>Every {@value #FIRE_CHECK_TICKS} ticks: when {@code now >= target} the schedule is
 *       cleared and {@link DayScheduler#setDay} fires with {@code day + 1} (bell +
 *       announcement + day triggers, exactly like a manual advance).</li>
 *   <li>A set schedule SUPERSEDES {@code general.json dayAutoAdvance} — the guard lives in
 *       {@link DayScheduler#onServerTick} (calls {@link #isScheduled}) and logs one warning
 *       per overlap.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class PhaseScheduler {
    /** Wall-clock fire check cadence (5 s — same as the auto-advance poll). */
    private static final int FIRE_CHECK_TICKS = 100;
    /** Bossbar text/progress refresh cadence (1 s). */
    private static final int BAR_UPDATE_TICKS = 20;
    /** Relative spec: {@code +2h30m}, {@code +45m}, {@code +1h}, {@code +90s} (at least one part). */
    private static final Pattern RELATIVE_SPEC =
            Pattern.compile("\\+(?:(\\d+)h)?(?:(\\d+)m)?(?:(\\d+)s)?");
    private static final DateTimeFormatter TARGET_FORMAT =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").withZone(ZoneId.systemDefault());

    /** The one lazy global countdown bar; {@code null} whenever no schedule is set. */
    @Nullable
    private static ServerBossEvent bossEvent;

    private PhaseScheduler() {}

    // --- public API (commands + DayScheduler guard + inspector) ---

    /**
     * Parses a schedule spec into absolute epoch millis: {@code +NhNNm[NNs]} relative to now,
     * or a server-local ISO-8601 date-time ({@code 2026-08-01T18:00[:ss]}).
     *
     * @throws IllegalArgumentException with a human-readable reason when unparseable
     */
    public static long parseSpec(String spec, long nowEpochMillis) {
        String trimmed = spec.trim();
        if (trimmed.startsWith("+")) {
            Matcher matcher = RELATIVE_SPEC.matcher(trimmed);
            if (!matcher.matches() || (matcher.group(1) == null && matcher.group(2) == null
                    && matcher.group(3) == null)) {
                throw new IllegalArgumentException("Bad relative spec '" + spec
                        + "' — use e.g. +2h30m, +45m or +90s");
            }
            long hours = matcher.group(1) == null ? 0 : Long.parseLong(matcher.group(1));
            long minutes = matcher.group(2) == null ? 0 : Long.parseLong(matcher.group(2));
            long seconds = matcher.group(3) == null ? 0 : Long.parseLong(matcher.group(3));
            return nowEpochMillis + ((hours * 60 + minutes) * 60 + seconds) * 1000L;
        }
        try {
            LocalDateTime local = LocalDateTime.parse(trimmed);
            return local.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli();
        } catch (DateTimeParseException e) {
            throw new IllegalArgumentException("Bad date-time '" + spec
                    + "' — use server-local ISO-8601 (e.g. 2026-08-01T18:00) or +NhNNm");
        }
    }

    /**
     * Sets (replacing any previous) the next-phase schedule and shows the countdown bar.
     * Returns a feedback line for the command source.
     *
     * @throws IllegalArgumentException when the spec is unparseable or not in the future
     */
    public static String scheduleNext(MinecraftServer server, String spec) {
        long now = System.currentTimeMillis();
        long target = parseSpec(spec, now);
        if (target <= now) {
            throw new IllegalArgumentException("Target " + TARGET_FORMAT.format(Instant.ofEpochMilli(target))
                    + " is not in the future");
        }
        EclipseWorldState state = EclipseWorldState.get(server);
        state.setPhaseSchedule(target, now);
        ensureBar(server);
        updateBar(server, state);
        int day = state.getDay();
        EclipseMod.LOGGER.info("PhaseScheduler: next phase (day {} -> {}) scheduled at {} ({} from now)",
                day, day + 1, TARGET_FORMAT.format(Instant.ofEpochMilli(target)), remainingText(target - now));
        return "Next phase (day " + day + " -> " + (day + 1) + ") scheduled at "
                + TARGET_FORMAT.format(Instant.ofEpochMilli(target)) + " — in " + remainingText(target - now);
    }

    /** Clears the schedule and hides the bar. Returns a feedback line ({@code null} = nothing was set). */
    @Nullable
    public static String clear(MinecraftServer server) {
        EclipseWorldState state = EclipseWorldState.get(server);
        if (state.getNextPhaseEpochMillis() == 0L) {
            return null;
        }
        long target = state.getNextPhaseEpochMillis();
        state.setPhaseSchedule(0L, 0L);
        removeBar();
        EclipseMod.LOGGER.info("PhaseScheduler: schedule cleared (was {})",
                TARGET_FORMAT.format(Instant.ofEpochMilli(target)));
        return "Phase schedule cleared (was " + TARGET_FORMAT.format(Instant.ofEpochMilli(target)) + ")";
    }

    /** Whether a next-phase schedule is currently set. {@code DayScheduler}'s auto-advance guard. */
    public static boolean isScheduled(MinecraftServer server) {
        return EclipseWorldState.get(server).getNextPhaseEpochMillis() != 0L;
    }

    /** One human-readable schedule line for {@code schedule list} and the W14 timeline inspector. */
    public static String describe(MinecraftServer server) {
        EclipseWorldState state = EclipseWorldState.get(server);
        long target = state.getNextPhaseEpochMillis();
        if (target == 0L) {
            return "none";
        }
        long remaining = target - System.currentTimeMillis();
        return TARGET_FORMAT.format(Instant.ofEpochMilli(target))
                + (remaining > 0 ? " (in " + remainingText(remaining) + ")" : " (due — firing shortly)");
    }

    // --- tick driver ---

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % BAR_UPDATE_TICKS != 0) {
            return;
        }
        EclipseWorldState state = EclipseWorldState.get(server);
        long target = state.getNextPhaseEpochMillis();
        if (target == 0L) {
            removeBar(); // lazy: no schedule, no bar
            return;
        }
        ensureBar(server); // covers restart-resume: the persisted schedule recreates the bar
        updateBar(server, state);
        if (server.getTickCount() % FIRE_CHECK_TICKS != 0) {
            return;
        }
        if (System.currentTimeMillis() < target) {
            return;
        }
        int newDay = state.getDay() + 1;
        state.setPhaseSchedule(0L, 0L);
        removeBar();
        EclipseMod.LOGGER.info("PhaseScheduler: scheduled phase reached — advancing day {} -> {}",
                state.getDay(), newDay);
        DayScheduler.setDay(server, newDay);
    }

    // --- bossbar lifecycle (ReviveRitual pattern) ---

    /** Creates the countdown bar if missing: all online players + the W8 {@code day} skin tag. */
    private static void ensureBar(MinecraftServer server) {
        if (bossEvent != null) {
            return;
        }
        bossEvent = new ServerBossEvent(Component.translatable("bossbar.eclipse.schedule", "…"),
                BossEvent.BossBarColor.PURPLE, BossEvent.BossBarOverlay.PROGRESS);
        for (ServerPlayer online : server.getPlayerList().getPlayers()) {
            bossEvent.addPlayer(online);
        }
        PacketDistributor.sendToAllPlayers(
                new S2CBossbarStylePayload(bossEvent.getId(), S2CBossbarStylePayload.THEME_DAY));
        EclipseMod.LOGGER.info("PhaseScheduler: countdown bossbar created (id {})", bossEvent.getId());
    }

    private static void removeBar() {
        if (bossEvent != null) {
            bossEvent.removeAllPlayers();
            bossEvent = null;
        }
    }

    /** Name "Next phase: 2h 14m"; progress = remaining/total of the CURRENT schedule window. */
    private static void updateBar(MinecraftServer server, EclipseWorldState state) {
        if (bossEvent == null) {
            return;
        }
        long now = System.currentTimeMillis();
        long target = state.getNextPhaseEpochMillis();
        long total = Math.max(1L, target - state.getPhaseScheduledAtEpochMillis());
        long remaining = Math.max(0L, target - now);
        bossEvent.setName(Component.translatable("bossbar.eclipse.schedule", remainingText(remaining)));
        bossEvent.setProgress(Mth.clamp((float) remaining / total, 0.0F, 1.0F));
    }

    /** {@code 2h 14m} / {@code 14m 3s} / {@code 42s} (coarsest two units). */
    private static String remainingText(long millis) {
        long totalSeconds = Math.max(0L, millis / 1000L);
        long hours = totalSeconds / 3600;
        long minutes = totalSeconds % 3600 / 60;
        long seconds = totalSeconds % 60;
        if (hours > 0) {
            return hours + "h " + minutes + "m";
        }
        if (minutes > 0) {
            return minutes + "m " + seconds + "s";
        }
        return seconds + "s";
    }

    // --- player/server hooks ---

    /** Late joiners see the running countdown (bar + W8 skin tag), like ReviveRitual. */
    @SubscribeEvent
    public static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (bossEvent != null && event.getEntity() instanceof ServerPlayer player) {
            bossEvent.addPlayer(player);
            PacketDistributor.sendToPlayer(player,
                    new S2CBossbarStylePayload(bossEvent.getId(), S2CBossbarStylePayload.THEME_DAY));
        }
    }

    /** Drop stale bossbar references for disconnecting players. */
    @SubscribeEvent
    public static void onPlayerLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        if (bossEvent != null && event.getEntity() instanceof ServerPlayer player) {
            bossEvent.removePlayer(player);
        }
    }

    /** The schedule itself is persisted; only the transient bar needs cleanup. */
    @SubscribeEvent
    public static void onServerStopping(ServerStoppingEvent event) {
        removeBar();
    }
}
