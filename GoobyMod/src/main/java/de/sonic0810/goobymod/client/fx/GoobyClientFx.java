package de.sonic0810.goobymod.client.fx;

import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.entity.GoobyMood;
import java.util.List;
import javax.annotation.Nullable;
import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Client-only FX brain: caches the nearest own tamed Gooby (refreshed every
 * {@value #SCAN_INTERVAL_TICKS} ticks, never per frame) and drives the smooth
 * envelopes consumed by the companion HUD, the screen effects and the camera
 * shake. All state is client-render-thread only and cosmetic.
 */
@EventBusSubscriber(modid = GoobyMod.MODID, value = Dist.CLIENT)
public final class GoobyClientFx {
    /** Nearest-Gooby rescan cadence; deliberately far away from once-per-frame. */
    private static final int SCAN_INTERVAL_TICKS = 15;
    private static final double SCAN_RADIUS = 24.0;
    private static final double DROP_RADIUS = 32.0;
    /** After this many ticks without any tracked-value change the HUD fades out. */
    private static final int HUD_IDLE_TIMEOUT_TICKS = 200;
    private static final int SHAKE_COOLDOWN_TICKS = 120;
    private static final int SHAKE_DURATION_TICKS = 16;
    private static final double SHAKE_MAX_DISTANCE = 16.0;
    private static final double BOND_GLOW_DISTANCE = 4.5;
    private static final float BOND_GLOW_INTENSITY = 0.35F;
    /**
     * Wrap for the oscillator time base, far below 2^24 so the float sum in
     * {@link #animationTime(float)} keeps sub-tick precision even in very long
     * sessions. The wrap causes one imperceptible phase jump every ~14 hours.
     */
    private static final long TIME_WRAP_TICKS = 1_000_000L;

    @Nullable
    private static GoobyEntity tracked;
    private static int scanCountdown;
    private static long clientTicks;

    private static boolean wasAlerting;
    private static int shakeCooldown;
    private static int shakeTicksLeft;
    private static float shakeStrength;

    private static float cuddle;
    private static float cuddlePrev;
    private static float pulse;
    private static float pulsePrev;
    private static float hudAlpha;
    private static float hudAlphaPrev;
    private static int hudIdleTicks = HUD_IDLE_TIMEOUT_TICKS;

    private static int lastTrackedId = Integer.MIN_VALUE;
    private static int lastMoodOrdinal = -1;
    private static int lastCommandOrdinal = -1;
    private static int lastSatisfaction = -1;
    private static int lastHealthHalfHearts = -1;
    private static boolean lastAlerting;

    @SubscribeEvent
    public static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        LocalPlayer player = minecraft.player;
        if (player == null || minecraft.level == null) {
            reset();
            return;
        }
        if (minecraft.isPaused()) {
            return;
        }
        clientTicks++;
        cuddlePrev = cuddle;
        pulsePrev = pulse;
        hudAlphaPrev = hudAlpha;
        if (shakeCooldown > 0) {
            shakeCooldown--;
        }
        if (shakeTicksLeft > 0) {
            shakeTicksLeft--;
        }

        validateTracked(minecraft, player);
        if (--scanCountdown <= 0) {
            scanCountdown = SCAN_INTERVAL_TICKS;
            refreshTracked(minecraft, player);
        }

        boolean alerting = false;
        float cuddleTarget = 0.0F;
        float pulseTarget = 0.0F;
        if (tracked != null) {
            boolean petting = tracked.isBeingPettedBy(player.getUUID());
            alerting = tracked.isAlerting();
            double distanceSqr = player.distanceToSqr(tracked);
            if (petting) {
                cuddleTarget = 1.0F;
            } else if (tracked.getMood() == GoobyMood.HAPPY
                    && distanceSqr <= BOND_GLOW_DISTANCE * BOND_GLOW_DISTANCE) {
                cuddleTarget = BOND_GLOW_INTENSITY;
            }
            pulseTarget = alerting ? 1.0F : 0.0F;
            if (alerting && !wasAlerting) {
                triggerShake(Math.sqrt(distanceSqr));
            }
            updateHudActivity(tracked, petting, alerting);
        } else {
            hudIdleTicks = HUD_IDLE_TIMEOUT_TICKS;
            lastTrackedId = Integer.MIN_VALUE;
        }
        wasAlerting = alerting;

        cuddle = approach(cuddle, cuddleTarget, cuddleTarget > cuddle ? 0.10F : 0.045F);
        pulse = approach(pulse, pulseTarget, pulseTarget > pulse ? 0.25F : 0.06F);
        float hudTarget = tracked != null && hudIdleTicks < HUD_IDLE_TIMEOUT_TICKS ? 1.0F : 0.0F;
        hudAlpha = approach(hudAlpha, hudTarget, hudTarget > hudAlpha ? 0.16F : 0.08F);
    }

    private static void validateTracked(Minecraft minecraft, LocalPlayer player) {
        if (tracked == null) {
            return;
        }
        if (tracked.isRemoved() || !tracked.isAlive() || tracked.level() != minecraft.level
                || player.distanceToSqr(tracked) > DROP_RADIUS * DROP_RADIUS) {
            tracked = null;
        }
    }

    /** The only entity scan; runs every {@value #SCAN_INTERVAL_TICKS} ticks, never per frame. */
    private static void refreshTracked(Minecraft minecraft, LocalPlayer player) {
        List<GoobyEntity> nearby = minecraft.level.getEntitiesOfClass(GoobyEntity.class,
                player.getBoundingBox().inflate(SCAN_RADIUS),
                gooby -> gooby.isAlive() && gooby.isTame()
                        && player.getUUID().equals(gooby.getOwnerUUID()));
        GoobyEntity nearest = null;
        double best = Double.MAX_VALUE;
        for (GoobyEntity candidate : nearby) {
            double distanceSqr = player.distanceToSqr(candidate);
            if (distanceSqr < best) {
                best = distanceSqr;
                nearest = candidate;
            }
        }
        tracked = nearest;
    }

    /** Any visible value change re-arms the HUD; long silence lets it auto-fade. */
    private static void updateHudActivity(GoobyEntity gooby, boolean petting, boolean alerting) {
        int moodOrdinal = gooby.getMood().ordinal();
        int commandOrdinal = gooby.getCommandMode().ordinal();
        int satisfaction = gooby.getSatisfaction();
        int healthHalfHearts = Mth.ceil(gooby.getHealth() * 2.0F);
        boolean changed = gooby.getId() != lastTrackedId
                || moodOrdinal != lastMoodOrdinal
                || commandOrdinal != lastCommandOrdinal
                || satisfaction != lastSatisfaction
                || healthHalfHearts != lastHealthHalfHearts
                || alerting != lastAlerting
                || petting;
        lastTrackedId = gooby.getId();
        lastMoodOrdinal = moodOrdinal;
        lastCommandOrdinal = commandOrdinal;
        lastSatisfaction = satisfaction;
        lastHealthHalfHearts = healthHalfHearts;
        lastAlerting = alerting;
        if (changed) {
            hudIdleTicks = 0;
        } else if (hudIdleTicks < HUD_IDLE_TIMEOUT_TICKS) {
            hudIdleTicks++;
        }
    }

    private static void triggerShake(double distance) {
        if (shakeCooldown > 0 || distance > SHAKE_MAX_DISTANCE) {
            return;
        }
        shakeStrength = Mth.clamp(1.0F - (float) (distance / SHAKE_MAX_DISTANCE), 0.2F, 1.0F);
        shakeTicksLeft = SHAKE_DURATION_TICKS;
        shakeCooldown = SHAKE_COOLDOWN_TICKS;
    }

    private static float approach(float value, float target, float rate) {
        return value + (target - value) * rate;
    }

    private static void reset() {
        tracked = null;
        scanCountdown = 0;
        wasAlerting = false;
        shakeCooldown = 0;
        shakeTicksLeft = 0;
        shakeStrength = 0.0F;
        cuddle = 0.0F;
        cuddlePrev = 0.0F;
        pulse = 0.0F;
        pulsePrev = 0.0F;
        hudAlpha = 0.0F;
        hudAlphaPrev = 0.0F;
        hudIdleTicks = HUD_IDLE_TIMEOUT_TICKS;
        lastTrackedId = Integer.MIN_VALUE;
        lastMoodOrdinal = -1;
        lastCommandOrdinal = -1;
        lastSatisfaction = -1;
        lastHealthHalfHearts = -1;
        lastAlerting = false;
    }

    @Nullable
    public static GoobyEntity trackedGooby() {
        return tracked;
    }

    public static float hudAlpha(float partialTick) {
        return Mth.lerp(partialTick, hudAlphaPrev, hudAlpha);
    }

    public static float cuddleIntensity(float partialTick) {
        return Mth.lerp(partialTick, cuddlePrev, cuddle);
    }

    public static float alarmPulse(float partialTick) {
        return Mth.lerp(partialTick, pulsePrev, pulse);
    }

    /** Decaying 0..1 shake envelope, already scaled by the distance falloff. */
    public static float shakeAmount(float partialTick) {
        if (shakeTicksLeft <= 0) {
            return 0.0F;
        }
        float remaining = (shakeTicksLeft - partialTick) / SHAKE_DURATION_TICKS;
        return Mth.clamp(remaining, 0.0F, 1.0F) * shakeStrength;
    }

    /** Shared oscillator time base in ticks, for sine-driven pulse/shake motion. */
    public static float animationTime(float partialTick) {
        return (clientTicks % TIME_WRAP_TICKS) + partialTick;
    }

    private GoobyClientFx() {
    }
}
