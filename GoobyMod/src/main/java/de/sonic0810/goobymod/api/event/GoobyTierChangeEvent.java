package de.sonic0810.goobymod.api.event;

import de.sonic0810.goobymod.entity.FriendshipTier;
import de.sonic0810.goobymod.entity.GoobyEntity;
import net.minecraft.world.entity.player.Player;
import net.neoforged.bus.api.Event;

/** Fired after one player's friendship tier with a Gooby changes. */
public final class GoobyTierChangeEvent extends Event {
    private final GoobyEntity gooby;
    private final Player player;
    private final FriendshipTier previousTier;
    private final FriendshipTier newTier;

    public GoobyTierChangeEvent(GoobyEntity gooby, Player player,
            FriendshipTier previousTier, FriendshipTier newTier) {
        this.gooby = gooby;
        this.player = player;
        this.previousTier = previousTier;
        this.newTier = newTier;
    }

    public GoobyEntity getGooby() {
        return this.gooby;
    }

    public Player getPlayer() {
        return this.player;
    }

    public FriendshipTier getPreviousTier() {
        return this.previousTier;
    }

    public FriendshipTier getNewTier() {
        return this.newTier;
    }
}
