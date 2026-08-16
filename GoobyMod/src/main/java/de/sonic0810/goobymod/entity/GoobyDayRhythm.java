package de.sonic0810.goobymod.entity;

/**
 * Pure day-phase tuning table used by existing idle goals. Minecraft day time
 * is normalized so the schedule remains stable after many world days.
 */
public enum GoobyDayRhythm {
    MORNING(500, 420, 100),
    MIDDAY(360, 650, 70),
    EVENING(900, 220, 140),
    NIGHT(1200, 180, 180);

    private final int digInterval;
    private final int sitInterval;
    private final int strollInterval;

    GoobyDayRhythm(int digInterval, int sitInterval, int strollInterval) {
        this.digInterval = digInterval;
        this.sitInterval = sitInterval;
        this.strollInterval = strollInterval;
    }

    public int digInterval() {
        return this.digInterval;
    }

    public int sitInterval() {
        return this.sitInterval;
    }

    public int strollInterval() {
        return this.strollInterval;
    }

    public static GoobyDayRhythm at(long dayTime) {
        long time = Math.floorMod(dayTime, 24000L);
        if (time < 4000L) {
            return MORNING;
        }
        if (time < 10000L) {
            return MIDDAY;
        }
        if (time < 13000L) {
            return EVENING;
        }
        return NIGHT;
    }
}
