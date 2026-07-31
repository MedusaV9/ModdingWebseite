package dev.projecteclipse.eclipse.veilfx;

import org.joml.Vector3f;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.util.Mth;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * NEWFX-D4 — <b>Diamond Ring</b> (PLAN-NEWFX §2): at the moment the sun goes fully
 * black, ONE blinding bead of light flares on the rim, streaks a short arc and dies —
 * the eclipse "diamond ring", ~1.5 s, then the drone owns the dark.
 *
 * <p><b>Seam:</b> a client observer on {@link EclipseFxState#eclipseAmount}: a RISING
 * crest through {@value #CREST} fires once per ramp; the trigger re-arms only after the
 * amount falls below {@value #REARM} (the music rung's threshold neighborhood — same
 * hysteresis discipline, so partial dips near totality never double-fire). Joining
 * mid-totality shows nothing: the first sample never counts as a crest.</p>
 *
 * <p><b>Tech (plan row):</b> Photon one-shot {@code eclipse:totality_diamond_ring} +
 * Quasar glint fallback, {@code Mode.LAYER} semantics spawned DIRECTLY through
 * {@link PhotonBridge}/{@link QuasarSpawner} — client-local, no cue crosses the wire
 * (see {@link AtmospherePhotonFxRows}). Anchored {@value #BEAD_DISTANCE_BLOCKS} blocks
 * out from the camera along {@link SunTracker#sunDirWorld} so the bead sits ON the
 * blacked-out disc's rim from this camera's exact vantage; skipped (and consumed — a
 * LATE diamond ring is a wrong diamond ring) when {@link SunTracker#sunOccluded()}
 * reports no sky line to the sun. <b>Budget:</b> SEQUENCE (the eclipse IS the scripted
 * sequence). <b>reducedFx:</b> skip — the world-grade exposure crush already tells the
 * story. <b>Photosensitivity:</b> the asset holds ONE bead with a ≤ 2-tick full-white
 * flash (§3 impact law) easing into the ~1.5 s streak — no strobe, no repeats.</p>
 *
 * <p><b>FX-13 A9 (census N2/N13) — this class is now the peak timeline of record:</b></p>
 * <ul>
 *   <li><b>Black-sun snap</b> ({@link #snapAmount}): the SAME rising crest that fires the
 *       diamond ring also arms a screen-side envelope — hard snap-in
 *       ({@value #SNAP_IN_TICKS} t), a {@value #SNAP_HOLD_TICKS}-tick black hold, then a
 *       soft {@value #SNAP_OUT_TICKS}-tick release. {@code VeilPostController.feedSunHalo}
 *       feeds it as the {@code sun_halo} {@code SunSnap} uniform (disc collapses to a
 *       black hole with a thin corona ring). Same gates as the ring (reducedFx skip,
 *       overworld only, sun not occluded), so ring and snap can never disagree.</li>
 *   <li><b>Shadow bands</b> ({@link #shadowBands}): the real-world totality phenomenon —
 *       thin, wavering, low-contrast shadow snakes racing over the ground shortly
 *       before/after the peak. Driver = a crescent window on the eased eclipse amount
 *       (bands live while the sun is a thin sliver: amount in ~[{@value #BAND_IN_LO},
 *       {@value #BAND_OUT_HI}], zero at full totality — physically correct), clipped by a
 *       {@value #BAND_WINDOW_TICKS}-tick (20 s) per-ramp-side time budget so a slow
 *       scripted ramp can never carry bands for minutes (the "±20 s around the peak"
 *       law: the BUILDUP side and the ENDING side each earn one window). Fed as the
 *       {@code world_grade} {@code ShadowBands} uniform; forced 0 under reducedFx, off
 *       the overworld, under rain, and while the sun is occluded.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class TotalityPeakFx {
    /** Rising-crest trigger threshold on the eased eclipse amount. */
    static final float CREST = 0.95F;
    /** Hysteresis re-arm: the amount must fall below this before the next crest counts. */
    static final float REARM = 0.6F;
    /** Bead anchor distance from the camera along the sun direction (blocks). */
    static final double BEAD_DISTANCE_BLOCKS = 60.0D;

    /** Armed = the next rising crest fires. Disarmed until the amount dips below REARM. */
    private static boolean armed = true;
    /** Previous tick's eclipse amount; NaN = no sample yet (login/dimension change). */
    private static float lastAmount = Float.NaN;

    // --- FX-13 A9: black-sun snap envelope (sun_halo SunSnap) ---
    /** Snap-in length — near-instant: the sun "snaps", it does not fade, into the hole. */
    static final int SNAP_IN_TICKS = 3;
    /** Black-hole hold (~1.25 s — the census "1–2 s" beat). */
    static final int SNAP_HOLD_TICKS = 25;
    /** Soft release back to the ordinary totality halo. */
    static final int SNAP_OUT_TICKS = 30;
    /** Tick the snap envelope started; {@code MIN_VALUE} = idle. */
    private static int snapStartTick = Integer.MIN_VALUE;

    // --- FX-13 A9: shadow-bands crescent-window driver (world_grade ShadowBands) ---
    /** Crescent window low edge: below this the sun is too open for bands. */
    static final float BAND_IN_LO = 0.82F;
    /** Crescent window full-on point on the rising edge. */
    static final float BAND_IN_HI = 0.93F;
    /** Bands start dying here — approaching full cover the sliver (and the bands) vanish. */
    static final float BAND_OUT_LO = 0.965F;
    /** Fully gone at (numerically just short of) totality. */
    static final float BAND_OUT_HI = 0.995F;
    /** Per-ramp-side time budget: ±20 s around the peak, never longer (census N2 law). */
    static final int BAND_WINDOW_TICKS = 400;
    /** Window fade-out length once the budget is spent (no pop on slow ramps). */
    private static final float BAND_WINDOW_FADE_TICKS = 60.0F;
    /** Quiet ticks (crescent ≈ 0) after which the NEXT ramp side earns a fresh window. */
    private static final int BAND_RESET_TICKS = 40;
    /** Eased-bands slew per tick: full on/off in ~25 ticks — wander in, never blink in. */
    private static final float BAND_SLEW = 0.04F;

    private static float bandsEased;
    private static int bandsWindowTicks;
    private static int bandsQuietTicks = BAND_RESET_TICKS;

    private TotalityPeakFx() {}

    // ------------------------------------------------------------------ A9 feeder surface

    /**
     * Eased black-sun snap amount 0..1 for the {@code sun_halo} {@code SunSnap} uniform
     * (0 outside the peak beat — bit-identical frame). Self-expiring envelope; the
     * mutate-on-read reset is the {@code TransitionFx.transitionEnvelope} idiom.
     */
    public static float snapAmount(float partialTick) {
        if (snapStartTick == Integer.MIN_VALUE) {
            return 0.0F;
        }
        float t = EclipseFxState.clientTicks() + partialTick - snapStartTick;
        if (t < SNAP_IN_TICKS) {
            return smooth(t / SNAP_IN_TICKS);
        }
        t -= SNAP_IN_TICKS;
        if (t < SNAP_HOLD_TICKS) {
            return 1.0F;
        }
        t -= SNAP_HOLD_TICKS;
        if (t < SNAP_OUT_TICKS) {
            return smooth(1.0F - t / SNAP_OUT_TICKS);
        }
        snapStartTick = Integer.MIN_VALUE; // envelope done
        return 0.0F;
    }

    /**
     * Eased shadow-bands strength 0..1 for the {@code world_grade} {@code ShadowBands}
     * uniform. Ticked by {@link #tickShadowBands}; already 0 under reducedFx / rain /
     * occlusion / off the overworld, so the feeder passes it through unfiltered.
     */
    public static float shadowBands() {
        return bandsEased;
    }

    /**
     * Per-tick shadow-bands driver: crescent factor × per-side time window, slewed.
     * The crescent factor is a band-pass on the eased eclipse amount — it rises while
     * the sun thins toward totality, is exactly 0 at full cover (no sliver, no bands)
     * and rises again on the ENDING ramp; each side's exposure is capped at
     * {@value #BAND_WINDOW_TICKS} ticks (a totality hold of ≥ {@value #BAND_RESET_TICKS}
     * quiet ticks re-arms the budget for the falling side).
     */
    private static void tickShadowBands(ClientLevel level, float amount) {
        float target = 0.0F;
        if (level.dimension() == Level.OVERWORLD && !EclipseClientConfig.reducedFx()
                && !SunTracker.sunOccluded()) {
            float crescent = ramp(amount, BAND_IN_LO, BAND_IN_HI)
                    * (1.0F - ramp(amount, BAND_OUT_LO, BAND_OUT_HI));
            if (crescent > 0.05F) {
                bandsQuietTicks = 0;
                bandsWindowTicks++;
            } else if (bandsQuietTicks < BAND_RESET_TICKS && ++bandsQuietTicks >= BAND_RESET_TICKS) {
                bandsWindowTicks = 0; // ramp side over — the other side earns a fresh window
            }
            float window = 1.0F - Mth.clamp(
                    (bandsWindowTicks - BAND_WINDOW_TICKS) / BAND_WINDOW_FADE_TICKS, 0.0F, 1.0F);
            // A rain-covered sky throws no crescent shadows — same physics as the halo fade.
            target = crescent * window * (1.0F - level.getRainLevel(1.0F));
        }
        if (bandsEased < target) {
            bandsEased = Math.min(target, bandsEased + BAND_SLEW);
        } else if (bandsEased > target) {
            bandsEased = Math.max(target, bandsEased - BAND_SLEW);
        }
    }

    /** Smoothstep band edge helper (0 at {@code lo}, 1 at {@code hi}). */
    private static float ramp(float x, float lo, float hi) {
        return smooth((x - lo) / (hi - lo));
    }

    private static float smooth(float x) {
        x = Mth.clamp(x, 0.0F, 1.0F);
        return x * x * (3.0F - 2.0F * x);
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        ClientLevel level = minecraft.level;
        if (level == null) {
            reset();
            return;
        }
        float amount = EclipseFxState.eclipseAmount(1.0F);
        float previous = lastAmount;
        lastAmount = amount;
        // A9: the bands driver runs every tick — it watches the whole ramp, not just the crest.
        tickShadowBands(level, amount);
        if (!armed) {
            if (amount < REARM) {
                armed = true; // ramp fully receded — the next totality earns a new ring
            }
            return;
        }
        // A crest is a RISING edge through the threshold observed across two samples —
        // a first sample already at totality (login mid-eclipse) is deliberately not one.
        if (Float.isNaN(previous) || previous >= CREST || amount < CREST) {
            return;
        }
        armed = false; // consumed either way: a late/second bead is never played
        if (EclipseClientConfig.reducedFx()) {
            return; // plan row: skip — the exposure crush carries the beat
        }
        if (level.dimension() != Level.OVERWORLD || SunTracker.sunOccluded()) {
            return; // no sight line to the sun rim: nothing to flare on
        }
        // A9: the black-sun snap rides the exact same crest — the post pass and the
        // Photon bead fire on the same tick, so ring and hole can never disagree.
        snapStartTick = EclipseFxState.clientTicks();
        Vector3f sunDir = SunTracker.sunDirWorld(1.0F); // shared scratch — read out now
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        Vec3 anchor = camera.add(sunDir.x() * BEAD_DISTANCE_BLOCKS,
                sunDir.y() * BEAD_DISTANCE_BLOCKS, sunDir.z() * BEAD_DISTANCE_BLOCKS);
        // LAYER law: Photon bead + Quasar glint together; either alone still reads.
        PhotonBridge.spawn(AtmospherePhotonFxRows.FX_TOTALITY_DIAMOND_RING, anchor);
        QuasarSpawner.spawn(AtmospherePhotonFxRows.QUASAR_DIAMOND_RING_GLINT, anchor,
                FxBudget.Channel.SEQUENCE);
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        reset();
    }

    private static void reset() {
        armed = true;
        lastAmount = Float.NaN;
        snapStartTick = Integer.MIN_VALUE;
        bandsEased = 0.0F;
        bandsWindowTicks = 0;
        bandsQuietTicks = BAND_RESET_TICKS;
    }
}
