package dev.projecteclipse.eclipse.cutscene.dev;

import java.util.Arrays;
import java.util.Locale;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.stormfx.StormFlashDevHold;
import dev.projecteclipse.eclipse.stormfx.StormVolumeFx;
import dev.projecteclipse.eclipse.veilfx.VeilPostController;
import net.minecraft.ChatFormatting;
import net.minecraft.Util;
import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.network.chat.Component;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.RenderFrameEvent;

/**
 * POLISH4 / STORM-MASS §6 V6: the client-side frametime probe behind
 * {@code /eclipsefx storm perfprobe [seconds]} — the headless-capable half of the V6
 * perf acceptance (fixed camera point, tier 2/1/0 A/B via {@code stormVolumeQuality}).
 *
 * <p>Samples {@link Minecraft#getFrameTimeNs()} once per rendered frame (via
 * {@link RenderFrameEvent.Post} — one event per frame; the value is the PREVIOUS
 * frame's render-phase duration, i.e. work time excluding the framerate-limiter wait,
 * so the very first event after start is skipped as pre-probe). After the wall-clock
 * window elapses it reports frame count, min/avg/p95/max frametime and the
 * render-bound fps estimate to the operator's chat AND the client log (grep for
 * {@code "V6 perfprobe"}), together with the A/B context that matters for V6:
 * {@code stormVolumeQuality} tier, whether the {@code eclipse:storm_volume} pipeline
 * is live in Veil's manager, and the {@code flashhold} dev-override state.</p>
 *
 * <p>Pure dev instrumentation: inert until started by the {@code FxDevClient} action,
 * zero per-frame work while inactive (one static boolean read), state cleared on
 * logout. Sample memory is bounded ({@value #MAX_SECONDS} s × 1000 fps worst case)
 * and released after the report.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class FrameTimeProbe {
    /** Probe window clamp (s) — matches the command's argument bounds. */
    private static final int MIN_SECONDS = 2;
    private static final int MAX_SECONDS = 120;
    /** Sample buffer sizing: no realistic client renders more than this many fps. */
    private static final int MAX_FPS_BUDGET = 1000;

    private static long[] samples;
    private static int count;
    private static long endMillis;
    private static boolean skippedFirst;
    /** Volatile: started from the netty/main thread, read per rendered frame. */
    private static volatile boolean active;

    private FrameTimeProbe() {}

    /** Entry point from {@code FxDevClient} ({@code /eclipsefx storm perfprobe}). */
    static void start(float seconds) {
        int secs = Mth.clamp(Math.round(seconds), MIN_SECONDS, MAX_SECONDS);
        samples = new long[secs * MAX_FPS_BUDGET];
        count = 0;
        skippedFirst = false;
        endMillis = Util.getMillis() + secs * 1000L;
        active = true;
        feedback(String.format(Locale.ROOT,
                "[perfprobe] sampling frametimes for %d s — %s ...", secs, context()),
                ChatFormatting.GOLD);
    }

    @SubscribeEvent
    static void onRenderFrame(RenderFrameEvent.Post event) {
        if (!active) {
            return;
        }
        if (!skippedFirst) {
            skippedFirst = true; // frameTimeNs still holds the pre-start frame
            return;
        }
        long ns = Minecraft.getInstance().getFrameTimeNs();
        if (ns > 0L && count < samples.length) {
            samples[count++] = ns;
        }
        if (Util.getMillis() >= endMillis || count >= samples.length) {
            finish();
        }
    }

    private static void finish() {
        active = false;
        long[] window = samples;
        samples = null;
        if (window == null || count == 0) {
            feedback("[perfprobe] no frames completed in the window — window too short"
                    + " for this frame rate, retry with more seconds", ChatFormatting.RED);
            return;
        }
        long[] sorted = Arrays.copyOf(window, count);
        Arrays.sort(sorted);
        double sum = 0.0D;
        for (int i = 0; i < count; i++) {
            sum += sorted[i];
        }
        double avgNs = sum / count;
        long p95Ns = sorted[Math.min(count - 1, (int) Math.ceil(count * 0.95D) - 1)];
        String line = String.format(Locale.ROOT,
                "%d frames — frametime min %.2f / avg %.2f / p95 %.2f / max %.2f ms"
                        + " (≈%.1f fps render-bound) | %s",
                count,
                sorted[0] / 1.0e6D,
                avgNs / 1.0e6D,
                p95Ns / 1.0e6D,
                sorted[count - 1] / 1.0e6D,
                1.0e9D / avgNs,
                context());
        feedback("[perfprobe] " + line, ChatFormatting.GREEN);
        EclipseMod.LOGGER.info("V6 perfprobe: {}", line);
    }

    /** The V6 A/B context: config tier, live volume pipeline, flash-hold override. */
    private static String context() {
        return String.format(Locale.ROOT,
                "stormVolumeQuality=%d, storm_volume pipeline %s, flashhold %s",
                EclipseClientConfig.stormVolumeQuality(),
                VeilPostController.isActive(StormVolumeFx.STORM_VOLUME_POST) ? "ACTIVE" : "off",
                StormFlashDevHold.active() ? "ON" : "off");
    }

    /** Dev-session hygiene: no probe survives a disconnect. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        active = false;
        samples = null;
    }

    private static void feedback(String message, ChatFormatting color) {
        LocalPlayer player = Minecraft.getInstance().player;
        if (player != null) {
            player.displayClientMessage(Component.literal(message).withStyle(color), false);
        } else {
            EclipseMod.LOGGER.info("FrameTimeProbe: {}", message);
        }
    }
}
