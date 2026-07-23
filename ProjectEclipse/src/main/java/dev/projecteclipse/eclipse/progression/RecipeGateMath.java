package dev.projecteclipse.eclipse.progression;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * Pure day-tier lock resolution for recipe gating (gametest-friendly).
 */
public final class RecipeGateMath {
    private RecipeGateMath() {}

    /**
     * Returns raw lock entries (item ids and {@code #tag} ids, plus recipe ids) that are
     * locked on {@code day}. An entry from tier {@code T} is locked while {@code day < T.unlockDay}.
     */
    public static LockedEntries lockedAt(int day, RecipeGateConfig.Snapshot cfg) {
        Set<String> items = new LinkedHashSet<>();
        Set<String> recipes = new LinkedHashSet<>();
        for (RecipeGateConfig.Tier tier : cfg.tiers()) {
            if (day < tier.unlockDay()) {
                items.addAll(tier.items());
                recipes.addAll(tier.recipes());
            }
        }
        return new LockedEntries(List.copyOf(items), List.copyOf(recipes));
    }

    /** Raw lock ids before tag expansion. */
    public record LockedEntries(List<String> itemEntries, List<String> recipeIds) {}
}
