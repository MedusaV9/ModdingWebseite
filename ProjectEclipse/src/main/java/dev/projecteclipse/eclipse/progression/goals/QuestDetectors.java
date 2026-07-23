package dev.projecteclipse.eclipse.progression.goals;

import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.state.BlockState;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.BabyEntitySpawnEvent;
import net.neoforged.neoforge.event.entity.living.LivingDamageEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;

/**
 * Signal-driven quest detectors (plans_v3 P4 §2.2 / §3.3 "detectors"). All progress arrives
 * either through {@code core/signal/EclipseSignals} fan-outs (registered once per server
 * start from {@link QuestEngine#onServerStarted}) or through the two NeoForge events this
 * class owns per the §2.2 event-ownership table: {@link BabyEntitySpawnEvent}
 * ({@code breed_animals} — analytics only counts, the trigger is B2's) and
 * {@link LivingDamageEvent.Post} (night-watcher damage flag only — analytics owns the
 * damage counters). Polled trigger types live in {@link QuestEngine#pollPlayer}; the
 * night-window state machine lives here but is stepped by the engine's shared 20t poll.
 *
 * <p>Every handler is O(active specs of that trigger type) with an empty-list fast path,
 * so days without e.g. {@code place_blocks} goals pay one map lookup per placement.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class QuestDetectors {
    /** Signals are cleared by A1 on ServerStopped, so registration re-arms per server start. */
    private static boolean signalsRegistered = false;
    // statics reset on ServerStopped
    private static boolean nightActive = false;
    /** Players online at nightfall who have neither taken damage nor logged out since. */
    private static final Set<UUID> NIGHT_ELIGIBLE = new HashSet<>();

    private QuestDetectors() {}

    // --- lifecycle (driven by QuestEngine) ---

    static void registerSignalListeners(MinecraftServer server) {
        if (signalsRegistered) {
            return;
        }
        signalsRegistered = true;
        EclipseSignals.onNaturalBlockMined(QuestDetectors::handleBlockMined);
        EclipseSignals.onBlockPlaced(QuestDetectors::handleBlockPlaced);
        EclipseSignals.onMobKilled(QuestDetectors::handleMobKilled);
        EclipseSignals.onItemCrafted(QuestDetectors::handleItemCrafted);
        EclipseSignals.onItemSmelted(QuestDetectors::handleItemSmelted);
        EclipseSignals.onChunkExplored(QuestDetectors::handleChunkExplored);
        EclipseSignals.onBiomeVisited(QuestDetectors::handleBiomeVisited);
        EclipseSignals.onAltarDeposit(QuestDetectors::handleAltarDeposit);
        EclipseSignals.onSkillLevelUp(QuestDetectors::handleSkillLevelUp);
        EclipseSignals.onDayRollover((srv, endedDay, newDay, phase) -> {
            if (phase == EclipseSignals.DayRolloverPhase.POST) {
                // Assignment on POST rollover (§3.3): resolve + assign + flush in one pass.
                QuestEngine.runPollNow(srv);
            }
        });
        EclipseMod.LOGGER.debug("Quest detectors registered on EclipseSignals");
    }

    static void resetOnServerStopped() {
        signalsRegistered = false;
        nightActive = false;
        NIGHT_ELIGIBLE.clear();
    }

    /**
     * Gametest hook: {@code HarnessSmokeTest.signalsDispatchAndClear} wipes EVERY signal
     * listener mid-run ({@code EclipseSignals.clearAllListeners()}) and nothing re-arms the
     * service registrations afterwards. Signal-driven quest tests therefore start from a
     * deterministic clean slate: clear all, then re-register just the quest detectors.
     * Production never calls this — {@link QuestEngine#onServerStarted} is the real path.
     */
    public static void rearmSignalListenersForTest(MinecraftServer server) {
        EclipseSignals.clearAllListeners();
        signalsRegistered = false;
        registerSignalListeners(server);
    }

    // --- EclipseSignals listeners ---

    private static void handleBlockMined(ServerPlayer player, BlockState state, BlockPos pos) {
        QuestEngine.ResolvedDay day = QuestEngine.resolved(player.server);
        for (GoalSpec spec : day.ofType(TriggerType.MINE_BLOCK)) {
            if (QuestEngine.matchesBlock(state, spec.trigger().target())) {
                QuestEngine.increment(player.server, player, spec, 1L);
            }
        }
    }

    private static void handleBlockPlaced(ServerPlayer player, BlockState state, BlockPos pos) {
        QuestEngine.ResolvedDay day = QuestEngine.resolved(player.server);
        for (GoalSpec spec : day.ofType(TriggerType.PLACE_BLOCKS)) {
            if (QuestEngine.matchesBlock(state, spec.trigger().target())) {
                QuestEngine.increment(player.server, player, spec, 1L);
            }
        }
    }

    private static void handleMobKilled(ServerPlayer player, LivingEntity victim) {
        QuestEngine.ResolvedDay day = QuestEngine.resolved(player.server);
        for (GoalSpec spec : day.ofType(TriggerType.KILL_ENTITY)) {
            if (QuestEngine.matchesEntity(victim, spec.trigger().target())) {
                QuestEngine.increment(player.server, player, spec, 1L);
            }
        }
    }

    private static void handleItemCrafted(ServerPlayer player, ItemStack stack) {
        if (stack.isEmpty()) {
            return;
        }
        QuestEngine.ResolvedDay day = QuestEngine.resolved(player.server);
        for (GoalSpec spec : day.ofType(TriggerType.CRAFT_ITEM)) {
            if (QuestEngine.matchesItemStack(stack, spec.trigger().target())) {
                QuestEngine.increment(player.server, player, spec, stack.getCount());
            }
        }
    }

    private static void handleItemSmelted(ServerPlayer player, ItemStack stack) {
        if (stack.isEmpty()) {
            return;
        }
        QuestEngine.ResolvedDay day = QuestEngine.resolved(player.server);
        for (GoalSpec spec : day.ofType(TriggerType.SMELT_ITEM)) {
            if (QuestEngine.matchesItemStack(stack, spec.trigger().target())) {
                QuestEngine.increment(player.server, player, spec, stack.getCount());
            }
        }
    }

    private static void handleChunkExplored(ServerPlayer player, ChunkPos chunkPos) {
        QuestEngine.ResolvedDay day = QuestEngine.resolved(player.server);
        for (GoalSpec spec : day.ofType(TriggerType.EXPLORE_CHUNKS)) {
            QuestEngine.increment(player.server, player, spec, 1L);
        }
    }

    private static void handleBiomeVisited(ServerPlayer player, ResourceLocation biomeId) {
        MinecraftServer server = player.server;
        QuestEngine.ResolvedDay day = QuestEngine.resolved(server);
        List<GoalSpec> specs = day.ofType(TriggerType.VISIT_BIOMES);
        if (specs.isEmpty()) {
            return;
        }
        QuestState state = QuestState.get(server);
        UUID uuid = player.getUUID();
        for (GoalSpec spec : specs) {
            if (state.isPlayerDone(day.day, uuid, spec.id()) || state.isTeamDone(day.day, spec.id())) {
                continue;
            }
            String target = spec.trigger().target();
            if (target.isEmpty()) {
                // Distinct-count mode: progress = number of different biomes visited.
                int distinct = state.addDistinct(day.day, uuid, spec.id(), biomeId.toString());
                QuestEngine.raiseTo(server, player, spec, distinct);
            } else if (QuestEngine.matchesBiome(server, biomeId, target)) {
                QuestEngine.raiseTo(server, player, spec, spec.target());
            }
        }
    }

    private static void handleAltarDeposit(ServerPlayer player, ResourceLocation itemId, int count,
            EclipseSignals.AltarDepositPurpose purpose) {
        if (count <= 0) {
            return;
        }
        QuestEngine.ResolvedDay day = QuestEngine.resolved(player.server);
        for (GoalSpec spec : day.ofType(TriggerType.DEPOSIT_ALTAR)) {
            GoalSpec.Trigger trigger = spec.trigger();
            if (!trigger.purpose().isEmpty() && !trigger.purpose().equals(purpose.name())) {
                continue;
            }
            if (QuestEngine.matchesItemId(itemId, trigger.target())) {
                QuestEngine.increment(player.server, player, spec, count);
            }
        }
    }

    private static void handleSkillLevelUp(ServerPlayer player, int newLevel) {
        QuestEngine.ResolvedDay day = QuestEngine.resolved(player.server);
        for (GoalSpec spec : day.ofType(TriggerType.SKILL_LEVEL)) {
            // Progress mirrors the reached level (capped); completes when level >= count.
            QuestEngine.raiseTo(player.server, player, spec, Math.min(newLevel, spec.target()));
        }
    }

    // --- owned NeoForge events (§2.2 ownership table) ---

    @SubscribeEvent
    static void onBabySpawn(BabyEntitySpawnEvent event) {
        if (!(event.getCausedByPlayer() instanceof ServerPlayer player)
                || player.level().isClientSide()) {
            return;
        }
        QuestEngine.ResolvedDay day = QuestEngine.resolved(player.server);
        for (GoalSpec spec : day.ofType(TriggerType.BREED_ANIMALS)) {
            // Target filters on the child type; pre-spawn cancellation can null the child,
            // then parent A stands in (same species for every vanilla breed pair).
            LivingEntity subject = event.getChild() != null ? event.getChild() : event.getParentA();
            if (QuestEngine.matchesEntity(subject, spec.trigger().target())) {
                QuestEngine.increment(player.server, player, spec, 1L);
            }
        }
    }

    @SubscribeEvent
    static void onLivingDamagePost(LivingDamageEvent.Post event) {
        // Cheap flag for survive_night_no_damage — no quest lookups on the damage hot path.
        if (nightActive && event.getNewDamage() > 0.0F
                && event.getEntity() instanceof ServerPlayer player
                && !player.level().isClientSide()) {
            NIGHT_ELIGIBLE.remove(player.getUUID());
        }
    }

    @SubscribeEvent
    static void onPlayerLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        // "Online for the whole night": leaving mid-night forfeits tonight's credit.
        if (nightActive && event.getEntity() instanceof ServerPlayer player) {
            NIGHT_ELIGIBLE.remove(player.getUUID());
        }
    }

    // --- night watcher (stepped by QuestEngine's shared 20t poll) ---

    /**
     * Night-window state machine for {@code survive_night_no_damage}: arms at dusk with the
     * players online right then; damage or logout drops eligibility; at dawn every survivor
     * gains one night of progress. Idle (and disarmed) while no such spec is active today.
     */
    static void pollNightWindow(MinecraftServer server, QuestEngine.ResolvedDay day) {
        List<GoalSpec> specs = day.ofType(TriggerType.SURVIVE_NIGHT_NO_DAMAGE);
        if (specs.isEmpty()) {
            if (nightActive) {
                nightActive = false;
                NIGHT_ELIGIBLE.clear();
            }
            return;
        }
        boolean night = server.overworld().isNight();
        if (night == nightActive) {
            return;
        }
        nightActive = night;
        if (night) {
            NIGHT_ELIGIBLE.clear();
            for (ServerPlayer player : server.getPlayerList().getPlayers()) {
                NIGHT_ELIGIBLE.add(player.getUUID());
            }
            return;
        }
        creditSurvivors(server, specs);
    }

    /** Dawn: credit the survivors that are still online and still eligible. */
    private static void creditSurvivors(MinecraftServer server, List<GoalSpec> specs) {
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            if (!NIGHT_ELIGIBLE.contains(player.getUUID())) {
                continue;
            }
            for (GoalSpec spec : specs) {
                QuestEngine.increment(server, player, spec, 1L);
            }
        }
        NIGHT_ELIGIBLE.clear();
    }

    /** Gametest hook: pretends dusk fell right now with the given players online. */
    public static void forceNightStartForTest(List<ServerPlayer> online) {
        nightActive = true;
        NIGHT_ELIGIBLE.clear();
        for (ServerPlayer player : online) {
            NIGHT_ELIGIBLE.add(player.getUUID());
        }
    }

    /** Gametest hook: whether the player would currently be credited at dawn. */
    public static boolean isNightEligibleForTest(UUID uuid) {
        return nightActive && NIGHT_ELIGIBLE.contains(uuid);
    }

    /**
     * Gametest hook: forces the dawn transition NOW (credits eligible survivors against the
     * current day's survive specs), bypassing the real overworld time check.
     */
    public static void forceDawnForTest(MinecraftServer server) {
        nightActive = false;
        creditSurvivors(server, QuestEngine.resolved(server).ofType(TriggerType.SURVIVE_NIGHT_NO_DAMAGE));
    }
}
