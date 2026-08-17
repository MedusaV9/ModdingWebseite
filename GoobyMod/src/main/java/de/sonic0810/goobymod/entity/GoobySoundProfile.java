package de.sonic0810.goobymod.entity;

/** Pure, table-testable selection rules for the v3.2 soundscape. */
public final class GoobySoundProfile {
    public enum AmbientPool {
        HAPPY,
        NEUTRAL,
        SLEEPY
    }

    public static AmbientPool ambientPool(int satisfaction, boolean night) {
        if (night || satisfaction < 25) {
            return AmbientPool.SLEEPY;
        }
        return satisfaction >= GoobyEntity.HAPPY_THRESHOLD ? AmbientPool.HAPPY : AmbientPool.NEUTRAL;
    }

    public static String whistleSound(GoobyCommand command) {
        return switch (command) {
            case WANDER -> "entity.gooby.whistle_wander";
            case FOLLOW -> "entity.gooby.whistle_follow";
            case STAY -> "entity.gooby.whistle_stay";
        };
    }

    private GoobySoundProfile() {
    }
}
