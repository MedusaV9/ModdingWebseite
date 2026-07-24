package dev.projecteclipse.eclipse.devtools.dev.handbook;

import java.util.Locale;

/**
 * Fuzzy matcher behind the Dev Handbook search box (P5-W2, §2.2). Pure string logic with no
 * Minecraft imports so the ranking can be sanity-checked with plain {@code java} outside the
 * game. Matching is instant per keystroke (the registry is ~100 entries).
 *
 * <p>Ranking (higher = better; {@code 0} = no match):</p>
 * <ol>
 *   <li>{@code 400} — the command syntax starts with the query ({@code "buf" → /dev buff …}),</li>
 *   <li>{@code 300} — the syntax contains the query as a substring,</li>
 *   <li>{@code 200} — the localized description contains the query,</li>
 *   <li>{@code 100} — every whitespace-separated query word appears in syntax+description,</li>
 *   <li>{@code 1..50} — the query is an in-order character subsequence of the syntax
 *       ({@code "dtp" → /dev timer pause}); denser matches score higher.</li>
 * </ol>
 */
public final class DevHandbookSearch {
    private DevHandbookSearch() {}

    /** Convenience predicate over {@link #score}. A blank query matches everything. */
    public static boolean matches(String query, String syntax, String description) {
        return score(query, syntax, description) > 0;
    }

    /** Ranks one entry against the query; {@code 0} = filtered out. Blank query = neutral 1. */
    public static int score(String query, String syntax, String description) {
        String q = normalize(query);
        if (q.isEmpty()) {
            return 1;
        }
        String syn = normalize(syntax);
        String desc = normalize(description);
        if (syn.startsWith(q) || stripSlashes(syn).startsWith(q)) {
            return 400;
        }
        if (syn.contains(q)) {
            return 300;
        }
        if (desc.contains(q)) {
            return 200;
        }
        if (allWordsContained(q, syn + ' ' + desc)) {
            return 100;
        }
        int span = subsequenceSpan(q, syn);
        if (span > 0) {
            // Tighter spans (match chars close together) rank higher, capped into 1..50.
            return Math.max(1, 50 - Math.min(49, span - q.length()));
        }
        return 0;
    }

    private static String normalize(String text) {
        return text == null ? "" : text.strip().toLowerCase(Locale.ROOT);
    }

    private static String stripSlashes(String syntax) {
        return syntax.startsWith("/") ? syntax.substring(1) : syntax;
    }

    /** True when every whitespace-separated word of {@code query} occurs in {@code haystack}. */
    private static boolean allWordsContained(String query, String haystack) {
        String[] words = query.split("\\s+");
        if (words.length < 2) {
            return false;
        }
        for (String word : words) {
            if (!word.isEmpty() && !haystack.contains(word)) {
                return false;
            }
        }
        return true;
    }

    /**
     * Width of the shortest window in {@code haystack} containing {@code query} as an
     * in-order subsequence (greedy left-to-right — good enough for ranking); {@code 0} = none.
     */
    private static int subsequenceSpan(String query, String haystack) {
        int first = -1;
        int hi = 0;
        for (int qi = 0; qi < query.length(); qi++) {
            char c = query.charAt(qi);
            if (c == ' ') {
                continue;
            }
            int found = haystack.indexOf(c, hi);
            if (found < 0) {
                return 0;
            }
            if (first < 0) {
                first = found;
            }
            hi = found + 1;
        }
        return first < 0 ? 0 : hi - first;
    }
}
