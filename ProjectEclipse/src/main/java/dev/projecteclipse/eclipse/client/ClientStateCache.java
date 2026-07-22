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
    /** The current day's goal lines, as sent by the server; empty until the first day-state sync. */
    public static volatile java.util.List<String> goals = java.util.List.of();

    /** Last start-event cutscene phase received from the server; {@code null} until the event runs. */
    public static volatile dev.projecteclipse.eclipse.network.S2CCutscenePayload.Phase cutscenePhase = null;

    // World stage sync (S2CStagePayload; sent on login and on every stage commit/completion).
    public static volatile int stageOverworld = 0;
    public static volatile int stageNether = 0;
    /** Fused-disc radius of the committed overworld stage (stage 0 = main disc radius 96). */
    public static volatile int stageRadiusOverworld = 96;
    /** Fused-disc radius of the committed nether stage (stage 0 = no disc, radius 0). */
    public static volatile int stageRadiusNether = 0;
    /** Whether a ring-growth sweep is currently animating in that dimension. */
    public static volatile boolean stageAnimatingOverworld = false;
    public static volatile boolean stageAnimatingNether = false;

    private ClientStateCache() {}
}
