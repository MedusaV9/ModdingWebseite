package de.sonic0810.goobymod.api.event;

import de.sonic0810.goobymod.entity.GoobyEntity;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.item.ItemStack;
import net.neoforged.bus.api.Event;

/** Fired after a dug gift is delivered to the world or a Gooby satchel. */
public final class GoobyGiftEvent extends Event {
    private final GoobyEntity gooby;
    private final ServerPlayer recipient;
    private final ItemStack gift;
    private final boolean stashed;

    public GoobyGiftEvent(GoobyEntity gooby, ServerPlayer recipient, ItemStack gift, boolean stashed) {
        this.gooby = gooby;
        this.recipient = recipient;
        this.gift = gift.copy();
        this.stashed = stashed;
    }

    public GoobyEntity getGooby() {
        return this.gooby;
    }

    public ServerPlayer getRecipient() {
        return this.recipient;
    }

    public ItemStack getGift() {
        return this.gift.copy();
    }

    public boolean isStashed() {
        return this.stashed;
    }
}
