package dev.projecteclipse.eclipse.voice;

import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.server.MinecraftServer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;

/**
 * W4-TOGGLES voice-changer state broker. Deliberately has ZERO Simple Voice Chat API imports:
 * commands and persistence work with or without the mod installed; the API-facing packet
 * plumbing lives exclusively in {@link VoiceChangerPlugin} (mirroring how
 * {@code EclipseVoicePlugin} → {@code VoiceMuteApi} is split).
 *
 * <p><b>Threading</b>: {@code MicrophonePacketEvent} fires on Simple Voice Chat's packet
 * processing thread, NOT the server thread, so the hot path never touches SavedData. Presets
 * are mirrored into a {@link ConcurrentHashMap} + volatile global default whenever the server
 * thread mutates {@link VoiceChangerState} (all mutations funnel through this class) and once
 * at server start. {@link #effectivePreset} is the only call the voice thread makes.</p>
 *
 * <p><b>Budget kill switch</b>: {@link VoiceChangerPlugin} reports the measured DSP time per
 * frame; {@link VoiceChangerConfig#current() autoDisableStrikes} consecutive frames over the
 * configured budget (default 2 ms) trip a global auto-disable with a WARN log. Re-arm with
 * {@code /dev voice changer reset} (or a server restart).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class VoiceChangerService {
    /** Runtime mirror of per-player presets — the voice thread reads this, never SavedData. */
    private static final Map<UUID, VoicePreset> RUNTIME_PRESETS = new ConcurrentHashMap<>();
    private static volatile VoicePreset runtimeGlobalDefault = VoicePreset.OFF;

    private static volatile boolean autoDisabled = false;
    private static final AtomicInteger overBudgetStrikes = new AtomicInteger();
    /** Worst frame observed since the last reset (status display, nanoseconds). */
    private static final AtomicLong worstFrameNanos = new AtomicLong();

    /**
     * FFIX-B (FINAL-SAT-SOL H5): consecutive decode/DSP/encode failure strikes per speaker.
     * A failed frame never reaches {@link #reportFrameNanos}, so without this counter a
     * broken native codec is retried on every mic packet forever. After
     * {@value #MAX_PIPELINE_FAILURE_STRIKES} consecutive failures for one speaker the
     * global kill switch trips (same re-arm as the budget switch). Reset by a successful
     * frame, disconnect, {@code /dev voice changer reset} and server start.
     */
    private static final Map<UUID, Integer> FAILURE_STRIKES = new ConcurrentHashMap<>();
    private static final int MAX_PIPELINE_FAILURE_STRIKES = 3;

    private VoiceChangerService() {}

    // --- hot path (voice packet thread) ---

    /**
     * Effective preset for a speaking player: OFF while the config master switch is off or
     * the budget kill switch tripped, else the player's override, else the global default.
     */
    public static VoicePreset effectivePreset(UUID player) {
        if (autoDisabled || !VoiceChangerConfig.current().enabled()) {
            return VoicePreset.OFF;
        }
        VoicePreset override = RUNTIME_PRESETS.get(player);
        return override != null ? override : runtimeGlobalDefault;
    }

    /**
     * Budget accounting for one processed frame (called from the voice thread with the
     * measured decode→DSP→encode time). Consecutive over-budget frames trip the kill switch.
     */
    public static void reportFrameNanos(long nanos) {
        worstFrameNanos.accumulateAndGet(nanos, Math::max);
        VoiceChangerConfig.Snapshot config = VoiceChangerConfig.current();
        long budgetNanos = config.frameBudgetMicros() * 1000L;
        if (nanos <= budgetNanos) {
            overBudgetStrikes.set(0);
            return;
        }
        int strikes = overBudgetStrikes.incrementAndGet();
        if (strikes >= config.autoDisableStrikes() && !autoDisabled) {
            autoDisabled = true;
            EclipseMod.LOGGER.warn(
                    "VoiceChanger: auto-disabled — {} consecutive frames exceeded the {} us budget "
                            + "(worst {} us). Re-arm with /dev voice changer reset.",
                    strikes, config.frameBudgetMicros(), worstFrameNanos.get() / 1000L);
        }
    }

    /**
     * Failure accounting for one broken decode→DSP→encode attempt (voice thread; FFIX-B /
     * FINAL-SAT-SOL H5). The plugin closes and discards the failed pipeline before calling
     * this; after {@value #MAX_PIPELINE_FAILURE_STRIKES} consecutive failures for the same
     * speaker the global kill switch trips so the changer stops retrying entirely — the
     * original voice always keeps flowing.
     */
    public static void reportPipelineFailure(UUID speaker) {
        int strikes = FAILURE_STRIKES.merge(speaker, 1, Integer::sum);
        if (strikes >= MAX_PIPELINE_FAILURE_STRIKES && !autoDisabled) {
            autoDisabled = true;
            EclipseMod.LOGGER.warn(
                    "VoiceChanger: auto-disabled — {} consecutive pipeline failures for {}. "
                            + "Re-arm with /dev voice changer reset.",
                    strikes, speaker);
        }
    }

    /** Breaks a speaker's consecutive-failure streak (successful frame or disconnect). */
    public static void clearPipelineFailures(UUID speaker) {
        FAILURE_STRIKES.remove(speaker);
    }

    // --- queries (server thread; commands/status) ---

    public static VoicePreset globalDefault(MinecraftServer server) {
        return VoiceChangerState.get(server).globalDefault();
    }

    /** {@code null} = no override (inherit global default). */
    @Nullable
    public static VoicePreset playerPreset(MinecraftServer server, UUID player) {
        return VoiceChangerState.get(server).playerPreset(player);
    }

    public static Map<UUID, VoicePreset> playerPresets(MinecraftServer server) {
        return VoiceChangerState.get(server).playerPresets();
    }

    public static boolean isAutoDisabled() {
        return autoDisabled;
    }

    /** Worst measured frame since the last reset, in microseconds (status display). */
    public static long worstFrameMicros() {
        return worstFrameNanos.get() / 1000L;
    }

    // --- mutations (server thread) ---

    public static void setGlobalDefault(MinecraftServer server, VoicePreset preset) {
        VoiceChangerState.get(server).setGlobalDefault(preset);
        runtimeGlobalDefault = preset;
        EclipseMod.LOGGER.info("VoiceChanger: global default preset -> {}", preset.id());
    }

    /** @param preset the override, or {@code null} to clear (inherit global default). */
    public static void setPlayerPreset(MinecraftServer server, UUID player, @Nullable VoicePreset preset) {
        VoiceChangerState.get(server).setPlayerPreset(player, preset);
        if (preset == null) {
            RUNTIME_PRESETS.remove(player);
        } else {
            RUNTIME_PRESETS.put(player, preset);
        }
        EclipseMod.LOGGER.info("VoiceChanger: preset for {} -> {}", player,
                preset == null ? "cleared" : preset.id());
    }

    /** Re-arms the budget/failure kill switch ({@code /dev voice changer reset}). */
    public static void resetAutoDisable() {
        autoDisabled = false;
        overBudgetStrikes.set(0);
        worstFrameNanos.set(0L);
        FAILURE_STRIKES.clear();
        EclipseMod.LOGGER.info("VoiceChanger: budget kill switch re-armed");
    }

    // --- lifecycle ---

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        // Static runtime mirror dies with the JVM, not the save — rebuild for this world.
        RUNTIME_PRESETS.clear();
        VoiceChangerState state = VoiceChangerState.get(event.getServer());
        RUNTIME_PRESETS.putAll(state.playerPresets());
        runtimeGlobalDefault = state.globalDefault();
        autoDisabled = false;
        overBudgetStrikes.set(0);
        worstFrameNanos.set(0L);
        FAILURE_STRIKES.clear();
    }
}
