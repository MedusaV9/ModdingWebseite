package dev.projecteclipse.eclipse.client.backrooms;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.backrooms.BackroomsPayloads;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.resources.sounds.SimpleSoundInstance;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.RegisterGuiLayersEvent;
import net.neoforged.neoforge.client.gui.VanillaGuiLayers;

/**
 * The F-042 <b>light flicker</b> — client presentation of
 * {@code BackroomsPayloads.S2CBackroomsFlickerPayload}. The server never toggles a single
 * blockstate for this: it sends one envelope ({@code duration}, {@code intensity},
 * {@code pattern}) and every recipient of that trigger derives the SAME irregular dark
 * train from {@code pattern}, so a whole room blacks out together for free.
 *
 * <p><b>Envelope</b>: {@value #MIN_PULSES}–{@value #MAX_PULSES} dark pulses spread over
 * the 2–4 s window, each one a short raised-cosine dip to at most
 * {@value #PEAK_ALPHA} alpha of near-black with the backrooms yellow rot in it, plus a
 * {@code SCULK_CLICKING} tick as the lights go and a second one on the pulse after (the
 * failing-ballast read).</p>
 *
 * <p><b>Photosensitivity</b> (the §A2/§A4 house rule): pulse STARTS are hard-spaced at
 * least {@value #MIN_PULSE_GAP_MILLIS} ms apart, i.e. never more than ~2 Hz, and every
 * dip fades in and out instead of hard-cutting. With {@code reducedFx} the strobe is
 * replaced entirely by ONE slow dim to {@value #REDUCED_PEAK_ALPHA} over the whole
 * window plus the sound.</p>
 *
 * <p>GUI layer: registered from THIS class (the {@code BackroomsRenderers} P6
 * no-shared-file precedent) under the crosshair, so the HUD stays readable while the
 * room is dark. Deliberately NOT added to {@code LetterboxLayer}'s HUD whitelist — that
 * single call stays owned by {@code EclipseGuiLayers}, and cutscene HUD suppression is
 * supposed to hide this. Reset on logout.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class BackroomsFlickerOverlay {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "backrooms_flicker");

    private static final int MIN_PULSES = 3;
    private static final int MAX_PULSES = 6;
    /** Photosensitivity floor: ≥ 450 ms between pulse starts ⇒ ≤ ~2.2 flashes/second. */
    private static final long MIN_PULSE_GAP_MILLIS = 450L;
    private static final long MIN_PULSE_LENGTH_MILLIS = 160L;
    private static final long MAX_PULSE_LENGTH_MILLIS = 420L;
    /** Darkest a pulse may get (never fully opaque — you can still see the exit). */
    private static final float PEAK_ALPHA = 0.82F;
    /** reducedFx: one slow dim instead of the train. */
    private static final float REDUCED_PEAK_ALPHA = 0.35F;
    /** Near-black with the yellow rot tint (the JumpscareOverlay vignette colour). */
    private static final int TINT_RED = 0x0D;
    private static final int TINT_GREEN = 0x0B;
    private static final int TINT_BLUE = 0x02;

    /** Envelope start, wall clock; {@code 0} = idle (a stalled tick cannot freeze it). */
    private static long startMillis;
    private static long durationMillis;
    private static float intensity;
    private static boolean reduced;
    private static long[] pulseStart = new long[0];
    private static long[] pulseLength = new long[0];
    /** Whether the second (ballast-echo) click of this envelope has already played. */
    private static boolean ballastClicked;

    static {
        // Payload consumer seam: installed on client class-load so the common-side
        // BackroomsPayloads never references client classes.
        BackroomsPayloads.setClientFlickerHandler(payload ->
                trigger(payload.durationTicks(), payload.intensity(), payload.pattern()));
    }

    private BackroomsFlickerOverlay() {}

    @SubscribeEvent
    static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
        event.registerBelow(VanillaGuiLayers.CROSSHAIR, LAYER_ID, BackroomsFlickerOverlay::render);
    }

    /** Payload entry (client main thread). A running envelope is never stacked/extended. */
    public static void trigger(int durationTicks, float payloadIntensity, long pattern) {
        long now = System.currentTimeMillis();
        if (startMillis != 0L && now - startMillis < durationMillis) {
            return;
        }
        startMillis = now;
        durationMillis = Math.max(500L, durationTicks * 50L);
        intensity = Mth.clamp(payloadIntensity, 0.0F, 1.0F);
        reduced = EclipseClientConfig.reducedFx();
        ballastClicked = false;
        buildPulses(pattern);

        playClick(0.75F);
        EclipseMod.LOGGER.debug("Backrooms flicker: {} ms, intensity {}, {} pulses (reducedFx {})",
                durationMillis, intensity, pulseStart.length, reduced);
    }

    /**
     * Derives the irregular dark train from the shared pattern seed: pulses walk forward
     * with a hashed gap that is never shorter than {@value #MIN_PULSE_GAP_MILLIS} ms, so
     * the rhythm reads broken but stays under the flash ceiling.
     */
    private static void buildPulses(long pattern) {
        if (reduced) {
            pulseStart = new long[0];
            pulseLength = new long[0];
            return;
        }
        int wanted = MIN_PULSES + (int) Math.floorMod(pattern, MAX_PULSES - MIN_PULSES + 1L);
        long[] starts = new long[wanted];
        long[] lengths = new long[wanted];
        long cursor = 60L;
        int count = 0;
        for (int i = 0; i < wanted; i++) {
            long h = scramble(pattern + i * 0x9E3779B97F4A7C15L);
            long length = MIN_PULSE_LENGTH_MILLIS
                    + Math.floorMod(h, MAX_PULSE_LENGTH_MILLIS - MIN_PULSE_LENGTH_MILLIS + 1L);
            if (cursor + length > durationMillis) {
                break;
            }
            starts[count] = cursor;
            lengths[count] = length;
            count++;
            cursor += Math.max(MIN_PULSE_GAP_MILLIS, length + Math.floorMod(h >>> 17, 260L));
        }
        pulseStart = java.util.Arrays.copyOf(starts, count);
        pulseLength = java.util.Arrays.copyOf(lengths, count);
    }

    private static long scramble(long x) {
        x ^= x >>> 33;
        x *= 0xFF51AFD7ED558CCDL;
        x ^= x >>> 33;
        return x;
    }

    /** GUI-layer body (registered above by this class, below the crosshair). */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        if (startMillis == 0L) {
            return;
        }
        long t = System.currentTimeMillis() - startMillis;
        if (t >= durationMillis) {
            startMillis = 0L;
            return;
        }
        float alpha;
        if (reduced) {
            alpha = reducedAlpha(t);
        } else {
            int pulse = activePulse(t);
            if (pulse == 1 && !ballastClicked) {
                ballastClicked = true; // the ballast tries once more before it gives up
                playClick(0.55F);
            }
            alpha = pulse < 0 ? 0.0F : pulseAlpha(t, pulse);
        }
        if (alpha <= 0.01F) {
            return;
        }
        guiGraphics.fill(0, 0, guiGraphics.guiWidth(), guiGraphics.guiHeight(),
                argb(alpha, TINT_RED, TINT_GREEN, TINT_BLUE));
    }

    private static void playClick(float volume) {
        Minecraft.getInstance().getSoundManager().play(SimpleSoundInstance.forUI(
                SoundEvents.SCULK_CLICKING, 0.45F + 0.2F * intensity, volume * intensity));
    }

    /** reducedFx: a single raised-cosine dim across the whole window, no strobe at all. */
    private static float reducedAlpha(long t) {
        float phase = Mth.clamp(t / (float) durationMillis, 0.0F, 1.0F);
        return REDUCED_PEAK_ALPHA * intensity
                * (float) (0.5D - 0.5D * Math.cos(phase * Math.PI * 2.0D));
    }

    /** Index of the pulse covering {@code t}, or {@code -1} between pulses. */
    private static int activePulse(long t) {
        for (int i = 0; i < pulseStart.length; i++) {
            if (t >= pulseStart[i] && t < pulseStart[i] + pulseLength[i]) {
                return i;
            }
        }
        return -1;
    }

    /** The strobe train: each pulse is a raised-cosine dip, so nothing hard-cuts. */
    private static float pulseAlpha(long t, int pulse) {
        float phase = (t - pulseStart[pulse]) / (float) pulseLength[pulse];
        return PEAK_ALPHA * intensity * (float) (0.5D - 0.5D * Math.cos(phase * Math.PI * 2.0D));
    }

    private static int argb(float alpha, int red, int green, int blue) {
        return (Mth.floor(Mth.clamp(alpha, 0.0F, 1.0F) * 255.0F) << 24)
                | (red << 16) | (green << 8) | blue;
    }

    /** Disconnect reset — a blackout can never leak into the next session. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        startMillis = 0L;
        durationMillis = 0L;
        ballastClicked = false;
        pulseStart = new long[0];
        pulseLength = new long[0];
    }
}
