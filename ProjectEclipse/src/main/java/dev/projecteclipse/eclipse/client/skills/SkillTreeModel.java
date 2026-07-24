package dev.projecteclipse.eclipse.client.skills;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.Localized;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

import javax.annotation.Nullable;

/**
 * Client-side view of the {@code S2CSkillTreePayload} JSON blob (WB-SKILLS, plan §3.9).
 * The wire schema is whatever {@code skills.SkillTreeConfig#clientJson} serialized —
 * {@code {branches:{id:{en,de}|string}, nodes:[{id, branch, cost, requires[], title{en,de},
 * desc{en,de}, effect{type,value,duration?,cooldown?}}]}} — deliberately re-parsed here
 * with zero references to server classes (only the shared {@link Localized} record), so a
 * schema drift degrades to missing nodes instead of a crash.
 *
 * <p><b>Layout is 100% data-driven:</b> the payload carries no x/y, so positions are
 * auto-derived — column = branch (payload branch-map order), row = prerequisite depth
 * ("tier": 0 for roots, else 1 + max parent tier). Several nodes sharing a branch+tier
 * cell fan out horizontally. If a future payload ever adds explicit {@code x}/{@code y}
 * (or {@code tier}/{@code column}) fields they win over the auto layout, and an optional
 * {@code iconItem} id wins over the client-side icon table below.</p>
 */
@OnlyIn(Dist.CLIENT)
public final class SkillTreeModel {
    /** Grid spacing of the auto layout, in canvas units (nodes are 24px tiles). */
    public static final int COL_WIDTH = 64;
    public static final int ROW_HEIGHT = 44;
    /** Horizontal fan-out for siblings sharing one branch+tier cell. */
    public static final int SIBLING_SPREAD = 30;
    public static final int NODE_SIZE = 24;

    /**
     * Cosmetic icon table for the shipped default tree (the payload carries no icon field
     * today). Unknown ids fall back per branch, then to a book — never a missing texture.
     * Kept as item-id strings (resolved lazily in {@link #resolveIcon}) so loading this
     * class never touches the item registry — parse/layout stay registry-free.
     */
    private static final Map<String, String> NODE_ICONS = Map.ofEntries(
            Map.entry("S1", "minecraft:experience_bottle"),
            Map.entry("S2", "minecraft:amethyst_shard"),
            Map.entry("S3", "minecraft:ender_eye"),
            Map.entry("U1", "minecraft:iron_sword"),
            Map.entry("U2", "minecraft:wither_skeleton_skull"),
            Map.entry("U3", "minecraft:shield"),
            Map.entry("U4", "minecraft:echo_shard"),
            Map.entry("U5", "minecraft:golden_sword"),
            Map.entry("U6", "minecraft:netherite_sword"),
            Map.entry("T1", "minecraft:iron_pickaxe"),
            Map.entry("T2", "minecraft:raw_gold"),
            Map.entry("T3", "minecraft:cooked_beef"),
            Map.entry("T4", "minecraft:deepslate"),
            Map.entry("T5", "minecraft:furnace"),
            Map.entry("T6", "minecraft:raw_iron"),
            Map.entry("V1", "minecraft:grass_block"),
            Map.entry("V2", "minecraft:map"),
            Map.entry("V3", "minecraft:feather"),
            Map.entry("V4", "minecraft:hay_block"),
            Map.entry("V5", "minecraft:clock"),
            Map.entry("V6", "minecraft:compass"));

    private static final Map<String, String> BRANCH_ICONS = Map.of(
            "spine", "minecraft:nether_star",
            "hunt", "minecraft:iron_sword",
            "delve", "minecraft:iron_pickaxe",
            "stride", "minecraft:leather_boots");

    /** Cache: re-parse only when the payload text (or its identity) changes. */
    private static String cachedJson;
    private static SkillTreeModel cachedModel;

    private final Map<String, Node> nodes;
    private final List<Branch> branches;
    /** Canvas-space content bounds (min/max over node tiles, padding excluded). */
    private final int minX;
    private final int minY;
    private final int maxX;
    private final int maxY;

    /** One laid-out node; {@code x}/{@code y} are the tile's top-left in canvas units. */
    public static final class Node {
        public final String id;
        public final String branch;
        public final int cost;
        public final List<String> requires;
        public final Localized title;
        public final Localized desc;
        public final String effectType;
        public final int tier;
        public int x;
        public int y;
        /** Optional payload {@code iconItem} id; {@code null} = use the client-side tables. */
        @Nullable
        private final String iconItemId;
        /** Lazily resolved on first render — keeps {@link #parse} registry-free (testable). */
        @Nullable
        private ItemStack iconCache;

        Node(String id, String branch, int cost, List<String> requires, Localized title,
                Localized desc, String effectType, int tier, @Nullable String iconItemId) {
            this.id = id;
            this.branch = branch;
            this.cost = cost;
            this.requires = requires;
            this.title = title;
            this.desc = desc;
            this.effectType = effectType;
            this.tier = tier;
            this.iconItemId = iconItemId;
        }

        /**
         * The node's cosmetic icon stack, resolved once on the render thread: an explicit
         * payload {@code iconItem} wins, then the per-id table, the branch table, a book.
         */
        public ItemStack icon() {
            ItemStack stack = iconCache;
            if (stack == null) {
                stack = resolveIcon(this);
                iconCache = stack;
            }
            return stack;
        }

        public int centerX() {
            return x + NODE_SIZE / 2;
        }

        public int centerY() {
            return y + NODE_SIZE / 2;
        }
    }

    /** Branch header rendered above each column. */
    public record Branch(String id, Localized title, int centerX) {}

    /** Node availability derived from the synced state — server truth, never predicted. */
    public enum State {
        OWNED, AVAILABLE, LOCKED
    }

    private SkillTreeModel(Map<String, Node> nodes, List<Branch> branches,
            int minX, int minY, int maxX, int maxY) {
        this.nodes = nodes;
        this.branches = branches;
        this.minX = minX;
        this.minY = minY;
        this.maxX = maxX;
        this.maxY = maxY;
    }

    // ------------------------------------------------------------------
    // Accessors
    // ------------------------------------------------------------------

    public Map<String, Node> nodes() {
        return nodes;
    }

    public List<Branch> branches() {
        return branches;
    }

    public boolean isEmpty() {
        return nodes.isEmpty();
    }

    public int minX() {
        return minX;
    }

    public int minY() {
        return minY;
    }

    public int maxX() {
        return maxX;
    }

    public int maxY() {
        return maxY;
    }

    /** Localized pick token for {@link Localized#pick}: "de" for de_de, else "en". */
    public static String pickLocale() {
        return EclipseLang.locale().startsWith("de") ? "de" : "en";
    }

    /** Current state of a node against the synced cache (owned list + prereqs). */
    public State stateOf(Node node) {
        List<String> owned = ClientStateCache.skillOwnedNodes;
        if (owned.contains(node.id)) {
            return State.OWNED;
        }
        for (String req : node.requires) {
            if (!owned.contains(req)) {
                return State.LOCKED;
            }
        }
        return State.AVAILABLE;
    }

    /** AVAILABLE and the player can pay for it right now. */
    public boolean affordable(Node node) {
        return stateOf(node) == State.AVAILABLE && ClientStateCache.skillUnspent >= node.cost;
    }

    // ------------------------------------------------------------------
    // Parse + layout
    // ------------------------------------------------------------------

    /** The model for {@code ClientStateCache.skillTreeJson}, re-parsed only on change. */
    public static SkillTreeModel current() {
        String json = ClientStateCache.skillTreeJson;
        SkillTreeModel model = cachedModel;
        if (model == null || !json.equals(cachedJson)) {
            model = parse(json);
            cachedModel = model;
            cachedJson = json;
        }
        return model;
    }

    /** Never throws — malformed payloads degrade to an empty tree (screen shows a hint). */
    public static SkillTreeModel parse(String json) {
        try {
            JsonElement rootElement = JsonParser.parseString(json == null || json.isBlank() ? "{}" : json);
            if (!rootElement.isJsonObject()) {
                return empty();
            }
            return parseRoot(rootElement.getAsJsonObject());
        } catch (Exception e) {
            EclipseMod.LOGGER.warn("WB-SKILLS: unparseable skill tree payload — rendering empty tree", e);
            return empty();
        }
    }

    private static SkillTreeModel empty() {
        return new SkillTreeModel(Map.of(), List.of(), 0, 0, 0, 0);
    }

    private static SkillTreeModel parseRoot(JsonObject root) {
        // Branch order defines column order; branches only referenced by nodes are appended.
        Map<String, Localized> branchTitles = new LinkedHashMap<>();
        if (root.has("branches") && root.get("branches").isJsonObject()) {
            for (Map.Entry<String, JsonElement> entry : root.getAsJsonObject("branches").entrySet()) {
                if (!entry.getKey().startsWith("_")) {
                    branchTitles.put(entry.getKey(), Localized.parse(entry.getValue()));
                }
            }
        }

        Map<String, Node> nodes = new LinkedHashMap<>();
        if (root.has("nodes") && root.get("nodes").isJsonArray()) {
            // First pass: raw fields (tier needs the full requires graph, second pass).
            Map<String, JsonObject> raw = new LinkedHashMap<>();
            for (JsonElement element : root.getAsJsonArray("nodes")) {
                if (!element.isJsonObject()) {
                    continue;
                }
                JsonObject obj = element.getAsJsonObject();
                String id = obj.has("id") ? obj.get("id").getAsString() : "";
                if (!id.isEmpty() && !raw.containsKey(id)) {
                    raw.put(id, obj);
                }
            }
            Map<String, Integer> tiers = new HashMap<>();
            for (String id : raw.keySet()) {
                computeTier(id, raw, tiers, 0);
            }
            for (Map.Entry<String, JsonObject> entry : raw.entrySet()) {
                JsonObject obj = entry.getValue();
                String id = entry.getKey();
                String branch = obj.has("branch") ? obj.get("branch").getAsString() : "spine";
                branchTitles.putIfAbsent(branch, Localized.of(branch));
                List<String> requires = new ArrayList<>();
                if (obj.has("requires") && obj.get("requires").isJsonArray()) {
                    for (JsonElement req : obj.getAsJsonArray("requires")) {
                        requires.add(req.getAsString());
                    }
                }
                JsonObject effect = obj.has("effect") && obj.get("effect").isJsonObject()
                        ? obj.getAsJsonObject("effect") : new JsonObject();
                // Future-proof explicit placement: tier/column fields override the auto rows.
                int tier = obj.has("tier") ? obj.get("tier").getAsInt()
                        : tiers.getOrDefault(id, 0);
                nodes.put(id, new Node(
                        id,
                        branch,
                        obj.has("cost") ? Math.max(1, obj.get("cost").getAsInt()) : 1,
                        List.copyOf(requires),
                        Localized.parse(obj.get("title")),
                        Localized.parse(obj.get("desc")),
                        effect.has("type") ? effect.get("type").getAsString() : "none",
                        tier,
                        obj.has("iconItem") && obj.get("iconItem").isJsonPrimitive()
                                ? obj.get("iconItem").getAsString() : null));
            }
        }

        return layout(nodes, branchTitles);
    }

    /** Longest-prerequisite-chain depth; unknown parents count as roots, cycles clamp. */
    private static int computeTier(String id, Map<String, JsonObject> raw, Map<String, Integer> tiers,
            int guard) {
        Integer known = tiers.get(id);
        if (known != null) {
            return known;
        }
        if (guard > raw.size()) {
            return 0; // defensive cycle break — a broken payload must not hang the client
        }
        JsonObject obj = raw.get(id);
        int tier = 0;
        if (obj != null && obj.has("requires") && obj.get("requires").isJsonArray()) {
            JsonArray requires = obj.getAsJsonArray("requires");
            for (JsonElement req : requires) {
                String parent = req.getAsString();
                if (raw.containsKey(parent)) {
                    tier = Math.max(tier, computeTier(parent, raw, tiers, guard + 1) + 1);
                }
            }
        }
        tiers.put(id, tier);
        return tier;
    }

    /** Columns per branch (payload order), rows per tier, siblings fanned out. */
    private static SkillTreeModel layout(Map<String, Node> nodes, Map<String, Localized> branchTitles) {
        List<String> branchOrder = new ArrayList<>(branchTitles.keySet());
        // Group nodes into branch+tier cells, preserving payload order inside a cell.
        Map<String, Map<Integer, List<Node>>> cells = new LinkedHashMap<>();
        for (Node node : nodes.values()) {
            cells.computeIfAbsent(node.branch, key -> new LinkedHashMap<>())
                    .computeIfAbsent(node.tier, key -> new ArrayList<>()).add(node);
        }

        // A branch column must be wide enough for its fattest sibling fan.
        Map<String, Integer> branchWidth = new HashMap<>();
        for (String branch : branchOrder) {
            int widest = 1;
            Map<Integer, List<Node>> tiers = cells.get(branch);
            if (tiers != null) {
                for (List<Node> cell : tiers.values()) {
                    widest = Math.max(widest, cell.size());
                }
            }
            branchWidth.put(branch, Math.max(COL_WIDTH, widest * SIBLING_SPREAD + NODE_SIZE + 8));
        }

        int minX = Integer.MAX_VALUE;
        int minY = Integer.MAX_VALUE;
        int maxX = Integer.MIN_VALUE;
        int maxY = Integer.MIN_VALUE;
        List<Branch> branches = new ArrayList<>();
        int columnLeft = 0;
        for (String branch : branchOrder) {
            int width = branchWidth.getOrDefault(branch, COL_WIDTH);
            int centerX = columnLeft + width / 2;
            Map<Integer, List<Node>> tiers = cells.get(branch);
            if (tiers != null) {
                for (Map.Entry<Integer, List<Node>> cell : tiers.entrySet()) {
                    List<Node> siblings = cell.getValue();
                    int count = siblings.size();
                    for (int i = 0; i < count; i++) {
                        Node node = siblings.get(i);
                        int fan = Math.round((i - (count - 1) / 2.0F) * SIBLING_SPREAD);
                        node.x = centerX + fan - NODE_SIZE / 2;
                        node.y = cell.getKey() * ROW_HEIGHT;
                        minX = Math.min(minX, node.x);
                        minY = Math.min(minY, node.y);
                        maxX = Math.max(maxX, node.x + NODE_SIZE);
                        maxY = Math.max(maxY, node.y + NODE_SIZE);
                    }
                }
            }
            branches.add(new Branch(branch, branchTitles.get(branch), centerX));
            columnLeft += width;
        }
        if (nodes.isEmpty()) {
            minX = minY = maxX = maxY = 0;
        }
        return new SkillTreeModel(Map.copyOf(nodes), List.copyOf(branches), minX, minY, maxX, maxY);
    }

    /**
     * Icon resolution ({@link Node#icon()} lazy path, render thread): the payload's
     * optional {@code iconItem} wins; else the per-id table, branch table, book.
     */
    private static ItemStack resolveIcon(Node node) {
        if (node.iconItemId != null) {
            ResourceLocation itemId = ResourceLocation.tryParse(node.iconItemId);
            if (itemId != null) {
                Item item = BuiltInRegistries.ITEM.getOptional(itemId).orElse(null);
                if (item != null && item != Items.AIR) {
                    return new ItemStack(item);
                }
            }
        }
        String mappedId = NODE_ICONS.get(node.id);
        if (mappedId == null) {
            mappedId = BRANCH_ICONS.get(node.branch);
        }
        if (mappedId != null) {
            ResourceLocation itemId = ResourceLocation.tryParse(mappedId);
            if (itemId != null) {
                Item item = BuiltInRegistries.ITEM.getOptional(itemId).orElse(null);
                if (item != null && item != Items.AIR) {
                    return new ItemStack(item);
                }
            }
        }
        return new ItemStack(Items.BOOK);
    }
}
