package dev.projecteclipse.eclipse.xboxevent;

import javax.annotation.Nullable;

import net.minecraft.resources.ResourceKey;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.Level;

/**
 * Small cross-planner facade for the Xbox event (plan §4.4).
 *
 * <p><b>For P4's death pipeline</b>: {@link #isProtectedDeath(ServerPlayer)} is the agreed
 * ONE-boolean hook — when true, Eclipse death handling (life loss, grave, ban, kill
 * transfer) must skip entirely; W9 cancels the death and runs the exit sequence instead
 * (§2.13.6). W9's own {@code LivingDeathEvent} intercept runs at HIGHEST priority and
 * cancels, so default-priority handlers never see the event; this query exists so future
 * {@code DeathFlowHooks} refactors can short-circuit explicitly as well.</p>
 */
public final class XboxEventApi {

    private XboxEventApi() {}

    /**
     * Whether a death of {@code player} right now must be fully absorbed by the Xbox event
     * (no item loss, no Eclipse life loss, no grave): true inside any Xbox event dimension.
     */
    public static boolean isProtectedDeath(ServerPlayer player) {
        return player != null && XboxDimensions.isInXboxDimension(player);
    }

    /** Whether {@code dimension} is one of the three Xbox event dimensions. */
    public static boolean isXboxDimension(ResourceKey<Level> dimension) {
        return XboxDimensions.isXboxDimension(dimension);
    }

    /** Active event world id ({@code tu1|tu12|tu14}) or {@code null} when no event is open. */
    @Nullable
    public static String activeWorldId(MinecraftServer server) {
        XboxEventState state = XboxEventState.get(server);
        return state.phase() == XboxEventState.Phase.OPEN
                || state.phase() == XboxEventState.Phase.ANNOUNCED ? state.worldId() : null;
    }

    /** Whether an event is currently open for entries. */
    public static boolean isEventOpen(MinecraftServer server) {
        return XboxEventState.get(server).phase() == XboxEventState.Phase.OPEN;
    }
}
