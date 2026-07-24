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
 * <p><b>Per-id overrides</b> (kill counts must stay reachable — FINAL-DOPA-SOL §6):</p>
 * <ul>
 *   <li>{@link #BOSS_IDS} — the four set-piece bosses may only ever be defeated once
 *       per world, so ONE kill is full mastery (T1 → T3 in a single tier-up; you beat
 *       it, you know it).</li>
 *   <li>{@link #SIGHTING_IDS} — mobs studied by OBSERVATION, not slaughter: the gazer
 *       vanishes when damaged, Orin is a unique neutral NPC nobody should farm, the
 *       deckhands exist only aboard the day-14 crossing (8 benches — 10 kills is
 *       impossible), and The Other's spawn schedule yields 10 world spawns in only
 *       45.77% of events. Their count field accumulates throttled SIGHTINGS from the
 *       proximity scan (kills still count via the kill lane).</li>
 *   <li>{@link #LATE_IDS} — families that cannot exist before late stages/days
 *       (stage-3 fog sites and dungeons, the stage-4 pale garden, the finale ship):
 *       T2/T3 lowered {@value #DEFAULT_T2_COUNT}/{@value #DEFAULT_T3_COUNT} →
 *       {@value #LATE_T2_COUNT}/{@value #LATE_T3_COUNT} so a 14-day event can still
 *       complete their dossiers.</li>
 *   <li>{@code the_other} — T3 {@value #DEFAULT_T3_COUNT} → {@value #THE_OTHER_T3_COUNT}
 *       (eval: the pale-night schedule then reaches it in ~90% of worlds).</li>
 *   <li>{@code gazer} — sightings count out to {@value #GAZER_SIGHTING_RANGE} blocks:
 *       it spawns/relocates 20–40 blocks away, deliberately OUTSIDE the global 16-block
 *       scan, so the default range made T3 a 9-minute chase.</li>
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

    /** Lowered T2/T3 for {@link #LATE_IDS} (FINAL-DOPA-SOL §6: 3/10 → 2/5). */
    public static final int LATE_T2_COUNT = 2;
    public static final int LATE_T3_COUNT = 5;

    /** The Other's T3 (FINAL-DOPA-SOL §6: 10 → 6; ~90% of spawn schedules reach it). */
    public static final int THE_OTHER_T3_COUNT = 6;

    /** Gazer sighting radius in blocks (FINAL-DOPA-SOL §6: its spawn ring is 20–40 blocks out). */
    public static final double GAZER_SIGHTING_RANGE = 40.0D;

    /** Set-piece bosses: first kill = full dossier (T3). Registry paths, {@code eclipse:} ns. */
    private static final Set<String> BOSS_IDS = Set.of(
            "herald", "ferryman", "rift_warden", "fog_tyrant");

    /**
     * Progress counts sightings, not kills (see class doc). {@code wizard_orin} tolerates
     * absence — the id simply never appears in a scan until that worker's family is wired.
     * {@code deckhand} + {@code the_other} joined per FINAL-DOPA-SOL §6 (kill-only
     * progression was unreachable/unreliable for both).
     */
    private static final Set<String> SIGHTING_IDS = Set.of("gazer", "wizard_orin",
            "deckhand", "the_other");

    /**
     * Mobs that cannot spawn before late stages/days (FINAL-DOPA-SOL §6): stage-3 fog
     * elites and dungeon cultists, the stage-4/day-10 pale sentinel, and the day-14-only
     * deckhand. They use {@value #LATE_T2_COUNT}/{@value #LATE_T3_COUNT} thresholds.
     */
    private static final Set<String> LATE_IDS = Set.of("fog_revenant", "storm_hound",
            "fog_colossus", "eclipse_cultist", "pale_sentinel", "deckhand");

    private BestiaryTiers() {}

    /** Whether this mob's progress count accumulates sightings instead of kills. */
    public static boolean isSightingProgress(String id) {
        return SIGHTING_IDS.contains(id);
    }

    /**
     * The sighting-scan radius for this id; non-overridden ids use {@code fallback}
     * (the global encounter range). Only the gazer extends it — see class doc.
     */
    public static double sightingRange(String id, double fallback) {
        return "gazer".equals(id) ? GAZER_SIGHTING_RANGE : fallback;
    }

    /** Upper bound of all per-id sighting ranges — sizes the service's single scan box. */
    public static double maxSightingRange(double fallback) {
        return Math.max(fallback, GAZER_SIGHTING_RANGE);
    }

    /** T2 threshold for this id (bosses 1, late-stage families {@value #LATE_T2_COUNT}, else {@value #DEFAULT_T2_COUNT}). */
    public static int t2Count(String id) {
        if (BOSS_IDS.contains(id)) {
            return 1;
        }
        return LATE_IDS.contains(id) ? LATE_T2_COUNT : DEFAULT_T2_COUNT;
    }

    /** T3 threshold for this id (bosses 1, late-stage {@value #LATE_T3_COUNT}, The Other {@value #THE_OTHER_T3_COUNT}, else {@value #DEFAULT_T3_COUNT}). */
    public static int t3Count(String id) {
        if (BOSS_IDS.contains(id)) {
            return 1;
        }
        if (LATE_IDS.contains(id)) {
            return LATE_T3_COUNT;
        }
        return "the_other".equals(id) ? THE_OTHER_T3_COUNT : DEFAULT_T3_COUNT;
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
