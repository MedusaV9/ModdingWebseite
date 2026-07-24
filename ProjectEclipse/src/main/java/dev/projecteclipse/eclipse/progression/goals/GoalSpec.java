package dev.projecteclipse.eclipse.progression.goals;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;

import dev.projecteclipse.eclipse.core.config.Localized;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;

/**
 * One authored goal/quest entry (plans_v3 P4 §2.2 schema), parsed from {@code goals.json}
 * (mains + sides per day) or {@code quests.json} (personal pool). Immutable; equality is by
 * {@link #id()} within one config generation.
 *
 * <p>Implements {@link EclipseSignals.QuestSpecRef} so the {@code questCompleted} signal can
 * carry the spec without coupling the signal layer to this schema. Downstream consumers
 * (skills reward XP — see {@code docs/plans_v3/wiring/P4-B2_wiring.md}) may cast the ref back
 * to {@code GoalSpec} to read {@link #reward()}.</p>
 */
public final class GoalSpec implements EclipseSignals.QuestSpecRef {
    /** Goal kind; the byte codes match {@code S2CQuestStatePayload.QuestEntry.kind}. */
    public enum Kind {
        MAIN("main", (byte) 0),
        SIDE("side", (byte) 1),
        PERSONAL("personal", (byte) 2);

        private final String id;
        private final byte wire;

        Kind(String id, byte wire) {
            this.id = id;
            this.wire = wire;
        }

        public String id() {
            return id;
        }

        public byte wire() {
            return wire;
        }

        public static Kind byId(String id) {
            for (Kind kind : values()) {
                if (kind.id.equals(id)) {
                    return kind;
                }
            }
            return MAIN;
        }
    }

    /** Completion scope (§2.2): per player, one shared team counter, or every online player. */
    public enum Scope {
        EACH_PLAYER("each_player"),
        TEAM_TOTAL("team_total"),
        TEAM_ALL("team_all");

        private final String id;

        Scope(String id) {
            this.id = id;
        }

        public String id() {
            return id;
        }

        public boolean team() {
            return this != EACH_PLAYER;
        }

        public static Scope byId(String id) {
            for (Scope scope : values()) {
                if (scope.id.equals(id)) {
                    return scope;
                }
            }
            return EACH_PLAYER;
        }
    }

    /**
     * Trigger condition. Only the fields relevant to {@link #type} are meaningful; the rest
     * keep their defaults (schema §2.2 — one flat object so the editor round-trips cleanly).
     *
     * @param type        registered trigger type
     * @param target      item/block/entity/biome id or {@code #tag}; {@code any_hostile} for kills;
     *                    empty = any (where the type supports it)
     * @param count       completion target (>= 1); meters for travel, level for skill_level
     * @param naturalOnly mine_block only (the fan-out signal is already natural-only; kept for schema)
     * @param x           visit_location center X
     * @param z           visit_location center Z
     * @param radius      visit_location radius in blocks
     * @param y           reach_depth Y level (inclusive, "at or below")
     * @param statId      stat_threshold: {@code <stat_type_id>/<value_id>} or bare custom stat id
     * @param beatId      manual only: team beat id completing this goal (e.g. {@code herald_summoned},
     *                    {@code altar_level_4}, {@code shard_pool_32}, {@code all_hearts_4})
     * @param purpose     deposit_altar only: {@code MILESTONE} / {@code OFFERING} / {@code SHARD_BANK};
     *                    empty = any purpose
     */
    public record Trigger(TriggerType type, String target, long count, boolean naturalOnly,
            int x, int z, int radius, int y, String statId, String beatId, String purpose) {

        public Trigger {
            target = target == null ? "" : target;
            count = Math.max(1L, count);
            radius = Math.max(0, radius);
            statId = statId == null ? "" : statId;
            beatId = beatId == null ? "" : beatId;
            purpose = purpose == null ? "" : purpose.toUpperCase(Locale.ROOT);
        }

        public static Trigger manual() {
            return new Trigger(TriggerType.MANUAL, "", 1L, true, 0, 0, 0, 0, "", "", "");
        }
    }

    /** One reward item stack ({@code reward.items[]} entry). */
    public record ItemReward(String id, int count) {
        public ItemReward {
            id = id == null ? "" : id;
            count = Math.max(1, count);
        }
    }

    /**
     * Completion reward. {@code skillXp} is granted by the skills system from the
     * {@code questCompleted} signal (B2 fires, B4 grants — see wiring doc); shards and items
     * are granted directly by {@code QuestEngine} to every credited online player.
     */
    public record Reward(int skillXp, int shards, List<ItemReward> items) {
        public static final Reward NONE = new Reward(0, 0, List.of());

        public Reward {
            skillXp = Math.max(0, skillXp);
            shards = Math.max(0, shards);
            items = items == null ? List.of() : List.copyOf(items);
        }

        public boolean isEmpty() {
            return skillXp == 0 && shards == 0 && items.isEmpty();
        }
    }

    private final String id;
    private final Kind kind;
    private final Scope scope;
    private final Trigger trigger;
    private final Reward reward;
    private final Localized text;
    private final int weight;
    private final int minDay;
    private final int maxDay;

    public GoalSpec(String id, Kind kind, Scope scope, Trigger trigger, Reward reward,
            Localized text, int weight, int minDay, int maxDay) {
        this.id = id == null || id.isBlank() ? "goal" : id;
        this.kind = kind == null ? Kind.MAIN : kind;
        this.scope = scope == null ? Scope.EACH_PLAYER : scope;
        this.trigger = trigger == null ? Trigger.manual() : trigger;
        this.reward = reward == null ? Reward.NONE : reward;
        this.text = text == null ? Localized.of("") : text;
        this.weight = Math.max(0, weight);
        this.minDay = Math.max(0, minDay);
        this.maxDay = Math.max(0, maxDay);
    }

    // --- EclipseSignals.QuestSpecRef ---

    @Override
    public String id() {
        return id;
    }

    /** Wire byte 0 main / 1 side / 2 personal (see {@link Kind#wire()}). */
    @Override
    public byte kind() {
        return kind.wire();
    }

    // --- accessors ---

    public Kind goalKind() {
        return kind;
    }

    public Scope scope() {
        return scope;
    }

    public Trigger trigger() {
        return trigger;
    }

    public Reward reward() {
        return reward;
    }

    public Localized text() {
        return text;
    }

    /** Personal-pool draw weight (>= 0; 0 = never drawn). */
    public int weight() {
        return weight;
    }

    /** Personal only: earliest day this quest may be drawn (0 = any). */
    public int minDay() {
        return minDay;
    }

    /** Personal only: latest day this quest may be drawn (0 = any). */
    public int maxDay() {
        return maxDay;
    }

    /** Whether the personal quest is drawable on {@code day} (window check only). */
    public boolean inDayWindow(int day) {
        return (minDay == 0 || day >= minDay) && (maxDay == 0 || day <= maxDay);
    }

    /** Completion target for progress bars ({@code trigger.count}, >= 1). */
    public long target() {
        return trigger.count();
    }

    // --- JSON ---

    /**
     * Lenient parser used by {@code GoalConfig} loading (unknown fields ignored, unknown enum
     * ids fall back). Use {@code GoalConfig.validateAndNormalize} for the strict editor path.
     */
    public static GoalSpec fromJson(JsonObject obj, Kind defaultKind) {
        Kind kind = obj.has("kind") ? Kind.byId(obj.get("kind").getAsString()) : defaultKind;
        Scope scope = obj.has("scope") ? Scope.byId(obj.get("scope").getAsString()) : Scope.EACH_PLAYER;

        Trigger trigger = Trigger.manual();
        if (obj.has("trigger") && obj.get("trigger").isJsonObject()) {
            JsonObject t = obj.getAsJsonObject("trigger");
            trigger = new Trigger(
                    TriggerType.byId(t.has("type") ? t.get("type").getAsString() : "manual"),
                    t.has("target") ? t.get("target").getAsString() : "",
                    t.has("count") ? t.get("count").getAsLong() : 1L,
                    !t.has("naturalOnly") || t.get("naturalOnly").getAsBoolean(),
                    t.has("x") ? t.get("x").getAsInt() : 0,
                    t.has("z") ? t.get("z").getAsInt() : 0,
                    t.has("radius") ? t.get("radius").getAsInt() : 0,
                    t.has("y") ? t.get("y").getAsInt() : 0,
                    t.has("statId") ? t.get("statId").getAsString() : "",
                    t.has("beatId") ? t.get("beatId").getAsString() : "",
                    t.has("purpose") ? t.get("purpose").getAsString() : "");
        }

        Reward reward = Reward.NONE;
        if (obj.has("reward") && obj.get("reward").isJsonObject()) {
            JsonObject r = obj.getAsJsonObject("reward");
            List<ItemReward> items = new ArrayList<>();
            if (r.has("items") && r.get("items").isJsonArray()) {
                for (JsonElement element : r.getAsJsonArray("items")) {
                    JsonObject item = element.getAsJsonObject();
                    items.add(new ItemReward(
                            item.has("id") ? item.get("id").getAsString() : "",
                            item.has("count") ? item.get("count").getAsInt() : 1));
                }
            }
            reward = new Reward(
                    r.has("skillXp") ? r.get("skillXp").getAsInt() : 0,
                    r.has("shards") ? r.get("shards").getAsInt() : 0,
                    items);
        }

        return new GoalSpec(
                obj.has("id") ? obj.get("id").getAsString() : "goal",
                kind, scope, trigger, reward,
                obj.has("text") ? Localized.parse(obj.get("text")) : Localized.of(""),
                obj.has("weight") ? obj.get("weight").getAsInt() : 1,
                obj.has("minDay") ? obj.get("minDay").getAsInt() : 0,
                obj.has("maxDay") ? obj.get("maxDay").getAsInt() : 0);
    }

    /** Normalized JSON form (stable field order; defaults omitted where legal). */
    public JsonObject toJson() {
        JsonObject obj = new JsonObject();
        obj.addProperty("id", id);
        obj.addProperty("kind", kind.id());
        obj.addProperty("scope", scope.id());

        JsonObject t = new JsonObject();
        t.addProperty("type", trigger.type().id());
        if (!trigger.target().isEmpty()) {
            t.addProperty("target", trigger.target());
        }
        t.addProperty("count", trigger.count());
        if (trigger.type() == TriggerType.MINE_BLOCK && !trigger.naturalOnly()) {
            t.addProperty("naturalOnly", false);
        }
        if (trigger.type() == TriggerType.VISIT_LOCATION) {
            t.addProperty("x", trigger.x());
            t.addProperty("z", trigger.z());
            t.addProperty("radius", trigger.radius());
        }
        if (trigger.type() == TriggerType.REACH_DEPTH) {
            t.addProperty("y", trigger.y());
        }
        if (!trigger.statId().isEmpty()) {
            t.addProperty("statId", trigger.statId());
        }
        if (!trigger.beatId().isEmpty()) {
            t.addProperty("beatId", trigger.beatId());
        }
        if (!trigger.purpose().isEmpty()) {
            t.addProperty("purpose", trigger.purpose());
        }
        obj.add("trigger", t);

        if (!reward.isEmpty()) {
            JsonObject r = new JsonObject();
            if (reward.skillXp() > 0) {
                r.addProperty("skillXp", reward.skillXp());
            }
            if (reward.shards() > 0) {
                r.addProperty("shards", reward.shards());
            }
            if (!reward.items().isEmpty()) {
                JsonArray items = new JsonArray();
                for (ItemReward item : reward.items()) {
                    JsonObject entry = new JsonObject();
                    entry.addProperty("id", item.id());
                    entry.addProperty("count", item.count());
                    items.add(entry);
                }
                r.add("items", items);
            }
            obj.add("reward", r);
        }

        obj.add("text", text.toJsonElement());
        if (kind == Kind.PERSONAL) {
            obj.addProperty("weight", weight);
            if (minDay > 0) {
                obj.addProperty("minDay", minDay);
            }
            if (maxDay > 0) {
                obj.addProperty("maxDay", maxDay);
            }
        }
        return obj;
    }

    @Override
    public String toString() {
        return "GoalSpec[" + id + " " + kind.id() + "/" + scope.id() + " " + trigger.type().id()
                + " x" + trigger.count() + "]";
    }
}
