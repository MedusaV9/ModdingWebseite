package dev.projecteclipse.eclipse.collections;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Predicate;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.ReloadHooks;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.network.collections.CollectionsPayloads;
import dev.projecteclipse.eclipse.network.collections.S2CCollectionTierPayload;
import dev.projecteclipse.eclipse.network.collections.S2CCollectionsPayload;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import dev.projecteclipse.eclipse.progression.RecipeGate;
import dev.projecteclipse.eclipse.skills.SkillsApi;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.core.registries.Registries;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.tags.TagKey;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockState;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.server.ServerLifecycleHooks;

/**
 * D1 collections engine (IDEAS-collections): lifetime counters riding the sanctioned
 * {@link EclipseSignals} lanes — {@code onNaturalBlockMined} (mine, already
 * placed-block-filtered), {@code onCropHarvested} (harvest, max-age only),
 * {@code onMobKilled} (kill — kills not drops, Looting-neutral), {@code onAltarDeposit}
 * with {@code SHARD_BANK} (one-way shard sink) and {@code onItemCollected} (pickup,
 * thrower-null + allowlisted) — persisted in {@link CollectionsState}.
 *
 * <p><b>Tier grants are automatic and idempotent</b>: the threshold sweep runs on every
 * credit; {@code grantedTier} is monotonic, so re-sweeps (config reload, dev sets) only
 * ever grant NEWLY reached tiers. A grant pays skill XP via {@code SkillsApi.addXp}
 * (source {@code collection}, {@code XpGates}-exempt), skill points via
 * {@code addPoints}, unlocks recipes through the {@link RecipeGate} per-player lock
 * provider (re-synced in the same tick so the toast and the EMI un-hide land together),
 * fires {@link S2CCollectionTierPayload} (client toast + sting) and announces the tier
 * in the player's chat.</p>
 *
 * <p><b>Client sync</b>: full {@link S2CCollectionsPayload} (definitions + progress) on
 * login, after every tier grant and after a reload sweep; dirty counters flush as cheap
 * {@code S2CCollectionDeltaPayload}s at most once per second ({@code SkillService.DIRTY}
 * pattern).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class CollectionsService {
    private static final int SYNC_INTERVAL_TICKS = 20;

    // statics reset on ServerStopped
    private static final AtomicBoolean SIGNALS_REGISTERED = new AtomicBoolean();
    // statics reset on ServerStopped
    private static final Map<UUID, Set<String>> DIRTY = new ConcurrentHashMap<>();
    // statics reset on ServerStopped
    private static int tickCounter = 0;
    /** JVM-lifetime guard — ReloadHooks entries survive across saves by design. */
    private static final AtomicBoolean RELOAD_HOOK_REGISTERED = new AtomicBoolean();

    /** Lane → matchers, rebuilt lazily whenever the config snapshot identity changes. */
    private static volatile Map<String, List<Matcher>> laneIndex = Map.of();
    private static volatile CollectionsConfig.Snapshot indexedSnapshot;

    private CollectionsService() {}

    // ------------------------------------------------------------------
    // Lifecycle + signal wiring
    // ------------------------------------------------------------------

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        CollectionsConfig.reloadDefault();
        if (RELOAD_HOOK_REGISTERED.compareAndSet(false, true)) {
            ReloadHooks.register("collections", CollectionsService::onConfigReload);
        }
        if (SIGNALS_REGISTERED.compareAndSet(false, true)) {
            EclipseSignals.onNaturalBlockMined(CollectionsService::handleNaturalBlockMined);
            EclipseSignals.onCropHarvested(CollectionsService::handleCropHarvested);
            EclipseSignals.onMobKilled(CollectionsService::handleMobKilled);
            EclipseSignals.onAltarDeposit(CollectionsService::handleAltarDeposit);
            EclipseSignals.onItemCollected(CollectionsService::handleItemCollected);
            // RecipeGate clears its provider lists on server stop (EclipseSignals pattern),
            // so this CAS block re-registers them alongside the signals.
            RecipeGate.registerPlayerLockProvider(CollectionsService::lockedEntriesFor);
            RecipeGate.registerLockHintProvider(CollectionsService::lockHintFor);
        }
        RecipeGate.broadcastAll(event.getServer());
        EclipseMod.LOGGER.info("CollectionsService active ({} collection(s))",
                CollectionsConfig.current().collections().size());
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        SIGNALS_REGISTERED.set(false);
        DIRTY.clear();
        tickCounter = 0;
        laneIndex = Map.of();
        indexedSnapshot = null;
    }

    /** ReloadHooks body: re-read the config, re-sweep everyone (lowered thresholds grant retroactively). */
    private static void onConfigReload() {
        CollectionsConfig.reloadDefault();
        MinecraftServer server = ServerLifecycleHooks.getCurrentServer();
        if (server == null) {
            return;
        }
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            sweepAll(player);
            syncTo(player);
        }
        // Raised thresholds never revoke XP/points (fail-safe) — they only re-lock
        // un-reached recipes on this resync.
        RecipeGate.broadcastAll(server);
    }

    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            // DOPA-S-06: settle any crash-orphaned tier payouts before the first snapshot.
            replayPendingGrants(player);
            syncTo(player);
        }
    }

    // ------------------------------------------------------------------
    // Signal consumers (single sanctioned lanes — never NeoForge event subscribers)
    // ------------------------------------------------------------------

    static void handleNaturalBlockMined(ServerPlayer player, BlockState state, net.minecraft.core.BlockPos pos) {
        creditLane(player, CollectionsConfig.LANE_MINE, matcher -> matcher.matchesBlock(state), 1L);
    }

    static void handleCropHarvested(ServerPlayer player, BlockState state, net.minecraft.core.BlockPos pos) {
        creditLane(player, CollectionsConfig.LANE_HARVEST, matcher -> matcher.matchesBlock(state), 1L);
    }

    static void handleMobKilled(ServerPlayer player, LivingEntity victim) {
        creditLane(player, CollectionsConfig.LANE_KILL, matcher -> matcher.matchesEntity(victim), 1L);
    }

    static void handleAltarDeposit(ServerPlayer player, ResourceLocation itemId, int count,
            EclipseSignals.AltarDepositPurpose purpose) {
        if (purpose != EclipseSignals.AltarDepositPurpose.SHARD_BANK || count <= 0) {
            return;
        }
        String id = itemId.toString();
        creditLane(player, CollectionsConfig.LANE_SHARD_BANK,
                matcher -> matcher.exactIds().contains(id), count);
    }

    static void handleItemCollected(ServerPlayer player, ItemStack stack) {
        if (stack.isEmpty()) {
            return;
        }
        creditLane(player, CollectionsConfig.LANE_PICKUP,
                matcher -> matcher.matchesStack(stack), stack.getCount());
    }

    // ------------------------------------------------------------------
    // Credit + threshold sweep
    // ------------------------------------------------------------------

    private static void creditLane(ServerPlayer player, String lane, Predicate<Matcher> filter, long amount) {
        if (amount <= 0L) {
            return;
        }
        for (Matcher matcher : matchersFor(lane)) {
            if (filter.test(matcher)) {
                credit(player, matcher.def(), amount);
            }
        }
    }

    /** Applies the optional daily credit cap, bumps the counter and runs the tier sweep. */
    private static void credit(ServerPlayer player, CollectionsConfig.Collection def, long amount) {
        MinecraftServer server = player.server;
        CollectionsState state = CollectionsState.get(server);
        CollectionsState.Entry entry = state.entry(player.getUUID());

        long allowed = amount;
        if (def.dailyCreditCap() > 0L) {
            int day = DayScheduler.getDay(server);
            if (entry.capDay != day) {
                entry.capDay = day;
                entry.capUsed.clear();
            }
            long used = entry.capUsed.getOrDefault(def.id(), 0L);
            allowed = Math.min(amount, def.dailyCreditCap() - used);
            if (allowed <= 0L) {
                return; // capped out for today — fail-safe under-crediting (§5.7)
            }
            entry.capUsed.merge(def.id(), allowed, Long::sum);
        }

        entry.counts.merge(def.id(), allowed, Long::sum);
        state.setDirty();
        boolean granted = sweep(player, def, entry, state);
        if (!granted) {
            // Tier grants already pushed a full snapshot; plain credits coalesce as deltas.
            DIRTY.computeIfAbsent(player.getUUID(), ignored -> ConcurrentHashMap.newKeySet()).add(def.id());
        }
    }

    /**
     * Grants every newly crossed tier (idempotent — {@code grantedTier} is monotonic).
     * On any grant: XP + points, per-player recipe unlock resync, tier toast payload and
     * the chat announcement, then a full snapshot so the handbook tab is exact.
     *
     * <p><b>Crash-safety (DOPA-S-06, hardened per EVAL-V6-COMPLETE A#8)</b>:
     * claim-then-grant with idempotent destinations. Ordering:</p>
     * <ol>
     *   <li>The tier CLAIM ({@code grantedTiers}) and a pending-grant journal row are
     *       written to {@link CollectionsState} and force-flushed BEFORE any payout
     *       (a crash before this flush loses only the claim — the sweep re-crosses it
     *       from the counter, granting once).</li>
     *   <li>Payouts go through exactly-once destinations: XP/points via
     *       {@code SkillsApi.grantOnce} (receipt persisted in the SAME
     *       {@code eclipse_skills} write as the payout) and shards via
     *       {@link #grantShardsOnce} (receipt attachment in the SAME player NBT as the
     *       balance). A torn multi-file save can therefore never double-pay: the
     *       journal replay skips whatever already landed.</li>
     *   <li>The payout (player NBT + skills SavedData) is force-persisted, and only
     *       THEN are the journal rows cleared. The clear becoming durable strictly
     *       after the payout means a torn save can never drop a reward either.</li>
     * </ol>
     */
    private static boolean sweep(ServerPlayer player, CollectionsConfig.Collection def,
            CollectionsState.Entry entry, CollectionsState state) {
        CollectionsConfig.Snapshot cfg = CollectionsConfig.current();
        List<CollectionsConfig.Tier> tiers = def.tiers();
        int previous = entry.grantedTier(def.id());
        long count = entry.count(def.id());
        int granted = previous;
        while (granted < tiers.size() && count >= tiers.get(granted).threshold()) {
            granted++;
        }
        if (granted == previous) {
            return false;
        }

        // 1) Durable claim + journal BEFORE any grant (see javadoc).
        entry.grantedTiers.put(def.id(), granted);
        for (int tier = previous + 1; tier <= granted; tier++) {
            entry.addPendingGrant(def.id(), tier);
        }
        state.setDirty();
        dev.projecteclipse.eclipse.core.state.EclipseSavedData.flushOverworld(player.server);

        // 2) Idempotent payouts (receipts land in the destination files).
        for (int tier = previous + 1; tier <= granted; tier++) {
            applyTierGrant(player, def, tiers.get(tier - 1), tier, cfg, true);
        }

        // 3) Persist the payouts, THEN confirm (clear) the journal rows — never before.
        persistPayouts(player);
        for (int tier = previous + 1; tier <= granted; tier++) {
            entry.clearPendingGrant(def.id(), tier);
        }
        state.setDirty();

        // §4.2: recipe unlock + EMI un-hide land in the same tick as the toast.
        RecipeGate.syncTo(player);
        syncTo(player);
        return true;
    }

    /**
     * One tier's payout: XP + points + FIX-ECON personal shards + toast + chat line.
     * Idempotent per {@code (collection, tier, player)} — both destinations check a
     * durable receipt before paying (see {@link #sweep} javadoc). {@code announce}
     * controls the toast/chat: the live sweep always announces; the crash-recovery
     * replay announces only when something was actually re-paid.
     *
     * @return whether any XP/point/shard grant was applied NOW (false = pure replay)
     */
    private static boolean applyTierGrant(ServerPlayer player, CollectionsConfig.Collection def,
            CollectionsConfig.Tier tier, int tierNumber, CollectionsConfig.Snapshot cfg,
            boolean announce) {
        String receipt = "collections:" + def.id() + ":" + tierNumber;
        boolean applied = false;
        if (tier.xp() > 0 || tier.points() > 0) {
            applied |= SkillsApi.grantOnce(player, receipt, cfg.xpSourceKey(), tier.xp(), tier.points());
        }
        if (tier.shards() > 0) {
            // FIX-ECON: chunky (T4+) tiers pay PERSONAL shards — rebirth currency,
            // announced with the D14 gain toast. The sweep only runs for the online
            // acting player, so a direct credit is always deliverable.
            applied |= grantShardsOnce(player, receipt, tier.shards());
        }
        if (announce || applied) {
            if (cfg.toastsEnabled()) {
                CollectionsPayloads.sendTo(player, new S2CCollectionTierPayload(
                        def.id(), tierNumber, tier.xp(), tier.points(), tier.unlockItems()));
            }
            player.sendSystemMessage(Component.translatable("message.eclipse.collection.tier",
                    Component.translatable("collection.eclipse." + def.id()),
                    CollectionTiers.roman(tierNumber)));
        }
        return applied;
    }

    /**
     * Exactly-once personal-shard payout: the receipt rides
     * {@code EclipseAttachments.SHARD_GRANT_RECEIPTS} — the SAME player NBT write as the
     * {@code SHARDS} balance, so payout and receipt persist (or tear away) together.
     */
    private static boolean grantShardsOnce(ServerPlayer player, String receipt, int shards) {
        List<String> receipts = player.getData(
                dev.projecteclipse.eclipse.registry.EclipseAttachments.SHARD_GRANT_RECEIPTS);
        if (receipts.contains(receipt)) {
            return false; // already paid — replay after a torn save
        }
        List<String> updated = new ArrayList<>(receipts);
        updated.add(receipt);
        player.setData(dev.projecteclipse.eclipse.registry.EclipseAttachments.SHARD_GRANT_RECEIPTS.get(),
                List.copyOf(updated));
        dev.projecteclipse.eclipse.economy.ShardEconomy.addShards(player, shards, true);
        return true;
    }

    /**
     * Durability barrier between payout and journal-clear (sweep step 3): persists
     * every player .dat (shard balance + shard receipts ride attachments) and the dirty
     * overworld SavedData (skill XP/points + skill receipts). Rare one-shot event —
     * never on a per-tick path (the {@code flushOverworld} doctrine).
     */
    private static void persistPayouts(ServerPlayer player) {
        player.server.getPlayerList().saveAll();
        dev.projecteclipse.eclipse.core.state.EclipseSavedData.flushOverworld(player.server);
    }

    /**
     * DOPA-S-06 recovery: replays every journaled tier payout that a crash cut off
     * between the durable claim and the confirmed payout. Destinations are idempotent
     * ({@code grantOnce}/{@link #grantShardsOnce} receipts), so a row whose payout DID
     * land before the crash is skipped silently — the journal row alone is no longer
     * trusted as the only marker (EVAL-V6-COMPLETE A#8). Rows whose collection/tier no
     * longer exists in the config are dropped with a WARN. Payouts are persisted BEFORE
     * the rows clear, mirroring the sweep's ordering.
     */
    private static void replayPendingGrants(ServerPlayer player) {
        CollectionsState state = CollectionsState.get(player.server);
        CollectionsState.Entry entry = state.entry(player.getUUID());
        if (entry.pendingGrants.isEmpty()) {
            return;
        }
        CollectionsConfig.Snapshot cfg = CollectionsConfig.current();
        boolean any = false;
        for (Map.Entry<String, Set<Integer>> pending
                : new HashMap<>(entry.pendingGrants).entrySet()) {
            CollectionsConfig.Collection def = cfg.byId(pending.getKey());
            for (int tier : new ArrayList<>(pending.getValue())) {
                if (def != null && tier >= 1 && tier <= def.tiers().size()) {
                    boolean applied = applyTierGrant(player, def, def.tiers().get(tier - 1), tier, cfg, false);
                    EclipseMod.LOGGER.info("Collections crash-recovery: '{}' tier {} for {} — {}",
                            pending.getKey(), tier, player.getScoreboardName(),
                            applied ? "replayed missing payout" : "payout already applied, journal row confirmed");
                } else {
                    EclipseMod.LOGGER.warn("Collections crash-recovery: dropped stale pending "
                            + "grant '{}' tier {} for {} (no longer in config)",
                            pending.getKey(), tier, player.getScoreboardName());
                }
                any = true;
            }
        }
        if (any) {
            // Same ordering law as the sweep: payout durable BEFORE the journal clears.
            persistPayouts(player);
            for (Map.Entry<String, Set<Integer>> pending
                    : new HashMap<>(entry.pendingGrants).entrySet()) {
                for (int tier : new ArrayList<>(pending.getValue())) {
                    entry.clearPendingGrant(pending.getKey(), tier);
                }
            }
            state.setDirty();
            RecipeGate.syncTo(player);
        }
    }

    /** Re-sweeps every collection for one player (config reload path, dev sets). */
    private static void sweepAll(ServerPlayer player) {
        CollectionsState state = CollectionsState.get(player.server);
        CollectionsState.Entry entry = state.entry(player.getUUID());
        for (CollectionsConfig.Collection def : CollectionsConfig.current().collections()) {
            sweep(player, def, entry, state);
        }
    }

    // ------------------------------------------------------------------
    // RecipeGate providers (D1 §4.2)
    // ------------------------------------------------------------------

    /** Every {@code unlockItems} entry of every NOT-yet-reached tier for this player. */
    private static Set<String> lockedEntriesFor(ServerPlayer player) {
        CollectionsState.Entry entry = CollectionsState.get(player.server).entry(player.getUUID());
        Set<String> locked = new LinkedHashSet<>();
        for (CollectionsConfig.Collection def : CollectionsConfig.current().collections()) {
            List<CollectionsConfig.Tier> tiers = def.tiers();
            for (int i = entry.grantedTier(def.id()); i < tiers.size(); i++) {
                locked.addAll(tiers.get(i).unlockItems());
            }
        }
        return locked;
    }

    /** "Locked — reach Iron Collection II" when a collection tier owns the confiscated item. */
    @Nullable
    private static Component lockHintFor(ServerPlayer player, ItemStack stack) {
        String itemId = BuiltInRegistries.ITEM.getKey(stack.getItem()).toString();
        CollectionsState.Entry entry = CollectionsState.get(player.server).entry(player.getUUID());
        for (CollectionsConfig.Collection def : CollectionsConfig.current().collections()) {
            List<CollectionsConfig.Tier> tiers = def.tiers();
            for (int i = entry.grantedTier(def.id()); i < tiers.size(); i++) {
                for (String unlockEntry : tiers.get(i).unlockItems()) {
                    if (unlockEntryMatches(stack, itemId, unlockEntry)) {
                        return Component.translatable("message.eclipse.recipe.locked.collection",
                                Component.translatable("collection.eclipse." + def.id()),
                                CollectionTiers.roman(i + 1));
                    }
                }
            }
        }
        return null;
    }

    private static boolean unlockEntryMatches(ItemStack stack, String itemId, String entry) {
        if (entry.startsWith("#")) {
            ResourceLocation tagId = ResourceLocation.tryParse(entry.substring(1));
            return tagId != null && stack.is(TagKey.create(Registries.ITEM, tagId));
        }
        return entry.equals(itemId);
    }

    // ------------------------------------------------------------------
    // Client sync
    // ------------------------------------------------------------------

    /** Immediate full snapshot (definitions + progress) to one player. */
    public static void syncTo(ServerPlayer player) {
        CollectionsState.Entry entry = CollectionsState.get(player.server).entry(player.getUUID());
        List<S2CCollectionsPayload.Entry> entries = new ArrayList<>();
        for (CollectionsConfig.Collection def : CollectionsConfig.current().collections()) {
            List<S2CCollectionsPayload.Tier> tiers = new ArrayList<>(def.tiers().size());
            for (CollectionsConfig.Tier tier : def.tiers()) {
                tiers.add(new S2CCollectionsPayload.Tier(tier.threshold(), tier.xp(), tier.points(),
                        tier.unlockItems()));
            }
            entries.add(new S2CCollectionsPayload.Entry(def.id(), def.category(), def.icon(), tiers,
                    entry.count(def.id()), entry.grantedTier(def.id())));
        }
        CollectionsPayloads.sendTo(player, new S2CCollectionsPayload(entries));
        DIRTY.remove(player.getUUID());
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (++tickCounter < SYNC_INTERVAL_TICKS) {
            return;
        }
        tickCounter = 0;
        if (DIRTY.isEmpty()) {
            return;
        }
        for (Map.Entry<UUID, Set<String>> dirty : new HashMap<>(DIRTY).entrySet()) {
            ServerPlayer player = event.getServer().getPlayerList().getPlayer(dirty.getKey());
            DIRTY.remove(dirty.getKey());
            if (player == null) {
                continue;
            }
            CollectionsState.Entry entry = CollectionsState.get(player.server).entry(player.getUUID());
            for (String collectionId : dirty.getValue()) {
                CollectionsPayloads.sendTo(player,
                        new dev.projecteclipse.eclipse.network.collections.S2CCollectionDeltaPayload(
                                collectionId, entry.count(collectionId)));
            }
        }
    }

    // ------------------------------------------------------------------
    // Query / admin surface (dev commands + gametests)
    // ------------------------------------------------------------------

    /**
     * Hard-sets a lifetime counter (dev/gametest surface) and runs the sweep — newly
     * crossed tiers grant exactly once; already-granted tiers never re-pay or revoke.
     *
     * @return {@code false} when the collection id is unknown
     */
    public static boolean setCount(ServerPlayer player, String collectionId, long count) {
        CollectionsConfig.Collection def = CollectionsConfig.current().byId(collectionId);
        if (def == null) {
            return false;
        }
        CollectionsState state = CollectionsState.get(player.server);
        CollectionsState.Entry entry = state.entry(player.getUUID());
        entry.counts.put(collectionId, Math.max(0L, count));
        state.setDirty();
        if (!sweep(player, def, entry, state)) {
            syncTo(player);
        }
        return true;
    }

    public static long countOf(MinecraftServer server, UUID uuid, String collectionId) {
        return CollectionsState.get(server).entry(uuid).count(collectionId);
    }

    public static int grantedTierOf(MinecraftServer server, UUID uuid, String collectionId) {
        return CollectionsState.get(server).entry(uuid).grantedTier(collectionId);
    }

    // ------------------------------------------------------------------
    // Lane index
    // ------------------------------------------------------------------

    private static List<Matcher> matchersFor(String lane) {
        CollectionsConfig.Snapshot cfg = CollectionsConfig.current();
        if (cfg != indexedSnapshot) {
            rebuildIndex(cfg);
        }
        return laneIndex.getOrDefault(lane, List.of());
    }

    private static synchronized void rebuildIndex(CollectionsConfig.Snapshot cfg) {
        if (cfg == indexedSnapshot) {
            return;
        }
        Map<String, List<Matcher>> index = new HashMap<>();
        for (CollectionsConfig.Collection def : cfg.collections()) {
            index.computeIfAbsent(def.lane(), ignored -> new ArrayList<>()).add(new Matcher(def));
        }
        Map<String, List<Matcher>> frozen = new HashMap<>();
        for (Map.Entry<String, List<Matcher>> entry : index.entrySet()) {
            frozen.put(entry.getKey(), List.copyOf(entry.getValue()));
        }
        laneIndex = Map.copyOf(frozen);
        indexedSnapshot = cfg;
    }

    /**
     * Pre-split id matcher for one collection: exact registry ids plus {@code #tag}
     * entries materialized as block/entity/item tag keys (only the lane-relevant kind is
     * ever consulted; {@code TagKey.create} interns, so building all three is free).
     */
    private record Matcher(CollectionsConfig.Collection def, Set<String> exactIds,
            List<TagKey<Block>> blockTags, List<TagKey<EntityType<?>>> entityTags,
            List<TagKey<Item>> itemTags) {

        Matcher(CollectionsConfig.Collection def) {
            this(def, splitExact(def), splitTags(def, Registries.BLOCK),
                    splitTags(def, Registries.ENTITY_TYPE), splitTags(def, Registries.ITEM));
        }

        private static Set<String> splitExact(CollectionsConfig.Collection def) {
            Set<String> exact = new HashSet<>();
            for (String id : def.ids()) {
                if (!id.startsWith("#")) {
                    exact.add(id);
                }
            }
            return Set.copyOf(exact);
        }

        private static <T> List<TagKey<T>> splitTags(CollectionsConfig.Collection def,
                net.minecraft.resources.ResourceKey<? extends net.minecraft.core.Registry<T>> registry) {
            List<TagKey<T>> tags = new ArrayList<>();
            for (String id : def.ids()) {
                if (id.startsWith("#")) {
                    ResourceLocation tagId = ResourceLocation.tryParse(id.substring(1));
                    if (tagId != null) {
                        tags.add(TagKey.create(registry, tagId));
                    }
                }
            }
            return List.copyOf(tags);
        }

        boolean matchesBlock(BlockState state) {
            if (exactIds.contains(BuiltInRegistries.BLOCK.getKey(state.getBlock()).toString())) {
                return true;
            }
            for (TagKey<Block> tag : blockTags) {
                if (state.is(tag)) {
                    return true;
                }
            }
            return false;
        }

        boolean matchesEntity(LivingEntity victim) {
            if (exactIds.contains(BuiltInRegistries.ENTITY_TYPE.getKey(victim.getType()).toString())) {
                return true;
            }
            for (TagKey<EntityType<?>> tag : entityTags) {
                if (victim.getType().is(tag)) {
                    return true;
                }
            }
            return false;
        }

        boolean matchesStack(ItemStack stack) {
            if (exactIds.contains(BuiltInRegistries.ITEM.getKey(stack.getItem()).toString())) {
                return true;
            }
            for (TagKey<Item> tag : itemTags) {
                if (stack.is(tag)) {
                    return true;
                }
            }
            return false;
        }
    }
}
