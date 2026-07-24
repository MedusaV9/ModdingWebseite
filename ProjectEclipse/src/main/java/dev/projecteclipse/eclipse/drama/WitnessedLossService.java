package dev.projecteclipse.eclipse.drama;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDeathEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Witnessed heart-loss ripple (FIX-5, IDEAS-A #4): when a player loses a permanent MAX
 * heart, every player within {@value #WITNESS_RADIUS} blocks feels it — a half-second
 * purple vignette pulse (the existing {@code marked} variant of {@link S2CShakePayload},
 * which the client's {@code MarkVignetteOverlay} already renders) plus a muffled, distant
 * take of the heart-shatter crack. No text, no name: bystanders physically register a
 * teammate's permanent loss, which is what makes escorting low-heart players an instinct.
 *
 * <p><b>Pure event subscriber</b> — the death-driven heart loss is detected by bracketing
 * {@code lives.LifecycleEvents.onLivingDeath} (NORMAL): a {@link EventPriority#HIGHEST}
 * listener snapshots the pre-death heart count, a {@link EventPriority#LOWEST} listener
 * compares it against {@link LivesApi#get} after the whole death chain ran (LifecycleEvents
 * NORMAL, DeathFlowHooks LOW). No seam in {@code lives/}/{@code hearts/} is required for
 * the death path; the two non-death heart-loss call sites (altar heart sacrifice, Heart
 * Extractor) can additionally call {@link #onHeartLost} — one-line diffs are in
 * {@code docs/plans_v3/wiring/FIX-5_wiring.md}.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class WitnessedLossService {
    /** Witness radius (blocks). FIX-5 spec: 24 (IDEAS-A #4 proposed 16; 24 was ordered). */
    private static final double WITNESS_RADIUS = 24.0D;
    private static final double WITNESS_RADIUS_SQ = WITNESS_RADIUS * WITNESS_RADIUS;
    /**
     * Mark length: {@code MarkVignetteOverlay} fades in over 10 t and out over the last
     * 20 t, so 24 t reads as one soft half-second pulse (never the full hunt vignette).
     */
    private static final int PULSE_TICKS = 24;
    /** Muffled shatter: the owner's UI crack, quiet and pitched down = heard through walls. */
    private static final float SHATTER_VOLUME = 0.4F;
    private static final float SHATTER_PITCH = 0.6F;
    /** Snapshot map safety valve (entries can strand only if another mod cancels the death). */
    private static final int MAX_TRACKED_SNAPSHOTS = 64;

    /** Pre-death heart counts, keyed per victim between the HIGHEST and LOWEST listeners. */
    private static final Map<UUID, Integer> PRE_DEATH_HEARTS = new HashMap<>();

    private WitnessedLossService() {}

    /** HIGHEST: snapshot the heart count BEFORE the death economy decrements it. */
    @SubscribeEvent(priority = EventPriority.HIGHEST)
    static void onLivingDeathEarly(LivingDeathEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer victim)) {
            return;
        }
        if (PRE_DEATH_HEARTS.size() >= MAX_TRACKED_SNAPSHOTS) {
            PRE_DEATH_HEARTS.clear(); // stranded snapshots (canceled deaths) — reset cheaply
        }
        PRE_DEATH_HEARTS.put(victim.getUUID(), LivesApi.get(victim));
    }

    /** LOWEST: after the whole death chain — a lower count now means a MAX heart was lost. */
    @SubscribeEvent(priority = EventPriority.LOWEST)
    static void onLivingDeathLate(LivingDeathEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer victim)) {
            return;
        }
        Integer before = PRE_DEATH_HEARTS.remove(victim.getUUID());
        if (before != null && LivesApi.get(victim) < before) {
            onHeartLost(victim);
        }
    }

    /**
     * Public seam: ripples one permanent heart loss of {@code owner} to every OTHER player
     * within {@value #WITNESS_RADIUS} blocks in the same dimension. The owner keeps their
     * own existing cues (HUD shatter burst); witnesses get the short marked vignette pulse
     * plus the muffled shatter. Safe to call from any server-side heart-loss site.
     */
    public static void onHeartLost(ServerPlayer owner) {
        for (ServerPlayer witness : owner.serverLevel().players()) {
            if (witness == owner || witness.distanceToSqr(owner) > WITNESS_RADIUS_SQ) {
                continue;
            }
            PacketDistributor.sendToPlayer(witness, S2CShakePayload.mark(PULSE_TICKS));
            witness.playNotifySound(EclipseSounds.UI_HEART_SHATTER.get(), SoundSource.PLAYERS,
                    SHATTER_VOLUME, SHATTER_PITCH);
        }
    }

    /** Integrated-server restarts must never leak snapshots into the next world. */
    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        PRE_DEATH_HEARTS.clear();
    }
}
