package dev.projecteclipse.eclipse.progression;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.AnvilBlock;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityTravelToDimensionEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Server-authoritative phase locks tied to {@link UnlockState} keys. All effects are purely
 * derived from the current unlock set, so everything reverses on its own the moment a key
 * becomes unlocked (or re-applies if the day is lowered). Only SURVIVAL/ADVENTURE players are
 * affected; blocked actions show a brief accent-colored action-bar hint (translatable
 * {@code message.eclipse.sealed.*}, never chat), rate-limited per player and hint key so the
 * every-second inventory sweep cannot strobe the actionbar.
 *
 * <ul>
 *   <li>{@code main_inventory} — every second, stacks in main inventory slots 9–35 are moved
 *       to free hotbar slots (or dropped at the player when the hotbar is full).</li>
 *   <li>{@code armor} — armor slots 36–39 and offhand slot 40 are cleared the same way,
 *       except the {@code eclipse:arm_artifact} item (looked up by id, null-guarded).</li>
 *   <li>{@code workbenches}/{@code smithing}/{@code enchanting}/{@code brewing}/{@code ender_chests}
 *       — right-clicking the matching workstation blocks is cancelled.</li>
 *   <li>{@code nether}/{@code end} — dimension travel for players is cancelled.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class PhaseInventoryLock {
    public static final String KEY_MAIN_INVENTORY = "main_inventory";
    public static final String KEY_ARMOR = "armor";
    public static final String KEY_WORKBENCHES = "workbenches";
    public static final String KEY_SMITHING = "smithing";
    public static final String KEY_ENCHANTING = "enchanting";
    public static final String KEY_BREWING = "brewing";
    public static final String KEY_ENDER_CHESTS = "ender_chests";
    public static final String KEY_NETHER = "nether";
    public static final String KEY_END = "end";

    private static final int SWEEP_INTERVAL_TICKS = 20;
    private static final int MAIN_START = 9;
    private static final int MAIN_END = 35;
    private static final int ARMOR_START = 36;
    private static final int OFFHAND_SLOT = 40;
    private static final int HOTBAR_END = 8;
    /** The arm artifact may be registered by another worker; resolved by id and null-guarded. */
    private static final ResourceLocation ARM_ARTIFACT_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "arm_artifact");

    /** Eclipse accent (mirrors the client UI suite's 0xB98CFF) for the seal hints. */
    private static final int HINT_COLOR = 0xB98CFF;
    /** Minimum ticks between repeats of the SAME hint key for one player (anti-strobe). */
    private static final int HINT_COOLDOWN_TICKS = 100;

    /** Overworld game time each hint key was last shown, per player. Server thread only. */
    private static final Map<UUID, Map<String, Long>> HINT_SHOWN_AT = new HashMap<>();

    private PhaseInventoryLock() {}

    // --- inventory / armor sweep ---

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % SWEEP_INTERVAL_TICKS != 0) {
            return;
        }
        boolean mainLocked = !UnlockState.isUnlocked(server, KEY_MAIN_INVENTORY);
        boolean armorLocked = !UnlockState.isUnlocked(server, KEY_ARMOR);
        if (!mainLocked && !armorLocked) {
            return;
        }
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            if (!player.gameMode.isSurvival()) {
                continue;
            }
            if (mainLocked && sweepMainInventory(player)) {
                hint(player, "message.eclipse.sealed.main_inventory");
            }
            if (armorLocked && sweepArmorAndOffhand(player)) {
                hint(player, "message.eclipse.sealed.armor");
            }
        }
    }

    /** Moves stacks out of main inventory slots 9..35; returns whether anything moved. */
    private static boolean sweepMainInventory(ServerPlayer player) {
        Inventory inventory = player.getInventory();
        boolean moved = false;
        for (int slot = MAIN_START; slot <= MAIN_END; slot++) {
            ItemStack stack = inventory.getItem(slot);
            if (stack.isEmpty()) {
                continue;
            }
            inventory.setItem(slot, ItemStack.EMPTY);
            stashInHotbarOrDrop(player, stack);
            moved = true;
        }
        return moved;
    }

    /** Clears armor slots 36..39 + offhand 40 (except the arm artifact); returns whether anything moved. */
    private static boolean sweepArmorAndOffhand(ServerPlayer player) {
        Item armArtifact = BuiltInRegistries.ITEM.getOptional(ARM_ARTIFACT_ID).orElse(null);
        Inventory inventory = player.getInventory();
        boolean moved = false;
        for (int slot = ARMOR_START; slot <= OFFHAND_SLOT; slot++) {
            ItemStack stack = inventory.getItem(slot);
            if (stack.isEmpty() || (armArtifact != null && stack.is(armArtifact))) {
                continue;
            }
            inventory.setItem(slot, ItemStack.EMPTY);
            stashInHotbarOrDrop(player, stack);
            moved = true;
        }
        return moved;
    }

    private static void stashInHotbarOrDrop(ServerPlayer player, ItemStack stack) {
        Inventory inventory = player.getInventory();
        for (int slot = 0; slot <= HOTBAR_END; slot++) {
            if (inventory.getItem(slot).isEmpty()) {
                inventory.setItem(slot, stack);
                return;
            }
        }
        player.drop(stack, false);
    }

    // --- workstation blocks ---

    @SubscribeEvent
    public static void onRightClickBlock(PlayerInteractEvent.RightClickBlock event) {
        if (!(event.getEntity() instanceof ServerPlayer player) || !player.gameMode.isSurvival()) {
            return;
        }
        String key = workstationKey(event.getLevel().getBlockState(event.getPos()).getBlock());
        if (key == null || UnlockState.isUnlocked(player.server, key)) {
            return;
        }
        event.setCanceled(true);
        hint(player, "message.eclipse.sealed.block");
    }

    /** The unlock key guarding a workstation block, or {@code null} if the block is never gated. */
    private static String workstationKey(Block block) {
        if (block == Blocks.CRAFTING_TABLE || block instanceof AnvilBlock) {
            return KEY_WORKBENCHES;
        }
        if (block == Blocks.SMITHING_TABLE) {
            return KEY_SMITHING;
        }
        if (block == Blocks.ENCHANTING_TABLE) {
            return KEY_ENCHANTING;
        }
        if (block == Blocks.BREWING_STAND) {
            return KEY_BREWING;
        }
        if (block == Blocks.ENDER_CHEST) {
            return KEY_ENDER_CHESTS;
        }
        return null;
    }

    // --- dimension travel ---

    @SubscribeEvent
    public static void onEntityTravelToDimension(EntityTravelToDimensionEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player) || !player.gameMode.isSurvival()) {
            return;
        }
        ResourceKey<Level> destination = event.getDimension();
        String key = destination == Level.NETHER ? KEY_NETHER : destination == Level.END ? KEY_END : null;
        if (key == null || UnlockState.isUnlocked(player.server, key)) {
            return;
        }
        event.setCanceled(true);
        hint(player, "message.eclipse.sealed.dimension");
    }

    /**
     * Brief accent-colored action-bar hint (never chat), keyed by its {@code
     * message.eclipse.sealed.*} lang key. Each key repeats at most once per
     * {@value #HINT_COOLDOWN_TICKS} ticks per player — without the cooldown the
     * every-second inventory sweep would strobe the actionbar for as long as a sealed
     * inventory stays open. Overworld game time is the clock so a singleplayer relaunch
     * (fresh tick counter) can't wedge the cooldown; a backwards jump just re-shows once.
     */
    private static void hint(ServerPlayer player, String key) {
        long now = player.server.overworld().getGameTime();
        Map<String, Long> shownAt = HINT_SHOWN_AT.computeIfAbsent(player.getUUID(), id -> new HashMap<>());
        Long last = shownAt.get(key);
        if (last != null && now >= last && now - last < HINT_COOLDOWN_TICKS) {
            return;
        }
        shownAt.put(key, now);
        player.displayClientMessage(Component.translatable(key).withColor(HINT_COLOR), true);
    }

    /** Drops the hint cooldowns of departing players so the map cannot grow unbounded. */
    @SubscribeEvent
    public static void onPlayerLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        HINT_SHOWN_AT.remove(event.getEntity().getUUID());
    }
}
