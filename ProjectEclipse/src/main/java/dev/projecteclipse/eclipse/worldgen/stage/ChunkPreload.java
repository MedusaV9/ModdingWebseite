package dev.projecteclipse.eclipse.worldgen.stage;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.TicketType;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * RIFT-FX (user item 5 — the BLACK SCREEN fix): destination chunk pre-warming for
 * cinematic teleports. The vanilla {@code ReceivingLevelScreen} ("Downloading terrain",
 * pure black in 1.21.1) outlasts the mod's fixed-duration screen fade whenever the
 * destination chunks are not ready when the player arrives; {@link #warmThenRun} adds a
 * {@value #TICKET_RADIUS}-radius chunk ticket at the destination and defers the caller's
 * fade+teleport until the 3×3 chunk square around the destination is FULLY loaded
 * server-side — the chunk packets then stream immediately behind the respawn packet and
 * the level-ready screen clears inside the fade's black hold instead of after it.
 *
 * <p>The ticket is a timed type ({@value #TICKET_LIFESPAN_TICKS} ticks) — it expires by
 * itself after the teleport, so cleanup is guaranteed even if the action never runs. A
 * request that cannot complete within {@value #DEFAULT_TIMEOUT_TICKS} ticks (caller
 * override allowed) runs its action anyway: a slow chunk load degrades back to the old
 * behavior, it never strands a sequence. Requests are dropped wholesale on server stop.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ChunkPreload {
    /** Waited-on square around the destination chunk (1 → 3×3 chunks). */
    private static final int WAIT_RADIUS = 1;
    /** Ticket radius (2 → a 5×5 full-status band, so the 3×3 core loads fast and sends). */
    private static final int TICKET_RADIUS = 2;
    /** Timed-ticket lifespan: survives the wait + the teleport, then self-expires. */
    private static final int TICKET_LIFESPAN_TICKS = 400;
    /** Default wait budget before the action runs regardless (never strand a beat). */
    public static final int DEFAULT_TIMEOUT_TICKS = 100;

    /** Self-expiring ticket type — never needs a matching removeRegionTicket. */
    private static final TicketType<ChunkPos> PRELOAD_TICKET = TicketType.create(
            "eclipse_preload", Comparator.comparingLong(ChunkPos::toLong), TICKET_LIFESPAN_TICKS);

    /** Outstanding warms; server thread only. */
    private static final List<Pending> PENDING = new ArrayList<>(4);

    private record Pending(ServerLevel level, int centerChunkX, int centerChunkZ,
            long deadlineGameTime, Runnable action) {}

    private ChunkPreload() {}

    /**
     * Warms the 3×3 chunk square around {@code dest} in {@code level} and runs
     * {@code action} on the server thread as soon as every one of those chunks is fully
     * loaded — immediately (synchronously) when they already are — or when
     * {@code timeoutTicks} elapses, whichever comes first.
     */
    public static void warmThenRun(ServerLevel level, Vec3 dest, int timeoutTicks, Runnable action) {
        ChunkPos center = new ChunkPos(new net.minecraft.core.BlockPos(
                (int) Math.floor(dest.x), (int) Math.floor(dest.y), (int) Math.floor(dest.z)));
        level.getChunkSource().addRegionTicket(PRELOAD_TICKET, center, TICKET_RADIUS, center);
        if (isLoaded(level, center.x, center.z)) {
            action.run(); // hot path: destination already resident — zero added latency
            return;
        }
        PENDING.add(new Pending(level, center.x, center.z,
                level.getGameTime() + Math.max(1, timeoutTicks), action));
        EclipseMod.LOGGER.debug("ChunkPreload: warming 3x3 around chunk ({}, {}) in {}",
                center.x, center.z, level.dimension().location());
    }

    /** Whether the whole waited-on square is fully loaded ({@code getChunkNow} law). */
    private static boolean isLoaded(ServerLevel level, int centerX, int centerZ) {
        for (int dx = -WAIT_RADIUS; dx <= WAIT_RADIUS; dx++) {
            for (int dz = -WAIT_RADIUS; dz <= WAIT_RADIUS; dz++) {
                if (level.getChunkSource().getChunkNow(centerX + dx, centerZ + dz) == null) {
                    return false;
                }
            }
        }
        return true;
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (PENDING.isEmpty()) {
            return;
        }
        for (int i = PENDING.size() - 1; i >= 0; i--) {
            Pending pending = PENDING.get(i);
            if (pending.level().getServer() != event.getServer()) {
                continue;
            }
            boolean ready = isLoaded(pending.level(), pending.centerChunkX(), pending.centerChunkZ());
            boolean timedOut = pending.level().getGameTime() >= pending.deadlineGameTime();
            if (!ready && !timedOut) {
                continue;
            }
            PENDING.remove(i);
            if (timedOut && !ready) {
                EclipseMod.LOGGER.warn(
                        "ChunkPreload: 3x3 around chunk ({}, {}) not ready in time — running the action anyway",
                        pending.centerChunkX(), pending.centerChunkZ());
            }
            try {
                pending.action().run();
            } catch (Throwable t) {
                EclipseMod.LOGGER.error("ChunkPreload: deferred action threw", t);
            }
        }
    }

    /** Pending actions must never leak into (or run against) the next world. */
    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        PENDING.clear();
    }
}
