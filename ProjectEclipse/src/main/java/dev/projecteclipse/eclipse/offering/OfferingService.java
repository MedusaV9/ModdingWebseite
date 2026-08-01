package dev.projecteclipse.eclipse.offering;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.analytics.AnalyticsKeys;
import dev.projecteclipse.eclipse.analytics.AnalyticsService;
import dev.projecteclipse.eclipse.analytics.AnalyticsState;
import dev.projecteclipse.eclipse.awards.AwardConfig;
import dev.projecteclipse.eclipse.awards.AwardMath;
import dev.projecteclipse.eclipse.awards.AwardService;
import dev.projecteclipse.eclipse.awards.AwardsState;
import dev.projecteclipse.eclipse.core.config.ReloadHooks;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.network.S2CAnnouncePayload;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.ritual.BeamEmitter;
import dev.projecteclipse.eclipse.timeline.AnnouncementService;
import net.minecraft.core.BlockPos;
import net.minecraft.core.component.DataComponents;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.item.ItemStack;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/** Daily offering acceptance, exact-value accounting and rollover resolution. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class OfferingService {
    // statics reset on ServerStopped
    private static final AtomicBoolean SIGNALS_REGISTERED = new AtomicBoolean();
    /** ReloadHooks lives for the JVM, so this guard intentionally survives save changes. */
    private static final AtomicBoolean RELOAD_HOOK_REGISTERED = new AtomicBoolean();

    // --- WAVE5 (F-105 C) — C3 dawn-verdict bloom (IDEA-12 #10) --------------------------
    // A winner day gets a physical answer at the sanctum altar: 3 BeamEmitter salvos
    // spread over ~40 t. Duplicate-cancelled days (winners == 0) deliberately stay DARK —
    // the rule teaches itself without a single line of text. The pending emits are plain
    // statics driven by onServerTick; no scheduler infrastructure needed.

    /** Beam salvos per winner verdict. */
    private static final int BLOOM_EMITS = 3;
    /** Ticks between two bloom salvos (3 emits => ~40 t total). */
    private static final int BLOOM_STEP_TICKS = 20;

    /** Remaining bloom salvos ({@code 0} = idle). */
    // statics reset on ServerStopped
    private static int bloomEmitsLeft;
    /** Ticks until the next salvo. */
    // statics reset on ServerStopped
    private static int bloomCountdownTicks;
    /** Sanctum altar position the running bloom is anchored on. */
    // statics reset on ServerStopped
    private static BlockPos bloomPos;

    private OfferingService() {}

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        if (RELOAD_HOOK_REGISTERED.compareAndSet(false, true)) {
            ReloadHooks.register("offerings", OfferingConfig::reload);
        }
        OfferingConfig.reload();
        if (SIGNALS_REGISTERED.compareAndSet(false, true)) {
            EclipseSignals.onDayRollover((server, endedDay, newDay, phase) -> {
                if (phase == EclipseSignals.DayRolloverPhase.PRE) {
                    resolveDay(server, endedDay);
                } else if (!dev.projecteclipse.eclipse.drama.DawnCeremony.isRunning(server)) {
                    // FFIX-A / SAT-D3: while a DawnCeremony sequences the morning, IT owns
                    // the offering-announcement timing (its beat between toll and goals) —
                    // the exact AwardService sendRevealNow gating pattern. Quiet/catch-up
                    // rollovers have no ceremony and announce inline here at POST.
                    announceResult(server, endedDay);
                }
            });
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        SIGNALS_REGISTERED.set(false);
        OfferingConfig.invalidate();
        // WAVE5 (F-105 C) — C3 bloom statics
        bloomEmitsLeft = 0;
        bloomCountdownTicks = 0;
        bloomPos = null;
    }

    /** WAVE5 (F-105 C) — C3: drives the pending verdict-bloom salvos (idle = one int compare). */
    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (bloomEmitsLeft <= 0 || bloomPos == null) {
            return;
        }
        if (--bloomCountdownTicks > 0) {
            return;
        }
        BeamEmitter.emit(event.getServer().overworld(), bloomPos);
        bloomEmitsLeft--;
        bloomCountdownTicks = BLOOM_STEP_TICKS;
    }

    public static boolean hasOffered(MinecraftServer server, int day, UUID player) {
        return OfferingState.get(server).hasOffered(day, player);
    }

    public static boolean hasOfferedToday(ServerPlayer player) {
        return hasOffered(player.server, DayScheduler.getDay(player.server), player.getUUID());
    }

    /**
     * Atomically records and consumes exactly one held item. The caller owns confirmation and
     * visual feedback. Returns false without consuming when this player already offered today.
     */
    public static boolean accept(ServerPlayer player, ItemStack stack) {
        return acceptWithValue(player, stack).isPresent();
    }

    /**
     * {@link #accept} variant that additionally returns the (secret) exact value of the
     * accepted offering so the caller can shape private feedback (W4-ISLAND / IDEA-12 #2:
     * the offerer-only quantized pitch tell). Empty when nothing was accepted/consumed.
     * The value never reaches other players or any text channel — secrecy rules
     * ({@code resolveDay} duplicate cancellation etc.) are untouched, and {@code accept}
     * delegates here so gametest-covered behavior stays byte-identical.
     */
    public static java.util.OptionalInt acceptWithValue(ServerPlayer player, ItemStack stack) {
        if (stack.isEmpty()) {
            return java.util.OptionalInt.empty();
        }
        MinecraftServer server = player.server;
        int day = DayScheduler.getDay(server);
        ResourceLocation itemId = BuiltInRegistries.ITEM.getKey(stack.getItem());
        boolean enchanted = stack.isEnchanted();
        boolean renamed = stack.get(DataComponents.CUSTOM_NAME) != null;
        OfferingState state = OfferingState.get(server);
        if (!state.add(day, new OfferingState.Offer(player.getUUID(), itemId.toString(), enchanted, renamed))) {
            return java.util.OptionalInt.empty();
        }

        OfferingConfig.Data config = OfferingConfig.get();
        int exactValue = OfferingRules.value(itemId, enchanted, renamed, config);
        boolean tracked = AnalyticsService.isTracked(player);
        AnalyticsState analytics = AnalyticsState.get(server);
        long valueBeforeSignal = tracked
                ? analytics.value(day, player.getUUID(), AnalyticsKeys.ALTAR_VALUE) : 0L;
        stack.shrink(1);

        // This one signal drives deposit_altar quests, base altar_value analytics and altar XP.
        EclipseSignals.fireAltarDeposit(player, itemId, 1, EclipseSignals.AltarDepositPurpose.OFFERING);

        // A1's frozen signal has no ItemStack/value field. Reconcile only the difference between
        // what its listeners actually credited and the exact component-aware score. This stays
        // correct across listener order/test isolation without double-counting; analytics is read-only.
        if (tracked) {
            long signalDelta = analytics.value(day, player.getUUID(), AnalyticsKeys.ALTAR_VALUE)
                    - valueBeforeSignal;
            long reconciliation = exactValue - signalDelta;
            if (reconciliation != 0L) {
                analytics.add(day, player.getUUID(), AnalyticsKeys.ALTAR_VALUE, reconciliation);
            }
        }
        return java.util.OptionalInt.of(exactValue);
    }

    /**
     * Idempotently settles one ended day. Duplicate item ids score zero, the highest positive
     * unique score wins, and the bonus is queued before online delivery.
     */
    public static OfferingState.DayResult resolveDay(MinecraftServer server, int day) {
        OfferingState state = OfferingState.get(server);
        var existing = state.resolved(day);
        if (existing.isPresent()) {
            queueWinnerRewards(server, existing.get());
            return existing.get();
        }
        OfferingConfig.Data config = OfferingConfig.get();
        List<OfferingRules.Input> inputs = new ArrayList<>();
        for (OfferingState.Offer offer : state.offers(day)) {
            ResourceLocation itemId = ResourceLocation.tryParse(offer.itemId());
            int value = itemId == null ? 0
                    : OfferingRules.value(itemId, offer.enchanted(), offer.renamed(), config);
            inputs.add(new OfferingRules.Input(offer.player(), offer.itemId(), value));
        }
        OfferingRules.Resolution resolution = OfferingRules.resolve(inputs);
        OfferingState.DayResult result = new OfferingState.DayResult(day, resolution.offerings(),
                resolution.winners(), resolution.bestValue(), resolution.winningItemId(),
                config.winnerReward());
        boolean fresh = state.putResolved(result);
        if (!fresh) {
            result = state.resolved(day).orElse(result);
        }

        queueWinnerRewards(server, result);
        if (fresh) {
            // WAVE5 (F-105 C) — C3: only the FIRST resolution of a day blooms; the
            // idempotent re-entry/repair paths above must never replay the ceremony.
            fireVerdictBloom(server, result);
        }
        EclipseMod.LOGGER.info("Resolved {} altar offering(s) for day {}: {} winner(s), best value {}",
                result.offerings().size(), day, result.winners().size(), result.bestValue());
        return result;
    }

    /**
     * WAVE5 (F-105 C) — C3 dawn-verdict bloom: arms the 3-salvo beam bloom at the sanctum
     * altar (null-guarded for pre-intro worlds) and plays the private
     * {@code OFFERING_ACCEPT} at pitch 1.3 to every online winner. Winner identity leaks
     * nothing: the sound is {@code playNotifySound} (offerer-private, the split-chime law)
     * and the bloom itself is outcome-blind beyond "someone won today". Days without
     * winners (no offerings, or the duplicate cancellation zeroed everyone) stay dark.
     */
    private static void fireVerdictBloom(MinecraftServer server, OfferingState.DayResult result) {
        EclipseMod.LOGGER.debug("[w5c-verdict] winners={} day={}", result.winners().size(), result.day());
        if (result.winners().isEmpty()) {
            return;
        }
        BlockPos altar = EclipseWorldState.get(server).getSanctumAltarPos();
        if (altar != null) {
            bloomPos = altar;
            bloomEmitsLeft = BLOOM_EMITS;
            bloomCountdownTicks = 1; // first salvo on the next server tick, then every 20 t
        }
        for (UUID winner : result.winners()) {
            ServerPlayer online = server.getPlayerList().getPlayer(winner);
            if (online != null) {
                online.playNotifySound(EclipseSounds.OFFERING_ACCEPT.get(), SoundSource.BLOCKS, 1.0F, 1.3F);
            }
        }
    }

    /**
     * FFIX-A / SAT-D3: the offering-result announcement, extracted from {@link #resolveDay}
     * (which runs at rollover PRE, T+0 — a STYLE_GOAL line queued there sat AHEAD of the
     * ceremony's T+40 STYLE_DAY payload, displacing the day-number card and pushing it into
     * the T+200 roulette). {@code DawnCeremony} now fires this at its dedicated beat
     * between the toll and the goals reveal; rollovers without a ceremony announce inline
     * at POST. Idempotence rides the callers: exactly one of the two paths runs per
     * rollover, and dev re-announces are harmless (presentation only).
     */
    public static void announceResult(MinecraftServer server, int day) {
        OfferingState.get(server).resolved(day).ifPresent(result -> {
            if (!result.winners().isEmpty()) {
                AnnouncementService.announce(server, "announce.eclipse.offering.title",
                        itemDescriptionId(result.winningItemId()), S2CAnnouncePayload.STYLE_GOAL);
            }
        });
    }

    public static OfferingState.DayResult peek(MinecraftServer server, int day) {
        return OfferingState.get(server).resolved(day).orElseGet(() -> resolvePreview(server, day));
    }

    /** Converts the fixed offering result into the award reveal's fourth category. */
    public static AwardsState.CategoryResult toAwardCategory(OfferingState.DayResult result) {
        OfferingConfig.Data config = OfferingConfig.get();
        AwardConfig.Reward frozen = result.winnerReward().isEmpty()
                ? config.winnerReward() : result.winnerReward();
        AwardConfig.Reward share = frozen.split(result.winners().size());
        List<AwardMath.Candidate> candidates = result.offerings().stream()
                .map(row -> new AwardMath.Candidate(row.player(), row.value())).toList();
        String value = Integer.toString(result.bestValue());
        return new AwardsState.CategoryResult("best_offering", "altar_value",
                config.bestOfferingTitle().en(), config.bestOfferingTitle().de() == null
                        ? config.bestOfferingTitle().en() : config.bestOfferingTitle().de(),
                config.bestOfferingStatLine().en().replace("{value}", value),
                localized(config.bestOfferingStatLine()).replace("{value}", value),
                AwardService.rewardLine(share, false), AwardService.rewardLine(share, true),
                candidates, result.winners());
    }

    private static OfferingState.DayResult resolvePreview(MinecraftServer server, int day) {
        OfferingConfig.Data config = OfferingConfig.get();
        List<OfferingRules.Input> inputs = new ArrayList<>();
        for (OfferingState.Offer offer : OfferingState.get(server).offers(day)) {
            ResourceLocation itemId = ResourceLocation.tryParse(offer.itemId());
            inputs.add(new OfferingRules.Input(offer.player(), offer.itemId(), itemId == null ? 0
                    : OfferingRules.value(itemId, offer.enchanted(), offer.renamed(), config)));
        }
        OfferingRules.Resolution resolution = OfferingRules.resolve(inputs);
        return new OfferingState.DayResult(day, resolution.offerings(), resolution.winners(),
                resolution.bestValue(), resolution.winningItemId());
    }

    /**
     * Repairs a missing queue write from the frozen result; stable ids deduplicate retries.
     * FFIX-A / SAT-D1: best-offering winners are reveal-path rewards — queued silently and
     * delivered by {@code AwardService.sendRevealNow}, so the winner's materialization lands
     * after the roulette, never at rollover T+0.
     */
    private static void queueWinnerRewards(MinecraftServer server, OfferingState.DayResult result) {
        AwardConfig.Reward frozen = result.winnerReward().isEmpty()
                ? OfferingConfig.get().winnerReward() : result.winnerReward();
        AwardConfig.Reward share = frozen.split(result.winners().size());
        for (UUID winner : result.winners()) {
            // FFIX-B (POLISH-SOL-01): pass the settled day explicitly — this runs at rollover
            // PRE for the ENDED day, so the mutable current day must not decide AWARD_VOID.
            AwardService.queueRewardForReveal(server, winner,
                    "offering:" + result.day() + ":" + winner, share, result.day());
        }
    }

    private static String itemDescriptionId(String rawId) {
        ResourceLocation id = ResourceLocation.tryParse(rawId);
        if (id == null) {
            return rawId;
        }
        return BuiltInRegistries.ITEM.getOptional(id)
                .map(item -> item.getDescriptionId())
                .orElse(rawId);
    }

    private static String localized(dev.projecteclipse.eclipse.core.config.Localized value) {
        return value.de() == null || value.de().isBlank() ? value.en() : value.de();
    }
}
