package dev.projecteclipse.eclipse.progression;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.lives.InheritanceService;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.inventory.MerchantResultSlot;
import net.minecraft.world.inventory.ResultContainer;
import net.minecraft.world.inventory.Slot;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.block.state.BlockState;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.common.util.TriState;
import net.neoforged.neoforge.event.entity.player.AttackEntityEvent;
import net.neoforged.neoforge.event.entity.player.ItemEntityPickupEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import net.neoforged.neoforge.event.level.BlockEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Runtime gating of external content mods (Create, Simulated, Aeronautics, Sable, ...) purely by
 * registry-id <em>namespace string</em> — there is deliberately no compile-time dependency on any
 * of those mods. {@code modgate.json} maps each gated namespace to an {@link UnlockState} key; a
 * namespace is LOCKED while its key is not unlocked. While locked, using/placing/attacking
 * with/picking up items and blocks from that namespace is cancelled, crafting results are
 * shrunk to 0, and a periodic sweep confiscates gated stacks from online SURVIVAL/ADVENTURE
 * players' inventories AND from the container menu they have open (chest stashes don't
 * survive), depositing them into the spawn chests via
 * {@link InheritanceService#depositAtSpawn} (items are never destroyed). Everything reverses
 * automatically once the key unlocks.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ModGate {
    private static final int SWEEP_INTERVAL_TICKS = 100;
    /** Offset so the sweep never lands on the same tick as the PhaseInventoryLock sweep. */
    private static final int SWEEP_PHASE = 50;
    /** Eclipse accent (mirrors the client UI suite's 0xB98CFF) for the seal hint. */
    private static final int HINT_COLOR = 0xB98CFF;

    private ModGate() {}

    // --- lock queries ---

    /** Whether the namespace is gated by {@code modgate.json} and its unlock key is still locked. */
    public static boolean isNamespaceLocked(MinecraftServer server, String namespace) {
        EclipseConfig.ModGate gate = EclipseConfig.modGate();
        if (!gate.gatedNamespaces().contains(namespace)) {
            return false;
        }
        String key = gate.unlockKeys().getOrDefault(namespace, namespace);
        return !UnlockState.isUnlocked(server, key);
    }

    /** Whether the stack's item belongs to a currently-locked gated namespace. */
    public static boolean isItemLocked(MinecraftServer server, ItemStack stack) {
        if (stack.isEmpty()) {
            return false;
        }
        var id = BuiltInRegistries.ITEM.getKey(stack.getItem());
        return isNamespaceLocked(server, id.getNamespace()) || ModGateIds.isLocked(server, id);
    }

    /** Whether the block state's block belongs to a currently-locked gated namespace. */
    public static boolean isBlockLocked(MinecraftServer server, BlockState state) {
        var id = BuiltInRegistries.BLOCK.getKey(state.getBlock());
        return isNamespaceLocked(server, id.getNamespace()) || ModGateIds.isLocked(server, id);
    }

    // --- interaction gating ---

    @SubscribeEvent
    public static void onRightClickBlock(PlayerInteractEvent.RightClickBlock event) {
        if (!(event.getEntity() instanceof ServerPlayer player) || !player.gameMode.isSurvival()) {
            return;
        }
        BlockState state = event.getLevel().getBlockState(event.getPos());
        if (isBlockLocked(player.server, state) || isItemLocked(player.server, event.getItemStack())) {
            event.setCanceled(true);
            hint(player);
        }
    }

    @SubscribeEvent
    public static void onRightClickItem(PlayerInteractEvent.RightClickItem event) {
        if (!(event.getEntity() instanceof ServerPlayer player) || !player.gameMode.isSurvival()) {
            return;
        }
        if (isItemLocked(player.server, event.getItemStack())) {
            event.setCanceled(true);
            hint(player);
        }
    }

    /** Melee with a gated weapon worked between sweeps — cancel the swing itself. */
    @SubscribeEvent
    public static void onAttackEntity(AttackEntityEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player) || !player.gameMode.isSurvival()) {
            return;
        }
        if (isItemLocked(player.server, player.getMainHandItem())) {
            event.setCanceled(true);
            hint(player);
        }
    }

    @SubscribeEvent
    public static void onEntityPlace(BlockEvent.EntityPlaceEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player) || !player.gameMode.isSurvival()) {
            return;
        }
        if (isBlockLocked(player.server, event.getPlacedBlock())) {
            event.setCanceled(true);
            hint(player);
        }
    }

    @SubscribeEvent
    public static void onItemPickup(ItemEntityPickupEvent.Pre event) {
        if (!(event.getPlayer() instanceof ServerPlayer player) || !player.gameMode.isSurvival()) {
            return;
        }
        if (isItemLocked(player.server, event.getItemEntity().getItem())) {
            event.setCanPickup(TriState.FALSE);
        }
    }

    @SubscribeEvent
    public static void onItemCrafted(PlayerEvent.ItemCraftedEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player) || !player.gameMode.isSurvival()) {
            return;
        }
        ItemStack crafted = event.getCrafting();
        if (isItemLocked(player.server, crafted)) {
            crafted.shrink(crafted.getCount());
            hint(player);
        }
    }

    // --- inventory sweep ---

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % SWEEP_INTERVAL_TICKS != SWEEP_PHASE) {
            return;
        }
        boolean anyLocked = false;
        for (String namespace : EclipseConfig.modGate().gatedNamespaces()) {
            if (isNamespaceLocked(server, namespace)) {
                anyLocked = true;
                break;
            }
        }
        if (!anyLocked && !ModGateIds.hasLockedEntries(server)) {
            return;
        }
        List<ItemStack> confiscated = new ArrayList<>();
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            if (!player.gameMode.isSurvival()) {
                continue;
            }
            Inventory inventory = player.getInventory();
            boolean removed = false;
            for (int slot = 0; slot < inventory.getContainerSize(); slot++) {
                ItemStack stack = inventory.getItem(slot);
                if (isItemLocked(server, stack)) {
                    inventory.setItem(slot, ItemStack.EMPTY);
                    confiscated.add(stack);
                    removed = true;
                }
            }
            // The container menu the player has OPEN (chest, barrel, ...) is swept too, so a
            // gated stack can't ride out the lock in a stash. Player-inventory rows mirror
            // the slots above; result/trade-preview slots hold phantom items whose
            // ingredients still exist — confiscating those would MINT items, so both skip.
            for (Slot menuSlot : player.containerMenu.slots) {
                if (menuSlot.container instanceof Inventory
                        || menuSlot.container instanceof ResultContainer
                        || menuSlot instanceof MerchantResultSlot) {
                    continue;
                }
                ItemStack stack = menuSlot.getItem();
                if (isItemLocked(server, stack)) {
                    menuSlot.set(ItemStack.EMPTY);
                    confiscated.add(stack);
                    removed = true;
                }
            }
            if (removed) {
                hint(player);
            }
        }
        if (!confiscated.isEmpty()) {
            int count = confiscated.size();
            InheritanceService.depositAtSpawn(server.overworld(), confiscated);
            EclipseMod.LOGGER.info("ModGate confiscated {} locked stack(s); deposited at spawn", count);
        }
    }

    /** Brief accent-colored action-bar message (never chat). */
    private static void hint(ServerPlayer player) {
        player.displayClientMessage(
                Component.translatable("message.eclipse.sealed.mod").withColor(HINT_COLOR), true);
    }
}
