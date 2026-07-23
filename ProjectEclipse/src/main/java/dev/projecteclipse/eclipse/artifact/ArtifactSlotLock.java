package dev.projecteclipse.eclipse.artifact;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.inventory.Slot;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.item.ItemTossEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Server-authoritative slot lock for the arm artifact ({@code eclipse:arm_artifact}).
 *
 * <ul>
 *   <li>Every {@value #SWEEP_INTERVAL_TICKS} ticks, every non-spectator player is checked:
 *       exactly one artifact must sit in hotbar slot {@value #ARTIFACT_SLOT} (rightmost).
 *       Missing → insert (moving whatever occupies the slot to a free slot, or dropping it);
 *       misplaced → relocated into the slot; duplicates → removed. Copies stashed in the
 *       player's OPEN container menu are purged first — otherwise stash + re-grant would
 *       mint a second artifact every sweep.</li>
 *   <li>{@link PlayerEvent.PlayerLoggedInEvent} runs the same enforcement, so the artifact
 *       is granted on first join.</li>
 *   <li>{@link ItemTossEvent} is cancelled for the artifact and the stack is returned to
 *       slot {@value #ARTIFACT_SLOT} (cancelling only stops the item entity from spawning;
 *       the stack was already removed from the inventory).</li>
 * </ul>
 *
 * <p>Interaction with {@code progression.PhaseInventoryLock}: that sweep exempts
 * {@code eclipse:arm_artifact} by registry id, and this sweep only ever writes into slot 8
 * (hotbar), which the phase lock never clears — so the two never fight over the artifact.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ArtifactSlotLock {
    /** Rightmost hotbar slot. */
    public static final int ARTIFACT_SLOT = 8;

    private static final int SWEEP_INTERVAL_TICKS = 20;
    /** Player main inventory (hotbar 0-8 + storage 9-35); armor/offhand are never used for relocation. */
    private static final int MAIN_INVENTORY_SIZE = 36;

    private ArtifactSlotLock() {}

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % SWEEP_INTERVAL_TICKS != 0) {
            return;
        }
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            if (!player.isSpectator()) {
                enforce(player);
            }
        }
    }

    @SubscribeEvent
    public static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player && !player.isSpectator()) {
            enforce(player);
        }
    }

    /** The artifact cannot be dropped: cancel the toss and put the stack back into slot 8. */
    @SubscribeEvent
    public static void onItemToss(ItemTossEvent event) {
        ItemStack stack = event.getEntity().getItem();
        if (!stack.is(EclipseItems.ARM_ARTIFACT.get())) {
            return;
        }
        event.setCanceled(true);
        if (event.getPlayer() instanceof ServerPlayer player) {
            Inventory inventory = player.getInventory();
            if (inventory.getItem(ARTIFACT_SLOT).is(EclipseItems.ARM_ARTIFACT.get())) {
                // Slot 8 already holds one — the tossed stack was a duplicate; let it vanish.
                return;
            }
            ItemStack occupant = inventory.getItem(ARTIFACT_SLOT);
            inventory.setItem(ARTIFACT_SLOT, stack.copyWithCount(1));
            if (!occupant.isEmpty()) {
                relocate(player, occupant);
            }
        }
    }

    /** Ensures exactly one artifact in slot 8: dedupes, relocates a misplaced one, or inserts a new one. */
    private static void enforce(ServerPlayer player) {
        Inventory inventory = player.getInventory();
        Item artifact = EclipseItems.ARM_ARTIFACT.get();

        // Mid-drag the artifact sits on the cursor, invisible to the slot scan — inserting a
        // fresh one now would duplicate it. Skip; the next sweep runs after the drag settles.
        if (player.containerMenu != null && player.containerMenu.getCarried().is(artifact)) {
            return;
        }

        // Copies stashed in the OPEN container menu (chest, barrel, ...) sit outside the
        // inventory scan below — purge them, or the re-grant would mint a duplicate. The
        // player-inventory rows mirror the slots handled below, so only foreign slots clear.
        if (player.containerMenu != null) {
            for (Slot menuSlot : player.containerMenu.slots) {
                if (!(menuSlot.container instanceof Inventory) && menuSlot.getItem().is(artifact)) {
                    menuSlot.set(ItemStack.EMPTY);
                }
            }
        }

        boolean inSlot = inventory.getItem(ARTIFACT_SLOT).is(artifact);
        ItemStack misplaced = ItemStack.EMPTY;
        for (int slot = 0; slot < inventory.getContainerSize(); slot++) {
            if (slot == ARTIFACT_SLOT) {
                continue;
            }
            ItemStack stack = inventory.getItem(slot);
            if (!stack.is(artifact)) {
                continue;
            }
            inventory.setItem(slot, ItemStack.EMPTY);
            if (!inSlot && misplaced.isEmpty()) {
                misplaced = stack.copyWithCount(1);
            }
        }

        if (inSlot) {
            ItemStack slotStack = inventory.getItem(ARTIFACT_SLOT);
            if (slotStack.getCount() > 1) {
                slotStack.setCount(1);
            }
            return;
        }

        ItemStack occupant = inventory.getItem(ARTIFACT_SLOT);
        inventory.setItem(ARTIFACT_SLOT, misplaced.isEmpty() ? new ItemStack(artifact) : misplaced);
        if (!occupant.isEmpty()) {
            relocate(player, occupant);
        }
    }

    /** Moves a stack displaced from slot 8 into the first free main-inventory slot, or drops it. */
    private static void relocate(ServerPlayer player, ItemStack stack) {
        Inventory inventory = player.getInventory();
        for (int slot = 0; slot < MAIN_INVENTORY_SIZE; slot++) {
            if (slot != ARTIFACT_SLOT && inventory.getItem(slot).isEmpty()) {
                inventory.setItem(slot, stack);
                return;
            }
        }
        player.drop(stack, false);
    }
}
