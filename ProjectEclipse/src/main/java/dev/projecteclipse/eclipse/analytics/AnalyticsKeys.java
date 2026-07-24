package dev.projecteclipse.eclipse.analytics;

import java.util.List;
import java.util.Set;

/**
 * The documented, bounded per-player-per-day counter namespace (plans_v3 P4 §2.4). Every
 * counter analytics tracks lives under one of these STATIC keys or one of the three DYNAMIC
 * prefixes. Awards (P4-B6) reference these ids as {@code metric}s in {@code awards.json};
 * P5 dev commands and P3 UIs use {@link #categories()} for discovery and the langdrop keys
 * {@code analytics.eclipse.category.<id>} for display names.
 *
 * <p>Dynamic keys are formed as {@code kill:<entity_id>}, {@code mine:<block_id>} and
 * {@code craft:<item_id>} (craft only for allowlisted ids — see {@link AnalyticsConfig}).
 * The per-(player, day) distinct-key count is capped
 * ({@code analytics.json maxDynamicKeysPerPlayerPerDay}) so state size stays bounded;
 * overflow drops per-id detail but never the {@code *_total} aggregates
 * (fail-safe under-crediting).</p>
 */
public final class AnalyticsKeys {
    // --- combat ---
    /** Total mob kills (non-player victims). Per-type detail under {@code kill:<entity_id>}. */
    public static final String KILL_TOTAL = "kill_total";
    /** Player deaths. */
    public static final String DEATH = "death";
    /** Damage dealt to living entities, fixed-point ×10 (one heart = 20). */
    public static final String DMG_DEALT = "dmg_dealt";
    /** Damage taken, fixed-point ×10. */
    public static final String DMG_TAKEN = "dmg_taken";

    // --- blocks ---
    /** Naturally-generated blocks mined (placed-block tracker verdict). Detail: {@code mine:<block_id>}. */
    public static final String MINE_TOTAL = "mine_total";
    /** Blocks placed (every block of a multi-block placement counts). */
    public static final String PLACE_TOTAL = "place_total";
    /** Distinct block types placed that day (id-hash set held in memory, count persisted). */
    public static final String PLACE_TYPES = "place_types";

    // --- crafting ---
    /** Items crafted (result stack counts). Allowlisted per-id detail: {@code craft:<item_id>}. */
    public static final String CRAFT_TOTAL = "craft_total";
    /** Items smelted (taken from furnace-likes). */
    public static final String SMELT_TOTAL = "smelt_total";

    // --- movement / exploration ---
    /** Distance travelled in centimetres (1 Hz position delta, per-sample teleport cap). */
    public static final String DIST_CM = "dist_cm";
    /** First-EVER biome visits that day (lifetime-distinct; the lifetime set persists per player). */
    public static final String BIOMES = "biomes";
    /** New chunks entered that day (per-day-distinct, memory-capped). */
    public static final String CHUNKS_NEW = "chunks_new";
    /** Seconds online (1 Hz while online and tracked). */
    public static final String PLAYTIME_S = "playtime_s";
    /**
     * Deepest Y reached, stored as {@code 4096 - blockY} so higher = deeper and the usual
     * "max wins" aggregation works ({@code awards.json deep_diver} uses order max).
     */
    public static final String DEPTH_MIN_Y = "depth_min_y";

    // --- husbandry / trading ---
    /** Animals bred (breeding player credited). */
    public static final String BREED_TOTAL = "breed_total";
    /** Villager/wanderer trades completed. */
    public static final String TRADE_TOTAL = "trade_total";

    // --- altar / economy ---
    /** Offering + milestone deposit value points (secret table — see {@link DepositValues}). */
    public static final String ALTAR_VALUE = "altar_value";
    /** Umbral shards banked at the altar. */
    public static final String SHARDS_BANKED = "shards_banked";

    // --- quests (fed by the questCompleted signal) ---
    /** All quests completed (mains + sides + personals). */
    public static final String QUESTS_DONE = "quests_done";
    /** Main goals completed. */
    public static final String MAINS_DONE = "mains_done";
    /** Side goals completed. */
    public static final String SIDES_DONE = "sides_done";
    /** Personal quests completed. */
    public static final String PERSONALS_DONE = "personals_done";

    // --- dynamic prefixes ---
    /** Per-entity-type kill counters: {@code kill:minecraft:zombie}. */
    public static final String PREFIX_KILL = "kill:";
    /** Per-block-type NATURAL mine counters: {@code mine:minecraft:iron_ore}. */
    public static final String PREFIX_MINE = "mine:";
    /** Per-item-type craft counters (allowlisted ids only): {@code craft:minecraft:bread}. */
    public static final String PREFIX_CRAFT = "craft:";

    /** Every static category id, in documented order (frozen for B6 awards + P5-W4 commands). */
    private static final List<String> CATEGORIES = List.of(
            KILL_TOTAL, DEATH, DMG_DEALT, DMG_TAKEN,
            MINE_TOTAL, PLACE_TOTAL, PLACE_TYPES,
            CRAFT_TOTAL, SMELT_TOTAL,
            DIST_CM, BIOMES, CHUNKS_NEW, PLAYTIME_S, DEPTH_MIN_Y,
            BREED_TOTAL, TRADE_TOTAL,
            ALTAR_VALUE, SHARDS_BANKED,
            QUESTS_DONE, MAINS_DONE, SIDES_DONE, PERSONALS_DONE);

    private static final Set<String> STATIC_KEYS = Set.copyOf(CATEGORIES);

    private static final List<String> DYNAMIC_PREFIXES = List.of(PREFIX_KILL, PREFIX_MINE, PREFIX_CRAFT);

    private AnalyticsKeys() {}

    /** Immutable list of all static category ids (the frozen {@code categories()} surface). */
    public static List<String> categories() {
        return CATEGORIES;
    }

    /** The three dynamic key prefixes ({@code kill:}, {@code mine:}, {@code craft:}). */
    public static List<String> dynamicPrefixes() {
        return DYNAMIC_PREFIXES;
    }

    /** Whether {@code key} is one of the bounded static categories (exempt from the dynamic-key cap). */
    public static boolean isStaticKey(String key) {
        return STATIC_KEYS.contains(key);
    }
}
