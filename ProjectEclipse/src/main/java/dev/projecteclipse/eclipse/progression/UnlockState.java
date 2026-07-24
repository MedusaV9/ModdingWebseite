package dev.projecteclipse.eclipse.progression;

import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import net.minecraft.server.MinecraftServer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;

/**
 * Server-authoritative view of the currently-unlocked progression keys: the union of the
 * {@code unlocks[]} of every configured day plan from day 1 to the current day, plus the
 * {@code rewards[]} of every altar milestone up to the current altar level, plus the
 * derived boss key {@link #KEY_HERALD_SLAIN} while the Herald-defeated flag is set (W11 —
 * lets W13's config gate an unlock, e.g. {@code enchanting}, behind the day-7 boss kill).
 * Day-plan grants may additionally be held back by a gate ({@link #KEY_ENCHANTING} boss
 * gate, {@link #DAY_GRANT_GATES} altar gates) so the altar stays meaningful even though
 * the day plans list the same keys. Everything is derived from {@link EclipseWorldState}
 * + {@link EclipseConfig}, so lowering the day (or a config reload) reverses unlocks
 * automatically — nothing is stored separately.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class UnlockState {
    /** Derived unlock key present while {@link EclipseWorldState#isHeraldDefeated()}. */
    public static final String KEY_HERALD_SLAIN = "herald_slain";

    /**
     * W13 boss gate (spec §6 day 7): the day-plan {@code enchanting} key is unioned only
     * once the Herald has fallen, regardless of which day lists it. Milestone rewards are
     * NOT filtered — an admin can still grant enchanting early via a milestone if desired.
     */
    public static final String KEY_ENCHANTING = "enchanting";

    /** Altar gate of a day-granted key: passes at altar level {@code minAltarLevel} OR day {@code fallbackDay}. */
    private record AltarGate(int minAltarLevel, int fallbackDay) {
        boolean passes(int altarLevel, int day) {
            return altarLevel >= minAltarLevel || day >= fallbackDay;
        }
    }

    /**
     * Altar gates for day-plan grants (the {@link #KEY_ENCHANTING} boss-gate pattern,
     * generalized): each mapped key is filtered from the DAY-GRANTED set until the altar
     * milestone that also rewards it has been reached — or the fallback day passes, so a
     * stalled altar can never dead-lock the arc. Milestone rewards are NOT filtered:
     * paying the altar always unlocks immediately. {@code create}/{@code simulated}/
     * {@code end} are deliberately ungated — the early keys stay day-driven and the End
     * is already gated by its own day-12 arc.
     */
    private static final Map<String, AltarGate> DAY_GRANT_GATES = Map.of(
            "aeronautics", new AltarGate(3, 6),
            "sable", new AltarGate(4, 9));

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
                    AltarGate gate = DAY_GRANT_GATES.get(key);
                    if (gate != null && !gate.passes(altarLevel, day)) {
                        continue; // altar-locked until its milestone (or the fallback day) passes
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

    /** The cache pins the last world's config lists and key set — drop it with the server. */
    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        snapshot = null;
    }
}
