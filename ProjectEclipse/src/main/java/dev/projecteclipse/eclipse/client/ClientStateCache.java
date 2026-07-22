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

    // Personal goal progress (S2CGoalProgressPayload; sent at login and on day changes).
    // goalLines mirrors the day's goals; goalDone is all-false until W13 wires real ticking.
    public static volatile java.util.List<String> goalLines = java.util.List.of();
    public static volatile java.util.List<Boolean> goalDone = java.util.List.of();

    /**
     * Anonymized event timeline (S2CTimelinePayload; sent at login + day/altar changes).
     * Hidden (future) entries carry no title/icon — render them as "???" glitch nodes.
     * W9's handbook timeline tab reads this list.
     */
    public static volatile java.util.List<dev.projecteclipse.eclipse.timeline.TimelineEntry> timeline =
            java.util.List.of();

    /**
     * Altar milestone ladder (S2CMilestonesPayload; sent at login + on /eclipse reload).
     * The handbook Rewards tab renders it; Status derives the ring max level from it.
     */
    public static volatile java.util.List<dev.projecteclipse.eclipse.network.S2CMilestonesPayload.Entry> milestones =
            java.util.List.of();

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

    // Soft border sync (S2CBorderPayload; sent on login and on every ring/FX-range change).
    // The ring radius animates client-side: from -> to over lerpTicks starting at the sync
    // receipt millis. toRadius <= 0 = ring inactive; -1 = nothing received yet.
    public static volatile double borderCenterX = 0.5D;
    public static volatile double borderCenterZ = 0.5D;
    /** Client FX visibility band in blocks (server-configurable). */
    public static volatile float borderFxRange = 8.0F;
    public static volatile float borderFromRadiusOverworld = -1.0F;
    public static volatile float borderToRadiusOverworld = -1.0F;
    public static volatile int borderLerpTicksOverworld = 0;
    public static volatile long borderSyncMillisOverworld = 0L;
    public static volatile float borderFromRadiusNether = -1.0F;
    public static volatile float borderToRadiusNether = -1.0F;
    public static volatile int borderLerpTicksNether = 0;
    public static volatile long borderSyncMillisNether = 0L;

    /**
     * Current animated soft-ring radius for a dimension (area-proportional interpolation,
     * mirroring the server's {@code SoftBorder}). {@code <= 0} = ring inactive / not synced.
     */
    public static double currentBorderRadius(boolean nether, long nowMillis) {
        float from = nether ? borderFromRadiusNether : borderFromRadiusOverworld;
        float to = nether ? borderToRadiusNether : borderToRadiusOverworld;
        int lerpTicks = nether ? borderLerpTicksNether : borderLerpTicksOverworld;
        long syncMillis = nether ? borderSyncMillisNether : borderSyncMillisOverworld;
        if (to <= 0.0F) {
            return to;
        }
        if (lerpTicks <= 0 || from <= 0.0F) {
            return to;
        }
        double t = Math.min(1.0D, (nowMillis - syncMillis) / (lerpTicks * 50.0D));
        double fromSq = (double) from * from;
        double toSq = (double) to * to;
        return Math.sqrt(fromSq + (toSq - fromSq) * t);
    }

    private ClientStateCache() {}
}
