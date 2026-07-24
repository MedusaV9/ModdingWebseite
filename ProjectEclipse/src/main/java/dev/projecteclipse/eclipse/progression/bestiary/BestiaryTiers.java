package dev.projecteclipse.eclipse.progression.bestiary;

import java.util.Set;

/**
 * Shared tier math of the progressive bestiary (W4-BESTIARY): per-player, per-mob
 * knowledge tiers derived from a single lifetime progress count plus an "encountered"
 * flag. Pure functions over frozen thresholds — used by the server
 * ({@link BestiaryService}) to decide tier-ups and by the client
 * ({@code client.handbook.tabs.BestiaryTab}) to render pips/hints, so both sides always
 * agree. No Minecraft imports: loadable everywhere.
 *
 * <ul>
 *   <li><b>T0 UNSEEN</b> — silhouette + scrambled name; nothing known.</li>
 *   <li><b>T1 ENCOUNTERED</b> — name + base lore. First proximity encounter (within
 *       {@link BestiaryService#ENCOUNTER_RANGE} blocks) or first kill.</li>
 *   <li><b>T2 HUNTER</b> — field notes (hunting pattern + spawn grounds). Default
 *       {@value #DEFAULT_T2_COUNT} kills.</li>
 *   <li><b>T3 SLAYER</b> — WEAKNESSES. Default {@value #DEFAULT_T3_COUNT} kills.</li>
 * </ul>
 *
 * <p><b>Per-id overrides</b> (kill counts must stay reachable):</p>
 * <ul>
 *   <li>{@link #BOSS_IDS} — the four set-piece bosses may only ever be defeated once
 *       per world, so ONE kill is full mastery (T1 → T3 in a single tier-up; you beat
 *       it, you know it).</li>
 *   <li>{@link #SIGHTING_IDS} — mobs studied by OBSERVATION, not slaughter: the gazer
 *       vanishes when damaged (there is no kill lane to feed), and Orin is a unique
 *       neutral NPC nobody should farm. Their count field accumulates throttled
 *       SIGHTINGS from the proximity scan instead of kills; thresholds are unchanged.</li>
 * </ul>
 */
public final class BestiaryTiers {
    public static final byte TIER_UNSEEN = 0;
    public static final byte TIER_ENCOUNTERED = 1;
    public static final byte TIER_HUNTER = 2;
    public static final byte TIER_SLAYER = 3;

    /** Default kill (or sighting) counts for T2 / T3. */
    public static final int DEFAULT_T2_COUNT = 3;
    public static final int DEFAULT_T3_COUNT = 10;

    /** Set-piece bosses: first kill = full dossier (T3). Registry paths, {@code eclipse:} ns. */
    private static final Set<String> BOSS_IDS = Set.of(
            "herald", "ferryman", "rift_warden", "fog_tyrant");

    /**
     * Progress counts sightings, not kills (see class doc). {@code wizard_orin} tolerates
     * absence — the id simply never appears in a scan until that worker's family is wired.
     */
    private static final Set<String> SIGHTING_IDS = Set.of("gazer", "wizard_orin");

    private BestiaryTiers() {}

    /** Whether this mob's progress count accumulates sightings instead of kills. */
    public static boolean isSightingProgress(String id) {
        return SIGHTING_IDS.contains(id);
    }

    /** T2 threshold for this id ({@code 1} for bosses, else {@value #DEFAULT_T2_COUNT}). */
    public static int t2Count(String id) {
        return BOSS_IDS.contains(id) ? 1 : DEFAULT_T2_COUNT;
    }

    /** T3 threshold for this id ({@code 1} for bosses, else {@value #DEFAULT_T3_COUNT}). */
    public static int t3Count(String id) {
        return BOSS_IDS.contains(id) ? 1 : DEFAULT_T3_COUNT;
    }

    /** Knowledge tier for a progress count + encountered flag (see class doc). */
    public static byte tierFor(String id, int count, boolean encountered) {
        if (count >= t3Count(id)) {
            return TIER_SLAYER;
        }
        if (count >= t2Count(id)) {
            return TIER_HUNTER;
        }
        if (count > 0 || encountered) {
            return TIER_ENCOUNTERED;
        }
        return TIER_UNSEEN;
    }

    /**
     * The count needed for the NEXT tier from {@code tier}, or {@code -1} when maxed
     * (or still unseen — T0 unlocks by encounter, not by count).
     */
    public static int nextCount(String id, byte tier) {
        return switch (tier) {
            case TIER_ENCOUNTERED -> t2Count(id);
            case TIER_HUNTER -> t3Count(id);
            default -> -1;
        };
    }
}
