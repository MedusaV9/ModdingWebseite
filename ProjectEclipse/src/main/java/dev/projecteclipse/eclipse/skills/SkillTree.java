package dev.projecteclipse.eclipse.skills;

import java.util.Map;
import java.util.Set;

/**
 * Pure skill-tree decision logic (purchase validation + owned-effect aggregation) over
 * {@link SkillTreeConfig} data. Static and side-effect-free so gametests can pin every
 * branch without a live player.
 */
public final class SkillTree {
    /** Purchase validation outcome; anything but {@link #OK} is user-facing feedback. */
    public enum BuyResult {
        OK,
        UNKNOWN_NODE,
        ALREADY_OWNED,
        MISSING_PREREQ,
        NOT_ENOUGH_POINTS
    }

    private SkillTree() {}

    /**
     * Validates a purchase against the tree definition. The server calls this for BOTH the
     * {@code C2SSkillNodeBuyPayload} handler and the {@code /skills buy} fallback — clients
     * are never trusted with cost or prereq checks.
     */
    public static BuyResult canBuy(Map<String, SkillTreeConfig.Node> nodes, Set<String> owned,
            int unspentPoints, String nodeId) {
        SkillTreeConfig.Node node = nodes.get(nodeId);
        if (node == null) {
            return BuyResult.UNKNOWN_NODE;
        }
        if (owned.contains(nodeId)) {
            return BuyResult.ALREADY_OWNED;
        }
        for (String requirement : node.requires()) {
            if (!owned.contains(requirement)) {
                return BuyResult.MISSING_PREREQ;
            }
        }
        if (unspentPoints < node.cost()) {
            return BuyResult.NOT_ENOUGH_POINTS;
        }
        return BuyResult.OK;
    }

    /**
     * Sum of {@code effect.value} across owned nodes of the given effect type. Today each
     * type appears on exactly one node, but summing keeps authored trees free to stack.
     */
    public static float effectTotal(Map<String, SkillTreeConfig.Node> nodes, Set<String> owned, String effectType) {
        float total = 0.0F;
        for (String id : owned) {
            SkillTreeConfig.Node node = nodes.get(id);
            if (node != null && node.effectType().equals(effectType)) {
                total += node.value();
            }
        }
        return total;
    }

    /** First owned node of a type (for effects with duration/cooldown extras, e.g. U3). */
    public static SkillTreeConfig.Node ownedNode(Map<String, SkillTreeConfig.Node> nodes, Set<String> owned,
            String effectType) {
        for (String id : owned) {
            SkillTreeConfig.Node node = nodes.get(id);
            if (node != null && node.effectType().equals(effectType)) {
                return node;
            }
        }
        return null;
    }

    /** Total point cost of a set of owned nodes (tree-reset refund math). */
    public static int totalCost(Map<String, SkillTreeConfig.Node> nodes, Set<String> owned) {
        int total = 0;
        for (String id : owned) {
            SkillTreeConfig.Node node = nodes.get(id);
            if (node != null) {
                total += node.cost();
            }
        }
        return total;
    }
}
