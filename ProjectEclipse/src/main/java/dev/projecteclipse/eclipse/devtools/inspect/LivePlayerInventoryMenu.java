package dev.projecteclipse.eclipse.devtools.inspect;

import dev.projecteclipse.eclipse.lang.ServerLang;
import net.minecraft.ChatFormatting;
import net.minecraft.core.component.DataComponents;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.Style;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.Container;
import net.minecraft.world.MenuProvider;
import net.minecraft.world.SimpleContainer;
import net.minecraft.world.SimpleMenuProvider;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.inventory.AbstractContainerMenu;
import net.minecraft.world.inventory.MenuType;
import net.minecraft.world.inventory.Slot;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;

/**
 * F-066 {@code /invsee <player>}: a LIVE six-row chest view of another player's inventory.
 *
 * <p>The 41 real slots of the target's {@link Inventory} (36 inventory + 4 armor + offhand) are
 * bound DIRECTLY as menu slots — no copying, no snapshot, no sync task. Every operator edit hits
 * the target's own {@code NonNullList} instantly and the target's client picks it up on its next
 * {@code broadcastChanges} tick; conversely anything the target does shows up in the operator's
 * screen the same way.</p>
 *
 * <p><b>Layout</b> (menu index → source), chosen so the rendered grid reads like the vanilla
 * inventory screen with the hotbar on top:</p>
 * <ol start="0">
 *   <li>{@code 0..8} — the target's hotbar ({@code Inventory} 0-8)</li>
 *   <li>{@code 9..35} — the target's main grid ({@code Inventory} 9-35)</li>
 *   <li>{@code 36..40} — helmet, chestplate, leggings, boots, offhand
 *       ({@code Inventory} 39, 38, 37, 36, 40)</li>
 *   <li>{@code 41..53} — 13 decorative gray panes</li>
 *   <li>{@code 54..89} — the operator's own inventory, in the exact order the vanilla
 *       {@code GENERIC_9x6} screen expects (3 main rows, then the hotbar)</li>
 * </ol>
 *
 * <p>The decorative slots are sealed three ways: {@link DecorSlot} refuses
 * {@code mayPlace}/{@code mayPickup} (which covers PICKUP, SWAP, THROW, PICKUP_ALL and the
 * quick-craft drag), {@link #quickMoveStack} never targets them, and their filler carries a
 * custom name so {@code moveItemStackTo}'s stacking pass — the one vanilla path that ignores
 * {@code mayPlace} — cannot match a plain pane against them either.</p>
 */
public final class LivePlayerInventoryMenu extends AbstractContainerMenu {
    /** Rows the vanilla {@code GENERIC_9x6} screen renders. */
    private static final int ROWS = 6;
    private static final int VIEW_SLOTS = ROWS * 9;
    /** Menu indices {@code 0..35} mirror the target's 36 carried inventory slots. */
    private static final int TARGET_MAIN_SLOTS = 36;
    /**
     * {@link Inventory} container indices of the equipment row, in display order: the armor
     * compartment starts at 36 and is ordered by {@code EquipmentSlot#getIndex} (feet, legs,
     * chest, head), so head→feet reads 39, 38, 37, 36; the offhand compartment follows at 40.
     */
    private static final int[] EQUIPMENT_ORDER = {39, 38, 37, 36, Inventory.SLOT_OFFHAND};
    /** Filler count: whatever is left of the six rows after the 41 real slots. */
    private static final int DECOR_SLOTS = VIEW_SLOTS - TARGET_MAIN_SLOTS - EQUIPMENT_ORDER.length;

    private final ServerPlayer target;

    /**
     * Builds the {@code /invsee} provider for one operator/target pair. The title and the filler
     * label are baked for the OPERATOR's locale here, before the menu exists.
     */
    public static MenuProvider provider(ServerPlayer viewer, ServerPlayer target) {
        Component title = ServerLang.tr(viewer, "eclipse.invsee.title",
                target.getGameProfile().getName());
        ItemStack filler = decorStack(viewer);
        return new SimpleMenuProvider((containerId, viewerInventory, player) ->
                new LivePlayerInventoryMenu(containerId, viewerInventory, target, filler), title);
    }

    private LivePlayerInventoryMenu(int containerId, Inventory viewerInventory, ServerPlayer target,
            ItemStack filler) {
        super(MenuType.GENERIC_9x6, containerId);
        this.target = target;
        Inventory targetInventory = target.getInventory();

        SimpleContainer decor = new SimpleContainer(DECOR_SLOTS);
        for (int i = 0; i < DECOR_SLOTS; i++) {
            decor.setItem(i, filler.copy());
        }

        for (int i = 0; i < TARGET_MAIN_SLOTS; i++) {
            addSlot(new Slot(targetInventory, i, viewX(i), viewY(i)));
        }
        int index = TARGET_MAIN_SLOTS;
        for (int equipment : EQUIPMENT_ORDER) {
            addSlot(new Slot(targetInventory, equipment, viewX(index), viewY(index)));
            index++;
        }
        for (int decorIndex = 0; index < VIEW_SLOTS; decorIndex++, index++) {
            addSlot(new DecorSlot(decor, decorIndex, viewX(index), viewY(index)));
        }

        // The operator's own inventory, laid out exactly like ChestMenu does it for six rows.
        int yOffset = (ROWS - 4) * 18;
        for (int row = 0; row < 3; row++) {
            for (int col = 0; col < 9; col++) {
                addSlot(new Slot(viewerInventory, col + row * 9 + 9, 8 + col * 18,
                        103 + row * 18 + yOffset));
            }
        }
        for (int col = 0; col < 9; col++) {
            addSlot(new Slot(viewerInventory, col, 8 + col * 18, 161 + yOffset));
        }
    }

    private static int viewX(int index) {
        return 8 + (index % 9) * 18;
    }

    private static int viewY(int index) {
        return 18 + (index / 9) * 18;
    }

    @Override
    public boolean stillValid(Player viewer) {
        return InspectTarget.isLive(this.target);
    }

    @Override
    public ItemStack quickMoveStack(Player viewer, int index) {
        Slot slot = this.slots.get(index);
        if (slot instanceof DecorSlot || !slot.hasItem()) {
            return ItemStack.EMPTY;
        }
        ItemStack inSlot = slot.getItem();
        ItemStack before = inSlot.copy();
        if (index < VIEW_SLOTS) {
            if (!moveItemStackTo(inSlot, VIEW_SLOTS, this.slots.size(), true)) {
                return ItemStack.EMPTY;
            }
        } else if (!moveItemStackTo(inSlot, 0, TARGET_MAIN_SLOTS, false)) {
            // Shift-clicking INTO the target stops at their 36 carried slots on purpose: armor
            // and offhand would happily accept any junk, and moveItemStackTo's stacking pass
            // does not consult mayPlace, so the decor row must stay out of range entirely.
            return ItemStack.EMPTY;
        }
        if (inSlot.isEmpty()) {
            slot.setByPlayer(ItemStack.EMPTY);
        } else {
            slot.setChanged();
        }
        return before;
    }

    private static ItemStack decorStack(ServerPlayer viewer) {
        ItemStack stack = new ItemStack(Items.GRAY_STAINED_GLASS_PANE);
        stack.set(DataComponents.CUSTOM_NAME, ServerLang.tr(viewer, "eclipse.invsee.decor")
                .withStyle(Style.EMPTY.withItalic(false).withColor(ChatFormatting.DARK_GRAY)));
        return stack;
    }

    /** Pure decoration: never takeable, never a drop target, never a merge target. */
    private static final class DecorSlot extends Slot {
        DecorSlot(Container container, int index, int x, int y) {
            super(container, index, x, y);
        }

        @Override
        public boolean mayPlace(ItemStack stack) {
            return false;
        }

        @Override
        public boolean mayPickup(Player viewer) {
            return false;
        }
    }
}
