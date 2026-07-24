package dev.projecteclipse.eclipse.analytics;

import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.ReloadHooks;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.GameType;
import net.minecraft.world.level.block.state.BlockState;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.common.util.BlockSnapshot;
import net.neoforged.neoforge.common.util.FakePlayer;
import net.neoforged.neoforge.event.entity.living.BabyEntitySpawnEvent;
import net.neoforged.neoforge.event.entity.living.LivingDamageEvent;
import net.neoforged.neoforge.event.entity.living.LivingDeathEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.entity.player.TradeWithVillagerEvent;
import net.neoforged.neoforge.event.level.BlockEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * THE single owner of the shared gameplay event subscribers (P4 §2.0 rule 6 / §2.4):
 * {@code BlockEvent.BreakEvent}, {@code BlockEvent.EntityPlaceEvent},
 * {@code LivingDeathEvent} (LOW — after {@code lives/LifecycleEvents}),
 * {@code LivingDamageEvent.Post}, {@code ItemCraftedEvent}, {@code ItemSmeltedEvent},
 * {@code TradeWithVillagerEvent} and {@code BabyEntitySpawnEvent}. Every handler counts
 * into {@link AnalyticsState} for the CURRENT event day and fans out via
 * {@link EclipseSignals} exactly once per underlying game event — downstream systems
 * (skills, goals, buffs, awards) must NOT add their own break/place/death subscribers.
 *
 * <p>Write paths are event-driven (one hash lookup + one long increment per event; no
 * O(blocks) or O(chunks) scans anywhere). The 1 Hz {@link AnalyticsSampler} covers
 * playtime/distance/depth/chunk/biome. The placed-block natural check runs FIRST on every
 * break so downstream consumers only ever see naturally-generated blocks
 * ({@link PlacedBlockTracker} — fail-safe under-crediting).</p>
 *
 * <p>Tracking policy: creative-mode players, spectators and {@link FakePlayer}s (Create
 * deployers etc.) never earn counters and never trigger signals, but their block
 * placements/breaks still update the placed-bit world truth so the natural check cannot
 * be laundered through an untracked actor.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class AnalyticsService {
    /** Sampler cadence in ticks (1 Hz — §2.4 "cheap tick sampling"). */
    private static final int SAMPLE_INTERVAL_TICKS = 20;

    // statics reset on ServerStopped
    private static final AtomicBoolean SIGNALS_REGISTERED = new AtomicBoolean(false);
    /** JVM-lifetime guard: ReloadHooks entries are never cleared, so register exactly once. */
    private static final AtomicBoolean RELOAD_HOOK_REGISTERED = new AtomicBoolean(false);
    private AnalyticsService() {}

    // --- lifecycle ---

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        if (RELOAD_HOOK_REGISTERED.compareAndSet(false, true)) {
            ReloadHooks.register("analytics", () -> {
                AnalyticsConfig.reload();
                DepositValues.reload();
            });
        }
        AnalyticsConfig.reload();
        DepositValues.reload();
        if (SIGNALS_REGISTERED.compareAndSet(false, true)) {
            EclipseSignals.onAltarDeposit(AnalyticsService::handleAltarDeposit);
            EclipseSignals.onQuestCompleted((player, spec, scope) -> handleQuestCompleted(player, spec.kind()));
            EclipseSignals.onDayRollover(AnalyticsService::handleDayRollover);
            EclipseSignals.onTrade(AnalyticsService::handleTrade);
            EclipseSignals.onBreed(AnalyticsService::handleBreed);
        }
        EclipseMod.LOGGER.info("Eclipse analytics active (day {}, {} retained days)",
                currentDay(event.getServer()), AnalyticsState.get(event.getServer()).knownDays().size());
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        SIGNALS_REGISTERED.set(false);
        AnalyticsSampler.reset();
        AnalyticsConfig.invalidate();
        DepositValues.invalidate();
        EclipseMod.LOGGER.debug("Analytics statics reset on server stop");
    }

    // --- block break / place (single owners; LOW so protection cancels run first) ---

    @SubscribeEvent(priority = EventPriority.LOW)
    public static void onBlockBreak(BlockEvent.BreakEvent event) {
        if (event.getLevel() instanceof ServerLevel level
                && event.getPlayer() instanceof ServerPlayer player) {
            handleBreak(player, level, event.getPos(), event.getState());
        }
    }

    @SubscribeEvent(priority = EventPriority.LOW)
    public static void onEntityPlace(BlockEvent.EntityPlaceEvent event) {
        if (!(event.getLevel() instanceof ServerLevel level)
                || !(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        if (event instanceof BlockEvent.EntityMultiPlaceEvent multi) {
            // Doors/beds fire ONE multi event with every affected position; mark them all.
            for (BlockSnapshot snapshot : multi.getReplacedBlockSnapshots()) {
                handlePlace(player, level, snapshot.getPos(), snapshot.getCurrentState());
            }
        } else {
            handlePlace(player, level, event.getPos(), event.getPlacedBlock());
        }
    }

    /**
     * Break core: natural check + clear FIRST (bit truth updates for every player kind),
     * then counters + {@code naturalBlockMined} fan-out for tracked players only.
     */
    public static void handleBreak(ServerPlayer player, ServerLevel level, BlockPos pos, BlockState state) {
        boolean wasPlaced = PlacedBlockTracker.clear(level, pos);
        if (wasPlaced || !isTracked(player)) {
            return;
        }
        MinecraftServer server = player.server;
        int day = currentDay(server);
        UUID id = player.getUUID();
        AnalyticsState analytics = AnalyticsState.get(server);
        analytics.add(day, id, AnalyticsKeys.MINE_TOTAL, 1L);
        String blockId = BuiltInRegistries.BLOCK.getKey(state.getBlock()).toString();
        analytics.addDynamic(day, id, AnalyticsKeys.PREFIX_MINE + blockId, 1L,
                AnalyticsConfig.get().maxDynamicKeysPerPlayerPerDay());
        EclipseSignals.fireNaturalBlockMined(player, state, pos);
    }

    /** Place core: mark bit for every player kind; counters + signal for tracked players. */
    public static void handlePlace(ServerPlayer player, ServerLevel level, BlockPos pos, BlockState state) {
        PlacedBlockTracker.markPlaced(level, pos);
        if (!isTracked(player)) {
            return;
        }
        MinecraftServer server = player.server;
        int day = currentDay(server);
        UUID id = player.getUUID();
        AnalyticsState analytics = AnalyticsState.get(server);
        analytics.add(day, id, AnalyticsKeys.PLACE_TOTAL, 1L);
        // Distinct-type counting via a per-day id-hash set (plan §2.4: hash collisions may
        // under-count a type, never over-count — memory stays a few ints per player).
        String blockId = BuiltInRegistries.BLOCK.getKey(state.getBlock()).toString();
        if (analytics.markPlaceType(day, id, blockId.hashCode())) {
            analytics.add(day, id, AnalyticsKeys.PLACE_TYPES, 1L);
        }
        EclipseSignals.fireBlockPlaced(player, state, pos);
    }

    // --- deaths / kills / damage ---

    @SubscribeEvent(priority = EventPriority.LOW)
    public static void onLivingDeath(LivingDeathEvent event) {
        LivingEntity victim = event.getEntity();
        if (victim.level().isClientSide()) {
            return;
        }
        if (victim instanceof ServerPlayer deadPlayer) {
            LivingEntity killer = event.getSource().getEntity() instanceof LivingEntity living
                    && living != deadPlayer ? living : null;
            handlePlayerDeath(deadPlayer, killer);
        } else if (event.getSource().getEntity() instanceof ServerPlayer killer) {
            handleMobKilled(killer, victim);
        }
    }

    /** Player death core: counts {@code death} for tracked victims; signal fires for ALL players. */
    public static void handlePlayerDeath(ServerPlayer victim, LivingEntity killerOrNull) {
        if (isTracked(victim)) {
            AnalyticsState.get(victim.server)
                    .add(currentDay(victim.server), victim.getUUID(), AnalyticsKeys.DEATH, 1L);
        }
        EclipseSignals.firePlayerDeath(victim, killerOrNull);
    }

    /** Mob kill core: counts + {@code mobKilled} fan-out for tracked killers only. */
    public static void handleMobKilled(ServerPlayer killer, LivingEntity victim) {
        if (!isTracked(killer)) {
            return;
        }
        MinecraftServer server = killer.server;
        int day = currentDay(server);
        UUID id = killer.getUUID();
        AnalyticsState analytics = AnalyticsState.get(server);
        analytics.add(day, id, AnalyticsKeys.KILL_TOTAL, 1L);
        String entityId = BuiltInRegistries.ENTITY_TYPE.getKey(victim.getType()).toString();
        analytics.addDynamic(day, id, AnalyticsKeys.PREFIX_KILL + entityId, 1L,
                AnalyticsConfig.get().maxDynamicKeysPerPlayerPerDay());
        EclipseSignals.fireMobKilled(killer, victim);
    }

    @SubscribeEvent
    public static void onLivingDamagePost(LivingDamageEvent.Post event) {
        if (event.getEntity().level().isClientSide()) {
            return;
        }
        handleDamage(event.getEntity(), event.getSource().getEntity(), event.getNewDamage());
    }

    /** Damage core: ×10 fixed-point {@code dmg_taken} (player victims) / {@code dmg_dealt} (player attackers). */
    public static void handleDamage(LivingEntity victim, Entity attackerOrNull, float amount) {
        long fixed = Math.round(amount * 10.0D);
        if (fixed <= 0L) {
            return;
        }
        if (victim instanceof ServerPlayer hurtPlayer && isTracked(hurtPlayer)) {
            AnalyticsState.get(hurtPlayer.server)
                    .add(currentDay(hurtPlayer.server), hurtPlayer.getUUID(), AnalyticsKeys.DMG_TAKEN, fixed);
        }
        if (attackerOrNull instanceof ServerPlayer attacker && attacker != victim && isTracked(attacker)) {
            AnalyticsState.get(attacker.server)
                    .add(currentDay(attacker.server), attacker.getUUID(), AnalyticsKeys.DMG_DEALT, fixed);
        }
    }

    // --- crafting / smelting / trading / breeding ---

    @SubscribeEvent(priority = EventPriority.LOW)
    public static void onItemCrafted(PlayerEvent.ItemCraftedEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            // LOW: ModGate / RecipeGate shrink gated results at NORMAL — an emptied stack
            // means the craft was confiscated and must not count or fan out.
            handleCraft(player, event.getCrafting());
        }
    }

    /** Craft core: totals always, per-id detail only for allowlisted ids, then signal fan-out. */
    public static void handleCraft(ServerPlayer player, ItemStack crafted) {
        if (crafted.isEmpty() || !isTracked(player)) {
            return;
        }
        MinecraftServer server = player.server;
        int day = currentDay(server);
        UUID id = player.getUUID();
        AnalyticsState analytics = AnalyticsState.get(server);
        analytics.add(day, id, AnalyticsKeys.CRAFT_TOTAL, crafted.getCount());
        String itemId = BuiltInRegistries.ITEM.getKey(crafted.getItem()).toString();
        if (AnalyticsConfig.get().craftAllowlist().contains(itemId)) {
            analytics.addDynamic(day, id, AnalyticsKeys.PREFIX_CRAFT + itemId, crafted.getCount(),
                    AnalyticsConfig.get().maxDynamicKeysPerPlayerPerDay());
        }
        EclipseSignals.fireItemCrafted(player, crafted);
    }

    @SubscribeEvent(priority = EventPriority.LOW)
    public static void onItemSmelted(PlayerEvent.ItemSmeltedEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            handleSmelt(player, event.getSmelting());
        }
    }

    /** Smelt core: {@code smelt_total} + {@code itemSmelted} fan-out. */
    public static void handleSmelt(ServerPlayer player, ItemStack smelted) {
        if (smelted.isEmpty() || !isTracked(player)) {
            return;
        }
        AnalyticsState.get(player.server).add(currentDay(player.server), player.getUUID(),
                AnalyticsKeys.SMELT_TOTAL, smelted.getCount());
        EclipseSignals.fireItemSmelted(player, smelted);
    }

    @SubscribeEvent
    public static void onTradeWithVillager(TradeWithVillagerEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            EclipseSignals.fireTrade(player);
        }
    }

    @SubscribeEvent(priority = EventPriority.LOW)
    public static void onBabySpawn(BabyEntitySpawnEvent event) {
        if (event.getCausedByPlayer() instanceof ServerPlayer player) {
            LivingEntity subject = event.getChild() != null ? event.getChild() : event.getParentA();
            EclipseSignals.fireBreed(player, subject);
        }
    }

    /** Shared trade-lane consumer; creative/spectator/fake-player filtering is analytics-only. */
    public static void handleTrade(ServerPlayer player) {
        if (isTracked(player)) {
            AnalyticsState.get(player.server).add(currentDay(player.server), player.getUUID(),
                    AnalyticsKeys.TRADE_TOTAL, 1L);
        }
    }

    /** Shared breed-lane consumer; the child is carried for quest target filtering. */
    public static void handleBreed(ServerPlayer player, LivingEntity childOrParent) {
        if (isTracked(player)) {
            AnalyticsState.get(player.server).add(currentDay(player.server), player.getUUID(),
                    AnalyticsKeys.BREED_TOTAL, 1L);
        }
    }

    // --- signal-fed counters (altar, quests) ---

    /** {@code altarDeposit} listener: value points for milestone/offering, shard count for banking. */
    public static void handleAltarDeposit(ServerPlayer player, ResourceLocation itemId, int count,
            EclipseSignals.AltarDepositPurpose purpose) {
        if (!isTracked(player) || count <= 0) {
            return;
        }
        MinecraftServer server = player.server;
        int day = currentDay(server);
        AnalyticsState analytics = AnalyticsState.get(server);
        if (purpose == EclipseSignals.AltarDepositPurpose.SHARD_BANK) {
            analytics.add(day, player.getUUID(), AnalyticsKeys.SHARDS_BANKED, count);
        } else {
            long value = DepositValues.valuePerItem(itemId) * count;
            if (value > 0L) {
                analytics.add(day, player.getUUID(), AnalyticsKeys.ALTAR_VALUE, value);
            }
        }
    }

    /** {@code questCompleted} listener: kind 0 = main, 1 = side, 2 = personal (wire encoding). */
    public static void handleQuestCompleted(ServerPlayer player, byte kind) {
        if (!isTracked(player)) {
            return;
        }
        MinecraftServer server = player.server;
        int day = currentDay(server);
        UUID id = player.getUUID();
        AnalyticsState analytics = AnalyticsState.get(server);
        analytics.add(day, id, AnalyticsKeys.QUESTS_DONE, 1L);
        switch (kind) {
            case 0 -> analytics.add(day, id, AnalyticsKeys.MAINS_DONE, 1L);
            case 1 -> analytics.add(day, id, AnalyticsKeys.SIDES_DONE, 1L);
            case 2 -> analytics.add(day, id, AnalyticsKeys.PERSONALS_DONE, 1L);
            default -> { }
        }
    }

    // --- day cut (rollover PRE) ---

    /**
     * {@code dayRollover} listener. PRE (fired while the ended day is still current): the
     * ended day's counters freeze by construction (writes key off the CURRENT world-state
     * day, which flips inside {@code DayScheduler.setDay} right after PRE) — here we drop
     * the frozen day's distinct-identity sets and apply the retention window. Current-day
     * type/chunk identities are persisted and day-keyed in {@link AnalyticsState}. Catch-up
     * fires PRE once per skipped day; both operations are idempotent.
     */
    public static void handleDayRollover(MinecraftServer server, int endedDay, int newDay,
            EclipseSignals.DayRolloverPhase phase) {
        if (phase != EclipseSignals.DayRolloverPhase.PRE) {
            return;
        }
        AnalyticsState.get(server).clearDistinctDay(endedDay);
        int retention = AnalyticsConfig.get().retentionDays();
        int pruned = AnalyticsState.get(server).pruneDaysBefore(newDay - retention + 1);
        if (pruned > 0) {
            EclipseMod.LOGGER.info("Analytics pruned {} day(s) beyond the {}-day retention window",
                    pruned, retention);
        }
    }

    // --- sampler cadence ---

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        if (event.getServer().getTickCount() % SAMPLE_INTERVAL_TICKS == 0) {
            AnalyticsSampler.samplePass(event.getServer());
        }
    }

    // --- shared policy helpers ---

    /**
     * Whether a player's actions earn analytics counters and signal fan-outs: survival or
     * adventure mode real players only. Creative players, spectators and fake players
     * (automation) are excluded from CREDIT but still update placed-bit world truth.
     * Checks the authoritative server-side game mode (not the abilities flag, which mods
     * and mock players toggle independently).
     */
    public static boolean isTracked(ServerPlayer player) {
        if (player instanceof FakePlayer) {
            return false;
        }
        GameType mode = player.gameMode.getGameModeForPlayer();
        return mode == GameType.SURVIVAL || mode == GameType.ADVENTURE;
    }

    /** The current event day — every counter write keys off this. */
    public static int currentDay(MinecraftServer server) {
        return DayScheduler.getDay(server);
    }
}
