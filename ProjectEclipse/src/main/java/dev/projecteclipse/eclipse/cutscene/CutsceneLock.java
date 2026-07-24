package dev.projecteclipse.eclipse.cutscene;

/**
 * Mutable per-player freeze state, held by the TRANSIENT {@code eclipse:cutscene_lock}
 * attachment (registered in {@code registry.EclipseAttachments} WITHOUT a serializer and
 * without {@code copyOnDeath()} — a restart or relog can therefore never leave a player
 * frozen). Only {@link FreezeService} reads or writes these fields.
 */
public final class CutsceneLock {
    /** Remaining ticks until the watchdog force-releases this lock. Mandatory, never ∞. */
    public int ttlTicks;
    /**
     * Ticks during which the rubber-band anchor follows the player instead of holding them
     * — lets server-driven repositioning (intro teleport + rise launch) play out before the
     * position locks.
     */
    public int graceTicks;
    /** Keep the lock across a dimension change (scripted intro) instead of releasing. */
    public boolean survivesDimensionChange;
    /**
     * FFIX-B (POLISH-SOL-06): owner token of the system that installed this lock —
     * {@code null} for the default cutscene/admin lane. The single shared attachment is
     * overwriteable by design, so a non-cutscene owner (ActionToggles move-deny) must
     * release ONLY through {@code FreezeService.unfreeze(player, token)}, which refuses
     * when a foreign lock has replaced the owner's lock in the meantime.
     */
    @javax.annotation.Nullable
    public String ownerToken;
    /** Rubber-band anchor (the position the player is held at). */
    public double anchorX;
    public double anchorY;
    public double anchorZ;

    public CutsceneLock() {}
}
