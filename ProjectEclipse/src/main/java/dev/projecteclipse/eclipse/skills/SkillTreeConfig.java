package dev.projecteclipse.eclipse.skills;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.Localized;
import net.neoforged.fml.loading.FMLPaths;

/**
 * Loader for {@code config/eclipse/skilltree.json} (R3, plan §2.3 node table): 21 nodes on a
 * 3-point spine plus three 6-node branches (hunt / delve / stride). Node effects are small,
 * incremental and never OP by design — every magnitude is a config value consumed by
 * {@link SkillPerks} / {@link SkillService}, so balance can be retuned live via
 * {@code /eclipse reload}. The canonical serialized tree (not secret) ships to clients as
 * {@code S2CSkillTreePayload} for P3's GUI.
 */
public final class SkillTreeConfig {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final String FILE_NAME = "skilltree.json";

    // statics reset on ServerStopped (SkillService.onServerStopped calls invalidate())
    private static volatile Tree tree;

    private SkillTreeConfig() {}

    /** One skill tree node. {@code duration}/{@code cooldown} are seconds (U3 only today). */
    public record Node(
            String id,
            String branch,
            int cost,
            List<String> requires,
            Localized title,
            Localized desc,
            String effectType,
            float value,
            float duration,
            float cooldown) {}

    /** Parsed tree snapshot: ordered nodes + branch labels + canonical client JSON. */
    public record Tree(Map<String, Node> nodes, Map<String, Localized> branches, String clientJson) {
        public Node node(String id) {
            return nodes.get(id);
        }
    }

    /** Live tree (loads defaults on first access). */
    public static Tree get() {
        Tree snapshot = tree;
        if (snapshot == null) {
            reload();
            snapshot = tree;
        }
        return snapshot;
    }

    /** Re-reads {@code config/eclipse/skilltree.json}, creating it with defaults when missing. */
    public static synchronized void reload() {
        reloadFromDir(FMLPaths.CONFIGDIR.get().resolve("eclipse"));
    }

    /** Injectable-directory variant for gametests (plan risk #8). */
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
            tree = parse(root);
            EclipseMod.LOGGER.info("Skill tree loaded: {} nodes, {} branches", tree.nodes().size(),
                    tree.branches().size());
        } catch (Exception e) {
            EclipseMod.LOGGER.error("Failed to parse {}; keeping previous values (or defaults)", file, e);
            if (tree == null) {
                tree = parse(defaultsJson());
            }
        }
    }

    /** Drops the cached snapshot (server stop) so a SP relaunch re-reads cleanly. */
    static void invalidate() {
        tree = null;
    }

    /** Pure parser — validates ids and prereq references (warn + keep, never crash). */
    public static Tree parse(JsonObject root) {
        Map<String, Node> nodes = new LinkedHashMap<>();
        if (root.has("nodes") && root.get("nodes").isJsonArray()) {
            for (JsonElement element : root.getAsJsonArray("nodes")) {
                if (!element.isJsonObject()) {
                    continue;
                }
                JsonObject obj = element.getAsJsonObject();
                String id = obj.has("id") ? obj.get("id").getAsString() : "";
                if (id.isEmpty()) {
                    continue;
                }
                if (nodes.containsKey(id)) {
                    EclipseMod.LOGGER.warn("skilltree.json: duplicate node id '{}' — keeping the first", id);
                    continue;
                }
                List<String> requires = new java.util.ArrayList<>();
                if (obj.has("requires") && obj.get("requires").isJsonArray()) {
                    for (JsonElement req : obj.getAsJsonArray("requires")) {
                        requires.add(req.getAsString());
                    }
                }
                JsonObject effect = obj.has("effect") && obj.get("effect").isJsonObject()
                        ? obj.getAsJsonObject("effect") : new JsonObject();
                nodes.put(id, new Node(
                        id,
                        obj.has("branch") ? obj.get("branch").getAsString() : "spine",
                        obj.has("cost") ? Math.max(1, obj.get("cost").getAsInt()) : 1,
                        List.copyOf(requires),
                        Localized.parse(obj.get("title")),
                        Localized.parse(obj.get("desc")),
                        effect.has("type") ? effect.get("type").getAsString() : "none",
                        effect.has("value") ? effect.get("value").getAsFloat() : 0.0F,
                        effect.has("duration") ? effect.get("duration").getAsFloat() : 0.0F,
                        effect.has("cooldown") ? effect.get("cooldown").getAsFloat() : 0.0F));
            }
        }
        for (Node node : nodes.values()) {
            for (String req : node.requires()) {
                if (!nodes.containsKey(req)) {
                    EclipseMod.LOGGER.warn("skilltree.json: node '{}' requires unknown node '{}' — "
                            + "it will be unpurchasable until fixed", node.id(), req);
                }
            }
        }

        Map<String, Localized> branches = new LinkedHashMap<>();
        if (root.has("branches") && root.get("branches").isJsonObject()) {
            for (Map.Entry<String, JsonElement> entry : root.getAsJsonObject("branches").entrySet()) {
                if (!entry.getKey().startsWith("_")) {
                    branches.put(entry.getKey(), Localized.parse(entry.getValue()));
                }
            }
        }

        return new Tree(Map.copyOf(nodes), Map.copyOf(branches), GSON.toJson(clientJson(nodes, branches)));
    }

    /** Canonical client-facing JSON (what the server actually loaded, not the raw file). */
    private static JsonObject clientJson(Map<String, Node> nodes, Map<String, Localized> branches) {
        JsonObject root = new JsonObject();
        JsonObject branchObj = new JsonObject();
        branches.forEach((id, title) -> branchObj.add(id, title.toJsonElement()));
        root.add("branches", branchObj);
        JsonArray array = new JsonArray();
        for (Node node : nodes.values()) {
            JsonArray requires = new JsonArray();
            node.requires().forEach(requires::add);
            JsonObject effect = new JsonObject();
            effect.addProperty("type", node.effectType());
            effect.addProperty("value", node.value());
            if (node.duration() > 0.0F) {
                effect.addProperty("duration", node.duration());
            }
            if (node.cooldown() > 0.0F) {
                effect.addProperty("cooldown", node.cooldown());
            }
            JsonObject obj = new JsonObject();
            obj.addProperty("id", node.id());
            obj.addProperty("branch", node.branch());
            obj.addProperty("cost", node.cost());
            obj.add("requires", requires);
            obj.add("title", node.title().toJsonElement());
            obj.add("desc", node.desc().toJsonElement());
            obj.add("effect", effect);
            array.add(obj);
        }
        root.add("nodes", array);
        return root;
    }

    // ------------------------------------------------------------------
    // Defaults — plan §2.3 node table verbatim (ids, costs, effect values).
    // ------------------------------------------------------------------

    /** Canonical default tree JSON (public for gametest table pinning). */
    public static JsonObject defaultsJson() {
        JsonObject root = new JsonObject();

        JsonObject doc = new JsonObject();
        doc.addProperty("schema", "nodes[]: {id, branch, cost, requires[], title{en,de}, desc{en,de}, "
                + "effect{type, value, duration?, cooldown?}}. Effect magnitudes are fractions "
                + "(0.05 = 5%) except post_kill_absorption (hearts), no_fall_damage_below_blocks "
                + "(blocks) and first_biome_bonus_xp (flat XP). All values are live-tunable; "
                + "effect TYPE strings are code contracts (SkillPerks) - do not rename.");
        doc.addProperty("balance", "Total cost 51 points = level 51 to complete everything "
                + "(softcap 50). Perks are intentionally small utility boni, never OP.");
        root.add("_doc", doc);

        JsonObject branches = new JsonObject();
        branches.add("spine", loc("Spine", "Kernpfad"));
        branches.add("hunt", loc("Hunt", "Jagd"));
        branches.add("delve", loc("Delve", "Tiefe"));
        branches.add("stride", loc("Stride", "Wanderschaft"));
        root.add("branches", branches);

        JsonArray nodes = new JsonArray();
        nodes.add(node("S1", "spine", 1, List.of(),
                "Awakened", "Erwacht",
                "+5% vanilla XP from all sources.", "+5 % Vanilla-EP aus allen Quellen.",
                "vanilla_xp_pct", 0.05F, 0, 0));
        nodes.add(node("S2", "spine", 2, List.of("S1"),
                "Attuned", "Eingestimmt",
                "+5% skill XP from all sources.", "+5 % Skill-EP aus allen Quellen.",
                "skill_xp_pct", 0.05F, 0, 0));
        nodes.add(node("S3", "spine", 3, List.of("S2"),
                "Eclipsed", "Verfinstert",
                "+1% proc chance for all chance perks.", "+1 % Auslösechance für alle Zufalls-Perks.",
                "proc_chance_add", 0.01F, 0, 0));

        nodes.add(node("U1", "hunt", 1, List.of(),
                "Night's Edge", "Klinge der Nacht",
                "+3% melee damage at night.", "+3 % Nahkampfschaden bei Nacht.",
                "melee_damage_night_pct", 0.03F, 0, 0));
        nodes.add(node("U2", "hunt", 2, List.of("U1"),
                "Reaper", "Schnitter",
                "2% chance for double mob drops.", "2 % Chance auf doppelte Monster-Beute.",
                "double_mob_drop_chance", 0.02F, 0, 0));
        nodes.add(node("U3", "hunt", 2, List.of("U2"),
                "Bulwark", "Bollwerk",
                "Kills grant 2 absorption hearts for 10s (30s cooldown).",
                "Kills gewähren 2 Absorptionsherzen für 10 s (30 s Abklingzeit).",
                "post_kill_absorption", 2.0F, 10, 30));
        nodes.add(node("U4", "hunt", 3, List.of("U3"),
                "Shardseeker", "Splittersucher",
                "3% chance for a bonus umbral shard on night kills.",
                "3 % Chance auf einen Bonus-Umbralsplitter bei Nacht-Kills.",
                "bonus_shard_on_night_kill", 0.03F, 0, 0));
        nodes.add(node("U5", "hunt", 3, List.of("U4"),
                "Duelist", "Duellant",
                "+2% attack speed.", "+2 % Angriffsgeschwindigkeit.",
                "attack_speed_pct", 0.02F, 0, 0));
        nodes.add(node("U6", "hunt", 4, List.of("U5"),
                "Umbral Pact", "Umbraler Pakt",
                "+50% kill skill XP during night events.", "+50 % Kill-Skill-EP während Nachtereignissen.",
                "night_event_kill_xp_pct", 0.50F, 0, 0));

        nodes.add(node("T1", "delve", 1, List.of(),
                "Prospector", "Schürfer",
                "+10% mining skill XP.", "+10 % Bergbau-Skill-EP.",
                "mine_skill_xp_pct", 0.10F, 0, 0));
        nodes.add(node("T2", "delve", 2, List.of("T1"),
                "Fortune's Echo", "Echo des Glücks",
                "2% chance to double natural ore drops.", "2 % Chance, natürliche Erz-Drops zu verdoppeln.",
                "double_ore_drop_chance", 0.02F, 0, 0));
        nodes.add(node("T3", "delve", 2, List.of("T2"),
                "Iron Stomach", "Eiserner Magen",
                "-5% hunger drain.", "−5 % Hungerverbrauch.",
                "hunger_drain_pct", -0.05F, 0, 0));
        nodes.add(node("T4", "delve", 3, List.of("T3"),
                "Deep Delver", "Tiefengräber",
                "+5% mining speed below Y=0.", "+5 % Abbautempo unter Y=0.",
                "break_speed_below0_pct", 0.05F, 0, 0));
        nodes.add(node("T5", "delve", 3, List.of("T4"),
                "Smeltmaster", "Schmelzmeister",
                "5% chance for double smelting skill XP.", "5 % Chance auf doppelte Schmelz-Skill-EP.",
                "smelt_double_xp_chance", 0.05F, 0, 0));
        nodes.add(node("T6", "delve", 4, List.of("T5"),
                "Earthen Bond", "Erdenbund",
                "1% chance for a bonus raw ore from natural ores.",
                "1 % Chance auf ein Bonus-Roherz aus natürlichen Erzen.",
                "bonus_raw_ore_chance", 0.01F, 0, 0));

        nodes.add(node("V1", "stride", 1, List.of(),
                "Islander", "Inselläufer",
                "+1% movement speed on the spawn island.", "+1 % Bewegungstempo auf der Spawn-Insel.",
                "spawn_island_speed_pct", 0.01F, 0, 0));
        nodes.add(node("V2", "stride", 2, List.of("V1"),
                "Wayfarer", "Wanderer",
                "+25% exploration skill XP.", "+25 % Erkundungs-Skill-EP.",
                "explore_xp_pct", 0.25F, 0, 0));
        nodes.add(node("V3", "stride", 2, List.of("V2"),
                "Featherfall", "Federfall",
                "-10% fall damage.", "−10 % Fallschaden.",
                "fall_damage_reduce_pct", 0.10F, 0, 0));
        nodes.add(node("V4", "stride", 3, List.of("V3"),
                "Soft Landing", "Sanfte Landung",
                "No fall damage from falls up to 6 blocks.", "Kein Fallschaden bei Stürzen bis 6 Blöcke.",
                "no_fall_damage_below_blocks", 6.0F, 0, 0));
        nodes.add(node("V5", "stride", 3, List.of("V4"),
                "Night Stride", "Nachtschritt",
                "+2% movement speed at night.", "+2 % Bewegungstempo bei Nacht.",
                "night_speed_pct", 0.02F, 0, 0));
        nodes.add(node("V6", "stride", 4, List.of("V5"),
                "Cartographer", "Kartograf",
                "+100 bonus skill XP for each first biome visit.",
                "+100 Bonus-Skill-EP für jeden Erstbesuch eines Bioms.",
                "first_biome_bonus_xp", 100.0F, 0, 0));

        root.add("nodes", nodes);
        return root;
    }

    private static JsonObject loc(String en, String de) {
        JsonObject obj = new JsonObject();
        obj.addProperty("en", en);
        obj.addProperty("de", de);
        return obj;
    }

    private static JsonObject node(String id, String branch, int cost, List<String> requires,
            String titleEn, String titleDe, String descEn, String descDe,
            String effectType, float value, float duration, float cooldown) {
        JsonObject obj = new JsonObject();
        obj.addProperty("id", id);
        obj.addProperty("branch", branch);
        obj.addProperty("cost", cost);
        JsonArray req = new JsonArray();
        requires.forEach(req::add);
        obj.add("requires", req);
        obj.add("title", loc(titleEn, titleDe));
        obj.add("desc", loc(descEn, descDe));
        JsonObject effect = new JsonObject();
        effect.addProperty("type", effectType);
        effect.addProperty("value", value);
        if (duration > 0) {
            effect.addProperty("duration", duration);
        }
        if (cooldown > 0) {
            effect.addProperty("cooldown", cooldown);
        }
        obj.add("effect", effect);
        return obj;
    }
}
