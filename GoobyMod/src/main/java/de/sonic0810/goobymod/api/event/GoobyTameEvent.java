package de.sonic0810.goobymod.api.event;

import de.sonic0810.goobymod.entity.GoobyEntity;
import net.minecraft.world.entity.player.Player;
import net.neoforged.bus.api.Event;

/** Fired after a wild Gooby receives its first owner. */
public final class GoobyTameEvent extends Event {
    private final GoobyEntity gooby;
    private final Player owner;

    public GoobyTameEvent(GoobyEntity gooby, Player owner) {
        this.gooby = gooby;
        this.owner = owner;
    }

    public GoobyEntity getGooby() {
        return this.gooby;
    }

    public Player getOwner() {
        return this.owner;
    }
}
