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
 * Loader for {@code config/eclipse/skilltree.json} (R3, plan §2.3 node table; expanded by
 * wave-5 A14, then WANDFIX-4): 78 nodes — the original 25 keystones (4-point spine +
 * three 7-node branches: hunt / delve / stride), 35 incremental filler tiers threaded
 * between them (fortune-echo, loot-luck, xp-gain %, mining pace, night stride, fall
 * reduction, …) and the 18-node <b>wand branch</b> (Veilladung reservoir / cast economy /
 * damage / lore lines with two mutually exclusive specialisation pairs and a free-cast
 * capstone — contracts in {@code wand/WandPerks}). Every other node reuses an EXISTING
 * {@link SkillPerks}/{@link SkillService} effect-type contract — no node ships an effect
 * string the code does not implement. Node effects are small, incremental and never OP by
 * design — every magnitude is a config value consumed by {@link SkillPerks} /
 * {@link SkillService}, so balance can be retuned live via {@code /eclipse reload}. The
 * canonical serialized tree (not secret) ships to clients as {@code S2CSkillTreePayload}
 * for P3's GUI.
 */
public final class SkillTreeConfig {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final String FILE_NAME = "skilltree.json";

    // statics reset on ServerStopped (SkillService.onServerStopped calls invalidate())
    private static volatile Tree tree;

    private SkillTreeConfig() {}

    /**
     * One skill tree node. {@code duration}/{@code cooldown} are seconds (U3 only today).
     * {@code excludes} (WANDFIX-4) lists node ids this node can never coexist with —
     * mutually exclusive specialisations, enforced both ways in {@link SkillTree#canBuy}.
     */
    public record Node(
            String id,
            String branch,
            int cost,
            List<String> requires,
            List<String> excludes,
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
                List<String> excludes = new java.util.ArrayList<>();
                if (obj.has("excludes") && obj.get("excludes").isJsonArray()) {
                    for (JsonElement exc : obj.getAsJsonArray("excludes")) {
                        excludes.add(exc.getAsString());
                    }
                }
                JsonObject effect = obj.has("effect") && obj.get("effect").isJsonObject()
                        ? obj.getAsJsonObject("effect") : new JsonObject();
                nodes.put(id, new Node(
                        id,
                        obj.has("branch") ? obj.get("branch").getAsString() : "spine",
                        obj.has("cost") ? Math.max(1, obj.get("cost").getAsInt()) : 1,
                        List.copyOf(requires),
                        List.copyOf(excludes),
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
            for (String exc : node.excludes()) {
                if (!nodes.containsKey(exc)) {
                    EclipseMod.LOGGER.warn("skilltree.json: node '{}' excludes unknown node '{}' — "
                            + "the exclusion is inert until fixed", node.id(), exc);
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
            JsonArray excludes = new JsonArray();
            node.excludes().forEach(excludes::add);
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
            if (!node.excludes().isEmpty()) {
                obj.add("excludes", excludes);
            }
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
        doc.addProperty("schema", "nodes[]: {id, branch, cost, requires[], excludes[]?, title{en,de}, "
                + "desc{en,de}, effect{type, value, duration?, cooldown?}}. Effect magnitudes are fractions "
                + "(0.05 = 5%) except post_kill_absorption (hearts), no_fall_damage_below_blocks "
                + "(blocks), first_biome_bonus_xp (flat XP) and wand_charge_max_add (flat Veilladung). "
                + "excludes[] names nodes that can never coexist with this one (mutually exclusive "
                + "specialisations, enforced both ways). All values are live-tunable; "
                + "effect TYPE strings are code contracts (SkillPerks/WandPerks) - do not rename.");
        doc.addProperty("balance", "Total cost 200 points across 78 nodes; the two exclusive wand pairs "
                + "(W5/W6, W16/W17) lock 8 of them out per character, so ~192 points completes everything "
                + "ownable. Filler tiers are deliberately tiny (1-5% each); the keystones keep "
                + "their old values, so owning everything is a long-arc goal far beyond softcap 50.");
        doc.addProperty("migration", "Existing skilltree.json files are NOT rewritten (loadOrCreate). "
                + "To pick up the WANDFIX-4 78-node tree (wand branch) on a live save, delete "
                + "config/eclipse/skilltree.json (or merge the new nodes manually) and run /eclipse reload. "
                + "Old owned node ids are unchanged and stay owned.");
        root.add("_doc", doc);

        JsonObject branches = new JsonObject();
        branches.add("spine", loc("Spine", "Kernpfad"));
        branches.add("hunt", loc("Hunt", "Jagd"));
        branches.add("delve", loc("Delve", "Tiefe"));
        branches.add("stride", loc("Stride", "Wanderschaft"));
        branches.add("wand", loc("Wand", "Zauberstab"));
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
        nodes.add(node("S4", "spine", 3, List.of("S3"),
                "Resonant", "Nachhallend",
                "+2% skill XP from all sources.", "+2 % Skill-EP aus allen Quellen.",
                "skill_xp_pct", 0.02F, 0, 0));
        // Wave-5 A14 fillers: the xp-gain % family (small stacking tiers, existing contracts).
        nodes.add(node("S5", "spine", 2, List.of("S2"),
                "Keen Mind", "Wacher Geist",
                "+3% vanilla XP from all sources.", "+3 % Vanilla-EP aus allen Quellen.",
                "vanilla_xp_pct", 0.03F, 0, 0));
        nodes.add(node("S9", "spine", 2, List.of("S5"),
                "Bright Soul", "Helle Seele",
                "+2% vanilla XP from all sources.", "+2 % Vanilla-EP aus allen Quellen.",
                "vanilla_xp_pct", 0.02F, 0, 0));
        nodes.add(node("S6", "spine", 2, List.of("S4"),
                "Deep Attunement", "Tiefe Einstimmung",
                "+3% skill XP from all sources.", "+3 % Skill-EP aus allen Quellen.",
                "skill_xp_pct", 0.03F, 0, 0));
        nodes.add(node("S7", "spine", 3, List.of("S6"),
                "Fatewoven", "Schicksalsgewebt",
                "+0.5% proc chance for all chance perks.", "+0,5 % Auslösechance für alle Zufalls-Perks.",
                "proc_chance_add", 0.005F, 0, 0));
        nodes.add(node("S8", "spine", 4, List.of("S7"),
                "Umbral Resonance", "Umbrale Resonanz",
                "+5% skill XP from all sources.", "+5 % Skill-EP aus allen Quellen.",
                "skill_xp_pct", 0.05F, 0, 0));

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
        nodes.add(node("U7", "hunt", 4, List.of("U6"),
                "Quickened Edge", "Beschleunigte Klinge",
                "+2% attack speed.", "+2 % Angriffsgeschwindigkeit.",
                "attack_speed_pct", 0.02F, 0, 0));
        // Wave-5 A14 fillers: night-damage, loot-luck, shard-sense and attack-speed tiers.
        nodes.add(node("U8", "hunt", 1, List.of("U1"),
                "Sharpened Fang", "Geschärfter Fang",
                "+2% melee damage at night.", "+2 % Nahkampfschaden bei Nacht.",
                "melee_damage_night_pct", 0.02F, 0, 0));
        nodes.add(node("U9", "hunt", 2, List.of("U8"),
                "Night Predator", "Nachtjäger",
                "+2% melee damage at night.", "+2 % Nahkampfschaden bei Nacht.",
                "melee_damage_night_pct", 0.02F, 0, 0));
        nodes.add(node("U10", "hunt", 1, List.of("U2"),
                "Loot Luck I", "Beuteglück I",
                "+1% chance for double mob drops.", "+1 % Chance auf doppelte Monster-Beute.",
                "double_mob_drop_chance", 0.01F, 0, 0));
        nodes.add(node("U11", "hunt", 2, List.of("U10"),
                "Loot Luck II", "Beuteglück II",
                "+1% chance for double mob drops.", "+1 % Chance auf doppelte Monster-Beute.",
                "double_mob_drop_chance", 0.01F, 0, 0));
        nodes.add(node("U12", "hunt", 3, List.of("U11"),
                "Loot Luck III", "Beuteglück III",
                "+2% chance for double mob drops.", "+2 % Chance auf doppelte Monster-Beute.",
                "double_mob_drop_chance", 0.02F, 0, 0));
        nodes.add(node("U17", "hunt", 3, List.of("U12"),
                "Reaper's Due", "Schnitters Lohn",
                "+1% chance for double mob drops.", "+1 % Chance auf doppelte Monster-Beute.",
                "double_mob_drop_chance", 0.01F, 0, 0));
        nodes.add(node("U13", "hunt", 2, List.of("U4"),
                "Splinter Sense", "Splittergespür",
                "+1% chance for a bonus umbral shard on night kills.",
                "+1 % Chance auf einen Bonus-Umbralsplitter bei Nacht-Kills.",
                "bonus_shard_on_night_kill", 0.01F, 0, 0));
        nodes.add(node("U14", "hunt", 2, List.of("U5"),
                "Quick Wrists", "Flinke Handgelenke",
                "+1% attack speed.", "+1 % Angriffsgeschwindigkeit.",
                "attack_speed_pct", 0.01F, 0, 0));
        nodes.add(node("U15", "hunt", 3, List.of("U14"),
                "Battle Flow", "Kampffluss",
                "+2% attack speed.", "+2 % Angriffsgeschwindigkeit.",
                "attack_speed_pct", 0.02F, 0, 0));
        nodes.add(node("U16", "hunt", 4, List.of("U6"),
                "Night's Bounty", "Ernte der Nacht",
                "+25% kill skill XP during night events.", "+25 % Kill-Skill-EP während Nachtereignissen.",
                "night_event_kill_xp_pct", 0.25F, 0, 0));

        nodes.add(node("T1", "delve", 1, List.of(),
                "Prospector", "Schürfer",
                "+10% mining skill XP.", "+10 % Bergbau-Skill-EP.",
                "mine_skill_xp_pct", 0.10F, 0, 0));
        // FINAL-DOPA-SOL §2: at 2% the jackpot beat fired 1.2–2.4x/h (a no-proc hour was
        // 9–30% likely) — 3% keeps it rare but present in every focused mining hour.
        nodes.add(node("T2", "delve", 2, List.of("T1"),
                "Fortune's Echo", "Echo des Glücks",
                "3% chance to double natural ore drops.", "3 % Chance, natürliche Erz-Drops zu verdoppeln.",
                "double_ore_drop_chance", 0.03F, 0, 0));
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
        nodes.add(node("T7", "delve", 4, List.of("T6"),
                "Deep Rhythm", "Tiefer Rhythmus",
                "+3% mining speed below Y=0.", "+3 % Abbautempo unter Y=0.",
                "break_speed_below0_pct", 0.03F, 0, 0));
        // Wave-5 A14 fillers: fortune-echo tiers, miner's pace (mining speed %), mine-XP,
        // smelt and hunger tiers — all existing SkillPerks contracts.
        nodes.add(node("T8", "delve", 2, List.of("T2"),
                "Fortune's Echo II", "Echo des Glücks II",
                "+1% chance to double natural ore drops.",
                "+1 % Chance, natürliche Erz-Drops zu verdoppeln.",
                "double_ore_drop_chance", 0.01F, 0, 0));
        nodes.add(node("T9", "delve", 3, List.of("T8"),
                "Fortune's Echo III", "Echo des Glücks III",
                "+2% chance to double natural ore drops.",
                "+2 % Chance, natürliche Erz-Drops zu verdoppeln.",
                "double_ore_drop_chance", 0.02F, 0, 0));
        nodes.add(node("T10", "delve", 1, List.of("T1"),
                "Miner's Pace I", "Bergmannstempo I",
                "+3% mining speed below Y=0.", "+3 % Abbautempo unter Y=0.",
                "break_speed_below0_pct", 0.03F, 0, 0));
        nodes.add(node("T11", "delve", 2, List.of("T10"),
                "Miner's Pace II", "Bergmannstempo II",
                "+3% mining speed below Y=0.", "+3 % Abbautempo unter Y=0.",
                "break_speed_below0_pct", 0.03F, 0, 0));
        nodes.add(node("T12", "delve", 3, List.of("T11"),
                "Miner's Pace III", "Bergmannstempo III",
                "+4% mining speed below Y=0.", "+4 % Abbautempo unter Y=0.",
                "break_speed_below0_pct", 0.04F, 0, 0));
        nodes.add(node("T13", "delve", 1, List.of("T1"),
                "Ore Scholar", "Erzgelehrter",
                "+5% mining skill XP.", "+5 % Bergbau-Skill-EP.",
                "mine_skill_xp_pct", 0.05F, 0, 0));
        nodes.add(node("T14", "delve", 2, List.of("T13"),
                "Vein Scholar", "Adergelehrter",
                "+5% mining skill XP.", "+5 % Bergbau-Skill-EP.",
                "mine_skill_xp_pct", 0.05F, 0, 0));
        nodes.add(node("T15", "delve", 2, List.of("T5"),
                "Bellows Rhythm", "Blasebalg-Rhythmus",
                "+3% chance for double smelting skill XP.", "+3 % Chance auf doppelte Schmelz-Skill-EP.",
                "smelt_double_xp_chance", 0.03F, 0, 0));
        nodes.add(node("T16", "delve", 2, List.of("T3"),
                "Iron Stomach II", "Eiserner Magen II",
                "-3% hunger drain.", "−3 % Hungerverbrauch.",
                "hunger_drain_pct", -0.03F, 0, 0));
        nodes.add(node("T17", "delve", 4, List.of("T6"),
                "Earthen Bond II", "Erdenbund II",
                "+1% chance for a bonus raw ore from natural ores.",
                "+1 % Chance auf ein Bonus-Roherz aus natürlichen Erzen.",
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
        nodes.add(node("V7", "stride", 4, List.of("V6"),
                "Surefooted", "Trittsicher",
                "-4% fall damage.", "−4 % Fallschaden.",
                "fall_damage_reduce_pct", 0.04F, 0, 0));
        // Wave-5 A14 fillers: fall-reduction, explore-XP, movement (sprint-at-night /
        // island stride) and safe-fall tiers. no_fall_damage_below_blocks SUMS with V4
        // (SkillPerks.effect adds owned values), so V10 extends the safe window 6 -> 8.
        nodes.add(node("V8", "stride", 1, List.of("V3"),
                "Featherfall II", "Federfall II",
                "-5% fall damage.", "−5 % Fallschaden.",
                "fall_damage_reduce_pct", 0.05F, 0, 0));
        nodes.add(node("V9", "stride", 2, List.of("V8"),
                "Featherfall III", "Federfall III",
                "-5% fall damage.", "−5 % Fallschaden.",
                "fall_damage_reduce_pct", 0.05F, 0, 0));
        nodes.add(node("V10", "stride", 3, List.of("V4"),
                "Soft Landing II", "Sanfte Landung II",
                "Safe falls extend by 2 more blocks.", "Sichere Stürze um 2 weitere Blöcke verlängert.",
                "no_fall_damage_below_blocks", 2.0F, 0, 0));
        nodes.add(node("V11", "stride", 2, List.of("V2"),
                "Wayfarer II", "Wanderer II",
                "+10% exploration skill XP.", "+10 % Erkundungs-Skill-EP.",
                "explore_xp_pct", 0.10F, 0, 0));
        nodes.add(node("V12", "stride", 3, List.of("V11"),
                "Wayfarer III", "Wanderer III",
                "+15% exploration skill XP.", "+15 % Erkundungs-Skill-EP.",
                "explore_xp_pct", 0.15F, 0, 0));
        nodes.add(node("V13", "stride", 2, List.of("V5"),
                "Night Stride II", "Nachtschritt II",
                "+1% movement speed at night.", "+1 % Bewegungstempo bei Nacht.",
                "night_speed_pct", 0.01F, 0, 0));
        nodes.add(node("V14", "stride", 3, List.of("V13"),
                "Night Stride III", "Nachtschritt III",
                "+2% movement speed at night.", "+2 % Bewegungstempo bei Nacht.",
                "night_speed_pct", 0.02F, 0, 0));
        nodes.add(node("V15", "stride", 1, List.of("V1"),
                "Islander II", "Inselläufer II",
                "+1% movement speed on the spawn island.", "+1 % Bewegungstempo auf der Spawn-Insel.",
                "spawn_island_speed_pct", 0.01F, 0, 0));
        nodes.add(node("V16", "stride", 4, List.of("V6"),
                "Cartographer II", "Kartograf II",
                "+50 bonus skill XP for each first biome visit.",
                "+50 Bonus-Skill-EP für jeden Erstbesuch eines Bioms.",
                "first_biome_bonus_xp", 50.0F, 0, 0));
        nodes.add(node("V17", "stride", 2, List.of("V7"),
                "Surefooted II", "Trittsicher II",
                "-3% fall damage.", "−3 % Fallschaden.",
                "fall_damage_reduce_pct", 0.03F, 0, 0));

        // WANDFIX-4: the Zauberstab branch — 18 nodes, four sub-lines out of one root
        // (reservoir / economy / damage / lore), TWO mutually exclusive specialisation
        // pairs (W5 Sturmgefäß vs W6 Ebbe und Flut; W16 Überladung vs W17 Leitmagie)
        // and a free-cast capstone that demands investment in two different lines.
        // Effect contracts live in wand/WandPerks (all magnitudes summed per type,
        // caps applied in code so a hand-edited config cannot zero costs/cooldowns).
        nodes.add(node("W1", "wand", 1, List.of(),
                "Veil Spark", "Veilfunke",
                "+10 maximum Veilladung.", "+10 maximale Veilladung.",
                "wand_charge_max_add", 10.0F, 0, 0));
        // Reservoir line: bigger/faster Veilladung, forked capstone.
        nodes.add(node("W2", "wand", 2, List.of("W1"),
                "Veil Stream", "Veilstrom",
                "+15% Veilladung regeneration.", "+15 % Veilladungs-Regeneration.",
                "wand_regen_pct", 0.15F, 0, 0));
        nodes.add(node("W3", "wand", 2, List.of("W2"),
                "Deep Reserves", "Tiefe Reserven",
                "+15 maximum Veilladung.", "+15 maximale Veilladung.",
                "wand_charge_max_add", 15.0F, 0, 0));
        nodes.add(node("W4", "wand", 3, List.of("W3"),
                "Veil Stream II", "Veilstrom II",
                "+20% Veilladung regeneration.", "+20 % Veilladungs-Regeneration.",
                "wand_regen_pct", 0.20F, 0, 0));
        nodes.add(node("W5", "wand", 4, List.of("W4"), List.of("W6"),
                "Stormvessel", "Sturmgefäß",
                "+40 maximum Veilladung. Locks out Ebb and Flow.",
                "+40 maximale Veilladung. Schließt Ebbe und Flut aus.",
                "wand_charge_max_add", 40.0F, 0, 0));
        nodes.add(node("W6", "wand", 4, List.of("W4"), List.of("W5"),
                "Ebb and Flow", "Ebbe und Flut",
                "+50% Veilladung regeneration. Locks out Stormvessel.",
                "+50 % Veilladungs-Regeneration. Schließt Sturmgefäß aus.",
                "wand_regen_pct", 0.50F, 0, 0));
        // Economy line: cheaper casts, shorter cooldowns, the Leitmagie specialisation.
        nodes.add(node("W7", "wand", 2, List.of("W1"),
                "Focused Weave", "Gezieltes Weben",
                "Wand powers cost 5% less Veilladung.", "Stabkräfte kosten 5 % weniger Veilladung.",
                "wand_cost_reduce_pct", 0.05F, 0, 0));
        nodes.add(node("W8", "wand", 2, List.of("W7"),
                "Practiced Caster", "Geübter Wirker",
                "-8% wand power cooldowns.", "−8 % Abklingzeit aller Stabkräfte.",
                "wand_cooldown_reduce_pct", 0.08F, 0, 0));
        nodes.add(node("W9", "wand", 3, List.of("W8"),
                "Focused Weave II", "Gezieltes Weben II",
                "Wand powers cost another 5% less Veilladung.",
                "Stabkräfte kosten weitere 5 % weniger Veilladung.",
                "wand_cost_reduce_pct", 0.05F, 0, 0));
        nodes.add(node("W10", "wand", 3, List.of("W9"),
                "Cut Through Silence", "Schnitt durch die Stille",
                "-7% wand power cooldowns.", "−7 % Abklingzeit aller Stabkräfte.",
                "wand_cooldown_reduce_pct", 0.07F, 0, 0));
        nodes.add(node("W17", "wand", 4, List.of("W10"), List.of("W16"),
                "Conduit", "Leitmagie",
                "-15% wand power cooldowns. Locks out Overload.",
                "−15 % Abklingzeit aller Stabkräfte. Schließt Überladung aus.",
                "wand_cooldown_reduce_pct", 0.15F, 0, 0));
        // Damage line: raw power, the Überladung specialisation.
        nodes.add(node("W11", "wand", 2, List.of("W1"),
                "Unbound Edge", "Entfesselte Klinge",
                "+10% wand power damage.", "+10 % Schaden aller Stabkräfte.",
                "wand_damage_pct", 0.10F, 0, 0));
        nodes.add(node("W12", "wand", 3, List.of("W11"),
                "Veilburn", "Veilbrand",
                "+10% wand power damage.", "+10 % Schaden aller Stabkräfte.",
                "wand_damage_pct", 0.10F, 0, 0));
        nodes.add(node("W15", "wand", 3, List.of("W12"),
                "Veilburn II", "Veilbrand II",
                "+8% wand power damage.", "+8 % Schaden aller Stabkräfte.",
                "wand_damage_pct", 0.08F, 0, 0));
        nodes.add(node("W16", "wand", 4, List.of("W15"), List.of("W17"),
                "Overload", "Überladung",
                "+20% wand power damage. Locks out Conduit.",
                "+20 % Schaden aller Stabkräfte. Schließt Leitmagie aus.",
                "wand_damage_pct", 0.20F, 0, 0));
        // Lore line: faster wand leveling.
        nodes.add(node("W13", "wand", 2, List.of("W1"),
                "Channel Bond", "Kanalbindung",
                "+10% wand XP from casts and kills.", "+10 % Zauberstab-EP aus Zaubern und Kills.",
                "wand_xp_pct", 0.10F, 0, 0));
        nodes.add(node("W14", "wand", 3, List.of("W13"),
                "Resonance Study", "Resonanzlehre",
                "+15% wand XP from casts and kills.", "+15 % Zauberstab-EP aus Zaubern und Kills.",
                "wand_xp_pct", 0.15F, 0, 0));
        // Capstone: demands the reservoir AND damage lines, rewards with free casts.
        nodes.add(node("W18", "wand", 6, List.of("W4", "W15"),
                "Heart of the Veil", "Herz des Schleiers",
                "15% chance a cast costs no Veilladung.",
                "15 % Chance, dass ein Zauber keine Veilladung kostet.",
                "wand_free_cast_chance", 0.15F, 0, 0));

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
        return node(id, branch, cost, requires, List.of(), titleEn, titleDe, descEn, descDe,
                effectType, value, duration, cooldown);
    }

    /** Excludes-capable builder variant (WANDFIX-4 mutually exclusive specialisations). */
    private static JsonObject node(String id, String branch, int cost, List<String> requires,
            List<String> excludes, String titleEn, String titleDe, String descEn, String descDe,
            String effectType, float value, float duration, float cooldown) {
        JsonObject obj = new JsonObject();
        obj.addProperty("id", id);
        obj.addProperty("branch", branch);
        obj.addProperty("cost", cost);
        JsonArray req = new JsonArray();
        requires.forEach(req::add);
        obj.add("requires", req);
        if (!excludes.isEmpty()) {
            JsonArray exc = new JsonArray();
            excludes.forEach(exc::add);
            obj.add("excludes", exc);
        }
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
