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

    // --- P4 gameplay payloads (stub cache fields; P3 replaces rendering) ---

    /** {@link dev.projecteclipse.eclipse.network.S2CDayClockPayload} */
    public static volatile int dayClockDay = 1;
    public static volatile long boundaryEpochMillis = 0L;
    public static volatile long prevBoundaryEpochMillis = 0L;
    public static volatile long serverNowEpochMillis = 0L;
    public static volatile boolean dayClockPaused = false;
    public static volatile long pauseRemainingMillis = 0L;
    /** Local millis when the last day-clock payload arrived (client offset helper). */
    public static volatile long clockSyncLocalMillis = 0L;

    /** {@link dev.projecteclipse.eclipse.network.S2CQuestStatePayload} */
    public static volatile int questDay = 1;
    public static volatile java.util.List<dev.projecteclipse.eclipse.network.S2CQuestStatePayload.QuestEntry> questEntries =
            java.util.List.of();

    /** {@link dev.projecteclipse.eclipse.network.S2CSkillStatePayload} */
    public static volatile int skillLevel = 0;
    public static volatile long skillTotalXp = 0L;
    public static volatile int skillXpIntoLevel = 0;
    public static volatile int skillXpForLevel = 0;
    public static volatile int skillPoints = 0;
    public static volatile int skillUnspent = 0;
    public static volatile java.util.List<String> skillOwnedNodes = java.util.List.of();
    public static volatile boolean skillProcMsgEnabled = true;
    public static volatile boolean skillSecretMultiplierActive = false;

    /** Last {@link dev.projecteclipse.eclipse.network.S2CSkillProcPayload} */
    public static volatile String lastSkillProcId = "";
    public static volatile float lastSkillProcMagnitude = 0.0F;

    /** {@link dev.projecteclipse.eclipse.network.S2CAwardRevealPayload} */
    public static volatile int awardRevealDay = 0;
    public static volatile java.util.List<dev.projecteclipse.eclipse.network.S2CAwardRevealPayload.Category> awardCategories =
            java.util.List.of();

    /** {@link dev.projecteclipse.eclipse.network.S2CBuffStatePayload} */
    public static volatile java.util.List<dev.projecteclipse.eclipse.network.S2CBuffStatePayload.Buff> activeBuffs =
            java.util.List.of();

    /** {@link dev.projecteclipse.eclipse.network.S2CRecipeLocksPayload} */
    public static volatile java.util.List<String> lockedItemIds = java.util.List.of();
    public static volatile java.util.List<String> lockedRecipeIds = java.util.List.of();

    /** {@link dev.projecteclipse.eclipse.network.S2CSidebarStatePayload} */
    public static volatile int sidebarDay = 1;
    public static volatile long sidebarBoundaryEpochMillis = 0L;
    public static volatile boolean sidebarPaused = false;
    public static volatile int sidebarSkillLevel = 0;
    public static volatile int sidebarXpIntoLevel = 0;
    public static volatile int sidebarXpForLevel = 0;
    public static volatile int sidebarAltarLevel = 0;
    public static volatile int sidebarMainsDone = 0;
    public static volatile int sidebarMainsTotal = 0;
    public static volatile int sidebarSidesDone = 0;
    public static volatile int sidebarSidesTotal = 0;
    public static volatile int sidebarPersonalsDone = 0;
    public static volatile int sidebarPersonalsTotal = 0;
    public static volatile java.util.List<String> sidebarBuffIds = java.util.List.of();
    public static volatile int sidebarShards = 0;

    /** {@link dev.projecteclipse.eclipse.network.S2CGhostRevealPayload} */
    public static volatile int ghostRevealEntityId = -1;
    public static volatile String ghostRevealOwnerName = "";
    public static volatile int ghostRevealTicks = 0;

    /** {@link dev.projecteclipse.eclipse.network.S2CSkillTreePayload} raw JSON text */
    public static volatile String skillTreeJson = "{}";

    /**
     * Snaps every synced field back to its pre-login default (disconnect hook): the cache
     * outlives the connection, so without this the next server's HUD/handbook would show
     * the previous session's day/lives/goals/timeline until its own payloads arrive.
     */
    public static void resetToDefaults() {
        lives = 5;
        day = 1;
        altarLevel = 0;
        goals = java.util.List.of();
        goalLines = java.util.List.of();
        goalDone = java.util.List.of();
        timeline = java.util.List.of();
        milestones = java.util.List.of();
        cutscenePhase = null;
        stageOverworld = 0;
        stageNether = 0;
        stageRadiusOverworld = 96;
        stageRadiusNether = 0;
        stageAnimatingOverworld = false;
        stageAnimatingNether = false;
        borderCenterX = 0.5D;
        borderCenterZ = 0.5D;
        borderFxRange = 8.0F;
        borderFromRadiusOverworld = -1.0F;
        borderToRadiusOverworld = -1.0F;
        borderLerpTicksOverworld = 0;
        borderSyncMillisOverworld = 0L;
        borderFromRadiusNether = -1.0F;
        borderToRadiusNether = -1.0F;
        borderLerpTicksNether = 0;
        borderSyncMillisNether = 0L;
        dayClockDay = 1;
        boundaryEpochMillis = 0L;
        prevBoundaryEpochMillis = 0L;
        serverNowEpochMillis = 0L;
        dayClockPaused = false;
        pauseRemainingMillis = 0L;
        clockSyncLocalMillis = 0L;
        questDay = 1;
        questEntries = java.util.List.of();
        skillLevel = 0;
        skillTotalXp = 0L;
        skillXpIntoLevel = 0;
        skillXpForLevel = 0;
        skillPoints = 0;
        skillUnspent = 0;
        skillOwnedNodes = java.util.List.of();
        skillProcMsgEnabled = true;
        skillSecretMultiplierActive = false;
        lastSkillProcId = "";
        lastSkillProcMagnitude = 0.0F;
        awardRevealDay = 0;
        awardCategories = java.util.List.of();
        activeBuffs = java.util.List.of();
        lockedItemIds = java.util.List.of();
        lockedRecipeIds = java.util.List.of();
        sidebarDay = 1;
        sidebarBoundaryEpochMillis = 0L;
        sidebarPaused = false;
        sidebarSkillLevel = 0;
        sidebarXpIntoLevel = 0;
        sidebarXpForLevel = 0;
        sidebarAltarLevel = 0;
        sidebarMainsDone = 0;
        sidebarMainsTotal = 0;
        sidebarSidesDone = 0;
        sidebarSidesTotal = 0;
        sidebarPersonalsDone = 0;
        sidebarPersonalsTotal = 0;
        sidebarBuffIds = java.util.List.of();
        sidebarShards = 0;
        ghostRevealEntityId = -1;
        ghostRevealOwnerName = "";
        ghostRevealTicks = 0;
        skillTreeJson = "{}";
    }

    /**
     * Disconnect reset hook ({@code QuasarSpawner.DisconnectReset} pattern — nested so the
     * outer class stays loadable on either dist; this class only exists on the client).
     * Also clears the synced cutscene library: both caches would otherwise leak the last
     * session's state into the next server join.
     */
    @net.neoforged.fml.common.EventBusSubscriber(modid = dev.projecteclipse.eclipse.EclipseMod.MOD_ID,
            value = net.neoforged.api.distmarker.Dist.CLIENT)
    static final class DisconnectReset {
        private DisconnectReset() {}

        @net.neoforged.bus.api.SubscribeEvent
        static void onLoggingOut(net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent.LoggingOut event) {
            resetToDefaults();
            dev.projecteclipse.eclipse.cutscene.client.ClientCutsceneLibrary.clear();
        }
    }

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
