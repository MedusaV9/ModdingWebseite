package de.sonic0810.goobymod.menu;

import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.registry.ModMenus;
import javax.annotation.Nullable;
import net.minecraft.network.RegistryFriendlyByteBuf;
import net.minecraft.world.Container;
import net.minecraft.world.SimpleContainer;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.inventory.AbstractContainerMenu;
import net.minecraft.world.inventory.Slot;
import net.minecraft.world.item.ItemStack;

/** Four-slot owner-only storage carried by an equipped tiny satchel. */
public final class GoobySatchelMenu extends AbstractContainerMenu {
    public static final int SATCHEL_SLOTS = 4;
    private final Container container;
    @Nullable
    private final GoobyEntity gooby;

    public GoobySatchelMenu(int containerId, Inventory inventory, RegistryFriendlyByteBuf data) {
        this(containerId, inventory, resolveGooby(inventory, data.readVarInt()));
    }

    public GoobySatchelMenu(int containerId, Inventory inventory, @Nullable GoobyEntity gooby) {
        super(ModMenus.GOOBY_SATCHEL.get(), containerId);
        this.gooby = gooby;
        this.container = gooby == null ? new SimpleContainer(SATCHEL_SLOTS) : gooby.satchelInventory();
        checkContainerSize(this.container, SATCHEL_SLOTS);
        this.container.startOpen(inventory.player);

        for (int slot = 0; slot < SATCHEL_SLOTS; slot++) {
            addSlot(new Slot(this.container, slot, 53 + slot * 18, 24));
        }
        for (int row = 0; row < 3; row++) {
            for (int column = 0; column < 9; column++) {
                addSlot(new Slot(inventory, column + row * 9 + 9, 8 + column * 18, 61 + row * 18));
            }
        }
        for (int column = 0; column < 9; column++) {
            addSlot(new Slot(inventory, column, 8 + column * 18, 119));
        }
    }

    @Nullable
    public GoobyEntity gooby() {
        return this.gooby;
    }

    @Override
    public boolean stillValid(Player player) {
        return this.gooby != null && this.gooby.isAlive() && this.gooby.canUseSatchel(player)
                && player.distanceToSqr(this.gooby) <= 64.0;
    }

    @Override
    public ItemStack quickMoveStack(Player player, int slotIndex) {
        if (slotIndex < 0 || slotIndex >= this.slots.size()) {
            return ItemStack.EMPTY;
        }
        Slot slot = this.slots.get(slotIndex);
        if (!slot.hasItem()) {
            return ItemStack.EMPTY;
        }
        ItemStack source = slot.getItem();
        ItemStack original = source.copy();
        if (slotIndex < SATCHEL_SLOTS) {
            if (!moveItemStackTo(source, SATCHEL_SLOTS, this.slots.size(), true)) {
                return ItemStack.EMPTY;
            }
        } else if (!moveItemStackTo(source, 0, SATCHEL_SLOTS, false)) {
            return ItemStack.EMPTY;
        }
        if (source.isEmpty()) {
            slot.setByPlayer(ItemStack.EMPTY);
        } else {
            slot.setChanged();
        }
        return original;
    }

    @Override
    public void removed(Player player) {
        super.removed(player);
        this.container.stopOpen(player);
    }

    @Nullable
    private static GoobyEntity resolveGooby(Inventory inventory, int entityId) {
        Entity entity = inventory.player.level().getEntity(entityId);
        return entity instanceof GoobyEntity gooby ? gooby : null;
    }
}
