package dev.projecteclipse.eclipse.client.sky;

import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.veilfx.FxBudget;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * SKYDAY — shared client-side sky drivers, derived from the server-synced
 * {@link ClientStateCache} fields ({@code day} and {@code altarLevel} both ride the
 * existing {@code S2CDayStatePayload}; login re-send included, no new packets):
 *
 * <ul>
 *   <li><b>Day escalation</b> ({@link #dayEscalation}): 0 on event day 1 → 1 on day
 *       {@value #ESCALATION_LAST_DAY} — the sky grows more dramatic every day (deeper
 *       purple grading, baseline coronas, a swelling sun, day-visible stars and the
 *       {@link DaySkyEscalation} aurora curtains, culminating on the final day).
 *       {@link #dayFxEscalation} is the tier-scaled variant for ADDITIVE EXTRAS: full at
 *       quality tier 2, halved at tier 1 (reducedFx), 0 at tier 0 — cheap color grading
 *       keeps the raw factor, everything that adds draw calls uses the fx variant.</li>
 *   <li><b>Zenith hold</b> ({@link #celestialAngleRadians}): from the community's FIRST
 *       altar completion on, the ECLIPSE leaves the vanilla day cycle — it glides to the
 *       very top of the sky over {@value #ZENITH_GLIDE_SECONDS} s and STAYS pinned there,
 *       day and night. The zenith is celestial angle 0, i.e. exactly where the vanilla
 *       noon sun stands at dayTime 6000 ({@code getTimeOfDay(6000) == 0}), so "noon = sun
 *       at the top" keeps holding by construction. Level tracking follows the
 *       {@code AltarVeilSky.trackLevel} law: the first observation of a session (login)
 *       and any decrease (world reset / resync) adopt silently — only a genuine
 *       mid-session 0 → ≥1 level-up plays the glide.</li>
 * </ul>
 *
 * <p><b>SunTracker seam</b>: {@code veilfx.SunTracker.sunAngleRadians} still returns the
 * raw vanilla angle, so the {@code eclipse:sun_halo} post pass and the CPU occlusion
 * probe keep tracking the TRUE sun while the hold is live. To bring them along, that one
 * method must delegate here ({@code return EclipseSkyState.celestialAngleRadians(level,
 * partialTick);}) — deliberately NOT done in this pass because {@code veilfx/} is owned
 * elsewhere; this class reads {@code level.getSunAngle} directly (never SunTracker) so
 * the delegation cannot recurse.</p>
 *
 * <p>Render-thread only (same seconds-clock idiom as {@link AltarVeilSky}); zero
 * per-frame allocations.</p>
 */
@OnlyIn(Dist.CLIENT)
public final class EclipseSkyState {
    /** The event day the escalation culminates on (day 1 = factor 0, this day = 1). */
    private static final float ESCALATION_LAST_DAY = 14.0F;
    /** Zenith glide length — slow and ceremonial, matching the altar level-up beat. */
    private static final float ZENITH_GLIDE_SECONDS = 10.0F;

    /** Last altar level this client SAW sky-side ({@code MIN_VALUE} = adopt-only). */
    private static int lastSeenAltarLevel = Integer.MIN_VALUE;
    /** Seconds-clock timestamp of a live zenith glide; {@code NaN} = none. */
    private static float glideStart = Float.NaN;
    /** Steady state while no glide is live: {@code true} = pinned at the zenith. */
    private static boolean held;

    private EclipseSkyState() {}

    /**
     * Raw day-escalation factor 0..1 (clamped; pre-event and day-1 clients read 0).
     * Use for zero-cost grading only — additive extras take {@link #dayFxEscalation}.
     */
    public static float dayEscalation() {
        return Mth.clamp((ClientStateCache.day - 1) / (ESCALATION_LAST_DAY - 1.0F), 0.0F, 1.0F);
    }

    /** Tier-scaled escalation for additive extras: full / halved / off (reducedFx law). */
    public static float dayFxEscalation() {
        int tier = FxBudget.qualityTier();
        if (tier <= 0) {
            return 0.0F;
        }
        return tier >= 2 ? dayEscalation() : dayEscalation() * 0.5F;
    }

    /**
     * The celestial angle the ECLIPSE renders with: the vanilla {@code getSunAngle} until
     * the first altar completion, then a shortest-path blend to (and a permanent hold at)
     * the zenith — angle 0, the tick-6000 noon position. The moon, stars and sunrise band
     * deliberately keep the vanilla angle so nights stay intact.
     */
    public static float celestialAngleRadians(ClientLevel level, float partialTick) {
        float vanilla = level.getSunAngle(partialTick);
        float hold = zenithHold();
        if (hold <= 0.0F) {
            return vanilla;
        }
        // Shortest path: wrap to ±180° so a night-time glide sweeps UP the near side
        // instead of winding the long way around the disc.
        float signedDegrees = Mth.wrapDegrees((float) Math.toDegrees(vanilla));
        return (float) Math.toRadians(signedDegrees * (1.0F - hold));
    }

    /** Zenith-hold blend 0..1 (0 = vanilla cycle, 1 = pinned at the top of the sky). */
    public static float zenithHold() {
        float seconds = (System.currentTimeMillis() % 3_600_000L) / 1000.0F;
        trackAltarLevel(seconds);
        if (Float.isNaN(glideStart)) {
            return held ? 1.0F : 0.0F;
        }
        float t = (seconds - glideStart) / ZENITH_GLIDE_SECONDS;
        if (t < 0.0F || t >= 1.0F) {
            glideStart = Float.NaN; // done (or the hourly clock wrapped) — hold forever
            held = true;
            return 1.0F;
        }
        return t * t * (3.0F - 2.0F * t); // smoothstep — eases off the cycle, eases onto the hold
    }

    /**
     * Watches the synced altar level from the render side ({@code AltarVeilSky.trackLevel}
     * law): first observation or any decrease adopts silently (login joins a completed
     * altar with the eclipse already pinned, a reset releases it), a genuine mid-session
     * 0 → ≥1 completion arms the ceremonial glide.
     */
    private static void trackAltarLevel(float seconds) {
        int level = Math.max(0, ClientStateCache.altarLevel);
        if (lastSeenAltarLevel == Integer.MIN_VALUE || level < lastSeenAltarLevel) {
            lastSeenAltarLevel = level;
            glideStart = Float.NaN;
            held = level >= 1;
            return;
        }
        if (level > lastSeenAltarLevel) {
            if (lastSeenAltarLevel == 0 && !held) {
                glideStart = seconds; // the community's 0→1 moment — the eclipse ascends
            }
            lastSeenAltarLevel = level;
        }
    }
}
