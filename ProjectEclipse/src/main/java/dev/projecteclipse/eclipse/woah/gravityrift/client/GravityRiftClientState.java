package dev.projecteclipse.eclipse.woah.gravityrift.client;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.woah.gravityrift.GravityRiftPayloads;
import dev.projecteclipse.eclipse.woah.gravityrift.GravityRiftZone;
import net.minecraft.client.Minecraft;
import net.minecraft.core.BlockPos;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * WOAH-02 client zone state (plan §4.1): the payload mirror (built + crater-floor
 * anchor + inversion window) and the eased inside-amount derived every client tick
 * from the camera's distance to the heart (the {@code ChronoZoneState} ease numbers).
 * The pulse beat is NOT synced — it is recomputed locally on the identical absolute
 * raster {@code gameTime % PERIOD == phaseOffset(anchor)} (client game time rides the
 * vanilla time sync), so lens kicks, Photon rings and the server launch land on the
 * same tick by construction.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class GravityRiftClientState {
    /** Below this eased amount every consumer idle-skips. */
    public static final float MIN_ACTIVE = 0.01F;
    /** Per-tick approach factor toward the distance target (~90% in 12 ticks). */
    private static final float EASE_RATE = 0.18F;
    /** Snap distance so the ease terminates instead of crawling. */
    private static final float SNAP = 0.004F;
    /** The amount ramps over the last 14 blocks before the zone edge. */
    private static final float RAMP_BLOCKS = 14.0F;
    /** Lens ramp outer edge: zone radius + a short approach apron. */
    private static final float EDGE_RADIUS = GravityRiftZone.ZONE_RADIUS + 6.0F;

    /** Beat-kick decay (ticks past the beat until the lens shock fades). */
    private static final int PULSE_KICK_TICKS = 24;
    /** Telegraph converge ramp peak (fraction of the full kick). */
    private static final float TELEGRAPH_PEAK = 0.4F;

    private static boolean built;
    @Nullable
    private static BlockPos anchor;
    /** Client game time the inversion window ends (0 = none). */
    private static long invertEndGameTime;

    private static float previousAmount;
    private static float amount;
    private static double cameraDistance = Double.MAX_VALUE;

    private GravityRiftClientState() {}

    // ------------------------------------------------------------------ payload mirror

    /** Payload hook ({@link GravityRiftPayloads} handler, client main thread). */
    public static void handleState(GravityRiftPayloads.S2CGravityRiftPayload payload) {
        built = payload.built();
        anchor = payload.built() ? payload.anchor() : null;
        Minecraft minecraft = Minecraft.getInstance();
        if (payload.invertRemainingTicks() > 0 && minecraft.level != null) {
            invertEndGameTime = minecraft.level.getGameTime() + payload.invertRemainingTicks();
        } else {
            invertEndGameTime = 0L;
        }
    }

    public static boolean built() {
        return built;
    }

    /** Crater-floor anchor, or {@code null} until the build payload arrived. */
    @Nullable
    public static BlockPos anchor() {
        return anchor;
    }

    /** Heart center in world space, or {@code null} until built. */
    @Nullable
    public static Vec3 heartCenter() {
        BlockPos current = anchor;
        if (current == null) {
            return null;
        }
        return new Vec3(current.getX() + 0.5D, current.getY() + GravityRiftZone.HEART_HEIGHT,
                current.getZ() + 0.5D);
    }

    // ------------------------------------------------------------------ derived reads

    /** Eased inside amount 0..1 (frame-interpolated). */
    public static float amount(float partialTick) {
        return Mth.lerp(partialTick, previousAmount, amount);
    }

    /** Eased inside amount 0..1 (tick-rate). */
    public static float amount() {
        return amount;
    }

    /** Camera→heart distance in blocks ({@code MAX_VALUE} while unbuilt). */
    public static double cameraDistance() {
        return cameraDistance;
    }

    /**
     * Pulse-kick envelope 0..1 on the local beat raster: the telegraph converges
     * 0→{@value #TELEGRAPH_PEAK} over the {@value GravityRiftZone#PULSE_TELEGRAPH_TICKS}
     * pre-beat ticks, snaps to 1 on the beat and decays over
     * {@value #PULSE_KICK_TICKS} t — the lens "shock front".
     */
    public static float pulseKick() {
        BlockPos current = anchor;
        Minecraft minecraft = Minecraft.getInstance();
        if (current == null || minecraft.level == null) {
            return 0.0F;
        }
        long gameTime = minecraft.level.getGameTime();
        int offset = GravityRiftZone.pulsePhaseOffset(current);
        long phase = Math.floorMod(gameTime - offset, (long) GravityRiftZone.PULSE_PERIOD_TICKS);
        if (phase < PULSE_KICK_TICKS) {
            return 1.0F - phase / (float) PULSE_KICK_TICKS;
        }
        long untilBeat = GravityRiftZone.PULSE_PERIOD_TICKS - phase;
        if (untilBeat <= GravityRiftZone.PULSE_TELEGRAPH_TICKS) {
            return TELEGRAPH_PEAK
                    * (1.0F - untilBeat / (float) GravityRiftZone.PULSE_TELEGRAPH_TICKS);
        }
        return 0.0F;
    }

    /**
     * Inversion envelope 0..1 mirroring the server window: rise over 20 t from the
     * start, hold through the active phase, glide to 0 across the last
     * {@code TOTAL − ACTIVE} ticks — feeds the lens {@code Invert} uniform.
     */
    public static float invertAmount() {
        Minecraft minecraft = Minecraft.getInstance();
        if (invertEndGameTime == 0L || minecraft.level == null) {
            return 0.0F;
        }
        long gameTime = minecraft.level.getGameTime();
        long tau = gameTime - (invertEndGameTime - GravityRiftZone.INVERT_TOTAL_TICKS);
        if (tau < 0 || tau >= GravityRiftZone.INVERT_TOTAL_TICKS) {
            return 0.0F;
        }
        if (tau < 20) {
            return tau / 20.0F;
        }
        if (tau < GravityRiftZone.INVERT_ACTIVE_TICKS) {
            return 1.0F;
        }
        float glide = (tau - GravityRiftZone.INVERT_ACTIVE_TICKS)
                / (float) (GravityRiftZone.INVERT_TOTAL_TICKS - GravityRiftZone.INVERT_ACTIVE_TICKS);
        return 1.0F - glide;
    }

    // ------------------------------------------------------------------ tick

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        previousAmount = amount;
        float target = computeTarget();
        amount = Mth.clamp(amount + (target - amount) * EASE_RATE,
                Math.min(amount, target), Math.max(amount, target));
        if (Math.abs(target - amount) < SNAP) {
            amount = target;
        }
    }

    private static float computeTarget() {
        Minecraft minecraft = Minecraft.getInstance();
        Vec3 heart = heartCenter();
        if (minecraft.level == null || heart == null) {
            cameraDistance = Double.MAX_VALUE;
            return 0.0F;
        }
        Vec3 camera = minecraft.gameRenderer.getMainCamera().getPosition();
        cameraDistance = camera.distanceTo(heart);
        return (float) Mth.clamp((EDGE_RADIUS - cameraDistance) / RAMP_BLOCKS, 0.0D, 1.0D);
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        built = false;
        anchor = null;
        invertEndGameTime = 0L;
        previousAmount = 0.0F;
        amount = 0.0F;
        cameraDistance = Double.MAX_VALUE;
    }
}
