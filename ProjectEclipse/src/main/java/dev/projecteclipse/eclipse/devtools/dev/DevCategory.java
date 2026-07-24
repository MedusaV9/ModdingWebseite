package dev.projecteclipse.eclipse.devtools.dev;

/**
 * Handbook category rail ordering (max 14 visible groups).
 */
public enum DevCategory {
    EVENT,
    TIMER,
    BUFFS,
    QUESTS,
    PLAYERS,
    STAGE,
    DISPLAY,
    SPAWN,
    XBOX,
    MODS,
    MUSIC,
    CONFIG,
    ANALYTICS,
    CUTSCENE,
    LEGACY;

    /** Lang key: {@code dev.eclipse.category.<id>}. */
    public String langKey() {
        return "dev.eclipse.category." + name().toLowerCase();
    }
}
