package dev.projecteclipse.eclipse.music;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ServerData;
import net.minecraft.server.MinecraftServer;
import net.neoforged.fml.loading.FMLPaths;

/**
 * WAVE6 (F-106 B) B7 / IDEA-08 #10 — the client-side "heard" ledger behind
 * {@link MusicCues#repeatVolume()}: cues that carry a repeat trim below 1.0
 * ({@code eclipse_totality} 0.7, {@code wand_awakening} 0.0) are remembered in
 * {@code config/eclipse-music-memory.json} once a voice of theirs actually reached full
 * level (a REAL audible playback — an engine-refused start never marks anything, see
 * {@code MusicFadeSound}); every later voice of the same cue resolves its trim at
 * construction. Damping only — no new tracks, no {@code _alt} variants (D-3 blocked).
 *
 * <p><b>Per-server key</b>: entries are scoped {@code mp:<address>} / {@code sp:<world>}
 * so a dev world's memories never bleed into the event server. {@code /dev music forget}
 * (→ {@link MusicPayloads} {@code !}-prefix → {@link MusicClientHooks#forgetMemory()})
 * clears ONLY the current server's entries.</p>
 *
 * <p>Client-only class ({@code Minecraft} reference): reached exclusively from
 * {@code MusicFadeSound} (a client sound instance) and the lazily-resolved
 * {@link MusicClientHooks} trampoline, so dedicated-server verification never loads it —
 * the {@code MusicClientHooks} precedent.</p>
 */
final class MusicMemory {
    private static final Path FILE = FMLPaths.CONFIGDIR.get().resolve("eclipse-music-memory.json");
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().create();

    /** Lazy-loaded ledger: server key → cue ids heard to full level there. */
    private static Map<String, Set<String>> ledger;

    private MusicMemory() {}

    /**
     * Repeat trim for a NEW voice of {@code cue} — 1.0 while the cue is untracked
     * ({@code repeatVolume >= 1}) or not yet heard on this server, else the cue's
     * {@link MusicCues#repeatVolume()}. Resolved ONCE per voice (constructor), so a
     * running playback never dips mid-stream when the ledger updates underneath it.
     */
    static synchronized float resolveRepeatFactor(MusicCues cue) {
        if (cue.repeatVolume() >= 1.0F) {
            return 1.0F;
        }
        boolean heard = heardSet(serverKey()).contains(cue.id());
        EclipseMod.LOGGER.debug("[w6b-musicmem] cue={} heard={}", cue.id(), heard);
        return heard ? cue.repeatVolume() : 1.0F;
    }

    /**
     * Marks {@code cue} heard on the current server (called by {@code MusicFadeSound}
     * exactly when its envelope FIRST reaches full level). Untracked cues are ignored —
     * the ledger only ever contains ids whose repeat behavior differs.
     */
    static synchronized void markHeard(MusicCues cue) {
        if (cue.repeatVolume() >= 1.0F) {
            return;
        }
        if (heardSet(serverKey()).add(cue.id())) {
            save();
            EclipseMod.LOGGER.debug("[w6b-musicmem] cue={} heard=now-marked", cue.id());
        }
    }

    /** {@code /dev music forget}: clears the CURRENT server's memory entries. */
    static synchronized void forget() {
        String key = serverKey();
        Set<String> removed = ledger().remove(key);
        save();
        EclipseMod.LOGGER.debug("[w6b-musicmem] forget key={} removed={}",
                key, removed == null ? 0 : removed.size());
    }

    // ------------------------------------------------------------------ plumbing

    /** {@code mp:<address>} (multiplayer) / {@code sp:<level name>} (integrated). */
    private static String serverKey() {
        Minecraft minecraft = Minecraft.getInstance();
        ServerData server = minecraft.getCurrentServer();
        if (server != null) {
            return "mp:" + server.ip;
        }
        MinecraftServer integrated = minecraft.getSingleplayerServer();
        if (integrated != null) {
            return "sp:" + integrated.getWorldData().getLevelName();
        }
        return "unknown";
    }

    private static Set<String> heardSet(String key) {
        return ledger().computeIfAbsent(key, unused -> new LinkedHashSet<>());
    }

    private static Map<String, Set<String>> ledger() {
        if (ledger != null) {
            return ledger;
        }
        ledger = new HashMap<>();
        if (!Files.isRegularFile(FILE)) {
            return ledger;
        }
        try {
            JsonObject root = JsonParser.parseString(
                    Files.readString(FILE, StandardCharsets.UTF_8)).getAsJsonObject();
            for (Map.Entry<String, JsonElement> entry : root.entrySet()) {
                if (!entry.getValue().isJsonArray()) {
                    continue;
                }
                Set<String> heard = new LinkedHashSet<>();
                for (JsonElement id : entry.getValue().getAsJsonArray()) {
                    heard.add(id.getAsString());
                }
                ledger.put(entry.getKey(), heard);
            }
        } catch (IOException | RuntimeException e) {
            // A corrupt ledger must never wedge the music channel: start fresh, the
            // worst case is one repeat playing at full volume again.
            EclipseMod.LOGGER.warn("Music memory ledger {} unreadable — starting fresh", FILE, e);
            ledger.clear();
        }
        return ledger;
    }

    private static void save() {
        JsonObject root = new JsonObject();
        for (Map.Entry<String, Set<String>> entry : ledger().entrySet()) {
            if (entry.getValue().isEmpty()) {
                continue;
            }
            JsonArray heard = new JsonArray();
            entry.getValue().forEach(heard::add);
            root.add(entry.getKey(), heard);
        }
        try {
            Files.createDirectories(FILE.getParent());
            Files.writeString(FILE, GSON.toJson(root), StandardCharsets.UTF_8);
        } catch (IOException e) {
            EclipseMod.LOGGER.warn("Music memory ledger {} not writable", FILE, e);
        }
    }
}
