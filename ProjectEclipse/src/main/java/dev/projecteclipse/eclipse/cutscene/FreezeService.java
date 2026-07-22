package dev.projecteclipse.eclipse.cutscene;

import java.util.ArrayDeque;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDeathEvent;
import net.neoforged.neoforge.event.entity.living.LivingIncomingDamageEvent;
import net.neoforged.neoforge.event.entity.living.LivingKnockBackEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import net.neoforged.neoforge.event.tick.PlayerTickEvent;

/**
 * Server-authoritative player freeze + invulnerability, used by the cutscene engine and by
 * ring-growth unlock animations (W14 adds manual {@code /eclipse freeze} wrappers on top).
 *
 * <p><b>Mechanism</b> ({@code docs/ideas/05_systems.md} §1): a TRANSIENT (never serialized,
 * never copied on death) {@code eclipse:cutscene_lock} attachment carrying a
 * {@link CutsceneLock}. While locked:</p>
 * <ul>
 *   <li>{@link PlayerTickEvent.Pre} rubber-bands the player back to the anchor
 *       ({@code connection.teleport} once they drift &gt; 0.1 blocks), zeroes
 *       {@code setDeltaMovement} and stops elytra flight — the client-side input swallow is
 *       comfort only, the server is the truth;</li>
 *   <li>every cancellable {@link PlayerInteractEvent} is cancelled;</li>
 *   <li>{@link LivingIncomingDamageEvent} and {@link LivingKnockBackEvent} are cancelled
 *       (invulnerability WITHOUT ever flipping {@code abilities.invulnerable}, which would
 *       leak on a crash).</li>
 * </ul>
 *
 * <p><b>Watchdog</b> (§5): every lock has a mandatory TTL and is force-released when it
 * expires, on death, on dimension change (unless the scripted-intro flag is set — then the
 * anchor re-follows the player for a short grace window instead), and on logout; stale locks
 * are cleared at login. Because the attachment is transient, a server restart always
 * unfreezes. Recent forced releases are kept in a small ring buffer for the W14 inspector.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class FreezeService {
    /** Squared rubber-band trigger distance (0.1 blocks). */
    private static final double RUBBER_BAND_DIST_SQ = 0.1D * 0.1D;
    /** Grace re-anchor window applied on an intro dimension change (covers the rise launch). */
    private static final int DIMENSION_CHANGE_GRACE_TICKS = 40;
    private static final int WATCHDOG_BUFFER_SIZE = 32;

    /** Ring buffer of recent watchdog/forced releases (newest last); W14's inspector prints it. */
    private static final ArrayDeque<String> WATCHDOG_EVENTS = new ArrayDeque<>();

    private FreezeService() {}

    // --- public API (frozen for W7 border physics + W14 commands) ---

    /** Freezes a player in place for at most {@code ttlTicks} (movement lock + invuln). */
    public static void freeze(ServerPlayer player, int ttlTicks) {
        freeze(player, ttlTicks, false, 0);
    }

    /**
     * Full-control freeze: {@code survivesDimensionChange} keeps the lock across the scripted
     * intro teleport, {@code graceTicks} lets the anchor follow the player first (so a
     * server-driven launch — e.g. the intro rise — plays out before the position locks).
     */
    public static void freeze(ServerPlayer player, int ttlTicks, boolean survivesDimensionChange,
            int graceTicks) {
        CutsceneLock lock = new CutsceneLock();
        lock.ttlTicks = Math.max(1, ttlTicks);
        lock.graceTicks = Math.max(0, graceTicks);
        lock.survivesDimensionChange = survivesDimensionChange;
        anchor(lock, player.position());
        player.setData(EclipseAttachments.CUTSCENE_LOCK, lock);
        EclipseMod.LOGGER.info("FreezeService: froze {} for {} ticks (grace {}, intro {})",
                player.getScoreboardName(), lock.ttlTicks, lock.graceTicks, survivesDimensionChange);
    }

    /** Releases a player's freeze immediately. Safe to call when not frozen. */
    public static void unfreeze(ServerPlayer player) {
        if (player.hasData(EclipseAttachments.CUTSCENE_LOCK)) {
            player.removeData(EclipseAttachments.CUTSCENE_LOCK);
            EclipseMod.LOGGER.info("FreezeService: unfroze {}", player.getScoreboardName());
        }
    }

    /** Whether the player is currently frozen. W7's border physics skips frozen players. */
    public static boolean isFrozen(ServerPlayer player) {
        return player.hasData(EclipseAttachments.CUTSCENE_LOCK);
    }

    /**
     * Re-anchors an existing lock at the player's CURRENT position and lets the anchor keep
     * following them for {@code graceTicks} — used after scripted teleports/launches.
     */
    public static void reanchorWithGrace(ServerPlayer player, int graceTicks) {
        if (!player.hasData(EclipseAttachments.CUTSCENE_LOCK)) {
            return;
        }
        CutsceneLock lock = player.getData(EclipseAttachments.CUTSCENE_LOCK);
        anchor(lock, player.position());
        lock.graceTicks = Math.max(lock.graceTicks, graceTicks);
    }

    /** Recent watchdog/forced releases, oldest first (ring buffer of {@value #WATCHDOG_BUFFER_SIZE}). */
    public static synchronized List<String> recentWatchdogEvents() {
        return List.copyOf(WATCHDOG_EVENTS);
    }

    // --- lock enforcement ---

    private static void anchor(CutsceneLock lock, Vec3 pos) {
        lock.anchorX = pos.x;
        lock.anchorY = pos.y;
        lock.anchorZ = pos.z;
    }

    private static void release(ServerPlayer player, String reason) {
        if (!player.hasData(EclipseAttachments.CUTSCENE_LOCK)) {
            return;
        }
        player.removeData(EclipseAttachments.CUTSCENE_LOCK);
        recordWatchdogEvent(player.getScoreboardName() + ": " + reason);
        EclipseMod.LOGGER.info("FreezeService: released {} ({})", player.getScoreboardName(), reason);
    }

    private static synchronized void recordWatchdogEvent(String line) {
        WATCHDOG_EVENTS.addLast(line);
        while (WATCHDOG_EVENTS.size() > WATCHDOG_BUFFER_SIZE) {
            WATCHDOG_EVENTS.removeFirst();
        }
    }

    @SubscribeEvent
    static void onPlayerTickPre(PlayerTickEvent.Pre event) {
        if (!(event.getEntity() instanceof ServerPlayer player)
                || !player.hasData(EclipseAttachments.CUTSCENE_LOCK)) {
            return;
        }
        CutsceneLock lock = player.getData(EclipseAttachments.CUTSCENE_LOCK);
        if (--lock.ttlTicks <= 0) {
            release(player, "watchdog TTL expired");
            return;
        }
        if (lock.graceTicks > 0) {
            lock.graceTicks--;
            anchor(lock, player.position());
            return;
        }
        double dx = player.getX() - lock.anchorX;
        double dy = player.getY() - lock.anchorY;
        double dz = player.getZ() - lock.anchorZ;
        if (dx * dx + dy * dy + dz * dz > RUBBER_BAND_DIST_SQ) {
            // Keep the player's own look direction — the freeze locks position, not the head.
            player.connection.teleport(lock.anchorX, lock.anchorY, lock.anchorZ,
                    player.getYRot(), player.getXRot());
        }
        player.setDeltaMovement(Vec3.ZERO);
        if (player.isFallFlying()) {
            player.stopFallFlying();
        }
    }

    // --- interaction cancels (server-side; the base PlayerInteractEvent is not cancellable) ---

    @SubscribeEvent
    static void onRightClickBlock(PlayerInteractEvent.RightClickBlock event) {
        if (event.getEntity() instanceof ServerPlayer player && isFrozen(player)) {
            event.setCanceled(true);
        }
    }

    @SubscribeEvent
    static void onRightClickItem(PlayerInteractEvent.RightClickItem event) {
        if (event.getEntity() instanceof ServerPlayer player && isFrozen(player)) {
            event.setCanceled(true);
        }
    }

    @SubscribeEvent
    static void onLeftClickBlock(PlayerInteractEvent.LeftClickBlock event) {
        if (event.getEntity() instanceof ServerPlayer player && isFrozen(player)) {
            event.setCanceled(true);
        }
    }

    @SubscribeEvent
    static void onEntityInteract(PlayerInteractEvent.EntityInteract event) {
        if (event.getEntity() instanceof ServerPlayer player && isFrozen(player)) {
            event.setCanceled(true);
        }
    }

    @SubscribeEvent
    static void onEntityInteractSpecific(PlayerInteractEvent.EntityInteractSpecific event) {
        if (event.getEntity() instanceof ServerPlayer player && isFrozen(player)) {
            event.setCanceled(true);
        }
    }

    // --- invulnerability (never flips abilities.invulnerable) ---

    @SubscribeEvent
    static void onIncomingDamage(LivingIncomingDamageEvent event) {
        if (event.getEntity() instanceof ServerPlayer player && isFrozen(player)) {
            event.setCanceled(true);
        }
    }

    @SubscribeEvent
    static void onKnockBack(LivingKnockBackEvent event) {
        if (event.getEntity() instanceof ServerPlayer player && isFrozen(player)) {
            event.setCanceled(true);
        }
    }

    // --- watchdog releases ---

    @SubscribeEvent
    static void onDeath(LivingDeathEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            release(player, "death");
        }
    }

    @SubscribeEvent
    static void onChangedDimension(PlayerEvent.PlayerChangedDimensionEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)
                || !player.hasData(EclipseAttachments.CUTSCENE_LOCK)) {
            return;
        }
        CutsceneLock lock = player.getData(EclipseAttachments.CUTSCENE_LOCK);
        if (lock.survivesDimensionChange) {
            // Scripted intro teleport: keep the lock, follow the player to the new position.
            reanchorWithGrace(player, DIMENSION_CHANGE_GRACE_TICKS);
        } else {
            release(player, "dimension change");
        }
    }

    @SubscribeEvent
    static void onLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            release(player, "logout");
        }
    }

    /** Transient attachments cannot survive a relog, but clear defensively anyway. */
    @SubscribeEvent
    static void onLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player
                && player.hasData(EclipseAttachments.CUTSCENE_LOCK)) {
            release(player, "stale lock at login");
        }
    }
}
