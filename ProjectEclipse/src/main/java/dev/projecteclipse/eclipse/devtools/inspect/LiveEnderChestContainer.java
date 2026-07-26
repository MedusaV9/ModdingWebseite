package dev.projecteclipse.eclipse.devtools.inspect;

import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.Container;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.inventory.PlayerEnderChestContainer;
import net.minecraft.world.item.ItemStack;

/**
 * F-066 backing container of {@code /enderchestsee}: a thin LIVE delegate onto the target's
 * {@link PlayerEnderChestContainer}. Every read and write hits the target's real container, so
 * the operator's edits land instantly and the target's own client resyncs on its next
 * {@code broadcastChanges} tick.
 *
 * <p>Two vanilla behaviours are deliberately NOT delegated:</p>
 * <ul>
 *   <li>{@link #stillValid} — {@code PlayerEnderChestContainer} validates against the ender
 *       chest BLOCK the target may currently stand at, which would instantly close the remote
 *       operator's screen. The only thing that matters here is that the target is still online
 *       ({@link InspectTarget#isLive}).</li>
 *   <li>{@link #startOpen} / {@link #stopOpen} — those forward to the target's
 *       {@code activeChest} and, on close, NULL it. A remote viewer opening and closing this
 *       menu must never touch the target's own open-chest bookkeeping (lid animation, block
 *       open count).</li>
 * </ul>
 */
final class LiveEnderChestContainer implements Container {
    private final ServerPlayer target;

    LiveEnderChestContainer(ServerPlayer target) {
        this.target = target;
    }

    private PlayerEnderChestContainer backing() {
        return this.target.getEnderChestInventory();
    }

    @Override
    public int getContainerSize() {
        return backing().getContainerSize();
    }

    @Override
    public boolean isEmpty() {
        return backing().isEmpty();
    }

    @Override
    public ItemStack getItem(int slot) {
        return backing().getItem(slot);
    }

    @Override
    public ItemStack removeItem(int slot, int count) {
        return backing().removeItem(slot, count);
    }

    @Override
    public ItemStack removeItemNoUpdate(int slot) {
        return backing().removeItemNoUpdate(slot);
    }

    @Override
    public void setItem(int slot, ItemStack stack) {
        backing().setItem(slot, stack);
    }

    @Override
    public void setChanged() {
        backing().setChanged();
    }

    @Override
    public void clearContent() {
        backing().clearContent();
    }

    @Override
    public boolean stillValid(Player viewer) {
        return InspectTarget.isLive(this.target);
    }

    @Override
    public void startOpen(Player viewer) {
        // Intentionally empty — see the class javadoc.
    }

    @Override
    public void stopOpen(Player viewer) {
        // Intentionally empty — see the class javadoc.
    }
}
