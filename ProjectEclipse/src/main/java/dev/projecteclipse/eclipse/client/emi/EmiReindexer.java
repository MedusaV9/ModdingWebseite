package dev.projecteclipse.eclipse.client.emi;

import java.lang.reflect.Method;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import net.minecraft.client.Minecraft;
import net.neoforged.fml.ModList;

/**
 * Reflection-guarded EMI re-index trigger (P3 §3.12): EMI has no official live-hide API
 * (emi#494 / emi#1207), so after an unlock-state diff we ask EMI's internal
 * {@code dev.emi.emi.runtime.EmiReloadManager.reload()} to rebuild its index — the plugin's
 * hiding predicates re-run during the bake and consult {@code ClientUnlockCache} live.
 * The reload runs async on EMI's worker thread (~1–3 s), fine at day-change cadence.
 *
 * <p>This class deliberately contains NO compile-time EMI reference (reflection only), so it
 * compiles and loads without the EMI jar; all calls no-op unless {@code isLoaded("emi")}.
 * Version-drift fail-safe (plan risk R-1): if reflection breaks, warn-log ONCE, then show a
 * one-line localized chat hint per session that newly-unlocked content appears in EMI after
 * the next resource reload/relog — nothing crashes and gameplay unlocks are unaffected
 * (hiding is cosmetic; ModGate stays the server truth).</p>
 */
public final class EmiReindexer {
    /** Debounce: EMI reloads are heavy; unlock diffs arrive at day-change cadence anyway. */
    private static final long MIN_INTERVAL_MILLIS = 5_000L;

    private static volatile long lastRequestMillis;
    private static volatile boolean reflectionBroken;
    private static volatile boolean staleHintShown;

    private EmiReindexer() {}

    /**
     * Requests an async EMI index rebuild. Safe to call from the client main thread at any
     * time: no-ops when EMI is absent, still mid-initial-load (the pending bake will read the
     * fresh cache anyway), debounced, or when reflection is broken (log-once + player hint).
     */
    public static void requestReload() {
        if (!ModList.get().isLoaded("emi") || reflectionBroken) {
            return;
        }
        long now = System.currentTimeMillis();
        if (now - lastRequestMillis < MIN_INTERVAL_MILLIS) {
            return;
        }
        lastRequestMillis = now;
        try {
            Class<?> manager = Class.forName("dev.emi.emi.runtime.EmiReloadManager");
            Method isLoaded = manager.getMethod("isLoaded");
            if (!Boolean.TRUE.equals(isLoaded.invoke(null))) {
                // Initial index bake still pending — it will consult the updated cache itself.
                EclipseMod.LOGGER.debug("EMI initial load pending; skipping explicit re-index");
                return;
            }
            manager.getMethod("reload").invoke(null);
            EclipseMod.LOGGER.info("Requested EMI re-index after unlock change");
        } catch (Throwable t) {
            reflectionBroken = true;
            EclipseMod.LOGGER.warn(
                    "EMI re-index reflection failed (EMI version drift?) — unlocked content will "
                            + "appear in EMI after the next resource reload or relog", t);
            showStaleHint();
        }
    }

    /** One localized chat line per session so players know the EMI index is merely stale. */
    private static void showStaleHint() {
        if (staleHintShown) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.player == null) {
            return;
        }
        staleHintShown = true;
        minecraft.player.displayClientMessage(EclipseLang.tr("gui.eclipse.emi.stale_hint"), false);
    }
}
