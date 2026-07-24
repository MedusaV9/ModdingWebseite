package dev.projecteclipse.eclipse.progression.goals;

import java.util.ArrayList;
import java.util.Collections;
import java.util.EnumMap;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.Localized;
import dev.projecteclipse.eclipse.core.config.ReloadHooks;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import dev.projecteclipse.eclipse.economy.ShardEconomy;
import dev.projecteclipse.eclipse.lang.LangService;
import dev.projecteclipse.eclipse.network.S2CGoalProgressPayload;
import dev.projecteclipse.eclipse.network.S2CQuestStatePayload;
import dev.projecteclipse.eclipse.network.rewards.RewardPayloads;
import dev.projecteclipse.eclipse.progression.goals.GoalSpec.Kind;
import dev.projecteclipse.eclipse.progression.goals.GoalSpec.Scope;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.timeline.AnnouncementService;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.core.registries.Registries;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.stats.Stat;
import net.minecraft.stats.StatType;
import net.minecraft.stats.Stats;
import net.minecraft.tags.TagKey;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.monster.Enemy;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.biome.Biome;
import net.minecraft.world.level.block.state.BlockState;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The goal &amp; personal-quest engine (plans_v3 P4 §2.2, worker P4-B2) — successor of the
 * hardcoded {@code GoalTracker} detectors. Mains + sides come from {@code goals.json},
 * personals are drawn per player per day from {@code quests.json}
 * (deterministic {@link QuestMath#draw}); progress is signal-driven via
 * {@code core/signal/EclipseSignals} (registered in {@link QuestDetectors}) plus ONE shared
 * 20-tick poll for location/depth/stat-delta triggers, world-state beats and payload
 * coalescing — never per-tick work proportional to blocks or chunks.
 *
 * <p>Completion pipeline (single choke point {@link #completeForPlayer} /
 * {@link #completeTeam}): mark {@link QuestState} → grant shard/item rewards to credited
 * online players → fire {@code questCompleted} (skills grants {@code reward.skillXp} from the
 * signal — B-wave workers must not call each other's classes) → resync
 * {@code S2CQuestStatePayload} + legacy {@code S2CGoalProgressPayload} → announce MAIN goals
 * globally via receiver-localized {@code AnnouncementService.announceGoalCompleted};
 * sides/personals stay action-bar-only for the completing player (anonymity: no global chat).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class QuestEngine {
    private static final int POLL_TICKS = 20;
    /** Movement stats summed for {@code travel_distance} (all in cm, matching analytics dist_cm). */
    private static final List<ResourceLocation> TRAVEL_STATS = List.of(
            Stats.WALK_ONE_CM, Stats.SPRINT_ONE_CM, Stats.CROUCH_ONE_CM, Stats.SWIM_ONE_CM,
            Stats.WALK_ON_WATER_ONE_CM, Stats.WALK_UNDER_WATER_ONE_CM, Stats.BOAT_ONE_CM,
            Stats.HORSE_ONE_CM, Stats.PIG_ONE_CM, Stats.MINECART_ONE_CM, Stats.AVIATE_ONE_CM,
            Stats.CLIMB_ONE_CM, Stats.FLY_ONE_CM, Stats.STRIDER_ONE_CM);

    /** Current day's resolved specs + per-detector indexes, rebuilt on day/config change. */
    static final class ResolvedDay {
        final int day;
        final int generation;
        final List<GoalSpec> mains;
        final List<GoalSpec> sides;
        final List<GoalSpec> shared;
        final Map<String, GoalSpec> byId = new LinkedHashMap<>();
        final Map<TriggerType, List<GoalSpec>> byType = new EnumMap<>(TriggerType.class);
        final Map<String, List<GoalSpec>> byBeat = new HashMap<>();
        /** collect_item goalId → resolved item list (tags expanded at build). */
        final Map<String, List<Item>> collectItems = new HashMap<>();
        /** stat_threshold goalId → resolved vanilla stat (null = unresolvable, logged once). */
        final Map<String, Stat<?>> stats = new HashMap<>();

        ResolvedDay(int day, int generation, List<GoalSpec> dayGoals) {
            this.day = day;
            this.generation = generation;
            List<GoalSpec> mainList = new ArrayList<>();
            List<GoalSpec> sideList = new ArrayList<>();
            for (GoalSpec spec : dayGoals) {
                if (spec.goalKind() == Kind.MAIN) {
                    mainList.add(spec);
                } else {
                    sideList.add(spec);
                }
                index(spec);
            }
            this.mains = List.copyOf(mainList);
            this.sides = List.copyOf(sideList);
            this.shared = List.copyOf(dayGoals);
        }

        /** Shared specs and the union of current personal assignments are indexed by id. */
        void index(GoalSpec spec) {
            if (byId.putIfAbsent(spec.id(), spec) != null) {
                return; // already indexed (another player's personal draw)
            }
            byType.computeIfAbsent(spec.trigger().type(), key -> new ArrayList<>()).add(spec);
            if (!spec.trigger().beatId().isEmpty()) {
                byBeat.computeIfAbsent(spec.trigger().beatId(), key -> new ArrayList<>()).add(spec);
            }
            if (spec.trigger().type() == TriggerType.COLLECT_ITEM) {
                collectItems.put(spec.id(), resolveItems(spec.trigger().target()));
            }
            if (spec.trigger().type() == TriggerType.STAT_THRESHOLD) {
                Stat<?> stat = resolveStat(spec.trigger().statId());
                if (stat == null) {
                    EclipseMod.LOGGER.warn("Quest '{}': unresolvable statId '{}' — goal is manual-only",
                            spec.id(), spec.trigger().statId());
                }
                stats.put(spec.id(), stat);
            }
        }

        /** Rebuilds the personal union so rerolled-away specs leave every detector index. */
        void rebuildIndexes(QuestState state) {
            byId.clear();
            byType.clear();
            byBeat.clear();
            collectItems.clear();
            stats.clear();
            shared.forEach(this::index);
            for (UUID uuid : state.knownPlayers(day)) {
                personalSpecs(this, state, uuid).forEach(this::index);
            }
        }

        List<GoalSpec> ofType(TriggerType type) {
            return byType.getOrDefault(type, List.of());
        }
    }

    // statics reset on ServerStopped
    private static ResolvedDay resolved = null;
    // statics reset on ServerStopped
    private static final Set<UUID> DIRTY = new HashSet<>();
    // statics reset on ServerStopped
    private static boolean dirtyAll = false;
    /** JVM-lifetime guard: ReloadHooks entries survive server restarts (list is never cleared). */
    private static boolean reloadHookRegistered = false;

    private QuestEngine() {}

    // --- lifecycle ---

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        if (!reloadHookRegistered) {
            reloadHookRegistered = true;
            ReloadHooks.register("goals", GoalConfig::reloadNow);
        }
        QuestDetectors.registerSignalListeners(event.getServer());
        resolved(event.getServer()); // warm cache + assign for any already-known day
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        resolved = null;
        DIRTY.clear();
        dirtyAll = false;
        QuestDetectors.resetOnServerStopped();
    }

    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            deliverPendingRewards(player);
            ensurePlayer(player.server, player);
            syncPlayer(player.server, player);
        }
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % POLL_TICKS != 0) {
            return;
        }
        runPollNow(server);
    }

    // --- resolution / assignment ---

    /** Current day's resolved specs; rebuilds (and re-assigns online players) on day/config change. */
    static ResolvedDay resolved(MinecraftServer server) {
        int day = EclipseWorldState.get(server).getDay();
        int generation = GoalConfig.generation();
        ResolvedDay current = resolved;
        if (current == null || current.day != day || current.generation != generation) {
            current = new ResolvedDay(day, generation, GoalConfig.goalsForDay(day));
            resolved = current;
            for (ServerPlayer player : server.getPlayerList().getPlayers()) {
                ensurePlayer(server, player);
            }
            markAllDirty();
            EclipseMod.LOGGER.info("Quest engine resolved day {} (gen {}): {} mains, {} sides, "
                    + "{} personal/player", day, generation, current.mains.size(), current.sides.size(),
                    GoalConfig.personalPerDay());
        }
        return current;
    }

    /**
     * Ensures the player's day slice exists: draws personals (deterministic; persisted so the
     * lifetime-exclusion snapshot never shifts), captures stat baselines for every polled
     * spec, and backfills already-fired team beats for {@code each_player}-scoped beat goals.
     */
    public static void ensurePlayer(MinecraftServer server, ServerPlayer player) {
        ResolvedDay day = resolved(server);
        QuestState state = QuestState.get(server);
        UUID uuid = player.getUUID();
        state.ensurePlayer(day.day, uuid);

        List<String> personals = state.personals(day.day, uuid);
        if (personals == null && GoalConfig.personalPerDay() > 0) {
            personals = drawPersonals(server, state, day.day, uuid, state.rerollNonce(day.day, uuid));
            state.setPersonals(day.day, uuid, personals);
            if (player.connection != null) {
                player.displayClientMessage(Component.translatable("quest.eclipse.assigned"), true);
            }
        }
        day.rebuildIndexes(state);

        for (GoalSpec spec : specsFor(day, state, uuid)) {
            captureBaselines(state, day, player, spec, false);
            if (spec.trigger().type() == TriggerType.SKILL_LEVEL) {
                QuestDetectors.backfillSkillLevel(player, spec);
            }
        }

        for (String beatId : state.beatsFired(day.day)) {
            for (GoalSpec spec : day.byBeat.getOrDefault(beatId, List.of())) {
                if (spec.scope() == Scope.EACH_PLAYER && isEligible(state, day, uuid, spec)
                        && !state.isPlayerDone(day.day, uuid, spec.id())) {
                    completeForPlayer(server, player, spec);
                }
            }
        }
        markDirty(uuid);
    }

    private static List<String> drawPersonals(MinecraftServer server, QuestState state, int day,
            UUID uuid, int nonce) {
        Set<String> completed = state.lifetimeCompletedPersonals(uuid);
        List<QuestMath.Candidate> candidates = new ArrayList<>();
        for (GoalSpec spec : GoalConfig.personalPool()) {
            if (spec.weight() > 0 && spec.inDayWindow(day) && !completed.contains(spec.id())) {
                candidates.add(new QuestMath.Candidate(spec.id(), spec.weight()));
            }
        }
        long seed = QuestMath.seed(server.overworld().getSeed(), uuid, day, nonce);
        return QuestMath.draw(seed, candidates, GoalConfig.personalPerDay());
    }

    /** The player's assigned personal specs (pool entries missing after a reload are skipped). */
    static List<GoalSpec> personalSpecs(ResolvedDay day, QuestState state, UUID uuid) {
        List<String> ids = state.personals(day.day, uuid);
        if (ids == null) {
            return List.of();
        }
        List<GoalSpec> specs = new ArrayList<>(ids.size());
        for (String id : ids) {
            GoalSpec spec = GoalConfig.personalById(id);
            if (spec != null) {
                specs.add(spec);
            }
        }
        return specs;
    }

    /** Mains + sides + the player's personals, payload order. */
    static List<GoalSpec> specsFor(ResolvedDay day, QuestState state, UUID uuid) {
        List<GoalSpec> specs = new ArrayList<>(day.mains.size() + day.sides.size() + 3);
        specs.addAll(day.mains);
        specs.addAll(day.sides);
        specs.addAll(personalSpecs(day, state, uuid));
        return specs;
    }

    private static void captureBaselines(QuestState state, ResolvedDay day, ServerPlayer player,
            GoalSpec spec, boolean force) {
        UUID uuid = player.getUUID();
        switch (spec.trigger().type()) {
            case COLLECT_ITEM -> {
                for (Item item : day.collectItems.getOrDefault(spec.id(), List.of())) {
                    ResourceLocation id = BuiltInRegistries.ITEM.getKey(item);
                    captureBaseline(state, day.day, player, "pu:" + id,
                            player.getStats().getValue(Stats.ITEM_PICKED_UP.get(item)), force);
                    captureBaseline(state, day.day, player, "cr:" + id,
                            player.getStats().getValue(Stats.ITEM_CRAFTED.get(item)), force);
                }
            }
            case TRAVEL_DISTANCE -> captureBaseline(state, day.day, player, "travel",
                    travelCm(player), force);
            case STAT_THRESHOLD -> {
                Stat<?> stat = day.stats.get(spec.id());
                if (stat != null) {
                    captureBaseline(state, day.day, player, "stat:" + spec.trigger().statId(),
                            player.getStats().getValue(stat), force);
                }
            }
            default -> { }
        }
        if (force) {
            state.resetPlayerProgress(day.day, uuid, spec.id());
        }
    }

    private static void captureBaseline(QuestState state, int day, ServerPlayer player, String key,
            long current, boolean force) {
        if (force || !state.hasBaseline(day, player.getUUID(), key)) {
            state.setBaseline(day, player.getUUID(), key, current);
        }
    }

    // --- progress routing (single write path for every detector) ---

    /**
     * Adds {@code amount} of progress for {@code player} toward {@code spec}, honoring the
     * scope semantics (§2.2): {@code each_player} completes just this player at target;
     * {@code team_total} feeds one shared counter and completes everyone at target;
     * {@code team_all} latches the player's part and completes once every online player's
     * part is satisfied.
     */
    static void increment(MinecraftServer server, ServerPlayer player, GoalSpec spec, long amount) {
        if (amount <= 0) {
            return;
        }
        QuestState state = QuestState.get(server);
        ResolvedDay resolvedDay = resolved(server);
        int day = resolvedDay.day;
        UUID uuid = player.getUUID();
        if (!isEligible(state, resolvedDay, uuid, spec)) {
            return;
        }
        long target = spec.target();
        switch (spec.scope()) {
            case EACH_PLAYER -> {
                if (state.isPlayerDone(day, uuid, spec.id())) {
                    return;
                }
                long next = state.addPlayerProgress(day, uuid, spec.id(), amount);
                markDirty(uuid);
                if (next >= target) {
                    completeForPlayer(server, player, spec);
                }
            }
            case TEAM_TOTAL -> {
                if (state.isTeamDone(day, spec.id())) {
                    return;
                }
                state.addPlayerProgress(day, uuid, spec.id(), amount); // personal contribution memo
                long next = state.addTeamProgress(day, spec.id(), amount);
                markAllDirty();
                if (next >= target) {
                    completeTeam(server, spec);
                }
            }
            case TEAM_ALL -> {
                if (state.isTeamDone(day, spec.id()) || state.isPlayerDone(day, uuid, spec.id())) {
                    return;
                }
                long next = state.addPlayerProgress(day, uuid, spec.id(), amount);
                markDirty(uuid);
                if (next >= target) {
                    state.setPlayerDone(day, uuid, spec.id());
                    if (player.connection != null) {
                        player.displayClientMessage(Component.translatable("quest.eclipse.done.team_part",
                                LangService.pick(spec.text(), player)), true);
                    }
                    checkTeamAll(server, spec, server.getPlayerList().getPlayers());
                }
            }
        }
    }

    /** Raises absolute-value progress (stat deltas, distinct counts) instead of adding. */
    static void raiseTo(MinecraftServer server, ServerPlayer player, GoalSpec spec, long value) {
        QuestState state = QuestState.get(server);
        ResolvedDay resolvedDay = resolved(server);
        int day = resolvedDay.day;
        if (!isEligible(state, resolvedDay, player.getUUID(), spec)) {
            return;
        }
        long previous = state.playerProgress(day, player.getUUID(), spec.id());
        if (value > previous) {
            increment(server, player, spec, value - previous);
        }
    }

    /**
     * Evaluates a {@code team_all} goal against the given online players (parameterized so
     * gametests can pass mock players — the production caller passes the real player list).
     * Completes the team the moment every listed player's part is done (empty list = never).
     */
    static void checkTeamAll(MinecraftServer server, GoalSpec spec, List<ServerPlayer> online) {
        QuestState state = QuestState.get(server);
        int day = resolved(server).day;
        if (online.isEmpty() || state.isTeamDone(day, spec.id())) {
            return;
        }
        for (ServerPlayer player : online) {
            if (!state.isPlayerDone(day, player.getUUID(), spec.id())) {
                return;
            }
        }
        completeTeam(server, spec);
    }

    // --- completion pipeline ---

    /** Full completion for one player ({@code each_player} scope or a team credit). */
    static void completeForPlayer(MinecraftServer server, ServerPlayer player, GoalSpec spec) {
        QuestState state = QuestState.get(server);
        int day = resolved(server).day;
        UUID uuid = player.getUUID();
        state.raisePlayerProgress(day, uuid, spec.id(), spec.target());
        if (!state.setPlayerDone(day, uuid, spec.id())) {
            return;
        }
        if (spec.goalKind() == Kind.PERSONAL) {
            state.addLifetimeCompletedPersonal(uuid, spec.id());
        }
        grantRewards(player, spec);
        EclipseSignals.fireQuestCompleted(player, spec, spec.scope().id());
        announceIfMain(server, state, day, spec);
        feedback(player, spec);
        markDirty(uuid);
        syncPlayer(server, player);
        EclipseMod.LOGGER.info("Quest completed: '{}' ({} {}) by {}", spec.id(),
                spec.goalKind().id(), spec.scope().id(), player.getScoreboardName());
    }

    /** Marks a team goal done and credits every known player, queueing offline rewards. */
    static void completeTeam(MinecraftServer server, GoalSpec spec) {
        QuestState state = QuestState.get(server);
        ResolvedDay resolvedDay = resolved(server);
        int day = resolvedDay.day;
        if (!state.setTeamDone(day, spec.id())) {
            return;
        }
        state.setTeamProgress(day, spec.id(), Math.max(spec.target(),
                state.teamProgress(day, spec.id())));
        announceIfMain(server, state, day, spec);
        Map<UUID, ServerPlayer> online = new HashMap<>();
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            online.put(player.getUUID(), player);
        }
        Set<UUID> recipients = new HashSet<>(state.knownPlayers(day));
        recipients.addAll(online.keySet());
        int queued = 0;
        for (UUID uuid : recipients) {
            if (!isEligible(state, resolvedDay, uuid, spec)) {
                continue;
            }
            state.raisePlayerProgress(day, uuid, spec.id(), spec.target());
            state.setPlayerDone(day, uuid, spec.id());
            if (spec.goalKind() == Kind.PERSONAL) {
                state.addLifetimeCompletedPersonal(uuid, spec.id());
            }
            ServerPlayer player = online.get(uuid);
            if (player != null) {
                grantRewards(player, spec);
                EclipseSignals.fireQuestCompleted(player, spec, spec.scope().id());
                feedback(player, spec);
            } else if (state.queueReward(uuid, QuestState.PendingReward.of(day, spec))) {
                queued++;
            }
        }
        markAllDirty();
        flushDirty(server);
        EclipseMod.LOGGER.info("Team quest completed: '{}' ({} {}) — {} online credited, {} offline queued",
                spec.id(), spec.goalKind().id(), spec.scope().id(),
                online.size(), queued);
    }

    private static void announceIfMain(MinecraftServer server, QuestState state, int day, GoalSpec spec) {
        if (spec.goalKind() == Kind.MAIN && state.markAnnounced(day, spec.id())) {
            AnnouncementService.announceGoalCompleted(server, spec.text());
        }
    }

    /** Shard + item rewards, granted directly; skillXp travels via the questCompleted signal (B4). */
    private static void grantRewards(ServerPlayer player, GoalSpec spec) {
        grantRewardContents(player, spec.id(), spec.reward(), false);
    }

    private static void grantRewardContents(ServerPlayer player, String goalId, GoalSpec.Reward reward,
            boolean replay) {
        if (reward.shards() > 0) {
            ShardEconomy.addShards(player, reward.shards());
        }
        List<RewardPayloads.ItemEntry> granted = new ArrayList<>(reward.items().size());
        for (GoalSpec.ItemReward itemReward : reward.items()) {
            BuiltInRegistries.ITEM.getOptional(ResourceLocation.tryParse(itemReward.id()))
                    .ifPresentOrElse(item -> {
                        ItemStack stack = new ItemStack(item, itemReward.count());
                        if (!player.getInventory().add(stack)) {
                            player.drop(stack, false);
                        }
                        granted.add(new RewardPayloads.ItemEntry(itemReward.id(), itemReward.count()));
                    }, () -> EclipseMod.LOGGER.warn("Quest '{}' reward item '{}' unknown — skipped",
                            goalId, itemReward.id()));
        }
        // W4-CEREMONY / IDEA-11 #1: presentation-only materialization payload — only what was
        // actually granted rides it; login replays flag the calm client variant.
        RewardPayloads.sendRewardGrant(player, granted, reward.shards(),
                RewardPayloads.SOURCE_QUEST, replay);
    }

    /** Delivers reward snapshots removed from the ledger at login (award-ledger pattern). */
    private static void deliverPendingRewards(ServerPlayer player) {
        List<QuestState.PendingReward> pending =
                QuestState.get(player.server).takePendingRewards(player.getUUID());
        for (QuestState.PendingReward reward : pending) {
            grantRewardContents(player, reward.goalId(), reward.reward(), true);
            Kind kind = switch (reward.kind()) {
                case 0 -> Kind.MAIN;
                case 1 -> Kind.SIDE;
                default -> Kind.PERSONAL;
            };
            GoalSpec replay = new GoalSpec(reward.goalId(), kind, Scope.byId(reward.scope()),
                    GoalSpec.Trigger.manual(), reward.reward(), Localized.of(""), 0, 0, 0);
            EclipseSignals.fireQuestCompleted(player, replay, reward.scope());
        }
        if (!pending.isEmpty()) {
            EclipseMod.LOGGER.info("Delivered {} queued team-quest reward(s) to {}",
                    pending.size(), player.getScoreboardName());
        }
    }

    /** Action bar + chime for the credited player (never chat — P4 rule 7). */
    private static void feedback(ServerPlayer player, GoalSpec spec) {
        if (player.connection == null) {
            return;
        }
        String key = switch (spec.goalKind()) {
            case MAIN -> "quest.eclipse.done.main";
            case SIDE -> "quest.eclipse.done.side";
            case PERSONAL -> "quest.eclipse.done.personal";
        };
        player.displayClientMessage(Component.translatable(key,
                LangService.pick(spec.text(), player)), true);
        if (spec.goalKind() == Kind.MAIN) {
            player.playNotifySound(SoundEvents.AMETHYST_BLOCK_CHIME, SoundSource.MASTER, 1.0F, 1.2F);
        } else {
            player.playNotifySound(EclipseSounds.SKILL_PROC.get(), SoundSource.MASTER, 0.8F, 1.0F);
        }
    }

    // --- team beats (data-driven successors of the hardcoded switch(day) detectors) ---

    /**
     * Fires a team beat: every current-day goal whose {@code trigger.beatId} matches is
     * completed (team scopes complete the team; {@code each_player} scopes credit everyone
     * online, with login backfill for late joiners). Once per (day, beat) — re-fires no-op.
     */
    public static void completeTeamBeat(MinecraftServer server, String beatId) {
        ResolvedDay day = resolved(server);
        QuestState state = QuestState.get(server);
        if (!state.markBeatFired(day.day, beatId)) {
            return;
        }
        List<GoalSpec> specs = day.byBeat.getOrDefault(beatId, List.of());
        if (specs.isEmpty()) {
            EclipseMod.LOGGER.debug("Team beat '{}' fired on day {} with no matching goals", beatId, day.day);
            return;
        }
        for (GoalSpec spec : specs) {
            if (spec.scope() == Scope.EACH_PLAYER) {
                for (ServerPlayer player : server.getPlayerList().getPlayers()) {
                    if (isEligible(state, day, player.getUUID(), spec)) {
                        completeForPlayer(server, player, spec);
                    }
                }
            } else {
                completeTeam(server, spec);
            }
        }
        EclipseMod.LOGGER.info("Team beat '{}' completed {} goal(s) on day {}", beatId, specs.size(), day.day);
    }

    /** Built-in world-state beat conditions, polled only while an active goal references them. */
    private static void pollBeats(MinecraftServer server, ResolvedDay day, QuestState state) {
        if (day.byBeat.isEmpty()) {
            return;
        }
        EclipseWorldState world = EclipseWorldState.get(server);
        for (String beatId : day.byBeat.keySet()) {
            if (state.isBeatFired(day.day, beatId) || !evaluateBuiltinBeat(server, world, beatId)) {
                continue;
            }
            completeTeamBeat(server, beatId);
        }
    }

    /** True when a built-in beat condition holds; unknown/external beat ids return false. */
    static boolean evaluateBuiltinBeat(MinecraftServer server, EclipseWorldState world, String beatId) {
        Integer altarLevel = suffixNumber(beatId, "altar_level_");
        if (altarLevel != null) {
            return world.getAltarLevel() >= altarLevel;
        }
        Integer pool = suffixNumber(beatId, "shard_pool_");
        if (pool != null) {
            return world.getShardPool() >= pool;
        }
        Integer hearts = suffixNumber(beatId, "all_hearts_");
        if (hearts != null) {
            List<ServerPlayer> online = server.getPlayerList().getPlayers();
            if (online.isEmpty()) {
                return false;
            }
            for (ServerPlayer player : online) {
                if (LivesApi.get(player) < hearts) {
                    return false;
                }
            }
            return true;
        }
        return switch (beatId) {
            case "herald_defeated" -> world.isHeraldDefeated();
            case "ferryman_defeated" -> world.isFerrymanDefeated();
            case "dragon_defeated" -> {
                ServerLevel end = server.getLevel(Level.END);
                yield end != null && end.getDragonFight() != null
                        && end.getDragonFight().hasPreviouslyKilledDragon();
            }
            default -> false; // external beats (herald_summoned, finale_begun) arrive via shims
        };
    }

    private static Integer suffixNumber(String beatId, String prefix) {
        if (!beatId.startsWith(prefix)) {
            return null;
        }
        try {
            return Integer.parseInt(beatId.substring(prefix.length()));
        } catch (NumberFormatException e) {
            return null;
        }
    }

    // --- the shared 20t poll ---

    /**
     * One poll pass: day/config-change resolution, built-in beats, polled trigger types for
     * every online player, night-watcher window, dirty payload flush. Public for gametests
     * and reference commands ({@code /eclipse-quests sync}); production cadence is 20 ticks.
     */
    public static void runPollNow(MinecraftServer server) {
        ResolvedDay day = resolved(server);
        QuestState state = QuestState.get(server);

        pollBeats(server, day, state);

        List<ServerPlayer> online = server.getPlayerList().getPlayers();
        for (ServerPlayer player : online) {
            pollPlayer(server, day, state, player);
        }
        for (GoalSpec spec : day.ofType(TriggerType.VISIT_LOCATION)) {
            if (spec.scope() == Scope.TEAM_ALL) {
                checkTeamAll(server, spec, online);
            }
        }
        QuestDetectors.pollNightWindow(server, day);
        flushDirty(server);
    }

    /** Polled trigger types for one player. O(active polled specs); zero allocation hot path. */
    static void pollPlayer(MinecraftServer server, ResolvedDay day, QuestState state, ServerPlayer player) {
        UUID uuid = player.getUUID();
        for (GoalSpec spec : day.ofType(TriggerType.VISIT_LOCATION)) {
            if (state.isPlayerDone(day.day, uuid, spec.id()) || state.isTeamDone(day.day, spec.id())) {
                continue;
            }
            if (player.serverLevel().dimension() == Level.OVERWORLD) {
                double dx = player.getX() - spec.trigger().x();
                double dz = player.getZ() - spec.trigger().z();
                long radius = spec.trigger().radius();
                if (dx * dx + dz * dz <= (double) (radius * radius)) {
                    raiseTo(server, player, spec, spec.target());
                }
            }
        }
        for (GoalSpec spec : day.ofType(TriggerType.REACH_DEPTH)) {
            if (!state.isPlayerDone(day.day, uuid, spec.id()) && !state.isTeamDone(day.day, spec.id())
                    && player.getY() <= spec.trigger().y()) {
                raiseTo(server, player, spec, spec.target());
            }
        }
        for (GoalSpec spec : day.ofType(TriggerType.COLLECT_ITEM)) {
            if (!isEligible(state, day, uuid, spec)
                    || state.isPlayerDone(day.day, uuid, spec.id())
                    || state.isTeamDone(day.day, spec.id())) {
                continue;
            }
            long value = collectValue(state, day, player, spec);
            raiseTo(server, player, spec, value);
        }
        for (GoalSpec spec : day.ofType(TriggerType.TRAVEL_DISTANCE)) {
            if (state.isPlayerDone(day.day, uuid, spec.id()) || state.isTeamDone(day.day, spec.id())) {
                continue;
            }
            Long baseline = state.baseline(day.day, uuid, "travel");
            if (baseline == null) {
                captureBaseline(state, day.day, player, "travel", travelCm(player), false);
                continue;
            }
            raiseTo(server, player, spec, Math.max(0L, travelCm(player) - baseline) / 100L);
        }
        for (GoalSpec spec : day.ofType(TriggerType.STAT_THRESHOLD)) {
            if (state.isPlayerDone(day.day, uuid, spec.id()) || state.isTeamDone(day.day, spec.id())) {
                continue;
            }
            Stat<?> stat = day.stats.get(spec.id());
            if (stat == null) {
                continue;
            }
            String key = "stat:" + spec.trigger().statId();
            Long baseline = state.baseline(day.day, uuid, key);
            if (baseline == null) {
                captureBaseline(state, day.day, player, key, player.getStats().getValue(stat), false);
                continue;
            }
            raiseTo(server, player, spec, Math.max(0L, player.getStats().getValue(stat) - baseline));
        }
    }

    /** collect_item value: per matched item max(picked-up delta, crafted delta), summed. */
    private static long collectValue(QuestState state, ResolvedDay day, ServerPlayer player, GoalSpec spec) {
        long sum = 0L;
        UUID uuid = player.getUUID();
        for (Item item : day.collectItems.getOrDefault(spec.id(), List.of())) {
            ResourceLocation id = BuiltInRegistries.ITEM.getKey(item);
            Long puBase = state.baseline(day.day, uuid, "pu:" + id);
            Long crBase = state.baseline(day.day, uuid, "cr:" + id);
            long pu = player.getStats().getValue(Stats.ITEM_PICKED_UP.get(item));
            long cr = player.getStats().getValue(Stats.ITEM_CRAFTED.get(item));
            if (puBase == null || crBase == null) {
                captureBaseline(state, day.day, player, "pu:" + id, pu, false);
                captureBaseline(state, day.day, player, "cr:" + id, cr, false);
                continue;
            }
            // max, not sum: drop/re-pickup inflates PICKED_UP (anti-abuse note §2.2).
            sum += Math.max(Math.max(0L, pu - puBase), Math.max(0L, cr - crBase));
        }
        return sum;
    }

    private static long travelCm(ServerPlayer player) {
        long sum = 0L;
        for (ResourceLocation statId : TRAVEL_STATS) {
            sum += player.getStats().getValue(Stats.CUSTOM.get(statId));
        }
        return sum;
    }

    // --- payload sync ---

    static void markDirty(UUID uuid) {
        DIRTY.add(uuid);
    }

    static void markAllDirty() {
        dirtyAll = true;
    }

    private static void flushDirty(MinecraftServer server) {
        if (dirtyAll) {
            dirtyAll = false;
            DIRTY.clear();
            for (ServerPlayer player : server.getPlayerList().getPlayers()) {
                syncPlayer(server, player);
            }
            return;
        }
        if (DIRTY.isEmpty()) {
            return;
        }
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            if (DIRTY.remove(player.getUUID())) {
                syncPlayer(server, player);
            }
        }
        DIRTY.clear(); // offline leftovers re-sync at login anyway
    }

    /** Sends the quest payload + the legacy goal-progress payload (old sidebar) to the player. */
    public static void syncPlayer(MinecraftServer server, ServerPlayer player) {
        if (player.connection == null) {
            return;
        }
        PacketDistributor.sendToPlayer(player, buildPayload(server, player));
        PacketDistributor.sendToPlayer(player, S2CGoalProgressPayload.currentFor(player));
    }

    /** Assembles the player's {@code S2CQuestStatePayload} (mains, sides, personals — §2.0 shape). */
    public static S2CQuestStatePayload buildPayload(MinecraftServer server, ServerPlayer player) {
        ResolvedDay day = resolved(server);
        QuestState state = QuestState.get(server);
        UUID uuid = player.getUUID();
        List<S2CQuestStatePayload.QuestEntry> entries = new ArrayList<>();
        for (GoalSpec spec : specsFor(day, state, uuid)) {
            long target = spec.target();
            long progress = spec.scope() == Scope.TEAM_TOTAL
                    ? state.teamProgress(day.day, spec.id())
                    : state.playerProgress(day.day, uuid, spec.id());
            boolean done = spec.scope() == Scope.EACH_PLAYER
                    ? state.isPlayerDone(day.day, uuid, spec.id())
                    : state.isTeamDone(day.day, spec.id());
            if (done) {
                progress = target;
            }
            entries.add(new S2CQuestStatePayload.QuestEntry(
                    spec.id(), spec.kind(),
                    spec.text().en(), spec.text().pick("de"),
                    QuestMath.clampToInt(Math.min(progress, target)), QuestMath.clampToInt(target),
                    done, spec.scope().team()));
        }
        return new S2CQuestStatePayload(day.day, entries);
    }

    // --- legacy adapter surface (GoalTracker + S2CGoalProgressPayload) ---

    /** Ordered mains done flags for the player (legacy bitmask; team scopes use team done). */
    public static List<Boolean> mainDoneFlags(MinecraftServer server, ServerPlayer player) {
        ResolvedDay day = resolved(server);
        QuestState state = QuestState.get(server);
        List<Boolean> done = new ArrayList<>(day.mains.size());
        for (GoalSpec spec : day.mains) {
            done.add(spec.scope() == Scope.EACH_PLAYER
                    ? state.isPlayerDone(day.day, player.getUUID(), spec.id())
                    : state.isTeamDone(day.day, spec.id()));
        }
        return done;
    }

    /** The current day's mains in payload order (legacy index mapping). */
    public static List<GoalSpec> currentMains(MinecraftServer server) {
        return resolved(server).mains;
    }

    // --- admin surface backing QuestApi ---

    /** Manual completion (admin tick / legacy command): team scopes complete the whole team. */
    static boolean completeManual(MinecraftServer server, ServerPlayer player, GoalSpec spec) {
        QuestState state = QuestState.get(server);
        int day = resolved(server).day;
        if (spec.scope() == Scope.EACH_PLAYER) {
            if (state.isPlayerDone(day, player.getUUID(), spec.id())) {
                return false;
            }
            completeForPlayer(server, player, spec);
            return true;
        }
        if (state.isTeamDone(day, spec.id())) {
            return false;
        }
        completeTeam(server, spec);
        return true;
    }

    /** Revokes a player's completion + progress ({@code each_player}); team scopes → team revoke. */
    static boolean revokeForPlayer(MinecraftServer server, ServerPlayer player, GoalSpec spec) {
        QuestState state = QuestState.get(server);
        int day = resolved(server).day;
        if (spec.scope() != Scope.EACH_PLAYER) {
            return revokeTeam(server, spec);
        }
        boolean was = state.isPlayerDone(day, player.getUUID(), spec.id())
                || state.playerProgress(day, player.getUUID(), spec.id()) > 0;
        state.resetPlayerProgress(day, player.getUUID(), spec.id());
        captureBaselines(state, resolved(server), player, spec, true);
        markDirty(player.getUUID());
        flushDirty(server);
        return was;
    }

    /** Clears a team goal (counter, done flags, per-player parts, re-armable beat). */
    static boolean revokeTeam(MinecraftServer server, GoalSpec spec) {
        QuestState state = QuestState.get(server);
        ResolvedDay day = resolved(server);
        boolean was = state.isTeamDone(day.day, spec.id()) || state.teamProgress(day.day, spec.id()) > 0;
        state.clearTeamDone(day.day, spec.id());
        for (UUID uuid : new ArrayList<>(state.knownPlayers(day.day))) {
            state.resetPlayerProgress(day.day, uuid, spec.id());
        }
        if (!spec.trigger().beatId().isEmpty()) {
            state.clearBeatFired(day.day, spec.trigger().beatId());
        }
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            captureBaselines(state, day, player, spec, true);
        }
        markAllDirty();
        flushDirty(server);
        return was;
    }

    /** Rerolls the player's personal quests (new deterministic nonce; persisted). */
    static List<String> reroll(MinecraftServer server, ServerPlayer player) {
        QuestState state = QuestState.get(server);
        ResolvedDay day = resolved(server);
        UUID uuid = player.getUUID();
        List<GoalSpec> previous = personalSpecs(day, state, uuid);
        for (GoalSpec spec : previous) {
            state.resetPlayerProgress(day.day, uuid, spec.id());
        }
        int nonce = state.bumpRerollNonce(day.day, uuid);
        List<String> drawn = drawPersonals(server, state, day.day, uuid, nonce);
        state.setPersonals(day.day, uuid, drawn);
        day.rebuildIndexes(state);
        for (GoalSpec spec : personalSpecs(day, state, uuid)) {
            captureBaselines(state, day, player, spec, true);
        }
        markDirty(uuid);
        flushDirty(server);
        return drawn;
    }

    /** Personal specs may only mutate the UUID that currently has them assigned. */
    static boolean isEligible(QuestState state, ResolvedDay day, UUID uuid, GoalSpec spec) {
        if (spec.goalKind() != Kind.PERSONAL) {
            return true;
        }
        List<String> assigned = state.personals(day.day, uuid);
        return assigned != null && assigned.contains(spec.id());
    }

    // --- id / target matching helpers (shared with QuestDetectors) ---

    static boolean matchesItemStack(ItemStack stack, String target) {
        if (target.isEmpty()) {
            return !stack.isEmpty();
        }
        if (target.startsWith("#")) {
            ResourceLocation tagId = ResourceLocation.tryParse(target.substring(1));
            return tagId != null && stack.is(TagKey.create(Registries.ITEM, tagId));
        }
        ResourceLocation id = ResourceLocation.tryParse(target);
        return id != null && id.equals(BuiltInRegistries.ITEM.getKey(stack.getItem()));
    }

    static boolean matchesItemId(ResourceLocation itemId, String target) {
        if (target.isEmpty()) {
            return true;
        }
        if (target.startsWith("#")) {
            ResourceLocation tagId = ResourceLocation.tryParse(target.substring(1));
            if (tagId == null) {
                return false;
            }
            return BuiltInRegistries.ITEM.getOptional(itemId)
                    .map(item -> new ItemStack(item).is(TagKey.create(Registries.ITEM, tagId)))
                    .orElse(false);
        }
        return itemId.toString().equals(target);
    }

    static boolean matchesEntity(LivingEntity victim, String target) {
        if (target.isEmpty()) {
            return true;
        }
        if ("any_hostile".equals(target)) {
            return victim instanceof Enemy;
        }
        if (target.startsWith("#")) {
            ResourceLocation tagId = ResourceLocation.tryParse(target.substring(1));
            return tagId != null && victim.getType().is(TagKey.create(Registries.ENTITY_TYPE, tagId));
        }
        ResourceLocation id = ResourceLocation.tryParse(target);
        return id != null && id.equals(BuiltInRegistries.ENTITY_TYPE.getKey(victim.getType()));
    }

    static boolean matchesBlock(BlockState blockState, String target) {
        if (target.isEmpty()) {
            return true;
        }
        if (target.startsWith("#")) {
            ResourceLocation tagId = ResourceLocation.tryParse(target.substring(1));
            return tagId != null && blockState.is(TagKey.create(Registries.BLOCK, tagId));
        }
        ResourceLocation id = ResourceLocation.tryParse(target);
        return id != null && id.equals(BuiltInRegistries.BLOCK.getKey(blockState.getBlock()));
    }

    static boolean matchesBiome(MinecraftServer server, ResourceLocation biomeId, String target) {
        if (target.isEmpty()) {
            return true;
        }
        if (target.startsWith("#")) {
            ResourceLocation tagId = ResourceLocation.tryParse(target.substring(1));
            if (tagId == null) {
                return false;
            }
            TagKey<Biome> tag = TagKey.create(Registries.BIOME, tagId);
            return server.registryAccess().registryOrThrow(Registries.BIOME)
                    .getHolder(ResourceKey.create(Registries.BIOME, biomeId))
                    .map(holder -> holder.is(tag))
                    .orElse(false);
        }
        return biomeId.toString().equals(target);
    }

    private static List<Item> resolveItems(String target) {
        if (target.isEmpty()) {
            return List.of();
        }
        if (target.startsWith("#")) {
            ResourceLocation tagId = ResourceLocation.tryParse(target.substring(1));
            if (tagId == null) {
                return List.of();
            }
            List<Item> items = new ArrayList<>();
            for (var holder : BuiltInRegistries.ITEM.getTagOrEmpty(TagKey.create(Registries.ITEM, tagId))) {
                items.add(holder.value());
            }
            return Collections.unmodifiableList(items);
        }
        ResourceLocation id = ResourceLocation.tryParse(target);
        return id == null ? List.of()
                : BuiltInRegistries.ITEM.getOptional(id).map(List::of).orElse(List.of());
    }

    /** Resolves {@code "<stat_type_id>/<value_id>"} (bare value id = {@code minecraft:custom}). */
    static Stat<?> resolveStat(String statId) {
        if (statId == null || statId.isEmpty()) {
            return null;
        }
        String typePart;
        String valuePart;
        int firstColon = statId.indexOf(':');
        int slash = statId.indexOf('/', firstColon >= 0 ? firstColon : 0);
        if (slash < 0) {
            typePart = "minecraft:custom";
            valuePart = statId;
        } else {
            typePart = statId.substring(0, slash);
            valuePart = statId.substring(slash + 1);
        }
        ResourceLocation typeId = ResourceLocation.tryParse(typePart);
        ResourceLocation valueId = ResourceLocation.tryParse(valuePart);
        if (typeId == null || valueId == null) {
            return null;
        }
        StatType<?> type = BuiltInRegistries.STAT_TYPE.getOptional(typeId).orElse(null);
        if (type == null) {
            return null;
        }
        return statFor(type, valueId);
    }

    private static <T> Stat<T> statFor(StatType<T> type, ResourceLocation valueId) {
        T value = type.getRegistry().getOptional(valueId).orElse(null);
        return value == null ? null : type.get(value);
    }
}
