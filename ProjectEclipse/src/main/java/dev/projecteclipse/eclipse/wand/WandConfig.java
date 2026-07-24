package dev.projecteclipse.eclipse.wand;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.Map;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import net.neoforged.fml.loading.FMLPaths;

/**
 * Loader for {@code config/eclipse/wand.json} — every wand knob is data-driven and
 * hot-reloadable via {@code /dev reload} ({@code WandItems.register} adds the hook).
 * Follows the {@code SkillConfig} playbook: defaults written on first run, parse failures
 * keep the previous snapshot, unknown keys ignored.
 *
 * <p>Layout: {@code charge} (regen economy), {@code xp} (wand leveling + skill-XP feed),
 * and one {@code powers.<path>.<power>} entry per {@link WandPath#powerKey} with
 * {@code cost}, {@code cooldownTicks} and free-form float params read via
 * {@link Power#param}. Missing entries fall back to the authored defaults, so a stale
 * config file can never brick a cast.</p>
 */
public final class WandConfig {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final String FILE_NAME = "wand.json";

    private static volatile Data data;

    private WandConfig() {}

    /** One power's tuning: charge cost, cooldown, and named float params. */
    public record Power(int cost, int cooldownTicks, Map<String, Float> params) {
        public float param(String key, float fallback) {
            Float value = params.get(key);
            return value != null ? value : fallback;
        }
    }

    public record Charge(int max, float regenHeldPerSecond, float regenStowedPerSecond, float nightMult) {}

    /**
     * @param perCostPoint wand XP granted per charge point spent on a successful cast
     * @param killBonus    flat wand XP for kills scored while holding your wand
     * @param levelCosts   XP to go from level (i+1) → (i+2); length {@code MAX_LEVEL - 1}
     * @param skillXpPerCostPoint base fed to {@code SkillsApi.addXp(player, "wand", …)}
     */
    public record Xp(float perCostPoint, float killBonus, int[] levelCosts, float skillXpPerCostPoint) {
        public int costForLevel(int currentLevel) {
            int index = Math.max(0, Math.min(levelCosts.length - 1, currentLevel - 1));
            return currentLevel >= WandPath.MAX_LEVEL ? Integer.MAX_VALUE : levelCosts[index];
        }
    }

    public record Data(Charge charge, Xp xp, Map<String, Power> powers) {
        /** Never null: unknown keys return the built-in default entry (or a safe stub). */
        public Power power(String key) {
            Power power = powers.get(key);
            if (power != null) {
                return power;
            }
            Power builtin = DEFAULTS.powers.get(key);
            return builtin != null ? builtin : new Power(20, 100, Map.of());
        }
    }

    private static final Data DEFAULTS = parse(defaultsJson());

    public static Data get() {
        Data snapshot = data;
        if (snapshot == null) {
            reload();
            snapshot = data;
        }
        return snapshot;
    }

    /** Re-reads {@code config/eclipse/wand.json}, creating it with defaults when missing. */
    public static synchronized void reload() {
        Path dir = FMLPaths.CONFIGDIR.get().resolve("eclipse");
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
            EclipseMod.LOGGER.info("Wand config loaded: {} powers, charge max {}, level costs {}",
                    data.powers().size(), data.charge().max(), data.xp().levelCosts().length);
        } catch (Exception e) {
            EclipseMod.LOGGER.error("Failed to parse {}; keeping previous values (or defaults)", file, e);
            if (data == null) {
                data = DEFAULTS;
            }
        }
    }

    /** Pure parser (defaults + runtime file share it). Unknown keys are ignored. */
    static Data parse(JsonObject root) {
        JsonObject charge = obj(root, "charge");
        Charge chargeData = new Charge(
                (int) asFloat(charge, "max", 100),
                asFloat(charge, "regenHeldPerSecond", 2.0F),
                asFloat(charge, "regenStowedPerSecond", 0.5F),
                asFloat(charge, "nightMult", 2.0F));

        JsonObject xp = obj(root, "xp");
        int[] levelCosts = new int[WandPath.MAX_LEVEL - 1];
        int[] defaults = {120, 260, 450, 700};
        if (xp.has("levelCosts") && xp.get("levelCosts").isJsonArray()) {
            var array = xp.getAsJsonArray("levelCosts");
            for (int i = 0; i < levelCosts.length; i++) {
                levelCosts[i] = i < array.size() ? array.get(i).getAsInt() : defaults[i];
            }
        } else {
            levelCosts = defaults;
        }
        Xp xpData = new Xp(
                asFloat(xp, "perCostPoint", 0.6F),
                asFloat(xp, "killBonus", 8.0F),
                levelCosts,
                asFloat(xp, "skillXpPerCostPoint", 0.4F));

        Map<String, Power> powers = new LinkedHashMap<>();
        JsonObject powersJson = obj(root, "powers");
        for (Map.Entry<String, JsonElement> entry : powersJson.entrySet()) {
            if (entry.getKey().startsWith("_") || !entry.getValue().isJsonObject()) {
                continue;
            }
            JsonObject power = entry.getValue().getAsJsonObject();
            Map<String, Float> params = new LinkedHashMap<>();
            for (Map.Entry<String, JsonElement> param : power.entrySet()) {
                if (!param.getKey().startsWith("_") && param.getValue().isJsonPrimitive()) {
                    params.put(param.getKey(), param.getValue().getAsFloat());
                }
            }
            powers.put(entry.getKey(), new Power(
                    (int) asFloat(power, "cost", 20),
                    (int) asFloat(power, "cooldownTicks", 100),
                    Map.copyOf(params)));
        }
        return new Data(chargeData, xpData, Map.copyOf(powers));
    }

    private static JsonObject obj(JsonObject parent, String key) {
        return parent.has(key) && parent.get(key).isJsonObject() ? parent.getAsJsonObject(key) : new JsonObject();
    }

    private static float asFloat(JsonObject obj, String key, float fallback) {
        return obj.has(key) && obj.get(key).isJsonPrimitive() ? obj.get(key).getAsFloat() : fallback;
    }

    // ------------------------------------------------------------------ defaults

    /** Canonical default config JSON. Every knob re-tunable live: edit + {@code /dev reload}. */
    static JsonObject defaultsJson() {
        JsonObject root = new JsonObject();

        JsonObject doc = new JsonObject();
        doc.addProperty("charge", "Veilladung pool on the wand item. regen*PerSecond applies every second "
                + "(held = main/offhand, stowed = anywhere else in the inventory); nightMult multiplies regen "
                + "during overworld night (the eclipse-dark hours).");
        doc.addProperty("xp", "Wand XP = cost * perCostPoint per successful cast + killBonus per kill while "
                + "holding your wand. levelCosts[i] = XP from level i+1 to i+2. skillXpPerCostPoint feeds "
                + "SkillsApi.addXp(player, \"wand\", cost * value) so the shared skill pipeline profits too.");
        doc.addProperty("powers", "cost = charge points, cooldownTicks = per-player per-power. Other keys are "
                + "power-specific floats (blocks, ticks, hearts of damage = damage/2). *_2 entries are the "
                + "level-4/5 upgraded re-runs of the level-2/3 powers.");
        root.add("_doc", doc);

        JsonObject charge = new JsonObject();
        charge.addProperty("max", 100);
        charge.addProperty("regenHeldPerSecond", 2.0F);
        charge.addProperty("regenStowedPerSecond", 0.5F);
        charge.addProperty("nightMult", 2.0F);
        root.add("charge", charge);

        JsonObject xp = new JsonObject();
        xp.addProperty("perCostPoint", 0.6F);
        xp.addProperty("killBonus", 8);
        var levelCosts = new com.google.gson.JsonArray();
        levelCosts.add(120);
        levelCosts.add(260);
        levelCosts.add(450);
        levelCosts.add(700);
        xp.add("levelCosts", levelCosts);
        xp.addProperty("skillXpPerCostPoint", 0.4F);
        root.add("xp", xp);

        JsonObject powers = new JsonObject();
        powers.add("riss.blink", power(15, 60,
                "range", 12));
        powers.add("riss.phasenwelle", power(40, 300,
                "length", 10, "maxBlocks", 24, "holdTicks", 200, "restoreEveryTicks", 10, "vanishPerTick", 6));
        powers.add("riss.rissschlag", power(30, 160,
                "range", 24, "width", 5, "damage", 8, "radius", 4, "knockback", 1.1F, "openTicks", 25));
        powers.add("riss.phasenwelle_2", power(50, 260,
                "length", 14, "maxBlocks", 40, "holdTicks", 240, "restoreEveryTicks", 8, "vanishPerTick", 8));
        powers.add("riss.rissschlag_2", power(45, 200,
                "range", 32, "width", 8, "damage", 14, "radius", 6, "knockback", 1.5F, "openTicks", 30));

        powers.add("glut.glutstoss", power(12, 40,
                "range", 12, "damage", 5, "fireSeconds", 3));
        powers.add("glut.feuerwelle", power(45, 400,
                "radius", 12, "expandTicks", 40, "damage", 7, "fireSeconds", 3, "knockup", 0.42F));
        powers.add("glut.magmasprung", power(25, 200,
                "launch", 1.15F, "damage", 6, "radius", 4, "knockback", 1.0F, "fireSeconds", 2));
        powers.add("glut.feuerwelle_2", power(55, 340,
                "radius", 18, "expandTicks", 50, "damage", 10, "fireSeconds", 4, "knockup", 0.55F));
        powers.add("glut.magmasprung_2", power(35, 160,
                "launch", 1.45F, "damage", 10, "radius", 6, "knockback", 1.4F, "fireSeconds", 3));

        powers.add("stern.funkenruf", power(12, 50,
                "range", 32, "damage", 5, "radius", 2));
        powers.add("stern.sternschauer", power(45, 400,
                "range", 32, "zoneRadius", 8, "count", 12, "telegraphTicks", 30, "durationTicks", 60,
                "damage", 5, "hitRadius", 2.5F));
        powers.add("stern.kometenschlag", power(30, 240,
                "range", 32, "damage", 12, "radius", 5, "telegraphTicks", 20, "knockback", 1.4F));
        powers.add("stern.sternschauer_2", power(55, 340,
                "range", 40, "zoneRadius", 10, "count", 20, "telegraphTicks", 24, "durationTicks", 70,
                "damage", 6, "hitRadius", 3.0F));
        powers.add("stern.kometenschlag_2", power(45, 200,
                "range", 40, "damage", 18, "radius", 7, "telegraphTicks", 16, "knockback", 1.8F));
        root.add("powers", powers);

        return root;
    }

    /** {@code power(cost, cd, "key", value, ...)} builder for the defaults table. */
    private static JsonObject power(int cost, int cooldownTicks, Object... keyValues) {
        JsonObject json = new JsonObject();
        json.addProperty("cost", cost);
        json.addProperty("cooldownTicks", cooldownTicks);
        for (int i = 0; i + 1 < keyValues.length; i += 2) {
            json.addProperty((String) keyValues[i], ((Number) keyValues[i + 1]).floatValue());
        }
        return json;
    }
}
