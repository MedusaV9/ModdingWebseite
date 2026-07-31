package dev.projecteclipse.eclipse.stormfx;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;

/**
 * POLISH4 (session 0730): the DEV-ONLY flash-HOLD override for the STORM-MASS B6
 * intra-storm double flash — {@code /eclipsefx storm flashhold on [amount] | off}.
 *
 * <p>The live B6 flash lasts {@code StormWeatherFx.FLASH_TICKS} = 7 ticks (0.35 s),
 * which makes the dual-cell + emission-vein look unphotographable on software-rendered
 * rigs (seconds per frame). While the hold is ON, {@link StormVolumeFx#feedVolume}
 * force-feeds BOTH volume flash slots at {@link #amount()} (default 1.0) and cycles the
 * vein seed slowly ({@link #seed()}: +1 step every {@value #SEED_CYCLE_TICKS} ticks
 * instead of per-flash), so the two cells and the vein filament structure can be
 * inspected at leisure.</p>
 *
 * <p><b>Scope rules (frozen):</b></p>
 * <ul>
 *   <li><b>Client-visual only.</b> The override lives entirely in the volume UNIFORM
 *       feed. {@code StormWeatherFx}'s scheduler, serial, budgeted point light, interior
 *       beat and the W-A/W-C/W-D contracts run completely untouched — no server state,
 *       no payload beyond the one dev action that flips this switch.</li>
 *   <li><b>Idle rule.</b> {@link #active()} defaults to {@code false} and is flipped only
 *       by the {@code /eclipsefx storm flashhold} dev action; every hold branch in
 *       {@code feedVolume} is gated on it, so with the hold OFF all fed uniforms are the
 *       bit-identical expressions that shipped with B6.</li>
 *   <li><b>Cell positions stay honest.</b> The held cells use the scheduler's normal
 *       per-slot bearings/lats ({@code innerFlashBearing/Lat}, {@code innerFlash2*}),
 *       which persist between flashes — only a slot that has NEVER picked a cell (lat
 *       rests at 0, unreachable for real picks since {@code FLASH_LAT_MIN} = 0.15) falls
 *       back to the distinct {@link #FALLBACK_LAT1}/{@link #FALLBACK_LAT2} cells at
 *       camera bearing ∓/± {@link #FALLBACK_SPREAD}, so TWO separate cells are visible
 *       from the first held frame on.</li>
 * </ul>
 *
 * <p>Dev-session-scoped: logout clears the hold (the {@code FxDevClient} override
 * hygiene pattern).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class StormFlashDevHold {
    /** Vein-seed cycle under hold: +1 seed step every 40 ticks (2 s) — inspectable. */
    private static final int SEED_CYCLE_TICKS = 40;
    /** Held-amount clamp — matches the command's argument bounds (defensive re-clamp). */
    private static final float AMOUNT_MIN = 0.05F;
    private static final float AMOUNT_MAX = 2.0F;
    /**
     * Fallback cells for never-picked slots: camera bearing −/+ this (rad), so the two
     * cells flank the nearest wall point exactly like the scheduler's own
     * camera-bearing ± spread law.
     */
    static final double FALLBACK_SPREAD = 0.7D;
    /** Fallback latFrac of slot 1 / slot 2 — distinct heights inside the scheduler's
     *  own 0.15–0.70 pick window. */
    static final float FALLBACK_LAT1 = 0.35F;
    static final float FALLBACK_LAT2 = 0.55F;

    /** Volatile: flipped on the netty/main thread by the dev payload, read per frame. */
    private static volatile boolean active;
    private static volatile float amount = 1.0F;

    private StormFlashDevHold() {}

    /** Entry point from {@code FxDevClient} ({@code /eclipsefx storm flashhold}). */
    public static void set(boolean on, float holdAmount) {
        active = on;
        if (on) {
            amount = Mth.clamp(holdAmount, AMOUNT_MIN, AMOUNT_MAX);
        }
    }

    /** True while the dev hold forces both volume flash slots (default {@code false}). */
    public static boolean active() {
        return active;
    }

    /** The held flash envelope for BOTH slots (only read while {@link #active()}). */
    static float amount() {
        return amount;
    }

    /**
     * Slow vein-seed cycle replacing {@code innerFlashSerial() % 64} under hold: the
     * shader re-rolls its vein field per seed step, so cycling every 2 s lets each
     * filament pattern be inspected before the next one fades in. Pause-safe by the
     * same clock as everything else ({@code StormFxClient.ticks()} freezes on pause).
     */
    static float seed() {
        return (StormFxClient.ticks() / SEED_CYCLE_TICKS) % 64;
    }

    /** Dev-session hygiene: no hold survives a disconnect. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        active = false;
        amount = 1.0F;
    }
}
