package dev.projecteclipse.eclipse.progression;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import dev.projecteclipse.eclipse.economy.ShardEconomy;
import dev.projecteclipse.eclipse.network.S2CGoalProgressPayload;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import dev.projecteclipse.eclipse.timeline.AnnouncementService;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.Level;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Per-player daily goal completion (W13, replacing W8's all-false stand-in).
 *
 * <p>Progress lives in the {@code eclipse:goal_progress} attachment as
 * {@code (day << 8) | bitmask}; a stored day different from the current event day reads
 * as an empty mask, so day changes reset progress with zero bookkeeping. {@link #complete}
 * is the single write path: it stamps the bit, re-sends the player's
 * {@link S2CGoalProgressPayload} (sidebar tick boxes) and fires the global
 * {@code GOAL COMPLETE} announcement the FIRST time each (day, goal) pair is completed by
 * anyone (deduped via a reserved {@code goal_announced:<day>:<index>} milestone-progress
 * key — same reserved-key pattern as {@code DayScheduler}).</p>
 *
 * <p>Trivially detectable goals of the DEFAULT v2 arc tick automatically:</p>
 * <ul>
 *   <li>day 1 "Everyone touches the altar" — proximity poll (4 blocks from the sanctum altar);</li>
 *   <li>day 2 "Enter the Nether" — dimension-change event;</li>
 *   <li>day 7 "Defeat the Herald" — the herald-defeated flag, credited to all online players;</li>
 *   <li>day 9 "Pool 24 umbral shards" — the team shard pool crossing the beacon threshold;</li>
 *   <li>day 11 "Everyone reaches 4+ hearts" — polled once every online player has 4+.</li>
 * </ul>
 * Everything else is admin-marked via {@code /eclipse goals tick <player> <index>}. The
 * detectors match goals by (day, index), so a rewritten {@code days.json} simply turns
 * them into extra manual goals — never a crash.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class GoalTracker {
    private static final int POLL_TICKS = 20;
    private static final double ALTAR_TOUCH_RANGE_SQ = 4.0D * 4.0D;
    private static final String ANNOUNCED_KEY_PREFIX = "goal_announced:";
    /** The attachment encodes the mask in the low 8 bits (3 goals/day in practice). */
    private static final int MAX_GOALS = 8;

    /** Last day whose goal payloads were broadcast; detects day changes (any source). {@code MIN_VALUE} = not booted. */
    private static int lastBroadcastDay = Integer.MIN_VALUE;

    private GoalTracker() {}

    /** The player's completion bitmask for {@code day}; stale (other-day) progress reads as 0. */
    public static int mask(ServerPlayer player, int day) {
        int value = player.getData(EclipseAttachments.GOAL_PROGRESS);
        return (value >>> 8) == day ? value & 0xFF : 0;
    }

    /**
     * Ticks goal {@code index} (0-based) of the CURRENT day for the player. Returns false
     * when already ticked or out of range. Syncs the player's sidebar and announces the
     * first completion of that goal server-wide.
     */
    public static boolean complete(ServerPlayer player, int index) {
        MinecraftServer server = player.server;
        int day = EclipseWorldState.get(server).getDay();
        int goalCount = Math.min(EclipseConfig.day(day).goals().size(), MAX_GOALS);
        if (index < 0 || index >= goalCount) {
            return false;
        }
        int mask = mask(player, day);
        int bit = 1 << index;
        if ((mask & bit) != 0) {
            return false;
        }
        player.setData(EclipseAttachments.GOAL_PROGRESS, (day << 8) | mask | bit);
        PacketDistributor.sendToPlayer(player, S2CGoalProgressPayload.currentFor(player));
        announceFirstCompletion(server, day, index);
        EclipseMod.LOGGER.info("Goal ticked for {}: day {} goal {} ('{}')",
                player.getScoreboardName(), day, index, EclipseConfig.day(day).goals().get(index));
        return true;
    }

    /** Global GOAL COMPLETE announce, once per (day, goal) pair; the goal text is the subtitle. */
    private static void announceFirstCompletion(MinecraftServer server, int day, int index) {
        EclipseWorldState state = EclipseWorldState.get(server);
        String announcedKey = ANNOUNCED_KEY_PREFIX + day + ":" + index;
        if (state.getMilestoneProgress(announcedKey) != 0L) {
            return;
        }
        state.setMilestoneProgress(announcedKey, 1L);
        // The raw goal line doubles as the subtitle "key": the overlay renders unknown
        // keys literally, so players see the actual goal text under GOAL COMPLETE.
        AnnouncementService.announceGoalCompleted(server, EclipseConfig.day(day).goals().get(index));
    }

    // --- auto-detectors ---

    /** Day 2 "Enter the Nether" (goal 0): dimension-change into the nether. */
    @SubscribeEvent
    static void onChangedDimension(PlayerEvent.PlayerChangedDimensionEvent event) {
        if (event.getEntity() instanceof ServerPlayer player && event.getTo() == Level.NETHER
                && EclipseWorldState.get(player.server).getDay() == 2) {
            complete(player, 0);
        }
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (lastBroadcastDay == Integer.MIN_VALUE || server.getTickCount() % POLL_TICKS != 0) {
            return;
        }
        EclipseWorldState state = EclipseWorldState.get(server);
        int day = state.getDay();
        if (day != lastBroadcastDay) {
            // Day changed (scheduler, admin command, or auto-advance): fresh per-player
            // payloads — the encoded day mismatch already zeroed everyone's mask.
            lastBroadcastDay = day;
            for (ServerPlayer player : server.getPlayerList().getPlayers()) {
                PacketDistributor.sendToPlayer(player, S2CGoalProgressPayload.currentFor(player));
            }
        }
        switch (day) {
            case 1 -> {
                // "Everyone touches the altar" (goal 2): 4-block proximity to the sanctum altar.
                BlockPos altarPos = state.getSanctumAltarPos();
                if (altarPos != null) {
                    for (ServerPlayer player : server.overworld().players()) {
                        if (player.distanceToSqr(altarPos.getCenter()) <= ALTAR_TOUCH_RANGE_SQ) {
                            complete(player, 2);
                        }
                    }
                }
            }
            case 7 -> {
                // "Defeat the Herald" (goal 1): the kill is a team feat — credit everyone online.
                if (state.isHeraldDefeated()) {
                    for (ServerPlayer player : server.getPlayerList().getPlayers()) {
                        complete(player, 1);
                    }
                }
            }
            case 9 -> {
                // "Pool 24 umbral shards" (goal 2): the team pool crossing the beacon threshold.
                if (state.getShardPool() >= ShardEconomy.SUPPLY_BEACON_COST) {
                    for (ServerPlayer player : server.getPlayerList().getPlayers()) {
                        complete(player, 2);
                    }
                }
            }
            case 11 -> {
                // "Everyone reaches 4+ hearts" (goal 0): ticks only while ALL online qualify.
                boolean everyone = !server.getPlayerList().getPlayers().isEmpty();
                for (ServerPlayer player : server.getPlayerList().getPlayers()) {
                    if (LivesApi.get(player) < 4) {
                        everyone = false;
                        break;
                    }
                }
                if (everyone) {
                    for (ServerPlayer player : server.getPlayerList().getPlayers()) {
                        complete(player, 0);
                    }
                }
            }
            default -> { }
        }
    }

    /** Baseline the day at boot so startup never rebroadcasts (the login sync covers joins). */
    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        lastBroadcastDay = EclipseWorldState.get(event.getServer()).getDay();
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        lastBroadcastDay = Integer.MIN_VALUE;
    }
}
