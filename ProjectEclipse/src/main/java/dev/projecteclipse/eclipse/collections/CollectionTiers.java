package dev.projecteclipse.eclipse.collections;

/**
 * Tiny side-agnostic helpers shared by the D1 collections server code, the dev commands
 * and the client toast/tab (no Minecraft imports so both dists can use it freely).
 */
public final class CollectionTiers {
    private static final String[] ROMAN = {
            "", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"
    };

    private CollectionTiers() {}

    /** Roman numeral for a 1-based tier ({@code 2 → "II"}); plain digits past XII. */
    public static String roman(int tier) {
        if (tier <= 0) {
            return "0";
        }
        return tier < ROMAN.length ? ROMAN[tier] : Integer.toString(tier);
    }

    /**
     * Grouped count for UI ({@code 12500 → "12 500"}, narrow no-break spaces) — the tab
     * and toast never print raw longs.
     */
    public static String formatCount(long count) {
        String raw = Long.toString(Math.max(0L, count));
        StringBuilder grouped = new StringBuilder(raw.length() + 4);
        int lead = raw.length() % 3 == 0 ? 3 : raw.length() % 3;
        for (int i = 0; i < raw.length(); i++) {
            if (i == lead || (i > lead && (i - lead) % 3 == 0)) {
                grouped.append('\u202F');
            }
            grouped.append(raw.charAt(i));
        }
        return grouped.toString();
    }
}
