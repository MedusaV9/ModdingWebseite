package dev.projecteclipse.eclipse.limbo.door;

/**
 * Server-authoritative GLOBAL state of the Respawn Door (plans_v3 §2.5), stored on
 * {@link RespawnDoorBlockEntity} and synced to every client via plain BE data. The
 * per-viewer rule (ghosts always SEE the door closed regardless of a global
 * {@link #OPEN}) is applied client-side in the renderer path and needs no networking;
 * per-player open sequences ride {@link S2CDoorCuePayload} instead of this state.
 *
 * <p>P4's lives/death flow drives transitions via
 * {@link RespawnDoorApi#setGlobalState}; the door itself never runs lives logic.</p>
 */
public enum DoorState {
    /** Dormant prop: leaves shut, seam glow nearly dead (pre-event / between phases). */
    SEALED,
    /** Default: leaves shut, purple light breathing through the seam. */
    CLOSED,
    /** Leaves swung wide, the void beyond ablaze (held on the open pose). */
    OPEN;

    /** Stable wire/NBT id (ordinal is frozen by this accessor — do not reorder). */
    public int id() {
        return ordinal();
    }

    /** Inverse of {@link #id()}; out-of-range ids clamp to {@link #CLOSED}. */
    public static DoorState byId(int id) {
        DoorState[] values = values();
        return id >= 0 && id < values.length ? values[id] : CLOSED;
    }
}
