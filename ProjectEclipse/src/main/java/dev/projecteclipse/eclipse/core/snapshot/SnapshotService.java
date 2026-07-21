package dev.projecteclipse.eclipse.core.snapshot;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;
import java.util.stream.Stream;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.mojang.serialization.JsonOps;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import net.minecraft.core.NonNullList;
import net.minecraft.resources.RegistryOps;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.Container;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.storage.LevelResource;
import net.neoforged.neoforge.server.ServerLifecycleHooks;

/**
 * Writes and restores JSON snapshots of a player's items (main inventory, armor, offhand,
 * ender chest) plus contextual metadata. Files live at
 * {@code <worldFolder>/eclipse/snapshots/<playerUuid>/<epochMillis>.json}.
 * All IO errors are logged and never thrown.
 */
public final class SnapshotService {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();

    private SnapshotService() {}

    /** Captures a snapshot of the player's items, position, dimension, lives and day under the given reason. */
    public static void snapshot(ServerPlayer player, String reason) {
        MinecraftServer server = player.server;
        RegistryOps<JsonElement> ops = RegistryOps.create(JsonOps.INSTANCE, player.registryAccess());
        Inventory inventory = player.getInventory();

        JsonObject root = new JsonObject();
        long timestamp = System.currentTimeMillis();
        root.addProperty("player", player.getUUID().toString());
        root.addProperty("player_name", player.getGameProfile().getName());
        root.addProperty("reason", reason);
        root.addProperty("timestamp", timestamp);
        root.addProperty("dimension", player.level().dimension().location().toString());

        JsonObject position = new JsonObject();
        position.addProperty("x", player.getX());
        position.addProperty("y", player.getY());
        position.addProperty("z", player.getZ());
        root.add("position", position);

        root.addProperty("lives", LivesApi.get(player));
        root.addProperty("day", EclipseWorldState.get(server).getDay());

        root.add("main", encodeList(inventory.items, ops));
        root.add("armor", encodeList(inventory.armor, ops));
        root.add("offhand", encodeList(inventory.offhand, ops));
        root.add("ender_chest", encodeContainer(player.getEnderChestInventory(), ops));

        Path dir = snapshotDir(server, player.getUUID());
        try {
            Files.createDirectories(dir);
            Path file = dir.resolve(timestamp + ".json");
            // Avoid clobbering a snapshot taken within the same millisecond.
            while (Files.exists(file)) {
                timestamp++;
                root.addProperty("timestamp", timestamp);
                file = dir.resolve(timestamp + ".json");
            }
            Files.writeString(file, GSON.toJson(root), StandardCharsets.UTF_8);
            EclipseMod.LOGGER.info("Saved snapshot for {} (reason: {}) to {}", player.getGameProfile().getName(), reason, file);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to write snapshot for {} (reason: {})", player.getUUID(), reason, e);
        }
    }

    /**
     * Lists all snapshot files for the given player, sorted by timestamp (oldest first).
     * Uses the currently running server; returns an empty list if none is running or on IO errors.
     */
    public static List<Path> list(UUID playerId) {
        MinecraftServer server = ServerLifecycleHooks.getCurrentServer();
        if (server == null) {
            EclipseMod.LOGGER.warn("SnapshotService.list called without a running server");
            return List.of();
        }
        return list(server, playerId);
    }

    /** Lists all snapshot files for the given player on the given server, sorted by timestamp (oldest first). */
    public static List<Path> list(MinecraftServer server, UUID playerId) {
        Path dir = snapshotDir(server, playerId);
        if (!Files.isDirectory(dir)) {
            return List.of();
        }
        try (Stream<Path> files = Files.list(dir)) {
            List<Path> result = new ArrayList<>(files
                    .filter(path -> path.getFileName().toString().endsWith(".json"))
                    .toList());
            result.sort(Comparator.comparingLong(SnapshotService::timestampOf));
            return List.copyOf(result);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to list snapshots for {}", playerId, e);
            return List.of();
        }
    }

    /**
     * Clears the player's inventory and ender chest, then re-applies the item contents of the
     * given snapshot file. Returns {@code true} on success; on failure logs and returns
     * {@code false} without modifying the player.
     */
    public static boolean restore(ServerPlayer player, Path snapshotFile) {
        JsonObject root;
        try {
            root = JsonParser.parseString(Files.readString(snapshotFile, StandardCharsets.UTF_8)).getAsJsonObject();
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("Failed to read snapshot {}", snapshotFile, e);
            return false;
        }

        RegistryOps<JsonElement> ops = RegistryOps.create(JsonOps.INSTANCE, player.registryAccess());
        Inventory inventory = player.getInventory();

        inventory.clearContent();
        player.getEnderChestInventory().clearContent();

        decodeInto(root.getAsJsonArray("main"), inventory.items, ops);
        decodeInto(root.getAsJsonArray("armor"), inventory.armor, ops);
        decodeInto(root.getAsJsonArray("offhand"), inventory.offhand, ops);

        JsonArray enderItems = root.getAsJsonArray("ender_chest");
        Container enderChest = player.getEnderChestInventory();
        if (enderItems != null) {
            for (int i = 0; i < enderItems.size() && i < enderChest.getContainerSize(); i++) {
                enderChest.setItem(i, decodeStack(enderItems.get(i), ops));
            }
        }

        player.inventoryMenu.broadcastChanges();
        player.containerMenu.broadcastChanges();
        EclipseMod.LOGGER.info("Restored snapshot {} for {}", snapshotFile, player.getGameProfile().getName());
        return true;
    }

    private static Path snapshotDir(MinecraftServer server, UUID playerId) {
        return server.getWorldPath(LevelResource.ROOT).resolve("eclipse").resolve("snapshots").resolve(playerId.toString());
    }

    private static long timestampOf(Path file) {
        String name = file.getFileName().toString();
        try {
            return Long.parseLong(name.substring(0, name.length() - ".json".length()));
        } catch (NumberFormatException e) {
            return Long.MAX_VALUE;
        }
    }

    private static JsonArray encodeList(NonNullList<ItemStack> stacks, RegistryOps<JsonElement> ops) {
        JsonArray array = new JsonArray(stacks.size());
        for (ItemStack stack : stacks) {
            array.add(encodeStack(stack, ops));
        }
        return array;
    }

    private static JsonArray encodeContainer(Container container, RegistryOps<JsonElement> ops) {
        JsonArray array = new JsonArray(container.getContainerSize());
        for (int i = 0; i < container.getContainerSize(); i++) {
            array.add(encodeStack(container.getItem(i), ops));
        }
        return array;
    }

    private static JsonElement encodeStack(ItemStack stack, RegistryOps<JsonElement> ops) {
        return ItemStack.OPTIONAL_CODEC.encodeStart(ops, stack)
                .resultOrPartial(error -> EclipseMod.LOGGER.error("Failed to encode item stack {}: {}", stack, error))
                .orElseGet(JsonObject::new);
    }

    private static void decodeInto(JsonArray items, NonNullList<ItemStack> target, RegistryOps<JsonElement> ops) {
        if (items == null) {
            return;
        }
        for (int i = 0; i < items.size() && i < target.size(); i++) {
            target.set(i, decodeStack(items.get(i), ops));
        }
    }

    private static ItemStack decodeStack(JsonElement json, RegistryOps<JsonElement> ops) {
        return ItemStack.OPTIONAL_CODEC.parse(ops, json)
                .resultOrPartial(error -> EclipseMod.LOGGER.error("Failed to decode item stack from {}: {}", json, error))
                .orElse(ItemStack.EMPTY);
    }
}
