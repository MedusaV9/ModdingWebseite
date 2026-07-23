package dev.projecteclipse.eclipse.progression.goals;

import java.util.ArrayList;
import java.util.List;

/**
 * Registry of goal trigger types (plans_v3 P4 §2.2). Every {@link GoalSpec} names exactly one
 * of these in its {@code trigger.type} field. The enum doubles as the frozen surface P5's
 * reworked goal editor renders its type dropdown from ({@link #ids()} / {@link #byId(String)}
 * / {@link #description()}), so ids are wire/config-stable and MUST NOT be renamed.
 *
 * <p>Detection sources are either {@code core/signal/EclipseSignals} listeners or the single
 * shared 20-tick poll in {@code QuestEngine} — never per-tick scans (P4 rule 6).</p>
 */
public enum TriggerType {
    /** Vanilla stat delta (picked-up vs crafted, whichever is larger) from the assignment baseline. */
    COLLECT_ITEM("collect_item", true, "Collect items (stat delta; target = item id or #tag)"),
    /** {@code itemCrafted} signal. */
    CRAFT_ITEM("craft_item", false, "Craft items (target = item id or #tag)"),
    /** {@code itemSmelted} signal. */
    SMELT_ITEM("smelt_item", false, "Smelt items (target = item id or #tag)"),
    /** {@code mobKilled} signal; target = entity id, #tag or {@code any_hostile}. */
    KILL_ENTITY("kill_entity", false, "Kill entities (target = entity id, #tag or any_hostile)"),
    /** {@code naturalBlockMined} signal (analytics fires it for NATURAL blocks only). */
    MINE_BLOCK("mine_block", false, "Mine natural blocks (target = block id or #tag)"),
    /** {@code blockPlaced} signal; optional target filter. */
    PLACE_BLOCKS("place_blocks", false, "Place blocks (optional target filter)"),
    /** {@code altarDeposit} signal; optional purpose + item filters. */
    DEPOSIT_ALTAR("deposit_altar", false, "Deposit items at the altar (optional purpose/item filter)"),
    /** 20t poll: squared 2D distance to (x, z) within radius, overworld only. */
    VISIT_LOCATION("visit_location", true, "Reach a location (x/z/radius, overworld)"),
    /** {@code biomeVisited} signal; target biome/#tag = visit it once, empty = count distinct. */
    VISIT_BIOMES("visit_biomes", false, "Visit biomes (target = biome/#tag, or count distinct)"),
    /** {@code chunkExplored} signal. */
    EXPLORE_CHUNKS("explore_chunks", false, "Explore new chunks"),
    /** 20t poll on player Y <= trigger.y. */
    REACH_DEPTH("reach_depth", true, "Descend to a Y level (trigger.y)"),
    /** 20t poll: vanilla movement stat sum delta from baseline; count in METERS. */
    TRAVEL_DISTANCE("travel_distance", true, "Travel a distance (count = meters)"),
    /** {@code BabyEntitySpawnEvent} (the one NeoForge event the goal engine owns). */
    BREED_ANIMALS("breed_animals", false, "Breed animals (optional child entity target)"),
    /** 20t poll: generic vanilla stat delta from baseline; statId = "type_id/value_id". */
    STAT_THRESHOLD("stat_threshold", true, "Vanilla stat delta reaches count (trigger.statId)"),
    /** Night-window watcher: full MC night online without taking damage. */
    SURVIVE_NIGHT_NO_DAMAGE("survive_night_no_damage", true, "Survive a whole night without damage"),
    /** {@code skillLevelUp} signal; done when the new level reaches count. */
    SKILL_LEVEL("skill_level", false, "Reach a skill level (count = level)"),
    /**
     * No detector: completed via {@code /eclipse goals tick}, {@code /eclipse-quests tick} or a
     * team beat ({@code trigger.beatId}) fired by {@code QuestApi.completeTeamBeat} / the
     * engine's built-in world-state beat watchers (see {@code QuestEngine#pollBeats}).
     */
    MANUAL("manual", false, "Manual / admin tick, or trigger.beatId team beat");

    private final String id;
    private final boolean polled;
    private final String description;

    TriggerType(String id, boolean polled, String description) {
        this.id = id;
        this.polled = polled;
        this.description = description;
    }

    /** Stable config/JSON id ({@code goals.json} {@code trigger.type}). */
    public String id() {
        return id;
    }

    /** Whether progress is (re)computed in the shared 20-tick poll rather than signal-pushed. */
    public boolean polled() {
        return polled;
    }

    /** One-line editor tooltip (English; the editor GUI localizes labels itself). */
    public String description() {
        return description;
    }

    /** All registered trigger ids in declaration order — the goal editor's dropdown source. */
    public static List<String> ids() {
        List<String> ids = new ArrayList<>(values().length);
        for (TriggerType type : values()) {
            ids.add(type.id);
        }
        return List.copyOf(ids);
    }

    /** Resolves a config id; unknown ids fall back to {@link #MANUAL} (never crash on config). */
    public static TriggerType byId(String id) {
        for (TriggerType type : values()) {
            if (type.id.equals(id)) {
                return type;
            }
        }
        return MANUAL;
    }

    /** Strict lookup for {@code GoalConfig.validateAndNormalize}; null when unknown. */
    public static TriggerType byIdStrict(String id) {
        for (TriggerType type : values()) {
            if (type.id.equals(id)) {
                return type;
            }
        }
        return null;
    }
}
