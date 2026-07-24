package dev.projecteclipse.eclipse.awards;

import java.text.DecimalFormat;
import java.text.DecimalFormatSymbols;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.analytics.AnalyticsApi;
import dev.projecteclipse.eclipse.analytics.AnalyticsKeys;
import dev.projecteclipse.eclipse.core.config.ReloadHooks;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.economy.ShardEconomy;
import dev.projecteclipse.eclipse.network.S2CAwardRevealPayload;
import dev.projecteclipse.eclipse.offering.OfferingService;
import dev.projecteclipse.eclipse.offering.OfferingState;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.skills.SkillsApi;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/** Daily award selection, resolution, reward delivery and reveal transport. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class AwardService {
    private record Materialized(AwardConfig.Category config, String metric, String target) {}

    // statics reset on ServerStopped
    private static final AtomicBoolean SIGNALS_REGISTERED = new AtomicBoolean();
    /** ReloadHooks entries live for the JVM; do not duplicate one on each integrated-server save. */
    private static final AtomicBoolean RELOAD_HOOK_REGISTERED = new AtomicBoolean();

    private AwardService() {}

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        if (RELOAD_HOOK_REGISTERED.compareAndSet(false, true)) {
            ReloadHooks.register("awards", AwardConfig::reload);
        }
        AwardConfig.reload();
        if (SIGNALS_REGISTERED.compareAndSet(false, true)) {
            EclipseSignals.onDayRollover(AwardService::onDayRollover);
        }
        // Rewards are removed from the pending ledger before application, so a server restart
        // with players already present (integrated server) safely resumes delivery.
        for (ServerPlayer player : event.getServer().getPlayerList().getPlayers()) {
            deliverPending(player);
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        SIGNALS_REGISTERED.set(false);
        AwardConfig.invalidate();
    }

    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        deliverPending(player);
        AwardsState state = AwardsState.get(player.server);
        int latest = state.latestResolvedDay();
        if (latest > 0 && !state.hasSeenReveal(player.getUUID(), latest)) {
            state.resolved(latest).ifPresent(day -> {
                PacketDistributor.sendToPlayer(player, payload(day));
                state.markRevealSeen(player.getUUID(), latest);
            });
        }
    }

    private static void onDayRollover(MinecraftServer server, int endedDay, int newDay,
            EclipseSignals.DayRolloverPhase phase) {
        if (phase == EclipseSignals.DayRolloverPhase.PRE) {
            // Explicitly settle offerings first: listener registration order is not an API, and
            // the fixed best-offering reveal must be present regardless of class scan order.
            OfferingService.resolveDay(server, endedDay);
            resolveDay(server, endedDay);
        } else {
            // POST runs after applyDayTriggers (the expansion sequence's server-side start). P2
            // may call sendRevealNow again at the actual cinematic completion seam.
            sendRevealNow(server);
        }
    }

    /**
     * Idempotently snapshots analytics and grants/queues all rewards for one ended day.
     * The resolved record is committed before any reward delivery, preventing repeated PRE
     * signals or catch-up retries from granting twice.
     */
    public static AwardsState.ResolvedDay resolveDay(MinecraftServer server, int day) {
        AwardsState state = AwardsState.get(server);
        var existing = state.resolved(day);
        if (existing.isPresent()) {
            queueResolvedRewards(server, existing.get());
            return existing.get();
        }

        AwardConfig.Data config = AwardConfig.get();
        List<Materialized> selected = select(server, day);
        List<String> chosenIds = selected.stream().map(category -> category.config().id()).toList();
        List<AwardsState.CategoryResult> results = new ArrayList<>();
        List<AwardsState.RewardGrant> rewards = new ArrayList<>();
        Set<UUID> universe = AnalyticsApi.onlineOrKnownUuids(server, day);

        for (Materialized category : selected) {
            List<AwardMath.Candidate> candidates = new ArrayList<>();
            for (UUID uuid : universe) {
                long playtime = AnalyticsApi.value(server, day, uuid, AnalyticsKeys.PLAYTIME_S);
                if (playtime < config.minPlaytimeSeconds()) {
                    continue;
                }
                candidates.add(new AwardMath.Candidate(uuid,
                        AnalyticsApi.value(server, day, uuid, category.metric())));
            }
            AwardMath.Resolution resolution = AwardMath.resolve(candidates, category.config().order());
            if (!resolution.hasWinner()) {
                continue;
            }
            AwardConfig.Reward full = category.config().reward(config.rewardTables());
            AwardConfig.Reward share = full.split(resolution.winners().size());
            String titleEn = replaceTarget(category.config().title().en(), category.target());
            String titleDe = replaceTarget(localized(category.config().title()), category.target());
            String displayValue = displayValue(category.metric(), resolution.bestValue());
            String statEn = replaceTarget(category.config().statLine().en(), category.target())
                    .replace("{value}", displayValue);
            String statDe = replaceTarget(localized(category.config().statLine()), category.target())
                    .replace("{value}", displayValue);
            results.add(new AwardsState.CategoryResult(category.config().id(), category.metric(),
                    titleEn, titleDe, statEn, statDe,
                    rewardLine(share, false), rewardLine(share, true),
                    resolution.candidates(), resolution.winners()));
            for (UUID winner : resolution.winners()) {
                String rewardId = "award:" + day + ":" + category.config().id() + ":" + winner;
                rewards.add(new AwardsState.RewardGrant(
                        winner, AwardsState.PendingReward.of(rewardId, share)));
            }
        }

        OfferingState.DayResult offering = OfferingService.resolveDay(server, day);
        if (!offering.winners().isEmpty()) {
            results.add(OfferingService.toAwardCategory(offering));
            chosenIds = new ArrayList<>(chosenIds);
            chosenIds.add("best_offering");
        }

        AwardsState.ResolvedDay resolved = new AwardsState.ResolvedDay(day, chosenIds, results, rewards);
        if (!state.putResolved(resolved)) {
            resolved = state.resolved(day).orElse(resolved);
        }
        queueResolvedRewards(server, resolved);
        EclipseMod.LOGGER.info("Resolved daily awards for day {}: {} chosen, {} revealed categories",
                day, chosenIds.size(), results.size());
        return resolved;
    }

    /** Alias frozen for the P5 command surface. */
    public static AwardsState.ResolvedDay resolveNow(MinecraftServer server, int day) {
        return resolveDay(server, day);
    }

    /**
     * Deterministic operator preview. This never persists a result or grants a reward; output
     * must remain permission-gated because categories are intentionally hidden from players.
     */
    public static List<String> preview(MinecraftServer server, int day) {
        return select(server, day).stream()
                .map(category -> category.config().id() + " [" + category.metric() + "]")
                .toList();
    }

    /** Persisted dev reroll; resolved days are immutable to preserve reward idempotence. */
    public static int reroll(MinecraftServer server, int day) {
        AwardsState state = AwardsState.get(server);
        if (state.resolved(day).isPresent()) {
            return -2;
        }
        return state.reroll(day, AwardConfig.get().maxRerollsPerDay());
    }

    /** Public expansion-sequence seam: broadcasts the latest frozen reveal immediately. */
    public static void sendRevealNow(MinecraftServer server) {
        AwardsState state = AwardsState.get(server);
        int day = state.latestResolvedDay();
        if (day <= 0) {
            return;
        }
        state.resolved(day).ifPresent(resolved -> {
            PacketDistributor.sendToAllPlayers(payload(resolved));
            for (ServerPlayer player : server.getPlayerList().getPlayers()) {
                state.markRevealSeen(player.getUUID(), day);
                player.playNotifySound(EclipseSounds.AWARD_STING.get(), SoundSource.MASTER, 0.8F, 1.0F);
            }
        });
    }

    public static void queueReward(MinecraftServer server, UUID player, String id, AwardConfig.Reward reward) {
        queueReward(server, player, AwardsState.PendingReward.of(id, reward));
    }

    private static void queueReward(MinecraftServer server, UUID player, AwardsState.PendingReward reward) {
        if (!AwardsState.get(server).queue(player, reward)) {
            return;
        }
        ServerPlayer online = server.getPlayerList().getPlayer(player);
        if (online != null) {
            deliverPending(online);
        }
    }

    /** Repairs queue writes from the frozen resolution; stable ids make this safe on every retry. */
    private static void queueResolvedRewards(MinecraftServer server, AwardsState.ResolvedDay resolved) {
        for (AwardsState.RewardGrant grant : resolved.rewardGrants()) {
            queueReward(server, grant.player(), grant.reward());
        }
    }

    /** Claims every queued award/offering reward for this player (login and immediate-online path). */
    public static int deliverPending(ServerPlayer player) {
        AwardsState state = AwardsState.get(player.server);
        List<AwardsState.PendingReward> rewards = List.copyOf(state.pending(player.getUUID()));
        int delivered = 0;
        for (AwardsState.PendingReward reward : rewards) {
            List<ItemStack> items = materializeItems(reward.items());
            // The durable id is written before any player-visible grant. Resolve repair and
            // login retries therefore cannot apply the same stable reward id twice.
            if (!state.claim(player.getUUID(), reward.id())) {
                continue;
            }
            if (reward.skillXp() > 0) {
                SkillsApi.addXp(player, "award", reward.skillXp());
            }
            if (reward.shards() > 0) {
                ShardEconomy.addShards(player, reward.shards());
            }
            for (ItemStack item : items) {
                giveItem(player, item);
            }
            delivered++;
        }
        return delivered;
    }

    /** Bilingual literal line baked into the secret reveal payload. */
    public static String rewardLine(AwardConfig.Reward reward, boolean german) {
        List<String> parts = new ArrayList<>();
        if (reward.skillXp() > 0) {
            parts.add(reward.skillXp() + (german ? " Skill-EP" : " Skill XP"));
        }
        if (reward.shards() > 0) {
            parts.add(reward.shards() + (german ? " Umbral-Splitter" : " Umbral Shards"));
        }
        for (AwardConfig.ItemReward item : reward.items()) {
            parts.add(item.count() + "× " + humanize(item.id()));
        }
        if (parts.isEmpty()) {
            return german ? "Ehre ohne materiellen Lohn" : "Honour without material reward";
        }
        return (german ? "Belohnt mit " : "Rewarded with ") + String.join(", ", parts);
    }

    private static List<Materialized> select(MinecraftServer server, int day) {
        AwardConfig.Data config = AwardConfig.get();
        AwardsState state = AwardsState.get(server);
        int nonce = state.rerollNonce(day);
        long seed = AwardMath.seed(server.overworld().getSeed(), day, nonce);
        Set<String> keys = AnalyticsApi.keys(server, day);
        List<Materialized> pool = new ArrayList<>();
        Map<String, Materialized> byId = new HashMap<>();
        for (AwardConfig.Category category : config.categories()) {
            Materialized materialized = materialize(category, keys, seed);
            if (materialized != null) {
                pool.add(materialized);
                byId.put(category.id(), materialized);
            }
        }
        List<String> picked = AwardMath.pick(seed, pool.stream().map(value -> value.config().choice()).toList(),
                config.themesFor(day), config.categoriesPerDay());
        return picked.stream().map(byId::get).filter(java.util.Objects::nonNull).toList();
    }

    private static Materialized materialize(AwardConfig.Category category, Set<String> keys, long seed) {
        if (category.metric().contains("$mob")) {
            List<String> available = keys.stream()
                    .filter(key -> key.startsWith(AnalyticsKeys.PREFIX_KILL)
                            && key.length() > AnalyticsKeys.PREFIX_KILL.length())
                    .sorted().toList();
            if (available.isEmpty()) {
                return null;
            }
            String metric = stableChoice(available, seed ^ category.id().hashCode());
            return new Materialized(category, metric, humanize(metric.substring(AnalyticsKeys.PREFIX_KILL.length())));
        }
        if (category.metric().contains("$ore")) {
            List<String> available = category.orePool().stream()
                    .map(id -> AnalyticsKeys.PREFIX_MINE + id)
                    .filter(keys::contains)
                    .sorted().toList();
            if (available.isEmpty()) {
                return null;
            }
            String metric = stableChoice(available, seed ^ category.id().hashCode());
            return new Materialized(category, metric, humanize(metric.substring(AnalyticsKeys.PREFIX_MINE.length())));
        }
        return new Materialized(category, category.metric(), "");
    }

    private static String stableChoice(List<String> values, long seed) {
        return values.get((int) Math.floorMod(seed ^ (seed >>> 32), values.size()));
    }

    private static S2CAwardRevealPayload payload(AwardsState.ResolvedDay resolved) {
        List<S2CAwardRevealPayload.Category> categories = new ArrayList<>();
        for (AwardsState.CategoryResult result : resolved.categories()) {
            List<S2CAwardRevealPayload.Candidate> candidates = result.candidates().stream()
                    .map(candidate -> new S2CAwardRevealPayload.Candidate(candidate.uuid(), candidate.value()))
                    .toList();
            // A1's checked-in frozen payload has no standalone statLine field despite the P3
            // handoff requiring one. Preserve both literals losslessly: P3 splits the first
            // newline into categoryLine/statLine until the payload owner lands the explicit field.
            categories.add(new S2CAwardRevealPayload.Category(result.id(),
                    result.titleEn() + "\n" + result.statLineEn(),
                    result.titleDe() + "\n" + result.statLineDe(),
                    result.rewardLineEn(), result.rewardLineDe(), candidates, result.winners()));
        }
        return new S2CAwardRevealPayload(resolved.day(), categories);
    }

    private static List<ItemStack> materializeItems(List<AwardConfig.ItemReward> rewards) {
        List<ItemStack> items = new ArrayList<>();
        for (AwardConfig.ItemReward reward : rewards) {
            ResourceLocation id = ResourceLocation.tryParse(reward.id());
            Item item = id == null ? null : BuiltInRegistries.ITEM.getOptional(id).orElse(null);
            if (item == null || reward.count() <= 0) {
                EclipseMod.LOGGER.warn("Skipping unknown/empty award item {} x{}", reward.id(), reward.count());
                continue;
            }
            int remaining = reward.count();
            int maxStackSize = new ItemStack(item).getMaxStackSize();
            while (remaining > 0) {
                int count = Math.min(remaining, maxStackSize);
                items.add(new ItemStack(item, count));
                remaining -= count;
            }
        }
        return items;
    }

    private static void giveItem(ServerPlayer player, ItemStack stack) {
        if (!player.getInventory().add(stack)) {
            player.drop(stack, false);
        }
    }

    private static String displayValue(String metric, long raw) {
        if (AnalyticsKeys.DIST_CM.equals(metric)) {
            return decimal(raw / 100.0D) + " m";
        }
        if (AnalyticsKeys.DMG_DEALT.equals(metric) || AnalyticsKeys.DMG_TAKEN.equals(metric)) {
            return decimal(raw / 10.0D);
        }
        if (AnalyticsKeys.DEPTH_MIN_Y.equals(metric)) {
            return "Y=" + (4096L - raw);
        }
        return Long.toString(raw);
    }

    private static String decimal(double value) {
        DecimalFormat format = new DecimalFormat("0.#", DecimalFormatSymbols.getInstance(Locale.ROOT));
        return format.format(value);
    }

    private static String localized(dev.projecteclipse.eclipse.core.config.Localized value) {
        return value.de() == null || value.de().isBlank() ? value.en() : value.de();
    }

    private static String replaceTarget(String line, String target) {
        return line.replace("$TARGET", target);
    }

    private static String humanize(String namespaced) {
        int colon = namespaced.indexOf(':');
        String path = colon >= 0 ? namespaced.substring(colon + 1) : namespaced;
        String[] words = path.replace('/', '_').split("_");
        StringBuilder result = new StringBuilder();
        for (String word : words) {
            if (word.isEmpty()) {
                continue;
            }
            if (!result.isEmpty()) {
                result.append(' ');
            }
            result.append(Character.toUpperCase(word.charAt(0))).append(word.substring(1));
        }
        return result.toString();
    }
}
