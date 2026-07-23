package dev.projecteclipse.eclipse.progression.goals;

import java.util.List;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.skills.SkillsApi;
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
import net.neoforged.neoforge.event.entity.living.LivingDamageEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStoppingEvent;

/**
 * Signal-driven quest detectors (plans_v3 P4 §2.2 / §3.3 "detectors"). All progress arrives
 * either through {@code core/signal/EclipseSignals} fan-outs (registered once per server
 * start from {@link QuestEngine#onServerStarted}) or through
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
    private static boolean serverStopping = false;

    private QuestDetectors() {}

    // --- lifecycle (driven by QuestEngine) ---

    static void registerSignalListeners(MinecraftServer server) {
        serverStopping = false;
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
        EclipseSignals.onBreed(QuestDetectors::handleBreed);
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
        serverStopping = false;
    }

    /**
     * Gametest hook retained for existing tests. The shared signal bus stays intact; the
     * harness now unregisters only its own temporary listener.
     */
    public static void rearmSignalListenersForTest(MinecraftServer server) {
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

    /** Assignment/login backfill for players who already reached the configured level. */
    static void backfillSkillLevel(ServerPlayer player, GoalSpec spec) {
        int currentLevel = SkillsApi.getLevel(player.server, player.getUUID());
        QuestEngine.raiseTo(player.server, player, spec, Math.min(currentLevel, spec.target()));
    }

    private static void handleBreed(ServerPlayer player, LivingEntity childOrParent) {
        QuestEngine.ResolvedDay day = QuestEngine.resolved(player.server);
        for (GoalSpec spec : day.ofType(TriggerType.BREED_ANIMALS)) {
            if (QuestEngine.matchesEntity(childOrParent, spec.trigger().target())) {
                QuestEngine.increment(player.server, player, spec, 1L);
            }
        }
    }

    // --- owned NeoForge event (§2.2 ownership table) ---

    @SubscribeEvent
    static void onLivingDamagePost(LivingDamageEvent.Post event) {
        // Cheap flag for survive_night_no_damage — no quest lookups on the damage hot path.
        if (event.getNewDamage() > 0.0F
                && event.getEntity() instanceof ServerPlayer player
                && !player.level().isClientSide()) {
            int day = EclipseWorldState.get(player.server).getDay();
            QuestState.get(player.server).markNightDamaged(day, player.getUUID());
        }
    }

    @SubscribeEvent
    static void onPlayerLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        // "Online for the whole night": leaving mid-night forfeits tonight's credit.
        // Server shutdown is not a player choice; retain the persisted window across restart.
        if (!serverStopping && event.getEntity() instanceof ServerPlayer player) {
            int day = EclipseWorldState.get(player.server).getDay();
            QuestState.get(player.server).forfeitNight(day, player.getUUID());
        }
    }

    @SubscribeEvent
    static void onServerStopping(ServerStoppingEvent event) {
        serverStopping = true;
    }

    // --- night watcher (stepped by QuestEngine's shared 20t poll) ---

    /**
     * Night-window state machine for {@code survive_night_no_damage}: arms at dusk with the
     * players online right then; damage or logout drops eligibility; at dawn every survivor
     * gains one night of progress. Idle (and disarmed) while no such spec is active today.
     */
    static void pollNightWindow(MinecraftServer server, QuestEngine.ResolvedDay day) {
        List<GoalSpec> specs = day.ofType(TriggerType.SURVIVE_NIGHT_NO_DAMAGE);
        QuestState state = QuestState.get(server);
        if (specs.isEmpty()) {
            state.endNight(day.day);
            return;
        }
        boolean night = server.overworld().isNight();
        if (night) {
            List<UUID> online = server.getPlayerList().getPlayers().stream()
                    .map(ServerPlayer::getUUID)
                    .toList();
            long nightId = Math.floorDiv(server.overworld().getDayTime(), 24_000L);
            state.beginNight(day.day, nightId, online);
            return;
        }
        if (state.isNightOpen(day.day)) {
            creditSurvivors(server, day.day, specs);
        }
    }

    /** Dawn: credit the survivors that are still online and still eligible. */
    private static void creditSurvivors(MinecraftServer server, int day, List<GoalSpec> specs) {
        QuestState state = QuestState.get(server);
        java.util.Set<UUID> survivors = state.nightSurvivors(day);
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            if (!survivors.contains(player.getUUID())) {
                continue;
            }
            for (GoalSpec spec : specs) {
                QuestEngine.increment(server, player, spec, 1L);
            }
        }
        state.endNight(day);
    }

    /** Gametest hook: pretends dusk fell right now with the given players online. */
    public static void forceNightStartForTest(List<ServerPlayer> online) {
        if (online.isEmpty()) {
            throw new IllegalArgumentException("night test needs at least one player");
        }
        MinecraftServer server = online.getFirst().server;
        int day = QuestEngine.resolved(server).day;
        QuestState.get(server).beginNight(day,
                Math.floorDiv(server.overworld().getDayTime(), 24_000L),
                online.stream().map(ServerPlayer::getUUID).toList());
    }

    /** Gametest hook: whether the player would currently be credited at dawn. */
    public static boolean isNightEligibleForTest(MinecraftServer server, UUID uuid) {
        int day = QuestEngine.resolved(server).day;
        return QuestState.get(server).isNightEligible(day, uuid);
    }

    /**
     * Gametest hook: forces the dawn transition NOW (credits eligible survivors against the
     * current day's survive specs), bypassing the real overworld time check.
     */
    public static void forceDawnForTest(MinecraftServer server) {
        QuestEngine.ResolvedDay day = QuestEngine.resolved(server);
        creditSurvivors(server, day.day, day.ofType(TriggerType.SURVIVE_NIGHT_NO_DAMAGE));
    }
}
