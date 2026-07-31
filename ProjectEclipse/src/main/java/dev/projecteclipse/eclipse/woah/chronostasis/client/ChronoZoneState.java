package dev.projecteclipse.eclipse.woah.chronostasis.client;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.veilfx.FxAnchors;
import dev.projecteclipse.eclipse.woah.chronostasis.ChronoStasisSite;
import net.minecraft.client.Minecraft;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * WOAH-03 client zone state (plan §4.1): the eased inside-amount derived every client
 * tick from the camera's distance to the {@link FxAnchors#CHRONO_CENTER} anchor (no
 * dedicated payload — the anchor lane already syncs at login), plus the short-lived
 * JOLT/DISCHARGE windows armed by the cue rows in {@code ChronoStasisFxRows}.
 *
 * <p>Ease numbers are the {@code GlitchZoneFx} set (EASE_RATE 0.18, SNAP, MIN_ACTIVE).
 * The amount deliberately IGNORES {@code reducedFx}: the tick sound and the rain-mixin
 * gate are gameplay-adjacent reads and stay on under reduced FX (plan §8) — the grade and
 * every Photon window apply their own gates.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ChronoZoneState {
    /** Below this eased amount every consumer idle-skips. */
    public static final float MIN_ACTIVE = 0.01F;
    /** Per-tick approach factor toward the distance target (~90% in 12 ticks). */
    private static final float EASE_RATE = 0.18F;
    /** Snap distance so the ease terminates instead of crawling. */
    private static final float SNAP = 0.004F;
    /** The amount ramps over the last 12 blocks before {@link ChronoStasisSite#RADIUS}. */
    private static final float RAMP_BLOCKS = 12.0F;

    /** Client mirror of the server DISCHARGE window (cue arrives at server t=30). */
    private static final int DISCHARGE_WINDOW_TICKS = 230;
    /** How long the falling-rain phase lasts after the discharge cue (server t=30..110). */
    private static final int RAIN_RELEASE_TICKS = 80;
    /** JOLT window: tick-sound pause + scene shimmer. */
    private static final int JOLT_WINDOW_TICKS = 60;

    private static float previousAmount;
    private static float amount;
    private static double cameraDistance = Double.MAX_VALUE;
    private static int joltTicks;
    private static int dischargeTicks;

    private ChronoZoneState() {}

    /** Eased inside amount 0..1 (frame-interpolated). */
    public static float amount(float partialTick) {
        return Mth.lerp(partialTick, previousAmount, amount);
    }

    /** Eased inside amount 0..1 (tick-rate). */
    public static float amount() {
        return amount;
    }

    /** Camera→anchor distance in blocks ({@code MAX_VALUE} while the anchor is unset). */
    public static double cameraDistance() {
        return cameraDistance;
    }

    /** 0 at the center, 1 at {@link ChronoStasisSite#RADIUS} (tick-sound period driver). */
    public static float distanceRatio() {
        return (float) Mth.clamp(cameraDistance / ChronoStasisSite.RADIUS, 0.0D, 1.0D);
    }

    /**
     * Mixin gate (plan §4.4): all-or-nothing above 0.6, released during the discharge
     * rain phase so the "rain falls all at once" beat uses REAL vanilla rain streaks on
     * photon-less clients too (the Photon release shot layers on top elsewhere).
     */
    public static boolean suppressVanillaRain() {
        return amount > 0.6F && !rainReleaseActive();
    }

    /** True during the falling-rain beat of a discharge (first ~4 s after the cue). */
    public static boolean rainReleaseActive() {
        return dischargeTicks > DISCHARGE_WINDOW_TICKS - RAIN_RELEASE_TICKS;
    }

    /** True while a time-jolt window runs (tick sound pauses, scene shimmers). */
    public static boolean joltActive() {
        return joltTicks > 0;
    }

    /** True while the discharge/rewind window runs (tick sound mutes, grade kicks). */
    public static boolean dischargeActive() {
        return dischargeTicks > 0;
    }

    /**
     * White-kick envelope for the grade (plan §4.2, W13-C3 flicker beat): the stasis
     * BREAKS in three receding stutters instead of one monotone decay — spikes
     * 1.00 @ t0 (8 t decay), 0.55 @ t14 (7 t) and 0.30 @ t26 (8 t). Three flashes in
     * 34 ticks ≈ 1.8 Hz, safely under the 3 Hz photosensitivity line; same single
     * {@code Flash} uniform, the feeder contract is unchanged.
     */
    public static float dischargeFlash() {
        int elapsed = DISCHARGE_WINDOW_TICKS - dischargeTicks;
        if (dischargeTicks <= 0 || elapsed > 34) {
            return 0.0F;
        }
        float flash = flashSpike(elapsed, 0, 8, 1.00F);
        flash = Math.max(flash, flashSpike(elapsed, 14, 7, 0.55F));
        return Math.max(flash, flashSpike(elapsed, 26, 8, 0.30F));
    }

    /** One stutter of the break flicker: {@code peak} at {@code start}, linear decay. */
    private static float flashSpike(int elapsed, int start, int decayTicks, float peak) {
        int local = elapsed - start;
        return local < 0 || local > decayTicks
                ? 0.0F
                : peak * (1.0F - (float) local / decayTicks);
    }

    /** Cue hook ({@code ChronoStasisFxRows}): a ≥ 0 = a real time-jolt. */
    public static void onJoltCue(float a) {
        if (a >= 0.0F) {
            joltTicks = JOLT_WINDOW_TICKS;
        }
    }

    /** Cue hook ({@code ChronoStasisFxRows}): the discharge resolution began. */
    public static void onDischargeCue() {
        dischargeTicks = DISCHARGE_WINDOW_TICKS;
        joltTicks = 0;
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        previousAmount = amount;
        float target = computeTarget();
        amount = Mth.clamp(amount + (target - amount) * EASE_RATE,
                Math.min(amount, target), Math.max(amount, target));
        if (Math.abs(target - amount) < SNAP) {
            amount = target;
        }
        if (!Minecraft.getInstance().isPaused()) {
            if (joltTicks > 0) {
                joltTicks--;
            }
            if (dischargeTicks > 0) {
                dischargeTicks--;
            }
        }
    }

    private static float computeTarget() {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            cameraDistance = Double.MAX_VALUE;
            return 0.0F;
        }
        Vec3 anchor = anchorPos();
        if (anchor == null) {
            cameraDistance = Double.MAX_VALUE;
            return 0.0F;
        }
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        cameraDistance = camera.distanceTo(anchor);
        // 1 inside RADIUS − 12, ramping to 0 at RADIUS (GlitchZoneFx-style edge gradient).
        return (float) Mth.clamp(
                (ChronoStasisSite.RADIUS - cameraDistance) / RAMP_BLOCKS, 0.0D, 1.0D);
    }

    @Nullable
    static Vec3 anchorPos() {
        return FxAnchors.get(FxAnchors.CHRONO_CENTER);
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        previousAmount = 0.0F;
        amount = 0.0F;
        cameraDistance = Double.MAX_VALUE;
        joltTicks = 0;
        dischargeTicks = 0;
    }
}
