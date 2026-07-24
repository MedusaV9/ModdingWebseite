package dev.projecteclipse.eclipse.worldgen.stage;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.ReloadHooks;
import dev.projecteclipse.eclipse.worldgen.vanilla.BiomeFeatureFilter;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;

/**
 * Loader/owner of {@code config/eclipse/worldgen_tuning.json} (design D11; Appendix B) —
 * the LIVE-RELOADABLE runtime knobs of the worldgen overhaul (unlike {@code ores.json} /
 * {@code stages.json} these are never frozen per save):
 *
 * <pre>{@code
 * { "growth": { "targetTicks": 1500,      // animated sweeps pace toward this duration
 *               "revealDelayTicks": 10,   // chunk resend lag behind its covering wavefront payload
 *               "ringsPerPulse": 5,       // max 1-block rings the wavefront advances per 5-tick FX pulse
 *               "shakeEveryRings": 25,    // S2CShakePayload pulse cadence in rings (<=0 disables)
 *               "columnRiseTicks": 30 },  // client column-rise animation hint (S2CGrowthWavePayload)
 *   "features": { "deny": [] },           // placed-feature ids removed from every biome (W1.1 filter)
 *   "glitch": { "freshTicks": 72000 } }   // NewRingRegistry freshness decay (3 in-game days)
 * }</pre>
 *
 * <p><b>features.deny push</b> (P1-W1.1 wiring contract): every {@link #reload} pushes the
 * parsed deny ids into {@link BiomeFeatureFilter#setConfigDeny} — the hardcoded vanilla
 * mineral-ore deny-list stays active on top. The filter freezes on the first
 * {@code settingsFor} call (vanilla memoises its feature-step order), so the push must land
 * before the first chunk decorates: this class reloads itself on
 * {@link ServerAboutToStartEvent} (highest priority — before dimensions exist, so before
 * any FEATURES chunk) and additionally registers a {@link ReloadHooks} entry so every
 * {@code EclipseConfig.reload()} / {@code /eclipse reload} re-reads the file. A post-freeze
 * deny CHANGE is ignored by the filter with a warning (restart applies it); the pacing and
 * glitch knobs always apply immediately.</p>
 *
 * <p>Reads are volatile-snapshot based and safe from any thread; {@code P2-W7} consumes the
 * pacing accessors, P4/P6 consume {@link #glitchFreshTicks()} via {@code NewRingRegistry}.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class GrowthPacing {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final String FILE_NAME = "worldgen_tuning.json";

    /** Default freshness window: 3 in-game days. */
    private static final int DEFAULT_FRESH_TICKS = 3 * 24000;

    /** Immutable knob snapshot; {@link #DEFAULTS} until the first successful load. */
    record Snapshot(int targetTicks, int revealDelayTicks, int ringsPerPulse, int shakeEveryRings,
            int columnRiseTicks, int glitchFreshTicks, List<ResourceLocation> denyIds) {}

    private static final Snapshot DEFAULTS =
            new Snapshot(1500, 10, 5, 25, 30, DEFAULT_FRESH_TICKS, List.of());

    private static volatile Snapshot current = DEFAULTS;

    static {
        // /eclipse reload path: EclipseConfig.reload() runs every registered hook at its
        // tail (same pattern FrozenParams uses for ores). Registered once per JVM at
        // class load (this class is loaded eagerly via @EventBusSubscriber scanning).
        ReloadHooks.register("worldgen_tuning",
                () -> reload(FMLPaths.CONFIGDIR.get().resolve("eclipse")));
    }

    private GrowthPacing() {}

    // --- accessors (P2-W7 pacing seam; frozen names, see P1 plan D11) ---

    /** Ticks an animated sweep paces toward (secondary cap next to the per-tick ms budget). */
    public static int targetTicks() {
        return current.targetTicks();
    }

    /** Ticks a rewritten chunk's relight/resend lags behind its covering wavefront payload. */
    public static int revealDelayTicks() {
        return current.revealDelayTicks();
    }

    /** Max 1-block rings the wavefront may advance per {@code S2CGrowthWavePayload} pulse (5 ticks). */
    public static int ringsPerPulse() {
        return current.ringsPerPulse();
    }

    /** Ring-advance interval between camera-shake pulses during animated growth; {@code <= 0} = off. */
    public static int shakeEveryRings() {
        return current.shakeEveryRings();
    }

    /** Client column-rise animation duration hint carried by every wave payload. */
    public static int columnRiseTicks() {
        return current.columnRiseTicks();
    }

    /** Freshness decay window of {@code NewRingRegistry} rows ({@code glitch.freshTicks}). */
    public static int glitchFreshTicks() {
        return current.glitchFreshTicks();
    }

    /** The last-loaded {@code features.deny[]} ids (already pushed into the biome filter). */
    public static List<ResourceLocation> denyIds() {
        return current.denyIds();
    }

    /**
     * Re-reads {@code worldgen_tuning.json} from {@code configDir} (writing the defaults
     * file when absent), swaps the volatile snapshot and pushes {@code features.deny[]}
     * into {@link BiomeFeatureFilter#setConfigDeny} (compile seam §3.10). Safe to call
     * repeatedly; never throws.
     */
    public static synchronized void reload(Path configDir) {
        Path file = configDir.resolve(FILE_NAME);
        Snapshot loaded = DEFAULTS;
        if (Files.isRegularFile(file)) {
            try {
                JsonObject root = JsonParser.parseString(
                        Files.readString(file, StandardCharsets.UTF_8)).getAsJsonObject();
                loaded = fromJson(root);
                EclipseMod.LOGGER.info(
                        "Growth pacing loaded: targetTicks {}, revealDelay {}, ringsPerPulse {}, "
                                + "shakeEveryRings {}, columnRise {}, freshTicks {}, {} denied feature(s)",
                        loaded.targetTicks(), loaded.revealDelayTicks(), loaded.ringsPerPulse(),
                        loaded.shakeEveryRings(), loaded.columnRiseTicks(), loaded.glitchFreshTicks(),
                        loaded.denyIds().size());
            } catch (IOException | RuntimeException e) {
                EclipseMod.LOGGER.error("Failed to read {}; keeping previous growth pacing", file, e);
                loaded = current;
            }
        } else {
            writeDefaults(configDir, file);
        }
        current = loaded;
        BiomeFeatureFilter.setConfigDeny(loaded.denyIds());
    }

    /**
     * Guarantees the deny-list is pushed before any chunk can decorate, even on boots
     * where no explicit {@code EclipseConfig.reload()} ran yet: dimensions do not exist
     * at {@code ServerAboutToStartEvent} time, so no FEATURES chunk can have frozen the
     * filter. Priority HIGH orders this before {@code FrozenParams}' listener on the same
     * event (not required for correctness — the deny-list is global config, not frozen —
     * but keeps the log sequence deterministic).
     */
    @SubscribeEvent(priority = EventPriority.HIGH)
    public static void onServerAboutToStart(ServerAboutToStartEvent event) {
        reload(FMLPaths.CONFIGDIR.get().resolve("eclipse"));
    }

    private static Snapshot fromJson(JsonObject root) {
        JsonObject growth = root.has("growth") ? root.getAsJsonObject("growth") : new JsonObject();
        JsonObject glitch = root.has("glitch") ? root.getAsJsonObject("glitch") : new JsonObject();
        JsonObject features = root.has("features") ? root.getAsJsonObject("features") : new JsonObject();

        List<ResourceLocation> deny = new ArrayList<>();
        if (features.has("deny") && features.get("deny").isJsonArray()) {
            for (JsonElement entry : features.getAsJsonArray("deny")) {
                ResourceLocation id = ResourceLocation.tryParse(entry.getAsString());
                if (id != null) {
                    deny.add(id);
                } else {
                    EclipseMod.LOGGER.warn("Ignoring malformed features.deny id '{}' in {}",
                            entry.getAsString(), FILE_NAME);
                }
            }
        }
        return new Snapshot(
                clamp(growth, "targetTicks", DEFAULTS.targetTicks(), 100, 20 * 60 * 30),
                clamp(growth, "revealDelayTicks", DEFAULTS.revealDelayTicks(), 0, 20 * 60),
                clamp(growth, "ringsPerPulse", DEFAULTS.ringsPerPulse(), 1, 512),
                clamp(growth, "shakeEveryRings", DEFAULTS.shakeEveryRings(), -1, 4096),
                clamp(growth, "columnRiseTicks", DEFAULTS.columnRiseTicks(), 1, 20 * 30),
                clamp(glitch, "freshTicks", DEFAULTS.glitchFreshTicks(), 20, 24000 * 100),
                List.copyOf(deny));
    }

    private static int clamp(JsonObject obj, String key, int fallback, int min, int max) {
        if (!obj.has(key)) {
            return fallback;
        }
        try {
            return Math.max(min, Math.min(max, obj.get(key).getAsInt()));
        } catch (RuntimeException e) {
            EclipseMod.LOGGER.warn("Ignoring malformed {} value '{}' in {}", key, obj.get(key), FILE_NAME);
            return fallback;
        }
    }

    private static void writeDefaults(Path configDir, Path file) {
        JsonObject root = new JsonObject();
        root.addProperty("_comment", "Live-reloadable worldgen tuning (never frozen per save). "
                + "growth.* paces animated ring sweeps; features.deny lists placed-feature ids removed "
                + "from every biome (applies on next boot once chunks have decorated); glitch.freshTicks "
                + "is the fresh-ring decay window for glitched-mob spawning.");
        JsonObject growth = new JsonObject();
        growth.addProperty("targetTicks", DEFAULTS.targetTicks());
        growth.addProperty("revealDelayTicks", DEFAULTS.revealDelayTicks());
        growth.addProperty("ringsPerPulse", DEFAULTS.ringsPerPulse());
        growth.addProperty("shakeEveryRings", DEFAULTS.shakeEveryRings());
        growth.addProperty("columnRiseTicks", DEFAULTS.columnRiseTicks());
        root.add("growth", growth);
        JsonObject features = new JsonObject();
        features.add("deny", new JsonArray());
        root.add("features", features);
        JsonObject glitch = new JsonObject();
        glitch.addProperty("freshTicks", DEFAULTS.glitchFreshTicks());
        root.add("glitch", glitch);
        try {
            Files.createDirectories(configDir);
            Files.writeString(file, GSON.toJson(root), StandardCharsets.UTF_8);
            EclipseMod.LOGGER.info("Created default {}", file);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to write default {}", file, e);
        }
    }
}
