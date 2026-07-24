package dev.projecteclipse.eclipse.timeline;

import dev.projecteclipse.eclipse.worldgen.end.EndFightState;
import net.minecraft.server.MinecraftServer;

/**
 * Server-truth predicates for the {@code days.json} done-variant text swap (PLAN-C §C13 /
 * Wave-5 A5-extra): once a day's headline content is actually beaten, its timeline node
 * and announcements switch from the hunt-text ({@code title}/{@code subtitle}) to the
 * authored done-text ({@code titleDone}/{@code subtitleDone}) — the arc stops advertising
 * content the team has already beaten.
 *
 * <p>Only days with BOTH an authored done-variant and a mapping here ever swap; every
 * other day is permanently "not done". Current truths:</p>
 * <ul>
 *   <li><b>Day 12 (stronghold/portal)</b> — done once the End materialization has begun
 *       (the portal era is over; there is no dedicated "portal room breached" flag) or
 *       the dragon is already dead.</li>
 *   <li><b>Day 13 (the dragon)</b> — done once {@link EndFightState#dragonKilled()}.</li>
 * </ul>
 */
public final class DayTextConditions {
    private DayTextConditions() {}

    /** Whether {@code day}'s headline content is beaten (server truth, cheap saved-data reads). */
    public static boolean isDone(MinecraftServer server, int day) {
        return switch (day) {
            case 12 -> {
                EndFightState fight = EndFightState.get(server);
                yield fight.materializationStarted() || fight.dragonKilled();
            }
            case 13 -> EndFightState.get(server).dragonKilled();
            default -> false;
        };
    }
}
