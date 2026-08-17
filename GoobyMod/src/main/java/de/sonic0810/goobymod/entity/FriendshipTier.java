package de.sonic0810.goobymod.entity;

/** Derived friendship progression; existing 0-100 saves require no migration. */
public enum FriendshipTier {
    STRANGER(0, "tier.goobymod.stranger", "○"),
    BUDDY(20, "tier.goobymod.buddy", "✦"),
    FRIEND(50, "tier.goobymod.friend", "❤"),
    BEST_FRIEND(90, "tier.goobymod.best_friend", "★");

    private final int minimum;
    private final String translationKey;
    private final String icon;

    FriendshipTier(int minimum, String translationKey, String icon) {
        this.minimum = minimum;
        this.translationKey = translationKey;
        this.icon = icon;
    }

    public int minimum() {
        return this.minimum;
    }

    public String translationKey() {
        return this.translationKey;
    }

    public String icon() {
        return this.icon;
    }

    public boolean canWaveGreeting() {
        return this.ordinal() >= BUDDY.ordinal();
    }

    public boolean canReceiveGifts() {
        return this.ordinal() >= FRIEND.ordinal();
    }

    public boolean canRide() {
        return this.ordinal() >= FRIEND.ordinal();
    }

    public boolean canSnuggle() {
        return this == BEST_FRIEND;
    }

    public boolean canReceiveGoldenGifts() {
        return this == BEST_FRIEND;
    }

    public static FriendshipTier of(int friendship) {
        int value = Math.max(0, Math.min(100, friendship));
        if (value >= BEST_FRIEND.minimum) {
            return BEST_FRIEND;
        }
        if (value >= FRIEND.minimum) {
            return FRIEND;
        }
        if (value >= BUDDY.minimum) {
            return BUDDY;
        }
        return STRANGER;
    }
}
