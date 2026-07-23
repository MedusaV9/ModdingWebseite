package dev.projecteclipse.eclipse.xboxevent;

import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.mojang.serialization.DynamicOps;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.RegistryOps;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.item.ItemStack;

/**
 * Read-only view of the bundled Xbox world payload metadata (plan §2.13.1 step 5, layout
 * frozen by P5-W7):
 *
 * <ul>
 *   <li>{@code assets/eclipse/xboxworlds/manifest.json} — world ids, display names, spawn,
 *       zip sha256/size (the installer verifies the zip bytes against it);</li>
 *   <li>{@code data/eclipse/xboxworlds/<id>_loot.json} — baked chest contents keyed by
 *       position, items in the vanilla {@link ItemStack#CODEC} JSON shape (original vanilla
 *       ids; classic mapping happens at spill time in {@code XboxEventService}).</li>
 * </ul>
 *
 * <p>The manifest itself is immutable jar content and parsed once per JVM. Decoded loot
 * holds {@link ItemStack}s and is cached per world id; {@link #clearRuntimeCaches()} is
 * called on server stop so nothing leaks across singleplayer relaunches.</p>
 */
public final class XboxWorldsManifest {

    /** One world entry of the frozen manifest schema. */
    public record WorldEntry(
            String worldId,
            String displayNameEn,
            String displayNameDe,
            BlockPos spawn,
            float spawnYaw,
            String sha256,
            long sizeBytes,
            String zipResourcePath,
            String lootResourcePath) {

        /** Translatable key kept consistent with the P5-W7 langdrop. */
        public String nameKey() {
            return "eclipse.xboxworld." + worldId + ".name";
        }
    }

    private static final String MANIFEST_RESOURCE = "assets/eclipse/xboxworlds/manifest.json";

    private static volatile Map<String, WorldEntry> entries;
    private static final Map<String, Map<BlockPos, List<ItemStack>>> LOOT_CACHE = new ConcurrentHashMap<>();

    private XboxWorldsManifest() {}

    /** All manifest worlds, keyed by world id, in manifest order. Empty map on parse failure. */
    public static Map<String, WorldEntry> all() {
        Map<String, WorldEntry> local = entries;
        if (local == null) {
            synchronized (XboxWorldsManifest.class) {
                local = entries;
                if (local == null) {
                    local = parseManifest();
                    entries = local;
                }
            }
        }
        return local;
    }

    public static Optional<WorldEntry> byId(String worldId) {
        return Optional.ofNullable(all().get(worldId));
    }

    /**
     * Baked container loot for {@code worldId}, keyed by block position. Decoded lazily with
     * the server's registry access (component-bearing stacks need {@link RegistryOps}) and
     * cached. Returned stacks are the cached instances — callers must {@link ItemStack#copy()}
     * before handing them to the world.
     */
    public static Map<BlockPos, List<ItemStack>> loot(MinecraftServer server, String worldId) {
        WorldEntry entry = all().get(worldId);
        if (entry == null) {
            return Map.of();
        }
        return LOOT_CACHE.computeIfAbsent(worldId, id -> parseLoot(server, entry));
    }

    /** Drops decoded loot stacks; called from the service on {@code ServerStoppedEvent}. */
    public static void clearRuntimeCaches() {
        LOOT_CACHE.clear();
    }

    // ------------------------------------------------------------------ parsing

    private static Map<String, WorldEntry> parseManifest() {
        try (InputStream in = resource(MANIFEST_RESOURCE)) {
            if (in == null) {
                EclipseMod.LOGGER.error("Xbox worlds manifest missing from jar: {}", MANIFEST_RESOURCE);
                return Map.of();
            }
            JsonObject root = JsonParser.parseReader(
                    new InputStreamReader(in, StandardCharsets.UTF_8)).getAsJsonObject();
            Map<String, WorldEntry> parsed = new LinkedHashMap<>();
            for (JsonElement worldElement : root.getAsJsonArray("worlds")) {
                JsonObject world = worldElement.getAsJsonObject();
                String worldId = world.get("worldId").getAsString();
                JsonObject names = world.getAsJsonObject("displayName");
                JsonArray spawn = world.getAsJsonArray("spawn");
                parsed.put(worldId, new WorldEntry(
                        worldId,
                        names.get("en_us").getAsString(),
                        names.get("de_de").getAsString(),
                        new BlockPos(spawn.get(0).getAsInt(), spawn.get(1).getAsInt(), spawn.get(2).getAsInt()),
                        world.get("spawnYaw").getAsFloat(),
                        world.get("sha256").getAsString(),
                        world.get("sizeBytes").getAsLong(),
                        world.get("zip").getAsString(),
                        world.get("lootManifest").getAsString()));
            }
            return Collections.unmodifiableMap(parsed);
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("Failed to parse {}", MANIFEST_RESOURCE, e);
            return Map.of();
        }
    }

    private static Map<BlockPos, List<ItemStack>> parseLoot(MinecraftServer server, WorldEntry entry) {
        try (InputStream in = resource(entry.lootResourcePath())) {
            if (in == null) {
                EclipseMod.LOGGER.warn("Xbox loot manifest missing from jar: {}", entry.lootResourcePath());
                return Map.of();
            }
            JsonObject root = JsonParser.parseReader(
                    new InputStreamReader(in, StandardCharsets.UTF_8)).getAsJsonObject();
            DynamicOps<JsonElement> ops = RegistryOps.create(
                    com.mojang.serialization.JsonOps.INSTANCE, server.registryAccess());
            Map<BlockPos, List<ItemStack>> loot = new LinkedHashMap<>();
            int badItems = 0;
            for (JsonElement containerElement : root.getAsJsonArray("containers")) {
                JsonObject container = containerElement.getAsJsonObject();
                JsonArray pos = container.getAsJsonArray("pos");
                BlockPos blockPos = new BlockPos(
                        pos.get(0).getAsInt(), pos.get(1).getAsInt(), pos.get(2).getAsInt());
                List<ItemStack> stacks = new ArrayList<>();
                for (JsonElement itemElement : container.getAsJsonArray("items")) {
                    var result = ItemStack.CODEC.parse(ops, itemElement);
                    if (result.result().isPresent()) {
                        stacks.add(result.result().get());
                    } else {
                        badItems++;
                        EclipseMod.LOGGER.warn("Undecodable loot item at {} in {}: {}", blockPos,
                                entry.lootResourcePath(),
                                result.error().map(Object::toString).orElse("unknown error"));
                    }
                }
                if (!stacks.isEmpty()) {
                    loot.put(blockPos, Collections.unmodifiableList(stacks));
                }
            }
            EclipseMod.LOGGER.info("Decoded xbox loot for {}: {} containers ({} undecodable items)",
                    entry.worldId(), loot.size(), badItems);
            return Collections.unmodifiableMap(loot);
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("Failed to parse {}", entry.lootResourcePath(), e);
            return Map.of();
        }
    }

    private static InputStream resource(String path) {
        return XboxWorldsManifest.class.getClassLoader().getResourceAsStream(path);
    }
}
