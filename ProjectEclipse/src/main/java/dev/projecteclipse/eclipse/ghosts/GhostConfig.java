package dev.projecteclipse.eclipse.ghosts;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.level.Level;
import net.neoforged.fml.loading.FMLPaths;

/**
 * Ghost settings — reads the {@code ghosts} section from {@code protection.json} when present,
 * otherwise uses plan defaults (B7 owns the file; B9 only consumes).
 */
public final class GhostConfig {
    public record Settings(
            boolean enabled,
            int revealTicks,
            int revealCooldownSeconds,
            List<ResourceKey<Level>> dimensions) {}

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().create();

    private static volatile Settings settings = defaults();

    private GhostConfig() {}

    public static Settings get() {
        return settings;
    }

    public static void reload() {
        Path file = FMLPaths.CONFIGDIR.get().resolve("eclipse").resolve("protection.json");
        if (!Files.isRegularFile(file)) {
            settings = defaults();
            return;
        }
        try {
            String json = Files.readString(file, StandardCharsets.UTF_8);
            JsonObject root = JsonParser.parseString(json).getAsJsonObject();
            if (!root.has("ghosts")) {
                settings = defaults();
                return;
            }
            JsonObject ghosts = root.getAsJsonObject("ghosts");
            boolean enabled = !ghosts.has("enabled") || ghosts.get("enabled").getAsBoolean();
            int revealTicks = ghosts.has("revealTicks") ? ghosts.get("revealTicks").getAsInt() : 60;
            int cooldown = ghosts.has("revealCooldownSeconds")
                    ? ghosts.get("revealCooldownSeconds").getAsInt() : 5;
            List<ResourceKey<Level>> dims = defaults().dimensions();
            if (ghosts.has("dimensions")) {
                JsonArray arr = ghosts.getAsJsonArray("dimensions");
                dims = new java.util.ArrayList<>();
                for (var el : arr) {
                    ResourceLocation id = ResourceLocation.parse(el.getAsString());
                    dims.add(ResourceKey.create(net.minecraft.core.registries.Registries.DIMENSION, id));
                }
                dims = List.copyOf(dims);
            }
            settings = new Settings(enabled, revealTicks, cooldown, dims);
        } catch (Exception e) {
            EclipseMod.LOGGER.warn("GhostConfig: failed to read protection.json ghosts section; using defaults", e);
            settings = defaults();
        }
    }

    public static Settings defaults() {
        return new Settings(true, 60, 5, List.of(
                Level.OVERWORLD,
                Level.NETHER));
    }
}
