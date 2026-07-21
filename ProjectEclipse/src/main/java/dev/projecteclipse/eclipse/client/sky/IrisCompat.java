package dev.projecteclipse.eclipse.client.sky;

import java.lang.reflect.Method;

import dev.projecteclipse.eclipse.EclipseMod;

/**
 * Reflection-only bridge to the Iris shaders API. Project: Eclipse has NO compile-time
 * dependency on Iris; this resolves {@code net.irisshaders.iris.api.v0.IrisApi} at runtime.
 *
 * <p>Custom {@code renderSky} implementations must bail out (return {@code false}) while a
 * shaderpack is active so Iris/Oculus-style pipelines own the sky. When Iris is absent, the
 * class lookup fails once and {@link #shadersActive()} is a constant {@code false} forever.</p>
 */
public final class IrisCompat {
    /** IrisApi singleton, or {@code null} when Iris is absent/broken. */
    private static Object irisApi;
    /** {@code IrisApi#isShaderPackInUse()}, or {@code null} when unavailable. */
    private static Method isShaderPackInUse;
    private static volatile boolean resolved;
    private static volatile boolean unavailable;

    private IrisCompat() {}

    /**
     * @return {@code true} when Iris is present and a shaderpack is currently in use;
     *         {@code false} when Iris is absent or any reflective step throws.
     */
    public static boolean shadersActive() {
        if (!resolved) {
            resolve();
        }
        if (unavailable) {
            return false;
        }
        try {
            return (Boolean) isShaderPackInUse.invoke(irisApi);
        } catch (Throwable t) {
            // Never let a broken Iris installation take the sky renderer down with it.
            unavailable = true;
            EclipseMod.LOGGER.warn("IrisApi.isShaderPackInUse() threw; disabling Iris compat", t);
            return false;
        }
    }

    private static synchronized void resolve() {
        if (resolved) {
            return;
        }
        try {
            Class<?> api = Class.forName("net.irisshaders.iris.api.v0.IrisApi");
            Object instance = api.getMethod("getInstance").invoke(null);
            Method inUse = api.getMethod("isShaderPackInUse");
            if (instance == null) {
                unavailable = true;
            } else {
                irisApi = instance;
                isShaderPackInUse = inUse;
                EclipseMod.LOGGER.info("Iris detected; custom sky will yield while a shaderpack is active");
            }
        } catch (Throwable t) {
            // Iris not installed (ClassNotFoundException) or API mismatch -> plain false.
            unavailable = true;
        }
        resolved = true;
    }
}
