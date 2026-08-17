package de.sonic0810.goobymod.entity;

import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.mojang.logging.LogUtils;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import javax.annotation.Nullable;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.packs.resources.ResourceManager;
import net.minecraft.server.packs.resources.SimpleJsonResourceReloadListener;
import net.minecraft.util.profiling.ProfilerFiller;
import org.slf4j.Logger;

/**
 * Datapack-Registry fuer namensgebundene Special-Lines (seit 5.3).
 *
 * <p>Generalisiert die frueher hart codierte sophiex456-Sonderbehandlung:
 * Datapacks koennen unter {@code data/<ns>/special_lines/*.json} eigene
 * Spielername→Line-Pool-Eintraege liefern:
 *
 * <pre>{@code
 * { "player": "gooby_example", "lines": ["bubble.goobymod.example_fan1", ...] }
 * }</pre>
 *
 * <p>Der eingebaute Default fuer {@link GoobySpeech#SOPHIE_NAME} bleibt
 * unangetastet bestehen (Datapack-Eintraege fuer denselben Namen ERGAENZEN
 * ihn nur), und der Server-Config-Killswitch {@code enableSpecialLines}
 * schaltet weiterhin ALLE Special-Lines ab — eingebaute wie Datapack-Lines.
 *
 * <p>Fail-safe statt fail-closed: fehlerhafte Datapack-Dateien werden mit
 * WARN uebersprungen und crashen nie den Server. Bounded: pro Spieler sind
 * hoechstens {@link #MAX_LINES_PER_PLAYER} Lines aktiv, Namen muessen gueltige
 * Minecraft-Accountnamen sein. Mehrere Dateien fuer denselben Namen werden
 * dedupliziert zusammengefuehrt (/reload ersetzt den kompletten Stand).
 */
public final class SpecialLineRegistry extends SimpleJsonResourceReloadListener {
    public static final String DIRECTORY = "special_lines";
    public static final int MAX_LINES_PER_PLAYER = 64;
    private static final Gson GSON = new Gson();
    private static final Logger LOGGER = LogUtils.getLogger();

    /** Kleingeschriebener Spielername → unveraenderlicher Line-Pool. */
    private static volatile Map<String, List<String>> pools = Map.of();
    /** Line-Key → kleingeschriebener Besitzername (fuer lokales Client-Gating). */
    private static volatile Map<String, String> owners = Map.of();

    public SpecialLineRegistry() {
        super(GSON, DIRECTORY);
    }

    @Override
    protected void apply(Map<ResourceLocation, JsonElement> files, ResourceManager manager,
            ProfilerFiller profiler) {
        Map<String, Set<String>> merged = new HashMap<>();
        for (Map.Entry<ResourceLocation, JsonElement> entry : files.entrySet()) {
            parseEntry(entry.getKey(), entry.getValue(), merged);
        }
        Map<String, List<String>> newPools = new HashMap<>();
        Map<String, String> newOwners = new HashMap<>();
        merged.forEach((name, lines) -> {
            List<String> pool = List.copyOf(lines);
            newPools.put(name, pool);
            pool.forEach(key -> newOwners.put(key, name));
        });
        pools = Map.copyOf(newPools);
        owners = Map.copyOf(newOwners);
        if (!newPools.isEmpty()) {
            LOGGER.info("GoobyMod: {} Special-Line-Pool(s) aus Datapacks geladen", newPools.size());
        }
    }

    private static void parseEntry(ResourceLocation id, JsonElement json, Map<String, Set<String>> merged) {
        if (!(json instanceof JsonObject object)
                || !object.has("player") || !object.get("player").isJsonPrimitive()
                || !object.has("lines") || !object.get("lines").isJsonArray()) {
            LOGGER.warn("Special-Lines {}: erwartet {{\"player\": \"...\", \"lines\": [...]}} — uebersprungen", id);
            return;
        }
        String player = object.get("player").getAsString();
        if (!player.matches("[A-Za-z0-9_]{1,16}")) {
            LOGGER.warn("Special-Lines {}: '{}' ist kein gueltiger Spielername — uebersprungen", id, player);
            return;
        }
        Set<String> pool = merged.computeIfAbsent(player.toLowerCase(Locale.ROOT),
                unused -> new LinkedHashSet<>());
        JsonArray lines = object.getAsJsonArray("lines");
        List<String> parsed = new ArrayList<>(lines.size());
        for (JsonElement line : lines) {
            if (!line.isJsonPrimitive() || line.getAsString().isBlank()) {
                LOGGER.warn("Special-Lines {}: 'lines' darf nur nicht-leere Strings enthalten — uebersprungen", id);
                return;
            }
            parsed.add(line.getAsString());
        }
        for (String key : parsed) {
            if (pool.size() >= MAX_LINES_PER_PLAYER) {
                LOGGER.warn("Special-Lines {}: Pool-Limit von {} Lines fuer '{}' erreicht — Rest ignoriert",
                        id, MAX_LINES_PER_PLAYER, player);
                break;
            }
            pool.add(key);
        }
    }

    /** Datapack-Pool fuer den Spielernamen (case-insensitive) oder leere Liste. */
    public static List<String> linesFor(@Nullable String playerName) {
        return playerName == null ? List.of()
                : pools.getOrDefault(playerName.toLowerCase(Locale.ROOT), List.of());
    }

    /** Kleingeschriebener Besitzername einer Datapack-Line oder {@code null}. */
    @Nullable
    public static String ownerOf(@Nullable String key) {
        return key == null ? null : owners.get(key);
    }

    public static int poolCountForTest() {
        return pools.size();
    }
}
