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
 * <p>F-039/F-040 layout: {@code charge} (regen economy), {@code xp} (Wand-XP-Punkte
 * earn rates — the currency of the {@link WandTree}; the old level-cost curve is gone,
 * levels derive from owned nodes) and one {@code powers.<spellKey>} entry per
 * {@link WandSpells} spell with {@code cost} and free-form float params read via
 * {@link Power#param}. <b>No cooldowns anywhere</b> (F-040) — Veilladung is the only
 * limiter. Missing entries fall back to the {@link WandSpells} authored defaults, so a
 * stale config file can never brick a cast.</p>
 */
public final class WandConfig {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final String FILE_NAME = "wand.json";

    private static volatile Data data;

    private WandConfig() {}

    /** One spell's tuning: charge cost and named float params (F-040: no cooldown). */
    public record Power(int cost, Map<String, Float> params) {
        public float param(String key, float fallback) {
            Float value = params.get(key);
            return value != null ? value : fallback;
        }
    }

    public record Charge(int max, float regenHeldPerSecond, float regenStowedPerSecond, float nightMult) {}

    /**
     * @param perCostPoint Wand-XP-Punkte granted per charge point spent on a successful cast
     * @param killBonus    flat Wand-XP-Punkte for kills scored while holding your wand
     * @param skillXpPerCostPoint base fed to {@code SkillsApi.addXp(player, "wand", …)}
     */
    public record Xp(float perCostPoint, float killBonus, float skillXpPerCostPoint) {}

    public record Data(Charge charge, Xp xp, Map<String, Power> powers) {
        /** Never null: unknown keys fall back to the {@link WandSpells} authored defaults. */
        public Power power(String key) {
            Power power = powers.get(key);
            if (power != null) {
                return power;
            }
            WandSpell spell = WandSpells.byKey(key);
            return spell != null ? new Power(spell.defaultCost(), spell.defaultParams())
                    : new Power(20, Map.of());
        }

        /** Live tuning of one spell (config override or authored defaults). */
        public Power power(WandSpell spell) {
            return power(spell.key());
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
            EclipseMod.LOGGER.info("Wand config loaded: {} spell entries, charge max {}",
                    data.powers().size(), data.charge().max());
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
                // F-040 rebalance: with cooldowns gone the charge pool is the ONLY
                // limiter, so held regen rises 2.0 → 3.0/s (a 30-cost spell every ~10 s
                // sustained at base; the tree's regen nodes and rebirths push it up).
                asFloat(charge, "regenHeldPerSecond", 3.0F),
                asFloat(charge, "regenStowedPerSecond", 0.5F),
                asFloat(charge, "nightMult", 2.0F));

        JsonObject xp = obj(root, "xp");
        Xp xpData = new Xp(
                asFloat(xp, "perCostPoint", 0.6F),
                asFloat(xp, "killBonus", 8.0F),
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
            // Legacy configs may still carry cooldownTicks — parsed as a param, used by
            // nothing (F-040). Cost falls back to the authored spell default when absent.
            WandSpell spell = WandSpells.byKey(entry.getKey());
            int defaultCost = spell != null ? spell.defaultCost() : 20;
            powers.put(entry.getKey(), new Power(
                    (int) asFloat(power, "cost", defaultCost),
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
        doc.addProperty("xp", "Wand-XP-Punkte = cost * perCostPoint per successful cast + killBonus per kill "
                + "while holding your wand. Points are the wand skill tree's currency (nodes + rebirths); "
                + "there is no level curve anymore — levels derive from owned nodes. skillXpPerCostPoint "
                + "feeds SkillsApi.addXp(player, \"wand\", cost * value).");
        doc.addProperty("powers", "One entry per spell key (see WandSpells): cost = charge points, other keys "
                + "are spell-specific floats (blocks, ticks, hearts of damage = damage/2). NO cooldowns "
                + "(F-040) — Veilladung is the only cast limiter.");
        root.add("_doc", doc);

        JsonObject charge = new JsonObject();
        charge.addProperty("max", 100);
        charge.addProperty("regenHeldPerSecond", 3.0F);
        charge.addProperty("regenStowedPerSecond", 0.5F);
        charge.addProperty("nightMult", 2.0F);
        root.add("charge", charge);

        JsonObject xp = new JsonObject();
        xp.addProperty("perCostPoint", 0.6F);
        xp.addProperty("killBonus", 8);
        xp.addProperty("skillXpPerCostPoint", 0.4F);
        root.add("xp", xp);

        // The authored spell table (30 entries) — written out so server owners can see
        // and tune every knob; values mirror the WandSpells Java defaults.
        JsonObject powers = new JsonObject();
        for (WandSpell spell : WandSpells.all()) {
            JsonObject entry = new JsonObject();
            entry.addProperty("cost", spell.defaultCost());
            for (Map.Entry<String, Float> param : spell.defaultParams().entrySet()) {
                entry.addProperty(param.getKey(), param.getValue());
            }
            powers.add(spell.key(), entry);
        }
        root.add("powers", powers);

        return root;
    }
}
