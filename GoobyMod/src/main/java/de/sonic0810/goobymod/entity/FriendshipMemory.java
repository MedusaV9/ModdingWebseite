package de.sonic0810.goobymod.entity;

import net.minecraft.nbt.CompoundTag;

/** Per-player firsts and milestones persisted on the Gooby. */
public final class FriendshipMemory {
    public static final long ANNIVERSARY_AGE_TICKS = 7L * 24000L;

    private long firstPet = -1L;
    private long firstFeed = -1L;
    private long buddyAt = -1L;
    private long friendAt = -1L;
    private long bestFriendAt = -1L;
    private long lastSnuggleDay = -1L;
    private boolean anniversaryShown;

    public void rememberFirstPet(long gameTime) {
        if (this.firstPet < 0L) {
            this.firstPet = gameTime;
        }
    }

    public void rememberFirstFeed(long gameTime) {
        if (this.firstFeed < 0L) {
            this.firstFeed = gameTime;
        }
    }

    public void rememberTier(FriendshipTier tier, long gameTime) {
        switch (tier) {
            case BUDDY -> {
                if (this.buddyAt < 0L) {
                    this.buddyAt = gameTime;
                }
            }
            case FRIEND -> {
                if (this.friendAt < 0L) {
                    this.friendAt = gameTime;
                }
            }
            case BEST_FRIEND -> {
                if (this.bestFriendAt < 0L) {
                    this.bestFriendAt = gameTime;
                }
            }
            case STRANGER -> {
            }
        }
    }

    public long firstPet() {
        return this.firstPet;
    }

    public long firstFeed() {
        return this.firstFeed;
    }

    public long tierAt(FriendshipTier tier) {
        return switch (tier) {
            case STRANGER -> -1L;
            case BUDDY -> this.buddyAt;
            case FRIEND -> this.friendAt;
            case BEST_FRIEND -> this.bestFriendAt;
        };
    }

    public boolean canSnuggle(long gameTime) {
        return Math.floorDiv(gameTime, 24000L) > this.lastSnuggleDay;
    }

    public void markSnuggle(long gameTime) {
        this.lastSnuggleDay = Math.floorDiv(gameTime, 24000L);
    }

    public long lastSnuggleDay() {
        return this.lastSnuggleDay;
    }

    public boolean isAnniversaryDue(long gameTime) {
        return !this.anniversaryShown && (isAboutSevenDaysOld(this.firstPet, gameTime)
                || isAboutSevenDaysOld(this.firstFeed, gameTime)
                || isAboutSevenDaysOld(this.buddyAt, gameTime)
                || isAboutSevenDaysOld(this.friendAt, gameTime)
                || isAboutSevenDaysOld(this.bestFriendAt, gameTime));
    }

    private static boolean isAboutSevenDaysOld(long timestamp, long gameTime) {
        long age = gameTime - timestamp;
        return timestamp >= 0L && age >= ANNIVERSARY_AGE_TICKS
                && age < ANNIVERSARY_AGE_TICKS + 24000L;
    }

    public void markAnniversaryShown() {
        this.anniversaryShown = true;
    }

    public CompoundTag save() {
        CompoundTag tag = new CompoundTag();
        tag.putLong("FirstPet", this.firstPet);
        tag.putLong("FirstFeed", this.firstFeed);
        tag.putLong("BuddyAt", this.buddyAt);
        tag.putLong("FriendAt", this.friendAt);
        tag.putLong("BestFriendAt", this.bestFriendAt);
        tag.putLong("LastSnuggleDay", this.lastSnuggleDay);
        tag.putBoolean("AnniversaryShown", this.anniversaryShown);
        return tag;
    }

    public static FriendshipMemory load(CompoundTag tag) {
        FriendshipMemory memory = new FriendshipMemory();
        memory.firstPet = tag.contains("FirstPet") ? tag.getLong("FirstPet") : -1L;
        memory.firstFeed = tag.contains("FirstFeed") ? tag.getLong("FirstFeed") : -1L;
        memory.buddyAt = tag.contains("BuddyAt") ? tag.getLong("BuddyAt") : -1L;
        memory.friendAt = tag.contains("FriendAt") ? tag.getLong("FriendAt") : -1L;
        memory.bestFriendAt = tag.contains("BestFriendAt") ? tag.getLong("BestFriendAt") : -1L;
        memory.lastSnuggleDay = tag.contains("LastSnuggleDay") ? tag.getLong("LastSnuggleDay") : -1L;
        memory.anniversaryShown = tag.getBoolean("AnniversaryShown");
        return memory;
    }
}
