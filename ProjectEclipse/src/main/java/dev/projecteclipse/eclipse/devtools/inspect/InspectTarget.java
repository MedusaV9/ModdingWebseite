package dev.projecteclipse.eclipse.devtools.inspect;

import net.minecraft.server.level.ServerPlayer;

/**
 * F-066 liveness check shared by both inspection menus.
 *
 * <p>An inspection menu holds a hard reference to the target's {@link ServerPlayer}, and that
 * object is replaced (not mutated) whenever the target logs out, respawns or changes dimension
 * through the end portal. Writing into a stale instance would silently vanish, so both menus
 * report {@code stillValid == false} as soon as the reference is no longer THE live session —
 * vanilla's {@code Player#tick} then closes the viewer's screen on the next tick.</p>
 */
final class InspectTarget {
    private InspectTarget() {}

    /** Whether {@code target} is still the live server-side player object for its UUID. */
    static boolean isLive(ServerPlayer target) {
        return !target.hasDisconnected()
                && target.server.getPlayerList().getPlayer(target.getUUID()) == target;
    }
}
