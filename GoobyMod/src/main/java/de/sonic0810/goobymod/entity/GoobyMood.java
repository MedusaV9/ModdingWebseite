package de.sonic0810.goobymod.entity;

/** Server-authoritative readable mood, synchronized as a compact byte. */
public enum GoobyMood {
    HAPPY("mood.goobymod.happy"),
    CONTENT("mood.goobymod.content"),
    HUNGRY("mood.goobymod.hungry"),
    SLEEPY("mood.goobymod.sleepy"),
    LONELY("mood.goobymod.lonely"),
    SCARED("mood.goobymod.scared");

    private final String translationKey;
    public static final long MIN_DWELL_TICKS = 600L;

    GoobyMood(String translationKey) {
        this.translationKey = translationKey;
    }

    public String translationKey() {
        return this.translationKey;
    }

    public static GoobyMood byId(int id) {
        GoobyMood[] values = values();
        return values[Math.floorMod(id, values.length)];
    }

    public static GoobyMood derive(int satisfaction, long ticksSinceFed, boolean night,
            int ownerAwayTicks, int hungerTicks, int lonelyTicks, boolean scared) {
        if (scared) {
            return SCARED;
        }
        if (night) {
            return SLEEPY;
        }
        if (ticksSinceFed >= hungerTicks) {
            return HUNGRY;
        }
        if (ownerAwayTicks >= lonelyTicks) {
            return LONELY;
        }
        return satisfaction >= 70 ? HAPPY : CONTENT;
    }

    public static boolean canTransition(long lastChange, long now) {
        return lastChange == 0L || now - lastChange >= MIN_DWELL_TICKS;
    }
}
