package dev.projecteclipse.eclipse.progression.goals;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;

/**
 * FROZEN quest surface for P5 (plans_v3 P4 §3.3 / P5-W4 {@code DevQuestCommands}, P5-W2
 * GoalEditor). Signatures here are stable — extend, never break. Everything is
 * server-thread only and delegates to {@link QuestEngine}; {@code QuestCommands}
 * ({@code /eclipse-quests}) is the in-repo reference caller for every mutator.
 *
 * <p>Editor integration: the trigger-type registry the reworked GoalEditor renders its
 * dropdown from is {@link #triggerTypes()} / {@link TriggerType#ids()}; config validation
 * for ConfigEditor's {@code goals.json}/{@code quests.json} allowlist entries is
 * {@link GoalConfig#validateAndNormalize} (P4 assigns wiring those into
 * {@code devtools/ConfigEditor} to P5).</p>
 */
public final class QuestApi {
    private QuestApi() {}

    // --- read surface ---

    /** Today's main goals in payload order. */
    public static List<GoalSpec> mains(MinecraftServer server) {
        return QuestEngine.resolved(server).mains;
    }

    /** Today's side goals in payload order. */
    public static List<GoalSpec> sides(MinecraftServer server) {
        return QuestEngine.resolved(server).sides;
    }

    /** The player's personal quests for today (assigning them now if missing). */
    public static List<GoalSpec> personals(MinecraftServer server, ServerPlayer player) {
        QuestEngine.ensurePlayer(server, player);
        return QuestEngine.personalSpecs(QuestEngine.resolved(server),
                QuestState.get(server), player.getUUID());
    }

    /** Mains + sides + the player's personals — exactly the payload's quest list. */
    public static List<GoalSpec> allForPlayer(MinecraftServer server, ServerPlayer player) {
        QuestEngine.ensurePlayer(server, player);
        return QuestEngine.specsFor(QuestEngine.resolved(server),
                QuestState.get(server), player.getUUID());
    }

    /**
     * Resolves a goal id against today's mains/sides, any indexed personal, then the whole
     * personal pool (so admins can tick a personal that nobody has drawn yet).
     */
    public static Optional<GoalSpec> byId(MinecraftServer server, String goalId) {
        QuestEngine.ResolvedDay day = QuestEngine.resolved(server);
        GoalSpec spec = day.byId.get(goalId);
        if (spec == null) {
            spec = GoalConfig.personalById(goalId);
        }
        return Optional.ofNullable(spec);
    }

    /** All goal ids an admin command should suggest: today's specs + the personal pool. */
    public static List<String> suggestedIds(MinecraftServer server) {
        QuestEngine.ResolvedDay day = QuestEngine.resolved(server);
        List<String> ids = new ArrayList<>(day.byId.keySet());
        for (GoalSpec spec : GoalConfig.personalPool()) {
            if (!day.byId.containsKey(spec.id())) {
                ids.add(spec.id());
            }
        }
        return ids;
    }

    /** The player's progress toward the goal (team_total returns the shared counter). */
    public static long progress(MinecraftServer server, ServerPlayer player, GoalSpec spec) {
        QuestState state = QuestState.get(server);
        int day = QuestEngine.resolved(server).day;
        return spec.scope() == GoalSpec.Scope.TEAM_TOTAL
                ? state.teamProgress(day, spec.id())
                : state.playerProgress(day, player.getUUID(), spec.id());
    }

    /** Whether the goal counts as done for this player (team scopes: team done). */
    public static boolean isDone(MinecraftServer server, ServerPlayer player, GoalSpec spec) {
        QuestState state = QuestState.get(server);
        int day = QuestEngine.resolved(server).day;
        return spec.scope() == GoalSpec.Scope.EACH_PLAYER
                ? state.isPlayerDone(day, player.getUUID(), spec.id())
                : state.isTeamDone(day, spec.id());
    }

    // --- write surface (P5-W4 /dev quest complete|revoke) ---

    /**
     * Completes the goal with full side effects (rewards, {@code questCompleted} signal,
     * announce for mains, payload resync). Team-scoped specs complete for the whole team.
     *
     * @return false when it was already complete (no side effects re-fire)
     */
    public static boolean complete(MinecraftServer server, ServerPlayer player, GoalSpec spec) {
        return QuestEngine.completeManual(server, player, spec);
    }

    /**
     * Un-completes the goal and clears its progress/baselines. {@code each_player} scope
     * revokes just this player; team scopes clear the team state (and re-arm the beat).
     *
     * @return false when there was nothing to revoke
     */
    public static boolean revoke(MinecraftServer server, ServerPlayer player, GoalSpec spec) {
        return QuestEngine.revokeForPlayer(server, player, spec);
    }

    /** Team-scope revoke without a player context (clears counter, done flags, parts). */
    public static boolean revokeTeam(MinecraftServer server, GoalSpec spec) {
        return QuestEngine.revokeTeam(server, spec);
    }

    /**
     * Fires a team beat by id (e.g. {@code herald_summoned}): completes every current-day
     * goal whose {@code trigger.beatId} matches, once per (day, beat). External systems
     * (rituals, finale) call this instead of poking goal internals.
     */
    public static void completeTeamBeat(MinecraftServer server, String beatId) {
        QuestEngine.completeTeamBeat(server, beatId);
    }

    /** Rerolls the player's personal quests (deterministic under the bumped nonce). */
    public static List<String> reroll(MinecraftServer server, ServerPlayer player) {
        return QuestEngine.reroll(server, player);
    }

    /** Re-sends quest + legacy goal payloads to everyone (after config edits etc.). */
    public static void resyncAll(MinecraftServer server) {
        QuestEngine.markAllDirty();
        QuestEngine.runPollNow(server);
    }

    // --- editor / registry surface (P5-W2 GoalEditor, devtools) ---

    /** Registered trigger types in dropdown order (id + polled flag + tooltip). */
    public static List<TriggerType> triggerTypes() {
        return List.of(TriggerType.values());
    }

    /** Stable trigger-type ids for suggestion providers (mirrors {@link TriggerType#ids()}). */
    public static List<String> triggerTypeIds() {
        return TriggerType.ids();
    }
}
