package dev.projecteclipse.eclipse.wand;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import javax.annotation.Nullable;

/**
 * F-036: the wand's REAL skill tree — 48 nodes (16 per {@link WandPath}), bought with
 * <b>Wand-XP-Punkten</b> ({@code WandStore.Progress.xp}, the currency every cast/kill
 * earns), with parent dependencies and escalating costs. Per path:
 *
 * <pre>
 * T1  s1 (baseline spell; AUTO-GRANTED when the path is chosen) ─┬─ s2 (spell 2)
 *                                                                └─ c1 (+15 max charge)
 * T2  s3 (spell 3, req s2)   d1 (+10% damage, req s2)   r1 (+20% regen, req c1)
 * T3  s4→s5 (spells, chain)  e1 (−10% cost, req d1)     c2 (+25 max charge, req r1)
 * T4  s6→s7 (spells, chain)  r2 (+30% regen, req c2)
 * T5  s8→s9 (spells, chain)  s10 (capstone spell, req s9 + e1)
 * </pre>
 *
 * <p><b>Rebirth:</b> once ALL 48 nodes are owned, {@link #rebirthCost} Wand-XP can be
 * burned to reset the tree (the chosen path's s1 is re-granted), incrementing the
 * permanent rebirth counter: every rebirth grants +{@value #REBIRTH_POWER_PCT} spell power
 * and +{@value #REBIRTH_CHARGE_PCT} max Veilladung (folded in by {@link WandPerks}). Costs
 * double per rebirth — deliberately brutal ("Rebirth wesentlich teurer").</p>
 *
 * <p>The wand's display level (1–5, drives the GeckoLib model stages) is DERIVED from the
 * owned-node count via {@link #levelForNodes}. Server validation + purchase flow live in
 * {@code WandTreeService}; effect aggregation in {@link WandPerks}.</p>
 */
public final class WandTree {
    /** Permanent spell-power bonus per rebirth (+15%). */
    public static final float REBIRTH_POWER_PCT = 0.15F;
    /** Permanent max-Veilladung bonus per rebirth (+10%). */
    public static final float REBIRTH_CHARGE_PCT = 0.10F;
    /** First rebirth costs this many Wand-XP points; doubles each rebirth. */
    public static final int REBIRTH_BASE_COST = 5000;

    // Stat-effect contracts (aggregated by WandPerks; caps applied there).
    public static final String FX_CHARGE_MAX_ADD = "charge_max_add";
    public static final String FX_REGEN_PCT = "regen_pct";
    public static final String FX_DAMAGE_PCT = "damage_pct";
    public static final String FX_COST_REDUCE_PCT = "cost_reduce_pct";

    /**
     * One tree node. Either a spell unlock ({@code spellKey != null}) or a stat node
     * ({@code effectType != null}). {@code requires} are ALL-required parent ids.
     */
    public record Node(
            String id,
            WandPath path,
            int tier,
            int cost,
            List<String> requires,
            @Nullable String spellKey,
            @Nullable String effectType,
            float effectValue,
            /** Shared stat suffix (c1/c2/r1/r2/d1/e1) for lang keys; null on spell nodes. */
            @Nullable String statSuffix) {

        /** Lang key of a stat node's display name; spell nodes use the spell's langKey. */
        public String statLangKey() {
            return "wand.eclipse.node." + statSuffix;
        }
    }

    private static final Map<String, Node> BY_ID = new LinkedHashMap<>();

    static {
        for (WandPath path : new WandPath[] {WandPath.RISS, WandPath.GLUT, WandPath.STERN}) {
            List<WandSpell> spells = WandSpells.ofPath(path);
            String p = path.name().toLowerCase(java.util.Locale.ROOT);
            // Tier 1
            spell(p + "_s1", path, 1, 50, List.of(), spells.get(0));
            spell(p + "_s2", path, 1, 100, List.of(p + "_s1"), spells.get(1));
            stat(p + "_c1", path, 1, 100, List.of(p + "_s1"), FX_CHARGE_MAX_ADD, 15.0F, "c1");
            // Tier 2
            spell(p + "_s3", path, 2, 200, List.of(p + "_s2"), spells.get(2));
            stat(p + "_d1", path, 2, 200, List.of(p + "_s2"), FX_DAMAGE_PCT, 0.10F, "d1");
            stat(p + "_r1", path, 2, 200, List.of(p + "_c1"), FX_REGEN_PCT, 0.20F, "r1");
            // Tier 3
            spell(p + "_s4", path, 3, 350, List.of(p + "_s3"), spells.get(3));
            spell(p + "_s5", path, 3, 400, List.of(p + "_s4"), spells.get(4));
            stat(p + "_e1", path, 3, 350, List.of(p + "_d1"), FX_COST_REDUCE_PCT, 0.10F, "e1");
            stat(p + "_c2", path, 3, 300, List.of(p + "_r1"), FX_CHARGE_MAX_ADD, 25.0F, "c2");
            // Tier 4
            spell(p + "_s6", path, 4, 550, List.of(p + "_s5"), spells.get(5));
            spell(p + "_s7", path, 4, 600, List.of(p + "_s6"), spells.get(6));
            stat(p + "_r2", path, 4, 500, List.of(p + "_c2"), FX_REGEN_PCT, 0.30F, "r2");
            // Tier 5
            spell(p + "_s8", path, 5, 800, List.of(p + "_s7"), spells.get(7));
            spell(p + "_s9", path, 5, 900, List.of(p + "_s8"), spells.get(8));
            spell(p + "_s10", path, 5, 1200, List.of(p + "_s9", p + "_e1"), spells.get(9));
        }
    }

    private WandTree() {}

    private static void spell(String id, WandPath path, int tier, int cost,
            List<String> requires, WandSpell unlock) {
        BY_ID.put(id, new Node(id, path, tier, cost, List.copyOf(requires),
                unlock.key(), null, 0.0F, null));
    }

    private static void stat(String id, WandPath path, int tier, int cost,
            List<String> requires, String effectType, float effectValue, String statSuffix) {
        BY_ID.put(id, new Node(id, path, tier, cost, List.copyOf(requires),
                null, effectType, effectValue, statSuffix));
    }

    /** All 48 nodes in canonical order (RISS block, GLUT block, STERN block). */
    public static List<Node> all() {
        return List.copyOf(BY_ID.values());
    }

    /** Node by id, or null. */
    @Nullable
    public static Node byId(@Nullable String id) {
        return id == null ? null : BY_ID.get(id);
    }

    /** The 16 nodes of one path in canonical order. */
    public static List<Node> ofPath(WandPath path) {
        List<Node> nodes = new ArrayList<>(16);
        for (Node node : BY_ID.values()) {
            if (node.path() == path) {
                nodes.add(node);
            }
        }
        return nodes;
    }

    /** Total node count (rebirth gate: ALL of these must be owned). */
    public static int nodeCount() {
        return BY_ID.size();
    }

    /** True when every node is owned — the rebirth precondition (F-036). */
    public static boolean isMaxed(Set<String> owned) {
        return owned.size() >= BY_ID.size() && owned.containsAll(BY_ID.keySet());
    }

    /** True when every parent of {@code node} is owned. */
    public static boolean parentsOwned(Node node, Set<String> owned) {
        for (String parent : node.requires()) {
            if (!owned.contains(parent)) {
                return false;
            }
        }
        return true;
    }

    /** Wand-XP cost of the NEXT rebirth given the current counter (doubles each time). */
    public static long rebirthCost(int rebirths) {
        return REBIRTH_BASE_COST * (1L << Math.min(20, Math.max(0, rebirths)));
    }

    /**
     * Display level 1–5 derived from the owned-node count (48 max). Thresholds:
     * 4 → L2, 10 → L3, 20 → L4, 32 → L5 — the model's growth stages track real
     * investment instead of the old XP curve.
     */
    public static int levelForNodes(int ownedCount) {
        if (ownedCount >= 32) {
            return 5;
        }
        if (ownedCount >= 20) {
            return 4;
        }
        if (ownedCount >= 10) {
            return 3;
        }
        return ownedCount >= 4 ? 2 : 1;
    }
}
