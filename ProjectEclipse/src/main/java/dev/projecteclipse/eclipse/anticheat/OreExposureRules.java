package dev.projecteclipse.eclipse.anticheat;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.ReloadHooks;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.level.block.state.BlockState;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;

/**
 * Behavioral anti-xray detector fed by the analytics-owned
 * {@link EclipseSignals#onNaturalBlockMined} lane.
 *
 * <p>Only configured valuable ores enter a fixed-size per-player ring buffer. Each sample
 * records whether all six neighbors were non-air immediately before the break. This makes
 * the block-break path O(1), excludes player-placed ore through the signal contract, and
 * avoids chunk scans or packet rewriting. Thresholds only notify by default; the strongest
 * supported action is a temporary mining-fatigue effect, never an automatic ban.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class OreExposureRules {
    public enum SuspicionLevel {
        CLEAR,
        SOFT,
        HARD
    }

    /** Immutable operator-query view of one player's current rolling window. */
    public record PlayerSnapshot(
            int samples,
            int exposedSamples,
            int unexposedSamples,
            double score,
            SuspicionLevel level) {
        static PlayerSnapshot empty() {
            return new PlayerSnapshot(0, 0, 0, 0.0D, SuspicionLevel.CLEAR);
        }
    }

    /** One row for command/status consumers. */
    public record PlayerScore(UUID playerId, PlayerSnapshot snapshot) {}

    /** Aggregate command/status view. */
    public record Status(int trackedPlayers, int softPlayers, int hardPlayers) {}

    /**
     * Allocation-free fixed-size rolling window. Public so GameTests can verify the exact
     * production scoring primitive without constructing world/player mocks.
     */
    public static final class RollingExposureWindow {
        private final boolean[] unexposed;
        private int next;
        private int samples;
        private int unexposedSamples;

        public RollingExposureWindow(int capacity) {
            if (capacity < 1) {
                throw new IllegalArgumentException("capacity must be positive");
            }
            this.unexposed = new boolean[capacity];
        }

        public void add(boolean wasUnexposed) {
            if (this.samples == this.unexposed.length) {
                if (this.unexposed[this.next]) {
                    this.unexposedSamples--;
                }
            } else {
                this.samples++;
            }
            this.unexposed[this.next] = wasUnexposed;
            if (wasUnexposed) {
                this.unexposedSamples++;
            }
            this.next = (this.next + 1) % this.unexposed.length;
        }

        public int samples() {
            return this.samples;
        }

        public int unexposedSamples() {
            return this.unexposedSamples;
        }

        public int exposedSamples() {
            return this.samples - this.unexposedSamples;
        }

        public double score() {
            return scorePercent(this.unexposedSamples, this.samples);
        }
    }

    private static final class PlayerState {
        private final RollingExposureWindow window;
        private SuspicionLevel previousLevel = SuspicionLevel.CLEAR;

        PlayerState(int windowSize) {
            this.window = new RollingExposureWindow(windowSize);
        }
    }

    private static final Direction[] NEIGHBORS = Direction.values();
    private static final Map<UUID, PlayerState> PLAYER_STATES = new HashMap<>();
    private static final AtomicBoolean SIGNAL_REGISTERED = new AtomicBoolean();
    private static final AtomicBoolean RELOAD_HOOK_REGISTERED = new AtomicBoolean();

    private OreExposureRules() {}

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        if (RELOAD_HOOK_REGISTERED.compareAndSet(false, true)) {
            ReloadHooks.register("anti_xray", OreExposureRules::reloadConfiguration);
        }
        reloadConfiguration();
        if (SIGNAL_REGISTERED.compareAndSet(false, true)) {
            EclipseSignals.onNaturalBlockMined(OreExposureRules::onNaturalBlockMined);
        }
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        SIGNAL_REGISTERED.set(false);
        PLAYER_STATES.clear();
        AntiXrayConfig.invalidate();
    }

    /** Reload hook: swap the config atomically and discard windows built with the old size. */
    public static void reloadConfiguration() {
        AntiXrayConfig.reload();
        clearTracking();
    }

    /** Clears all in-memory rolling windows; used after an operator changes thresholds. */
    public static void clearTracking() {
        PLAYER_STATES.clear();
    }

    private static void onNaturalBlockMined(ServerPlayer player, BlockState state, BlockPos pos) {
        AntiXrayConfig.Data config = AntiXrayConfig.get();
        if (!config.enabled()
                || !config.valuableOres().contains(BuiltInRegistries.BLOCK.getKey(state.getBlock()))) {
            return;
        }

        boolean unexposed = !isAirAdjacent(player.serverLevel(), pos);
        PlayerState playerState = PLAYER_STATES.computeIfAbsent(player.getUUID(),
                ignored -> new PlayerState(config.windowSize()));
        playerState.window.add(unexposed);
        PlayerSnapshot snapshot = evaluate(playerState.window.samples(),
                playerState.window.unexposedSamples(), config);

        if (snapshot.level().ordinal() > playerState.previousLevel.ordinal()) {
            alertOperators(player, pos, snapshot, config);
        }
        playerState.previousLevel = snapshot.level();
    }

    /**
     * True when any cardinal neighbor is air/cave-air/void-air. An unloaded neighbor is
     * treated as exposed (non-suspicious), a deliberate false-positive fail-safe.
     */
    public static boolean isAirAdjacent(ServerLevel level, BlockPos pos) {
        for (Direction direction : NEIGHBORS) {
            BlockPos neighbor = pos.relative(direction);
            if (!level.hasChunk(neighbor.getX() >> 4, neighbor.getZ() >> 4)
                    || level.getBlockState(neighbor).isAir()) {
                return true;
            }
        }
        return false;
    }

    /** Pure score math: percentage of valuable-ore samples that were fully encased. */
    public static double scorePercent(int unexposedSamples, int samples) {
        if (samples <= 0) {
            return 0.0D;
        }
        int bounded = Math.max(0, Math.min(unexposedSamples, samples));
        return bounded * 100.0D / samples;
    }

    /** Pure threshold classification used by production and unit-style GameTests. */
    public static PlayerSnapshot evaluate(int samples, int unexposedSamples,
            AntiXrayConfig.Data config) {
        int boundedSamples = Math.max(0, samples);
        int boundedUnexposed = Math.max(0, Math.min(unexposedSamples, boundedSamples));
        double score = scorePercent(boundedUnexposed, boundedSamples);
        SuspicionLevel level = SuspicionLevel.CLEAR;
        if (boundedSamples >= config.minimumSamples()) {
            if (score >= config.hardThreshold()) {
                level = SuspicionLevel.HARD;
            } else if (score >= config.softThreshold()) {
                level = SuspicionLevel.SOFT;
            }
        }
        return new PlayerSnapshot(boundedSamples, boundedSamples - boundedUnexposed,
                boundedUnexposed, score, level);
    }

    /** Read-only suspicion query for {@code /dev stats} and other operator tools. */
    public static PlayerSnapshot playerScore(UUID playerId) {
        PlayerState state = PLAYER_STATES.get(playerId);
        if (state == null) {
            return PlayerSnapshot.empty();
        }
        return evaluate(state.window.samples(), state.window.unexposedSamples(), AntiXrayConfig.get());
    }

    /** All currently tracked players, highest score first and UUID-tied deterministically. */
    public static List<PlayerScore> playerScores() {
        List<PlayerScore> scores = new ArrayList<>(PLAYER_STATES.size());
        for (Map.Entry<UUID, PlayerState> entry : PLAYER_STATES.entrySet()) {
            scores.add(new PlayerScore(entry.getKey(), playerScore(entry.getKey())));
        }
        scores.sort(Comparator.comparingDouble((PlayerScore row) -> row.snapshot().score())
                .reversed().thenComparing(PlayerScore::playerId));
        return List.copyOf(scores);
    }

    /** Aggregate read-only query, evaluated against the currently loaded thresholds. */
    public static Status status() {
        int soft = 0;
        int hard = 0;
        for (PlayerState state : PLAYER_STATES.values()) {
            SuspicionLevel level = evaluate(state.window.samples(),
                    state.window.unexposedSamples(), AntiXrayConfig.get()).level();
            if (level == SuspicionLevel.SOFT) {
                soft++;
            } else if (level == SuspicionLevel.HARD) {
                hard++;
            }
        }
        return new Status(PLAYER_STATES.size(), soft, hard);
    }

    private static void alertOperators(ServerPlayer player, BlockPos pos, PlayerSnapshot snapshot,
            AntiXrayConfig.Data config) {
        String formattedScore = String.format(java.util.Locale.ROOT, "%.1f", snapshot.score());
        Component message = Component.translatable("dev.eclipse.anticheat.alert",
                player.getScoreboardName(), levelName(snapshot.level()),
                formattedScore, snapshot.unexposedSamples(), snapshot.samples(), pos.toShortString());
        for (ServerPlayer operator : player.server.getPlayerList().getPlayers()) {
            if (operator.hasPermissions(2)) {
                operator.sendSystemMessage(message);
            }
        }
        EclipseMod.LOGGER.warn(
                "[ANTI-XRAY] {} crossed {} threshold: score={}%, encased={}/{}, position={}",
                player.getScoreboardName(), snapshot.level(), formattedScore,
                snapshot.unexposedSamples(), snapshot.samples(), pos.toShortString());

        if (snapshot.level() == SuspicionLevel.HARD
                && config.actionMode() == AntiXrayConfig.ActionMode.SLOWDOWN) {
            player.addEffect(new MobEffectInstance(MobEffects.DIG_SLOWDOWN,
                    config.slowdownDurationTicks(), config.slowdownAmplifier()));
            EclipseMod.LOGGER.warn("[ANTI-XRAY] Applied mining slowdown to {} for {} ticks (amplifier {})",
                    player.getScoreboardName(), config.slowdownDurationTicks(),
                    config.slowdownAmplifier());
        }
    }

    private static Component levelName(SuspicionLevel level) {
        return Component.translatable("dev.eclipse.anticheat.level."
                + level.name().toLowerCase(java.util.Locale.ROOT));
    }
}
