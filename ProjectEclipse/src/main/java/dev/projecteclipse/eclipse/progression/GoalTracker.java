package dev.projecteclipse.eclipse.progression;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import dev.projecteclipse.eclipse.economy.ShardEconomy;
import dev.projecteclipse.eclipse.network.S2CGoalProgressPayload;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import dev.projecteclipse.eclipse.ritual.FinaleRitual;
import dev.projecteclipse.eclipse.timeline.AnnouncementService;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.item.ItemStack;
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
 * key — same reserved-key pattern as {@code DayScheduler}). The one-shot team hooks
 * additionally persist {@code team_beat:} flags so {@link #onPlayerLoggedIn} can back-fill
 * late joiners.</p>
 *
 * <p>Auto-detected goals of the DEFAULT v2 arc (world feats — boss beats, altar levels,
 * banked milestone counters — credit every online player at once):</p>
 * <ul>
 *   <li>day 1 "Everyone touches the altar" — proximity poll (4 blocks from the sanctum
 *       altar); its FIRST completion also seeds every online player with
 *       {@value #DAY1_SEED_SHARDS} umbral shards + the banking hint (the shop tutorial beat);</li>
 *   <li>day 2 "Enter the Nether" — dimension-change event; "Raise the altar to level 1" —
 *       altar-level poll;</li>
 *   <li>day 7 "Summon the Herald at dusk" — the {@link #onHeraldSummoned} lure hook;
 *       "Defeat the Herald" — the herald-defeated flag; "Deposit the Herald Core at the
 *       altar" — the {@value #MILESTONE4_HERALD_CORE_KEY} milestone counter;</li>
 *   <li>day 8 "Bank 16 ender pearls" — the {@value #MILESTONE4_ENDER_PEARL_KEY} milestone
 *       counter; "Raise the altar to level 4" — altar-level poll;</li>
 *   <li>day 9 "Pool 24 umbral shards" — the team shard pool crossing the beacon threshold;</li>
 *   <li>day 11 "Everyone reaches 4+ hearts" — polled once every online player has 4+;</li>
 *   <li>day 13 "Defeat the Ender Dragon" — the End dragon fight's kill memory (also catches
 *       an early day-12 kill);</li>
 *   <li>day 14 "Offer the egg at dusk" — the {@link #onFinaleBegun} ritual hook; "Defeat the
 *       Ferryman before the ship sinks" — the ferryman-defeated flag.</li>
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
    /**
     * Reserved milestone-progress key ({@code team_beat:<day>:<index>}) marking a one-shot
     * team beat (Herald summon, finale begun) as fired — unlike {@code goal_announced:} it
     * is stamped only by the EVENT hooks, never by an admin goal tick, so the login
     * backfill can replay the credit for late joiners.
     */
    private static final String TEAM_BEAT_KEY_PREFIX = "team_beat:";
    /** Reserved milestone-progress key ({@code shard_seed:<uuid>}) marking a player's day-1 seed as granted. */
    private static final String SEED_GRANTED_KEY_PREFIX = "shard_seed:";
    /** The attachment encodes the mask in the low 8 bits (3 goals/day in practice). */
    private static final int MAX_GOALS = 8;
    /** Umbral shards seeded to everyone when the day-1 altar-touch goal first completes. */
    private static final int DAY1_SEED_SHARDS = 2;
    /** {@code AltarBlockEntity} milestone counter of the deposited Herald Core (L4 multi-cost key). */
    private static final String MILESTONE4_HERALD_CORE_KEY = "altar_level_4:eclipse:herald_core";
    /** {@code AltarBlockEntity} milestone counter of the banked ender pearls (L4 multi-cost key). */
    private static final String MILESTONE4_ENDER_PEARL_KEY = "altar_level_4:minecraft:ender_pearl";

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
        onFirstCompletion(server, day, index);
        EclipseMod.LOGGER.info("Goal ticked for {}: day {} goal {} ('{}')",
                player.getScoreboardName(), day, index, EclipseConfig.day(day).goals().get(index));
        return true;
    }

    /**
     * Once per (day, goal) pair: the global GOAL COMPLETE announce (the goal text is the
     * subtitle) plus any first-completion side effect — currently the day-1 shard seed.
     */
    private static void onFirstCompletion(MinecraftServer server, int day, int index) {
        EclipseWorldState state = EclipseWorldState.get(server);
        String announcedKey = ANNOUNCED_KEY_PREFIX + day + ":" + index;
        if (state.getMilestoneProgress(announcedKey) != 0L) {
            return;
        }
        state.setMilestoneProgress(announcedKey, 1L);
        // The raw goal line doubles as the subtitle "key": the overlay renders unknown
        // keys literally, so players see the actual goal text under GOAL COMPLETE.
        AnnouncementService.announceGoalCompleted(server, EclipseConfig.day(day).goals().get(index));
        if (day == 1 && index == 2) {
            grantDay1ShardSeed(server);
        }
    }

    /**
     * Day-1 shard seed (first completion of "Everyone touches the altar"): every online
     * player receives {@value #DAY1_SEED_SHARDS} umbral shards and the banking hint, so
     * the altar-shop loop is discoverable before the first night mobs ever drop shards.
     * Late day-1 joiners are back-filled by {@link #onPlayerLoggedIn}.
     */
    private static void grantDay1ShardSeed(MinecraftServer server) {
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            grantShardSeed(player);
        }
        EclipseMod.LOGGER.info("Day-1 shard seed: {} umbral shard(s) granted to {} online player(s)",
                DAY1_SEED_SHARDS, server.getPlayerList().getPlayerCount());
    }

    /** One player's shard seed + banking hint; stamps the persistent per-player marker. */
    private static void grantShardSeed(ServerPlayer player) {
        EclipseWorldState.get(player.server)
                .setMilestoneProgress(SEED_GRANTED_KEY_PREFIX + player.getStringUUID(), 1L);
        ItemStack shards = new ItemStack(EclipseItems.UMBRAL_SHARD.get(), DAY1_SEED_SHARDS);
        if (!player.getInventory().add(shards)) {
            player.drop(shards, false);
        }
        player.displayClientMessage(Component.translatable("shop.eclipse.shard_seed"), true);
        player.playNotifySound(SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.BLOCKS, 1.0F, 1.2F);
    }

    // --- auto-detectors ---

    /** Credits goal {@code index} of the CURRENT day to every online player (team feats). */
    private static void completeForAllOnline(MinecraftServer server, int index) {
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            complete(player, index);
        }
    }

    /**
     * {@code ritual.HeraldsLureItem} hook — a lure deposit successfully summoned the
     * Herald. Day-7 goal 0 ("Summon the Herald at dusk") is a team beat: one player
     * deposits, everyone online gets the tick (same crediting as the kill), and the
     * persisted {@code team_beat:} flag back-fills late joiners at login.
     */
    public static void onHeraldSummoned(MinecraftServer server) {
        EclipseWorldState state = EclipseWorldState.get(server);
        if (state.getDay() == 7) {
            state.setMilestoneProgress(TEAM_BEAT_KEY_PREFIX + state.getDay() + ":0", 1L);
            completeForAllOnline(server, 0);
        }
    }

    /**
     * {@code ritual.FinaleRitual#begin} hook — the finale catalyst was offered and the
     * crossing started. Day-14 goal 0 ("Offer the egg at dusk") is credited to everyone
     * online (the whole team ships out together) and back-filled at login via the
     * persisted {@code team_beat:} flag. Days past the configured plan floor to the last
     * plan, so {@code >= FINALE_DAY} still matches the goal.
     */
    public static void onFinaleBegun(MinecraftServer server) {
        EclipseWorldState state = EclipseWorldState.get(server);
        if (state.getDay() >= FinaleRitual.FINALE_DAY) {
            state.setMilestoneProgress(TEAM_BEAT_KEY_PREFIX + state.getDay() + ":0", 1L);
            completeForAllOnline(server, 0);
        }
    }

    /**
     * Login backfill of the one-shot team beats: the hooks credit only whoever is online
     * when they fire, so a late joiner replays the current day's {@code team_beat:} flag
     * here ({@link #complete}'s bitmask keeps the credit once per player). Day-1 joiners
     * also receive the shard seed if it was already distributed and their persistent
     * {@code shard_seed:} marker is still unset. The polled world feats (boss flags, altar
     * levels, counters) need no backfill — the every-second poll re-credits them anyway.
     */
    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        EclipseWorldState state = EclipseWorldState.get(player.server);
        int day = state.getDay();
        if (state.getMilestoneProgress(TEAM_BEAT_KEY_PREFIX + day + ":0") != 0L) {
            complete(player, 0);
        }
        if (day == 1 && state.getMilestoneProgress(ANNOUNCED_KEY_PREFIX + "1:2") != 0L
                && state.getMilestoneProgress(SEED_GRANTED_KEY_PREFIX + player.getStringUUID()) == 0L) {
            grantShardSeed(player);
        }
    }

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
            case 2 -> {
                // "Raise the altar to level 1" (goal 2): the first milestone is a team feat.
                if (state.getAltarLevel() >= 1) {
                    completeForAllOnline(server, 2);
                }
            }
            case 7 -> {
                // "Defeat the Herald" (goal 1): the kill is a team feat — credit everyone online.
                if (state.isHeraldDefeated()) {
                    completeForAllOnline(server, 1);
                }
                // "Deposit the Herald Core at the altar" (goal 2): the L4 milestone counter
                // (AltarBlockEntity progress key) already counts the deposited core.
                if (state.getMilestoneProgress(MILESTONE4_HERALD_CORE_KEY) >= 1L) {
                    completeForAllOnline(server, 2);
                }
            }
            case 8 -> {
                // "Bank 16 ender pearls" (goal 1): the altar's pearl counter toward milestone 4.
                if (state.getMilestoneProgress(MILESTONE4_ENDER_PEARL_KEY) >= 16L) {
                    completeForAllOnline(server, 1);
                }
                // "Raise the altar to level 4" (goal 2).
                if (state.getAltarLevel() >= 4) {
                    completeForAllOnline(server, 2);
                }
            }
            case 9 -> {
                // "Pool 24 umbral shards" (goal 2): the team pool crossing the beacon threshold.
                if (state.getShardPool() >= ShardEconomy.SUPPLY_BEACON_COST) {
                    completeForAllOnline(server, 2);
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
                    completeForAllOnline(server, 0);
                }
            }
            case 13 -> {
                // "Defeat the Ender Dragon" (goal 0): the End's dragon fight remembers the
                // kill, so an eager day-12 kill still ticks the goal once day 13 arrives.
                ServerLevel end = server.getLevel(Level.END);
                if (end != null && end.getDragonFight() != null
                        && end.getDragonFight().hasPreviouslyKilledDragon()) {
                    completeForAllOnline(server, 0);
                }
            }
            case 14 -> {
                // "Defeat the Ferryman before the ship sinks" (goal 2): the finale-won flag.
                if (state.isFerrymanDefeated()) {
                    completeForAllOnline(server, 2);
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
