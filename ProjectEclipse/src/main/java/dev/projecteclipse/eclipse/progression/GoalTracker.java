package dev.projecteclipse.eclipse.progression;

import java.util.List;

import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.progression.goals.GoalSpec;
import dev.projecteclipse.eclipse.progression.goals.QuestApi;
import dev.projecteclipse.eclipse.progression.goals.QuestEngine;
import dev.projecteclipse.eclipse.progression.goals.QuestMath;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;

/**
 * LEGACY ADAPTER (plans_v3 P4 §2.2 "Legacy bridge") — the W13 goal tracker retired in
 * place by P4-B2. The hardcoded {@code switch(day)} auto-detectors, the
 * {@code eclipse:goal_progress} attachment writes and the day-1 shard-seed logic are gone:
 * detection now lives in {@code progression/goals/QuestEngine} + {@code QuestDetectors}
 * (data-driven via goals.json triggers; the shard seed is an authored day-1 goal reward),
 * and progress persists in the {@code eclipse_quests} SavedData instead of the attachment
 * (which stays registered but is no longer written).
 *
 * <p>Only the call surfaces foreign code depends on remain, delegating to the engine:</p>
 * <ul>
 *   <li>{@link #complete} — {@code /eclipse goals tick <player> <index>} (untouchable
 *       command) maps the 0-based index onto TODAY'S MAIN goals and manual-completes;</li>
 *   <li>{@link #mask} — the legacy mains bitmask read by
 *       {@code S2CGoalProgressPayload.currentFor} (old sidebar tick boxes);</li>
 *   <li>{@link #onHeraldSummoned} / {@link #onFinaleBegun} — ritual hooks
 *       ({@code HeraldsLureItem}, {@code FinaleRitual}) reborn as team-beat shims for the
 *       {@code herald_summoned} / {@code finale_begun} beat ids that authored goals
 *       reference via {@code trigger.beatId}.</li>
 * </ul>
 */
public final class GoalTracker {
    /** Beat id fired by the Herald's Lure summon hook (goals reference it via {@code trigger.beatId}). */
    public static final String BEAT_HERALD_SUMMONED = "herald_summoned";
    /** Beat id fired by the finale-offering hook. */
    public static final String BEAT_FINALE_BEGUN = "finale_begun";

    private GoalTracker() {}

    /**
     * The player's legacy completion bitmask: bit {@code i} = today's main goal {@code i}
     * done (team scopes read the team flag). A {@code day} other than the current event
     * day reads as 0 — same stale-day semantics as the old attachment encoding.
     */
    public static int mask(ServerPlayer player, int day) {
        MinecraftServer server = player.server;
        if (EclipseWorldState.get(server).getDay() != day) {
            return 0;
        }
        return QuestMath.bitmask(QuestEngine.mainDoneFlags(server, player));
    }

    /**
     * Ticks main goal {@code index} (0-based) of the CURRENT day for the player with the
     * full completion pipeline (rewards, signal, announce, resync). Returns false when out
     * of range or already complete for that player/team — exactly the contract
     * {@code /eclipse goals tick} feedback relies on.
     */
    public static boolean complete(ServerPlayer player, int index) {
        MinecraftServer server = player.server;
        List<GoalSpec> mains = QuestEngine.currentMains(server);
        if (index < 0 || index >= mains.size()) {
            return false;
        }
        return QuestApi.complete(server, player, mains.get(index));
    }

    /** {@code ritual.HeraldsLureItem} hook → {@code herald_summoned} team beat. */
    public static void onHeraldSummoned(MinecraftServer server) {
        QuestEngine.completeTeamBeat(server, BEAT_HERALD_SUMMONED);
    }

    /** {@code ritual.FinaleRitual#begin} hook → {@code finale_begun} team beat. */
    public static void onFinaleBegun(MinecraftServer server) {
        QuestEngine.completeTeamBeat(server, BEAT_FINALE_BEGUN);
    }
}
