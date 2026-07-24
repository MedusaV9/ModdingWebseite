package dev.projecteclipse.eclipse.rebirth;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import net.neoforged.fml.loading.FMLPaths;

/**
 * Loader for {@code config/eclipse/rebirth.json} (D11). Defaults are written on first run
 * ({@code EclipseConfig.loadOrCreate} pattern); hot-reload rides {@code ReloadHooks}
 * (registered by {@link RebirthService}).
 *
 * <p>Knobs: {@code baseCostShards}/{@code costGrowth} price the n-th rebirth at
 * {@code round(base * growth^n)} personal umbral shards (plan formula 8&middot;1.6^n);
 * {@code levelCostMultiplierPerRebirth} scales every skill-level cost by
 * {@code mult^rebirthCount} (through {@code skills.RebirthHooks.curveFor});
 * {@code maxRebirths} caps the ladder (0 = uncapped); {@code lifeRewardPerRebirth} is the
 * permanent Leben granted per ceremony. {@code keepCollections}/{@code keepWand} document
 * the explicit non-goals of the reset &mdash; the transaction never touches either system.</p>
 */
public final class RebirthConfig {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final String FILE_NAME = "rebirth.json";

    // static snapshot reset on ServerStopped (RebirthService.onServerStopped calls invalidate())
    private static volatile Data data;

    private RebirthConfig() {}

    /** Immutable parsed config snapshot. */
    public record Data(
            int baseCostShards,
            double costGrowth,
            double levelCostMultiplierPerRebirth,
            int maxRebirths,
            int lifeRewardPerRebirth,
            boolean keepCollections,
            boolean keepWand) {

        /** Personal-shard price of the n-th rebirth (0-based): {@code round(base * growth^n)}. */
        public int costForCount(int rebirthCount) {
            return (int) Math.round(baseCostShards * Math.pow(costGrowth, Math.max(0, rebirthCount)));
        }

        /** Global level-cost multiplier after {@code rebirthCount} rebirths: {@code mult^count}. */
        public double levelCostMultiplier(int rebirthCount) {
            return Math.pow(levelCostMultiplierPerRebirth, Math.max(0, rebirthCount));
        }
    }

    /** Live config (loads defaults on first access). */
    public static Data get() {
        Data snapshot = data;
        if (snapshot == null) {
            reload();
            snapshot = data;
        }
        return snapshot;
    }

    /** Re-reads {@code config/eclipse/rebirth.json}, creating it with defaults when missing. */
    public static synchronized void reload() {
        reloadFromDir(FMLPaths.CONFIGDIR.get().resolve("eclipse"));
    }

    /** Injectable-directory variant for gametests. */
    public static synchronized void reloadFromDir(Path dir) {
        try {
            Files.createDirectories(dir);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to create config directory {}", dir, e);
        }
        Path file = dir.resolve(FILE_NAME);
        if (!Files.exists(file)) {
            try {
                Files.writeString(file, GSON.toJson(defaultsJson()), StandardCharsets.UTF_8);
                EclipseMod.LOGGER.info("Created default Eclipse config {}", file);
            } catch (IOException e) {
                EclipseMod.LOGGER.error("Failed to write default config {}", file, e);
            }
        }
        try {
            JsonObject root = JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)).getAsJsonObject();
            data = parse(root);
            EclipseMod.LOGGER.info("Rebirth config loaded: cost {}*{}^n shards, level-cost x{} per rebirth, "
                    + "max {}, +{} Leben each", data.baseCostShards(), data.costGrowth(),
                    data.levelCostMultiplierPerRebirth(), data.maxRebirths(), data.lifeRewardPerRebirth());
        } catch (Exception e) {
            EclipseMod.LOGGER.error("Failed to parse {}; keeping previous values (or defaults)", file, e);
            if (data == null) {
                data = parse(defaultsJson());
            }
        }
    }

    /** Drops the cached snapshot (server stop) so a SP relaunch re-reads cleanly. */
    static void invalidate() {
        data = null;
    }

    /** Pure parser — gametests feed synthetic JSON here. Unknown keys are ignored. */
    public static Data parse(JsonObject root) {
        return new Data(
                (int) asDouble(root, "baseCostShards", 8.0D),
                asDouble(root, "costGrowth", 1.6D),
                asDouble(root, "levelCostMultiplierPerRebirth", 1.15D),
                (int) asDouble(root, "maxRebirths", 0.0D),
                (int) asDouble(root, "lifeRewardPerRebirth", 1.0D),
                asBool(root, "keepCollections", true),
                asBool(root, "keepWand", true));
    }

    private static double asDouble(JsonObject obj, String key, double fallback) {
        return obj.has(key) && obj.get(key).isJsonPrimitive() ? obj.get(key).getAsDouble() : fallback;
    }

    private static boolean asBool(JsonObject obj, String key, boolean fallback) {
        return obj.has(key) && obj.get(key).isJsonPrimitive() ? obj.get(key).getAsBoolean() : fallback;
    }

    /** Canonical default config JSON (public for gametest pinning). */
    public static JsonObject defaultsJson() {
        JsonObject root = new JsonObject();

        JsonObject doc = new JsonObject();
        doc.addProperty("cost", "The n-th rebirth (n starts at 0) costs round(baseCostShards * costGrowth^n) "
                + "PERSONAL umbral shards (ShardEconomy balance, not the team pool): 8, 13, 20, 33, 52, ...");
        doc.addProperty("effect", "+lifeRewardPerRebirth permanent Leben (capped by HeartsService.MAX_HEARTS - "
                + "a rebirth AT the cap is refused, never burned), FULL skill+level reset (XP, levels, tree "
                + "nodes, points), and every skill level afterwards costs "
                + "levelCostMultiplierPerRebirth^rebirthCount times the base curve.");
        doc.addProperty("maxRebirths", "0 = uncapped ladder; >0 refuses the (n+1)-th rebirth.");
        doc.addProperty("nonGoals", "keepCollections/keepWand document what the reset deliberately NEVER "
                + "touches: collection-book progress and wand path/upgrades survive every rebirth. "
                + "The flags are honored by refusing to reset those systems - not toggles to wipe them.");
        root.add("_doc", doc);

        root.addProperty("baseCostShards", 8);
        root.addProperty("costGrowth", 1.6D);
        root.addProperty("levelCostMultiplierPerRebirth", 1.15D);
        root.addProperty("maxRebirths", 0);
        root.addProperty("lifeRewardPerRebirth", 1);
        root.addProperty("keepCollections", true);
        root.addProperty("keepWand", true);
        return root;
    }
}
