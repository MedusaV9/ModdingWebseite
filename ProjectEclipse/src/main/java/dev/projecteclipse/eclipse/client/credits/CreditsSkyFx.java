package dev.projecteclipse.eclipse.client.credits;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.credits.CreditsPayloads;
import dev.projecteclipse.eclipse.network.credits.CreditsPayloads.S2CCreditsSkyPayload;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Client sky state of the credits' two staged sky moments (F-056/F-058), driven by
 * {@link S2CCreditsSkyPayload} ({@code CreditsSequence} owns every send):
 *
 * <ul>
 *   <li><b>COLLAPSE</b> (island shatter) — {@link #skyDarken} eases toward the payload
 *       intensity and {@link #starBrightness} rises with it: the sky "zieht sich
 *       zusammen" while the stars come out. {@code OverworldPurpleEffects.renderSky}
 *       consumes both (dome crush + celestial fade + star pull).</li>
 *   <li><b>SPACE</b> (black-hole finale) — darken and stars pin to 1 (pure space dome,
 *       no sun/moon: the celestial fade zeroes them) and {@link #holeAmount} eases
 *       toward the payload intensity, feeding the {@code eclipse:black_hole} post pass
 *       ({@link CreditsBlackHolePostFx}) and any other black-hole layer.
 *       {@link #holeCenter} is the hole's world anchor for the per-frame screen-space
 *       projection.</li>
 * </ul>
 *
 * <p>All three scalars are eased client-side over the payload's {@code rampTicks}
 * (the {@code EclipseFxState} from/target/startTick recipe) so a mid-ramp re-send never
 * pops. Everything resets on logout — a credits sky can never leak into the next
 * session; mid-run rejoiners are re-synced by {@code CreditsSequence.onLoggedIn}.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class CreditsSkyFx {
    static {
        CreditsPayloads.setClientSkyHandler(CreditsSkyFx::handle);
        CreditsPayloads.setClientPulseHandler(CreditsSkyFx::handlePulse);
    }

    /** F-072 V3 gulp envelope: {@value}t attack, {@value #PULSE_DECAY_TICKS}t decay. */
    private static final float PULSE_ATTACK_TICKS = 3.0F;
    private static final float PULSE_DECAY_TICKS = 15.0F;

    /** Client thread only. */
    private static int clientTicks;

    private static float darkenFrom;
    private static float darkenTarget;
    private static float starsFrom;
    private static float starsTarget;
    private static float holeFrom;
    private static float holeTarget;
    private static int rampStartTick;
    private static int rampTicks = 1;
    private static Vec3 holeCenter = Vec3.ZERO;
    /** V3 gulp pulse state ({@code S2CCreditsPulsePayload}). */
    private static float pulseStrength;
    private static int pulseStartTick = Integer.MIN_VALUE / 2;

    private CreditsSkyFx() {}

    private static void handle(S2CCreditsSkyPayload payload) {
        float intensity = Mth.clamp(payload.intensity(), 0.0F, 1.0F);
        darkenFrom = skyDarken(0.0F);
        starsFrom = starBrightness(0.0F);
        holeFrom = holeAmount(0.0F);
        switch (payload.mode()) {
            case S2CCreditsSkyPayload.MODE_COLLAPSE -> {
                darkenTarget = intensity;
                starsTarget = intensity * 0.9F;
                holeTarget = 0.0F;
            }
            case S2CCreditsSkyPayload.MODE_SPACE -> {
                darkenTarget = 1.0F;
                starsTarget = 1.0F;
                holeTarget = intensity;
                holeCenter = new Vec3(payload.holeX(), payload.holeY(), payload.holeZ());
            }
            default -> {
                darkenTarget = 0.0F;
                starsTarget = 0.0F;
                holeTarget = 0.0F;
            }
        }
        rampStartTick = clientTicks;
        rampTicks = Math.max(1, payload.rampTicks());
        EclipseMod.LOGGER.info("Credits sky: mode {} intensity {} ramp {}t",
                payload.mode(), intensity, payload.rampTicks());
    }

    /** Eased sky-dome darkening 0..1 (0 = vanilla sky, 1 = pure space black). */
    public static float skyDarken(float partialTick) {
        return Mth.lerp(progress(partialTick), darkenFrom, darkenTarget);
    }

    /** Eased forced star brightness 0..1 (max()'d over the vanilla night value). */
    public static float starBrightness(float partialTick) {
        return Mth.lerp(progress(partialTick), starsFrom, starsTarget);
    }

    /** Eased black-hole strength 0..1 — drives the post distortion + desaturation. */
    public static float holeAmount(float partialTick) {
        return Mth.lerp(progress(partialTick), holeFrom, holeTarget);
    }

    /** The black hole's world center (SPACE mode; projected per frame by the post pass). */
    public static Vec3 holeCenter() {
        return holeCenter;
    }

    /** F-072 V3: latches one gulp impulse (overlapping gulps restart the envelope). */
    private static void handlePulse(CreditsPayloads.S2CCreditsPulsePayload payload) {
        // Never let a stray weak pulse cut a strong flare short mid-attack.
        float live = holePulse(0.0F);
        pulseStrength = Math.max(Mth.clamp(payload.strength(), 0.0F, 1.0F), live);
        pulseStartTick = clientTicks;
    }

    /**
     * F-072 V3: the eased gulp envelope 0..1 — a {@value #PULSE_ATTACK_TICKS}t attack
     * and a {@value #PULSE_DECAY_TICKS}t decay around each {@code
     * S2CCreditsPulsePayload}. Feeds the post pass's {@code Pulse} uniform (horizon
     * breath + ring flare); 0 between gulps, so the layer is a strict no-op then.
     */
    public static float holePulse(float partialTick) {
        float age = clientTicks - pulseStartTick + partialTick;
        if (age < 0.0F || age >= PULSE_ATTACK_TICKS + PULSE_DECAY_TICKS) {
            return 0.0F;
        }
        float env = age < PULSE_ATTACK_TICKS
                ? age / PULSE_ATTACK_TICKS
                : 1.0F - (age - PULSE_ATTACK_TICKS) / PULSE_DECAY_TICKS;
        return pulseStrength * env * env * (3.0F - 2.0F * env);
    }

    private static float progress(float partialTick) {
        float linear = Mth.clamp(
                (clientTicks - rampStartTick + partialTick) / rampTicks, 0.0F, 1.0F);
        return linear * linear * (3.0F - 2.0F * linear);
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        clientTicks++;
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        darkenFrom = 0.0F;
        darkenTarget = 0.0F;
        starsFrom = 0.0F;
        starsTarget = 0.0F;
        holeFrom = 0.0F;
        holeTarget = 0.0F;
        rampTicks = 1;
        rampStartTick = clientTicks;
        holeCenter = Vec3.ZERO;
        pulseStrength = 0.0F;
        pulseStartTick = Integer.MIN_VALUE / 2;
    }
}
