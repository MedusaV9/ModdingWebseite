package dev.projecteclipse.eclipse.client.sky;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import foundry.veil.api.compat.IrisCompat;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Thin wrapper around Veil's first-party {@link foundry.veil.api.compat.IrisCompat}
 * (replaces the v1 reflection-based Iris bridge). {@code IrisCompat.INSTANCE} is
 * {@code null} when Iris is not installed; {@code areShadersLoaded()} reports whether a
 * shaderpack is currently active.
 *
 * <p>Custom {@code renderSky} implementations must bail out (return {@code false}) while a
 * shaderpack is active so Iris-style pipelines own the sky, and all Veil post pipelines are
 * hard-gated off (see {@code veilfx.VeilPostController}) because Veil world shaders bypass
 * the Iris pipeline and break under an active pack (Veil issue #34).</p>
 */
@OnlyIn(Dist.CLIENT)
public final class EclipseIrisState {
    /** Latched when the Veil compat layer throws so a broken Iris install never loops warnings. */
    private static volatile boolean unavailable;
    private static volatile boolean loggedPresence;

    private EclipseIrisState() {}

    /**
     * @return {@code true} when Iris is present and a shaderpack is currently active;
     *         {@code false} when Iris is absent, no pack is active, or the compat layer throws.
     */
    public static boolean shaderPackActive() {
        if (unavailable) {
            return false;
        }
        try {
            IrisCompat iris = IrisCompat.INSTANCE;
            if (iris == null) {
                return false;
            }
            if (!loggedPresence) {
                loggedPresence = true;
                EclipseMod.LOGGER.info("Iris detected (via Veil IrisCompat); custom sky and Veil post FX yield while a shaderpack is active");
            }
            return iris.areShadersLoaded();
        } catch (Throwable t) {
            unavailable = true;
            EclipseMod.LOGGER.warn("Veil IrisCompat threw; treating shaderpacks as inactive from now on", t);
            return false;
        }
    }

    /**
     * The single combined gate for every Eclipse Veil post pipeline (P2 §3.4): post FX may
     * run only while no Iris shaderpack is active AND the {@code veilPostFx} client config is
     * enabled. The gate applies identically to every {@code VeilPostController} priority
     * class (GRADE/FEATURE/TRANSITION) — priorities only decide eviction order among ALLOWED
     * pipelines, never whether the gate opens. World-space FX (sky quads, storm shells,
     * beams, rifts) ignore this gate by design: they are the Iris fallback (§7).
     */
    public static boolean postFxAllowed() {
        return !shaderPackActive() && EclipseClientConfig.veilPostFx();
    }
}
