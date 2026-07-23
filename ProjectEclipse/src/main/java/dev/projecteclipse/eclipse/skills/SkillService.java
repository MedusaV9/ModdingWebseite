package dev.projecteclipse.eclipse.skills;

import java.util.HashSet;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.buffs.TimedBuffApi;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.network.C2SSkillNodeBuyPayload;
import dev.projecteclipse.eclipse.network.S2CSkillStatePayload;
import dev.projecteclipse.eclipse.network.S2CSkillTreePayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.BabyEntitySpawnEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.entity.player.TradeWithVillagerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.server.ServerLifecycleHooks;

/**
 * Skill engine (R3, plan §2.3): consumes {@link EclipseSignals} for action XP, runs the
 * add-XP pipeline (source scales → S2 → buff → secret multiplier → remainder → daily caps →
 * level-ups), owns node purchases and the client sync payloads.
 *
 * <p>Multiplier order (frozen, documented for gametests): {@code base × sourceScale(T1/V2/U6)
 * × (1 + S2) × TimedBuffApi("skill_xp") × secretMultiplier}. Negative XP (death penalty)
 * skips every multiplier and every cap; lifetime XP floors at 0. Points are granted once per
 * level via {@code lastLevelSeen}, which never decreases even if XP is reduced.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class SkillService {
    private static final int SYNC_INTERVAL_TICKS = 20;

    /** Frozen source keys (also the dailyCaps keys in skills.json). */
    public static final String SOURCE_MINE = "mine";
    public static final String SOURCE_KILL = "kill";
    public static final String SOURCE_EXPLORE = "explore";
    public static final String SOURCE_CRAFT = "craft";
    public static final String SOURCE_SMELT = "smelt";
    public static final String SOURCE_TRADE = "trade";
    public static final String SOURCE_BREED = "breed";
    public static final String SOURCE_ALTAR = "altar";
    public static final String SOURCE_QUEST = "quest";
    public static final String SOURCE_ADVANCEMENT = "advancement";
    public static final String SOURCE_DEATH = "death";
    public static final String SOURCE_ADMIN = "admin";

    // statics reset on ServerStopped
    private static final AtomicBoolean SIGNALS_REGISTERED = new AtomicBoolean();
    // statics reset on ServerStopped
    private static final Set<UUID> DIRTY = java.util.concurrent.ConcurrentHashMap.newKeySet();
    // statics reset on ServerStopped
    private static int tickCounter = 0;
    /** JVM-lifetime guard — ReloadHooks entries survive across saves by design. */
    private static final AtomicBoolean RELOAD_HOOK_REGISTERED = new AtomicBoolean();

    private SkillService() {}

    // ------------------------------------------------------------------
    // Lifecycle + signal wiring
    // ------------------------------------------------------------------

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        SkillConfig.get();
        SkillTreeConfig.get();
        if (RELOAD_HOOK_REGISTERED.compareAndSet(false, true)) {
            dev.projecteclipse.eclipse.core.config.ReloadHooks.register("skills", SkillService::onConfigReload);
        }
        if (SIGNALS_REGISTERED.compareAndSet(false, true)) {
            EclipseSignals.onNaturalBlockMined((player, state, pos) -> {
                // Signal is natural-only by contract (analytics filters via PlacedBlockTracker);
                // the belt-and-braces re-check keeps XP safe if a foreign caller misfires.
                if (SkillPerks.isPlaced(player.serverLevel(), pos)) {
                    return;
                }
                addXp(player, SOURCE_MINE, SkillConfig.get().mine().forBlock(state));
                SkillPerks.onNaturalOreMined(player, state, pos);
            });
            EclipseSignals.onMobKilled((player, victim) -> {
                addXp(player, SOURCE_KILL, SkillConfig.get().kill().forEntity(victim));
                SkillPerks.onMobKilled(player, victim);
            });
            EclipseSignals.onPlayerDeath((victim, killer) -> addXp(victim, SOURCE_DEATH,
                    SkillConfig.get().death()));
            EclipseSignals.onItemCrafted((player, stack) -> addXp(player, SOURCE_CRAFT,
                    SkillConfig.get().craft().forItem(stack) * Math.max(1, stack.getCount())));
            EclipseSignals.onItemSmelted((player, stack) -> {
                float base = SkillConfig.get().smelt().forItem(stack) * Math.max(1, stack.getCount());
                addXp(player, SOURCE_SMELT, base);
                if (SkillPerks.rollSmeltDouble(player)) {
                    addXp(player, SOURCE_SMELT, base);
                }
            });
            EclipseSignals.onChunkExplored((player, chunkPos) -> addXp(player, SOURCE_EXPLORE,
                    SkillConfig.get().exploreChunk()));
            EclipseSignals.onBiomeVisited((player, biomeId) -> {
                float base = SkillConfig.get().visitNewBiome();
                base += SkillPerks.firstBiomeBonus(player);
                addXp(player, SOURCE_EXPLORE, base);
            });
            EclipseSignals.onAltarDeposit((player, itemId, count, purpose) -> {
                SkillConfig.Data cfg = SkillConfig.get();
                float base = purpose == EclipseSignals.AltarDepositPurpose.SHARD_BANK
                        ? cfg.shardBankedEach() * count
                        // 1 value point per item: secret offering values must never be
                        // observable through the XP bar (anonymity rule 7).
                        : cfg.altarDepositPerValuePoint() * count;
                addXp(player, SOURCE_ALTAR, base);
            });
            EclipseSignals.onQuestCompleted((player, spec, scope) -> {
                SkillConfig.Data cfg = SkillConfig.get();
                float bonus = switch (spec.kind()) {
                    case 0 -> cfg.questMain();
                    case 1 -> cfg.questSide();
                    default -> cfg.questPersonal();
                };
                if (bonus > 0.0F) {
                    // Per-spec reward.skillXp is granted by P4-B2's QuestEngine through
                    // SkillsApi; this is the optional flat bonus on top (0 = disabled).
                    addXp(player, SOURCE_QUEST, bonus);
                }
            });
            EclipseMod.LOGGER.info("SkillService registered {} signal listeners", 9);
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        SIGNALS_REGISTERED.set(false);
        DIRTY.clear();
        tickCounter = 0;
        SkillConfig.invalidate();
        SkillTreeConfig.invalidate();
        SkillPerks.resetStatics();
    }

    /** ReloadHooks body: re-read both configs, then resync tree + state to everyone. */
    private static void onConfigReload() {
        SkillConfig.reload();
        SkillTreeConfig.reload();
        MinecraftServer server = ServerLifecycleHooks.getCurrentServer();
        if (server == null) {
            return;
        }
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            sendTree(player);
            syncTo(player);
        }
    }

    // ------------------------------------------------------------------
    // Low-frequency vanilla events without an EclipseSignals lane (trade/breed).
    // Analytics (B5) and goals (B2) own their own subscribers for counters; XP is
    // granted here so the earn table's trade/breed values are actually earnable.
    // Migrate to signals if A1 adds lanes in a later wave (wiring note).
    // ------------------------------------------------------------------

    @SubscribeEvent
    static void onTrade(TradeWithVillagerEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            addXp(player, SOURCE_TRADE, SkillConfig.get().trade());
        }
    }

    @SubscribeEvent
    static void onBreed(BabyEntitySpawnEvent event) {
        if (event.getCausedByPlayer() instanceof ServerPlayer player) {
            addXp(player, SOURCE_BREED, SkillConfig.get().breed());
        }
    }

    // ------------------------------------------------------------------
    // XP pipeline
    // ------------------------------------------------------------------

    /**
     * Grants (or removes) skill XP. Positive amounts run the full multiplier chain and the
     * per-source daily soft cap; negative amounts are applied raw (multipliers must never
     * amplify punishment — that would leak secret multipliers) and total XP floors at 0.
     *
     * @return whole XP points actually applied (after remainder carry; 0 when capped out)
     */
    public static int addXp(ServerPlayer player, String source, float baseAmount) {
        if (player == null || baseAmount == 0.0F || Float.isNaN(baseAmount)) {
            return 0;
        }
        MinecraftServer server = player.server;
        SkillState state = SkillState.get(server);
        SkillState.Entry entry = state.entry(player.getUUID());

        int applied;
        if (baseAmount < 0.0F) {
            long before = entry.totalXp;
            entry.totalXp = Math.max(0L, entry.totalXp + Math.round(baseAmount));
            applied = (int) (entry.totalXp - before);
        } else {
            float scaled = baseAmount * sourceScale(player, entry, source);
            scaled *= 1.0F + SkillTree.effectTotal(SkillTreeConfig.get().nodes(), entry.ownedNodes, "skill_xp_pct");
            scaled *= TimedBuffApi.Holder.get().multiplier(server, "skill_xp");
            scaled *= entry.secretMultiplier;
            if (scaled <= 0.0F || Float.isNaN(scaled) || Float.isInfinite(scaled)) {
                return 0;
            }

            entry.xpRemainder += scaled;
            int whole = (int) entry.xpRemainder;
            if (whole <= 0) {
                state.setDirty();
                return 0;
            }
            entry.xpRemainder -= whole;

            whole = applyDailyCap(server, entry, source, whole);
            if (whole <= 0) {
                state.setDirty();
                return 0;
            }
            entry.totalXp += whole;
            applied = whole;
        }

        state.setDirty();
        handleLevelUps(player, entry);
        markDirty(player.getUUID());
        return applied;
    }

    /** Source-specific node scales: T1 (mine), V2 (explore), U6 (kill during night events). */
    private static float sourceScale(ServerPlayer player, SkillState.Entry entry, String source) {
        var nodes = SkillTreeConfig.get().nodes();
        float scale = 1.0F;
        switch (source) {
            case SOURCE_MINE -> scale += SkillTree.effectTotal(nodes, entry.ownedNodes, "mine_skill_xp_pct");
            case SOURCE_EXPLORE -> scale += SkillTree.effectTotal(nodes, entry.ownedNodes, "explore_xp_pct");
            case SOURCE_KILL -> {
                if (!EclipseWorldState.NIGHT_EVENT_NONE.equals(
                        EclipseWorldState.get(player.server).getActiveNightEvent())) {
                    scale += SkillTree.effectTotal(nodes, entry.ownedNodes, "night_event_kill_xp_pct");
                }
            }
            default -> { }
        }
        return scale;
    }

    /** Clamps a grant to the remaining per-source daily budget (config {@code dailyCaps}). */
    private static int applyDailyCap(MinecraftServer server, SkillState.Entry entry, String source, int amount) {
        float cap = SkillConfig.get().dailyCap(source);
        if (cap == Float.MAX_VALUE) {
            return amount;
        }
        int day = EclipseWorldState.get(server).getDay();
        if (entry.capDay != day) {
            entry.capDay = day;
            entry.capUsed.clear();
        }
        float used = entry.capUsed.getOrDefault(source, 0.0F);
        int allowed = (int) Math.max(0.0F, Math.min(amount, cap - used));
        if (allowed > 0) {
            entry.capUsed.merge(source, (float) allowed, Float::sum);
        }
        return allowed;
    }

    /** Public sweep+sync for admin XP writes ({@code SkillsApi.setTotalXp}). */
    public static void runLevelSweepAndSync(ServerPlayer player) {
        handleLevelUps(player, SkillState.get(player.server).entry(player.getUUID()));
        syncTo(player);
    }

    /** Level-up sweep: +1 point per level (via lastLevelSeen), cue, signal, advancements. */
    private static void handleLevelUps(ServerPlayer player, SkillState.Entry entry) {
        SkillCurve.Params curve = SkillConfig.get().curve();
        int level = SkillCurve.levelForXp(entry.totalXp, curve);
        if (level <= entry.lastLevelSeen) {
            return;
        }
        int from = entry.lastLevelSeen;
        entry.lastLevelSeen = level;
        SkillState.get(player.server).setDirty();
        for (int reached = from + 1; reached <= level; reached++) {
            EclipseSignals.fireSkillLevelUp(player, reached);
            AdvancementXpBridge.onSkillLevelReached(player, reached);
        }
        player.serverLevel().playSound(null, player.blockPosition(),
                EclipseSounds.SKILL_LEVELUP.get(), SoundSource.PLAYERS, 0.8F, 1.0F);
        player.displayClientMessage(Component.translatable("message.eclipse.skill.levelup", level), true);
        syncTo(player);
    }

    // ------------------------------------------------------------------
    // Node purchase (payload entry + /skills buy fallback)
    // ------------------------------------------------------------------

    /**
     * Server entry point for {@code C2SSkillNodeBuyPayload}. Wired from
     * {@code EclipsePayloads.handleSkillNodeBuy} (one-liner — see P4-B4 wiring doc).
     */
    public static void handleNodeBuy(C2SSkillNodeBuyPayload payload, ServerPlayer player) {
        buyNode(player, payload.nodeId());
    }

    /** Validates + executes a node purchase; feedback via action bar, cue on success. */
    public static SkillTree.BuyResult buyNode(ServerPlayer player, String nodeId) {
        SkillState state = SkillState.get(player.server);
        SkillState.Entry entry = state.entry(player.getUUID());
        SkillTreeConfig.Tree tree = SkillTreeConfig.get();
        SkillTree.BuyResult result = SkillTree.canBuy(tree.nodes(), entry.ownedNodes,
                entry.unspentPoints(), nodeId);
        if (result == SkillTree.BuyResult.OK) {
            SkillTreeConfig.Node node = tree.node(nodeId);
            entry.ownedNodes.add(nodeId);
            entry.spentPoints += node.cost();
            state.setDirty();
            player.serverLevel().playSound(null, player.blockPosition(),
                    EclipseSounds.SKILL_LEVELUP.get(), SoundSource.PLAYERS, 0.6F, 1.3F);
            player.displayClientMessage(Component.translatable("message.eclipse.skill.buy.success",
                    node.title().pick(dev.projecteclipse.eclipse.lang.LangService.locale(player))), true);
            syncTo(player);
        } else {
            player.displayClientMessage(Component.translatable(switch (result) {
                case ALREADY_OWNED -> "message.eclipse.skill.buy.owned";
                case MISSING_PREREQ -> "message.eclipse.skill.buy.missing_prereq";
                case NOT_ENOUGH_POINTS -> "message.eclipse.skill.buy.no_points";
                default -> "message.eclipse.skill.buy.unknown_node";
            }), true);
        }
        return result;
    }

    // ------------------------------------------------------------------
    // Client sync
    // ------------------------------------------------------------------

    /** Queues a coalesced state resync (flushed at most every 20 ticks). */
    public static void markDirty(UUID uuid) {
        DIRTY.add(uuid);
    }

    /** Immediate full state payload to one player. {@code secretMultiplierActive} is ALWAYS false on wire. */
    public static void syncTo(ServerPlayer player) {
        SkillState.Entry entry = SkillState.get(player.server).entry(player.getUUID());
        SkillCurve.Params curve = SkillConfig.get().curve();
        int level = SkillCurve.levelForXp(entry.totalXp, curve);
        PacketDistributor.sendToPlayer(player, new S2CSkillStatePayload(
                level,
                entry.totalXp,
                SkillCurve.xpIntoLevel(entry.totalXp, level, curve),
                SkillCurve.xpForLevel(level + 1, curve),
                entry.totalPoints(),
                entry.unspentPoints(),
                java.util.List.copyOf(entry.ownedNodes),
                entry.procMsgEnabled,
                false));
        DIRTY.remove(player.getUUID());
    }

    /** Skill tree definition (not secret) — login + reload. */
    public static void sendTree(ServerPlayer player) {
        PacketDistributor.sendToPlayer(player, new S2CSkillTreePayload(SkillTreeConfig.get().clientJson()));
    }

    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            sendTree(player);
            syncTo(player);
        }
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
        Set<UUID> flush = new HashSet<>(DIRTY);
        for (UUID uuid : flush) {
            ServerPlayer player = event.getServer().getPlayerList().getPlayer(uuid);
            if (player != null) {
                syncTo(player);
            } else {
                DIRTY.remove(uuid);
            }
        }
    }
}
