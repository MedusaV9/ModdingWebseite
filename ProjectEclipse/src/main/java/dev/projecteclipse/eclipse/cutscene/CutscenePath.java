package dev.projecteclipse.eclipse.cutscene;

import java.util.ArrayList;
import java.util.List;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

/**
 * One camera path of the cutscene engine, the in-memory form of
 * {@code config/eclipse/cutscenes/<id>.json} (schema from {@code docs/ideas/05_systems.md}
 * §1). Dist-neutral and immutable: the server loads/saves/edits these through
 * {@link CutscenePaths}, the client parses the same JSON strings out of
 * {@code S2CCutsceneLibraryPayload} and evaluates them per render frame.
 *
 * <p>Field semantics:</p>
 * <ul>
 *   <li>{@code interpolation} — {@code "catmullrom"} (default; the camera flows through the
 *       keyframes) or {@code "bezier"} (segment-local cubic with damped tangents; the camera
 *       settles at every keyframe).</li>
 *   <li>{@code anchor} — {@code "world"}: keyframe positions are absolute block coordinates,
 *       or offsets from the per-play anchor position when the play payload carries one;
 *       {@code "player"}: keyframe positions are offsets from the watching player's feet at
 *       cutscene start, rotated by the player's yaw ({@code yaw} keyframe values are relative
 *       to the player's yaw too, so a final keyframe of {@code pos [0, 1.62, 0], yaw 0,
 *       pitch 0} hands the camera back seamlessly).</li>
 *   <li>{@code t} of keyframes/events — normalized 0..1 over {@code durationTicks}.</li>
 *   <li>{@code easing} — per-keyframe easing of the segment LEAVING that keyframe
 *       (camelCase names mapped onto Veil's {@code Easing} enum, e.g.
 *       {@code "easeInOutCubic"}; unknown names fall back to linear).</li>
 *   <li>{@code enabled} — config-level default switch. The world-scoped runtime toggle is
 *       {@code EclipseWorldState.disabledCutscenes} (see {@code /eclipse cutscene
 *       enable|disable}).</li>
 *   <li>{@code params} — free-form passthrough object (e.g. the {@code unlock_ring}
 *       template's orbit metadata); preserved verbatim on save.</li>
 * </ul>
 */
public record CutscenePath(
        String id,
        boolean enabled,
        boolean allowSkip,
        String interpolation,
        String anchor,
        String dimension,
        boolean letterbox,
        boolean hideHud,
        int durationTicks,
        List<Keyframe> keyframes,
        List<PathEvent> events,
        JsonObject params) {

    public static final String ANCHOR_WORLD = "world";
    public static final String ANCHOR_PLAYER = "player";
    public static final String INTERPOLATION_CATMULLROM = "catmullrom";
    public static final String INTERPOLATION_BEZIER = "bezier";

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();

    /** One camera keyframe: normalized time, position, orientation, fov and segment easing. */
    public record Keyframe(double t, double x, double y, double z,
            float yaw, float pitch, float roll, float fov, String easing) {}

    /** One timed side effect, e.g. {@code {"t": 0.9, "type": "sound", "id": "eclipse:event.emerge"}}. */
    public record PathEvent(double t, String type, String id) {}

    public CutscenePath {
        keyframes = List.copyOf(keyframes);
        events = List.copyOf(events);
        params = params == null ? new JsonObject() : params;
    }

    /** Whether keyframe positions/yaws are relative to the watching player (see class javadoc). */
    public boolean isPlayerAnchored() {
        return ANCHOR_PLAYER.equals(this.anchor);
    }

    // --- wither helpers for the editor commands ---

    public CutscenePath withKeyframes(List<Keyframe> newKeyframes) {
        return new CutscenePath(this.id, this.enabled, this.allowSkip, this.interpolation, this.anchor,
                this.dimension, this.letterbox, this.hideHud, this.durationTicks, newKeyframes,
                this.events, this.params);
    }

    public CutscenePath withAllowSkip(boolean newAllowSkip) {
        return new CutscenePath(this.id, this.enabled, newAllowSkip, this.interpolation, this.anchor,
                this.dimension, this.letterbox, this.hideHud, this.durationTicks, this.keyframes,
                this.events, this.params);
    }

    public CutscenePath withEnabled(boolean newEnabled) {
        return new CutscenePath(this.id, newEnabled, this.allowSkip, this.interpolation, this.anchor,
                this.dimension, this.letterbox, this.hideHud, this.durationTicks, this.keyframes,
                this.events, this.params);
    }

    // --- JSON ---

    /**
     * Parses one path JSON document. {@code fallbackId} (usually the file name) is used when
     * the document carries no {@code "id"}. Throws {@link RuntimeException} subclasses on
     * malformed documents — callers log and skip the file.
     */
    public static CutscenePath parse(String fallbackId, String json) {
        JsonObject obj = JsonParser.parseString(json).getAsJsonObject();
        String id = obj.has("id") ? obj.get("id").getAsString() : fallbackId;
        List<Keyframe> keyframes = new ArrayList<>();
        if (obj.has("keyframes")) {
            for (JsonElement element : obj.getAsJsonArray("keyframes")) {
                JsonObject kf = element.getAsJsonObject();
                JsonArray pos = kf.getAsJsonArray("pos");
                keyframes.add(new Keyframe(
                        kf.get("t").getAsDouble(),
                        pos.get(0).getAsDouble(), pos.get(1).getAsDouble(), pos.get(2).getAsDouble(),
                        kf.has("yaw") ? kf.get("yaw").getAsFloat() : 0.0F,
                        kf.has("pitch") ? kf.get("pitch").getAsFloat() : 0.0F,
                        kf.has("roll") ? kf.get("roll").getAsFloat() : 0.0F,
                        kf.has("fov") ? kf.get("fov").getAsFloat() : 70.0F,
                        kf.has("easing") ? kf.get("easing").getAsString() : "linear"));
            }
        }
        keyframes.sort(java.util.Comparator.comparingDouble(Keyframe::t));
        List<PathEvent> events = new ArrayList<>();
        if (obj.has("events")) {
            for (JsonElement element : obj.getAsJsonArray("events")) {
                JsonObject event = element.getAsJsonObject();
                events.add(new PathEvent(
                        event.get("t").getAsDouble(),
                        event.has("type") ? event.get("type").getAsString() : "sound",
                        event.has("id") ? event.get("id").getAsString() : ""));
            }
        }
        return new CutscenePath(
                id,
                !obj.has("enabled") || obj.get("enabled").getAsBoolean(),
                obj.has("allowSkip") && obj.get("allowSkip").getAsBoolean(),
                obj.has("interpolation") ? obj.get("interpolation").getAsString() : INTERPOLATION_CATMULLROM,
                obj.has("anchor") ? obj.get("anchor").getAsString() : ANCHOR_WORLD,
                obj.has("dimension") ? obj.get("dimension").getAsString() : "minecraft:overworld",
                !obj.has("letterbox") || obj.get("letterbox").getAsBoolean(),
                !obj.has("hideHud") || obj.get("hideHud").getAsBoolean(),
                obj.has("durationTicks") ? obj.get("durationTicks").getAsInt() : 100,
                keyframes,
                events,
                obj.has("params") ? obj.getAsJsonObject("params") : new JsonObject());
    }

    public JsonObject toJson() {
        JsonObject obj = new JsonObject();
        obj.addProperty("id", this.id);
        obj.addProperty("enabled", this.enabled);
        obj.addProperty("allowSkip", this.allowSkip);
        obj.addProperty("interpolation", this.interpolation);
        obj.addProperty("anchor", this.anchor);
        obj.addProperty("dimension", this.dimension);
        obj.addProperty("letterbox", this.letterbox);
        obj.addProperty("hideHud", this.hideHud);
        obj.addProperty("durationTicks", this.durationTicks);
        JsonArray keyframeArray = new JsonArray(this.keyframes.size());
        for (Keyframe kf : this.keyframes) {
            JsonObject kfObj = new JsonObject();
            kfObj.addProperty("t", kf.t());
            JsonArray pos = new JsonArray(3);
            pos.add(kf.x());
            pos.add(kf.y());
            pos.add(kf.z());
            kfObj.add("pos", pos);
            kfObj.addProperty("yaw", kf.yaw());
            kfObj.addProperty("pitch", kf.pitch());
            kfObj.addProperty("roll", kf.roll());
            kfObj.addProperty("fov", kf.fov());
            kfObj.addProperty("easing", kf.easing());
            keyframeArray.add(kfObj);
        }
        obj.add("keyframes", keyframeArray);
        JsonArray eventArray = new JsonArray(this.events.size());
        for (PathEvent event : this.events) {
            JsonObject eventObj = new JsonObject();
            eventObj.addProperty("t", event.t());
            eventObj.addProperty("type", event.type());
            eventObj.addProperty("id", event.id());
            eventArray.add(eventObj);
        }
        obj.add("events", eventArray);
        if (this.params.size() > 0) {
            obj.add("params", this.params);
        }
        return obj;
    }

    /** Pretty-printed JSON document, as written to disk and printed by {@code export}. */
    public String toJsonString() {
        return GSON.toJson(toJson());
    }
}
