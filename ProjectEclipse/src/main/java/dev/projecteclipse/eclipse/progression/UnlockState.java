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
 * {@code rewards[]} of every altar milestone up to the current altar level, plus the
 * derived boss key {@link #KEY_HERALD_SLAIN} while the Herald-defeated flag is set (W11 —
 * lets W13's config gate an unlock, e.g. {@code enchanting}, behind the day-7 boss kill).
 * Everything is derived from {@link EclipseWorldState} + {@link EclipseConfig}, so lowering
 * the day (or a config reload) reverses unlocks automatically — nothing is stored
 * separately.
 */
public final class UnlockState {
    /** Derived unlock key present while {@link EclipseWorldState#isHeraldDefeated()}. */
    public static final String KEY_HERALD_SLAIN = "herald_slain";

    /**
     * W13 boss gate (spec §6 day 7): the day-plan {@code enchanting} key is unioned only
     * once the Herald has fallen, regardless of which day lists it. Milestone rewards are
     * NOT filtered — an admin can still grant enchanting early via a milestone if desired.
     */
    public static final String KEY_ENCHANTING = "enchanting";

    /** Cache of the last derivation; the key fields detect day/altar changes and config reloads. */
    private record Snapshot(int day, int altarLevel, boolean heraldDefeated,
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
        boolean heraldDefeated = state.isHeraldDefeated();
        List<EclipseConfig.DayPlan> days = EclipseConfig.days();
        List<EclipseConfig.Milestone> milestones = EclipseConfig.milestones();

        Snapshot cached = snapshot;
        if (cached != null && cached.day() == day && cached.altarLevel() == altarLevel
                && cached.heraldDefeated() == heraldDefeated
                && cached.days() == days && cached.milestones() == milestones) {
            return cached.keys();
        }

        Set<String> keys = new LinkedHashSet<>();
        for (EclipseConfig.DayPlan plan : days) {
            if (plan.day() <= day) {
                for (String key : plan.unlocks()) {
                    if (KEY_ENCHANTING.equals(key) && !heraldDefeated) {
                        continue; // boss-locked until the day-7 Herald falls (see KEY_ENCHANTING)
                    }
                    keys.add(key);
                }
            }
        }
        for (EclipseConfig.Milestone milestone : milestones) {
            if (milestone.level() <= altarLevel) {
                keys.addAll(milestone.rewards());
            }
        }
        if (heraldDefeated) {
            keys.add(KEY_HERALD_SLAIN);
        }
        Set<String> result = Collections.unmodifiableSet(keys);
        snapshot = new Snapshot(day, altarLevel, heraldDefeated, days, milestones, result);
        return result;
    }
}
