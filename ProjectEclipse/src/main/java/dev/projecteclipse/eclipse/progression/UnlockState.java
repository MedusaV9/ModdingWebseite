package dev.projecteclipse.eclipse.progression;

import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import net.minecraft.server.MinecraftServer;

/**
 * Server-authoritative view of the currently-unlocked progression keys: the union of the
 * {@code unlocks[]} of every configured day plan from day 1 to the current day, plus the
 * {@code rewards[]} of every altar milestone up to the current altar level. Everything is
 * derived from {@link EclipseWorldState} + {@link EclipseConfig}, so lowering the day (or a
 * config reload) reverses unlocks automatically — nothing is stored separately.
 */
public final class UnlockState {
    /** Cache of the last derivation; the key fields detect day/altar changes and config reloads. */
    private record Snapshot(int day, int altarLevel,
                            List<EclipseConfig.DayPlan> days,
                            List<EclipseConfig.Milestone> milestones,
                            Set<String> keys) {}

    private static volatile Snapshot snapshot;

    private UnlockState() {}

    /** Whether the given progression key is currently unlocked. */
    public static boolean isUnlocked(MinecraftServer server, String key) {
        return unlockedKeys(server).contains(key);
    }

    /** Unmodifiable set of all currently-unlocked progression keys. */
    public static Set<String> unlockedKeys(MinecraftServer server) {
        EclipseWorldState state = EclipseWorldState.get(server);
        int day = state.getDay();
        int altarLevel = state.getAltarLevel();
        List<EclipseConfig.DayPlan> days = EclipseConfig.days();
        List<EclipseConfig.Milestone> milestones = EclipseConfig.milestones();

        Snapshot cached = snapshot;
        if (cached != null && cached.day() == day && cached.altarLevel() == altarLevel
                && cached.days() == days && cached.milestones() == milestones) {
            return cached.keys();
        }

        Set<String> keys = new LinkedHashSet<>();
        for (EclipseConfig.DayPlan plan : days) {
            if (plan.day() <= day) {
                keys.addAll(plan.unlocks());
            }
        }
        for (EclipseConfig.Milestone milestone : milestones) {
            if (milestone.level() <= altarLevel) {
                keys.addAll(milestone.rewards());
            }
        }
        Set<String> result = Collections.unmodifiableSet(keys);
        snapshot = new Snapshot(day, altarLevel, days, milestones, result);
        return result;
    }
}
