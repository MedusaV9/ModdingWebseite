package dev.projecteclipse.eclipse.client;

/**
 * Client-side cache of server-synced Eclipse state, written by the payload handlers in
 * {@code dev.projecteclipse.eclipse.network.EclipsePayloads} and read by client UI code.
 * Contains no client-only class references, so it is safe to load on either dist.
 */
public final class ClientStateCache {
    public static volatile int lives = 5;
    public static volatile int day = 1;
    public static volatile int altarLevel = 0;

    private ClientStateCache() {}
}
