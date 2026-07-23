package dev.projecteclipse.eclipse.devtools;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashSet;
import java.util.Set;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.cutscene.CutsceneService;
import dev.projecteclipse.eclipse.network.C2SConfigEditPayload;
import dev.projecteclipse.eclipse.network.S2CDayStatePayload;
import dev.projecteclipse.eclipse.network.S2CGoalProgressPayload;
import dev.projecteclipse.eclipse.network.S2CMilestonesPayload;
import dev.projecteclipse.eclipse.network.S2COpenGoalEditorPayload;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Server side of the W14 goal editor: {@code /eclipse goals edit} calls {@link #openFor}
 * (sends the CURRENT day plans as JSON in {@link S2COpenGoalEditorPayload}); the client's
 * {@code devtools.client.GoalEditorScreen} answers with {@link C2SConfigEditPayload}, handled
 * by {@link #handleEdit}.
 *
 * <p><b>Trust boundary</b>: the payload is untrusted client input. {@link #handleEdit}
 * requires {@code hasPermissions(3)} (same level as the {@code /eclipse} tree), allowlists
 * the file name ({@code days.json} / {@code milestones.json}), rejects &gt;
 * {@value C2SConfigEditPayload#MAX_JSON_BYTES}-byte payloads, and re-validates + NORMALIZES
 * the JSON against the {@code EclipseConfig} schema (day/goals bounds, ≤ 8 goals per day —
 * the {@code GoalTracker} bitmask limit — unique days) so a malformed edit can never leave
 * a {@code days.json} on disk that {@code EclipseConfig.reload} would refuse. The editor GUI
 * does not edit the hand-written {@code title}/{@code subtitle} announcement lines, so
 * normalization preserves the CURRENT config's lines whenever the payload omits them (a
 * save must never strip them); the deprecated {@code borderSize} is neither sent nor
 * written, matching {@code EclipseConfig.daysToJson}. On success: write,
 * {@code EclipseConfig.reload()}, re-broadcast day state + milestones + per-player goal
 * progress (the same sync set as {@code /eclipse reload}).</p>
 */
public final class ConfigEditor {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    /** {@code GoalTracker} tracks per-day completion in one byte — hard cap per day. */
    private static final int MAX_GOALS_PER_DAY = 8;
    private static final int MAX_DAYS = 64;

    private ConfigEditor() {}

    // --- open (server -> client) ---

    /** Sends the current day plans (as canonical {@code days.json} JSON) to open the editor. */
    public static void openFor(ServerPlayer player) {
        PacketDistributor.sendToPlayer(player, new S2COpenGoalEditorPayload(currentDaysJson()));
        EclipseMod.LOGGER.info("ConfigEditor: goal editor opened for {}", player.getScoreboardName());
    }

    /** The in-memory day plans re-serialized in the exact {@code days.json} shape. */
    private static String currentDaysJson() {
        JsonArray array = new JsonArray();
        for (EclipseConfig.DayPlan plan : EclipseConfig.days()) {
            JsonObject obj = new JsonObject();
            obj.addProperty("day", plan.day());
            JsonArray goals = new JsonArray();
            plan.goals().forEach(goals::add);
            obj.add("goals", goals);
            JsonArray unlocks = new JsonArray();
            plan.unlocks().forEach(unlocks::add);
            obj.add("unlocks", unlocks);
            // title/subtitle mirror EclipseConfig.daysToJson (written when non-empty) so a
            // round-trip never loses the hand-written announcement lines; the deprecated
            // borderSize is deliberately NOT written (daysToJson omits it too).
            if (!plan.title().isEmpty()) {
                obj.addProperty("title", plan.title());
            }
            if (!plan.subtitle().isEmpty()) {
                obj.addProperty("subtitle", plan.subtitle());
            }
            array.add(obj);
        }
        return GSON.toJson(array);
    }

    // --- edit (client -> server) ---

    /** Perm-checked, validated {@code config/eclipse/<file>} write + reload + re-broadcast. */
    public static void handleEdit(C2SConfigEditPayload payload, ServerPlayer player) {
        if (!player.hasPermissions(3)) {
            EclipseMod.LOGGER.warn("ConfigEditor: REJECTED config edit of '{}' from {} — permission level 3 required",
                    payload.fileName(), player.getScoreboardName());
            player.sendSystemMessage(Component.translatable("message.eclipse.goals_denied"));
            return;
        }
        if (payload.json().getBytes(StandardCharsets.UTF_8).length > C2SConfigEditPayload.MAX_JSON_BYTES) {
            fail(player, payload.fileName(), "payload exceeds " + C2SConfigEditPayload.MAX_JSON_BYTES + " bytes");
            return;
        }
        JsonElement normalized;
        try {
            normalized = switch (payload.fileName()) {
                case "days.json" -> normalizeDays(JsonParser.parseString(payload.json()));
                case "milestones.json" -> normalizeMilestones(JsonParser.parseString(payload.json()));
                default -> throw new IllegalArgumentException(
                        "file '" + payload.fileName() + "' is not editable (days.json|milestones.json)");
            };
        } catch (RuntimeException e) {
            fail(player, payload.fileName(), e.getMessage());
            return;
        }

        Path file = FMLPaths.CONFIGDIR.get().resolve("eclipse").resolve(payload.fileName());
        try {
            Files.createDirectories(file.getParent());
            Files.writeString(file, GSON.toJson(normalized), StandardCharsets.UTF_8);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("ConfigEditor: failed to write {}", file, e);
            fail(player, payload.fileName(), "write failed: " + e.getMessage());
            return;
        }

        EclipseConfig.reload();
        broadcastConfigState(player.server);
        EclipseMod.LOGGER.info("ConfigEditor: {} wrote {} ({} bytes) — config reloaded and re-synced",
                player.getScoreboardName(), file, payload.json().length());
        player.sendSystemMessage(Component.translatable("message.eclipse.goals_updated", payload.fileName()));
    }

    private static void fail(ServerPlayer player, String fileName, String reason) {
        EclipseMod.LOGGER.warn("ConfigEditor: rejected edit of '{}' from {}: {}",
                fileName, player.getScoreboardName(), reason);
        player.sendSystemMessage(Component.translatable("message.eclipse.goals_invalid", reason));
    }

    /** The {@code /eclipse reload} sync set: day state + milestones + per-player goal progress. */
    private static void broadcastConfigState(MinecraftServer server) {
        EclipseWorldState state = EclipseWorldState.get(server);
        PacketDistributor.sendToAllPlayers(new S2CDayStatePayload(state.getDay(), state.getAltarLevel(),
                EclipseConfig.day(state.getDay()).goals()));
        PacketDistributor.sendToAllPlayers(S2CMilestonesPayload.current());
        for (ServerPlayer online : server.getPlayerList().getPlayers()) {
            PacketDistributor.sendToPlayer(online, S2CGoalProgressPayload.currentFor(online));
        }
        CutsceneService.syncLibraryToAll(server); // parity with /eclipse reload (paths unchanged but cheap)
    }

    // --- schema validation / normalization ---

    /**
     * Validates a {@code days.json} candidate and returns a NORMALIZED array (sorted by day)
     * that {@code EclipseConfig.daysFromJson} is guaranteed to load. Payloads without
     * {@code title}/{@code subtitle} (the goal-editor GUI never round-trips them) inherit
     * the CURRENT config's lines for that day, so a goal edit can never strip the
     * hand-written announcement lines. The deprecated {@code borderSize} is dropped
     * (never written), matching {@code EclipseConfig.daysToJson}.
     *
     * @throws IllegalArgumentException with a human-readable reason
     */
    static JsonArray normalizeDays(JsonElement root) {
        if (!root.isJsonArray() || root.getAsJsonArray().isEmpty()) {
            throw new IllegalArgumentException("days.json must be a non-empty array of day objects");
        }
        JsonArray in = root.getAsJsonArray();
        if (in.size() > MAX_DAYS) {
            throw new IllegalArgumentException("too many day entries (" + in.size() + " > " + MAX_DAYS + ")");
        }
        JsonArray out = new JsonArray(in.size());
        Set<Integer> seenDays = new HashSet<>();
        for (JsonElement element : in) {
            if (!element.isJsonObject()) {
                throw new IllegalArgumentException("day entries must be objects");
            }
            JsonObject obj = element.getAsJsonObject();
            int day = requireInt(obj, "day");
            if (day < 1 || !seenDays.add(day)) {
                throw new IllegalArgumentException("day " + day + " is " + (day < 1 ? "< 1" : "duplicated"));
            }
            JsonArray goals = requireStringArray(obj, "goals", true);
            if (goals.size() > MAX_GOALS_PER_DAY) {
                throw new IllegalArgumentException("day " + day + " has " + goals.size()
                        + " goals (max " + MAX_GOALS_PER_DAY + " — GoalTracker bitmask)");
            }
            JsonArray unlocks = obj.has("unlocks") ? requireStringArray(obj, "unlocks", true) : new JsonArray();
            String title = obj.has("title") ? requireString(obj, "title") : fallbackTitle(day, true);
            String subtitle = obj.has("subtitle") ? requireString(obj, "subtitle") : fallbackTitle(day, false);

            JsonObject normalized = new JsonObject();
            normalized.addProperty("day", day);
            normalized.add("goals", goals);
            normalized.add("unlocks", unlocks);
            if (!title.isEmpty()) {
                normalized.addProperty("title", title);
            }
            if (!subtitle.isEmpty()) {
                normalized.addProperty("subtitle", subtitle);
            }
            out.add(normalized);
        }
        return sortByIntKey(out, "day");
    }

    /** Validates a {@code milestones.json} candidate; same normalization contract as days. */
    static JsonArray normalizeMilestones(JsonElement root) {
        if (!root.isJsonArray()) {
            throw new IllegalArgumentException("milestones.json must be an array of milestone objects");
        }
        JsonArray in = root.getAsJsonArray();
        JsonArray out = new JsonArray(in.size());
        Set<Integer> seenLevels = new HashSet<>();
        for (JsonElement element : in) {
            if (!element.isJsonObject()) {
                throw new IllegalArgumentException("milestone entries must be objects");
            }
            JsonObject obj = element.getAsJsonObject();
            int level = requireInt(obj, "level");
            if (level < 1 || !seenLevels.add(level)) {
                throw new IllegalArgumentException("level " + level + " is " + (level < 1 ? "< 1" : "duplicated"));
            }
            if (!obj.has("cost") || !obj.get("cost").isJsonArray()) {
                throw new IllegalArgumentException("level " + level + " is missing its cost array");
            }
            JsonArray cost = new JsonArray();
            for (JsonElement costElement : obj.getAsJsonArray("cost")) {
                if (!costElement.isJsonObject()) {
                    throw new IllegalArgumentException("level " + level + " cost entries must be objects");
                }
                JsonObject costObj = costElement.getAsJsonObject();
                String item = requireString(costObj, "item");
                int count = requireInt(costObj, "count");
                if (item.isBlank() || count < 1) {
                    throw new IllegalArgumentException("level " + level + " has a blank item or count < 1");
                }
                JsonObject normalizedCost = new JsonObject();
                normalizedCost.addProperty("item", item);
                normalizedCost.addProperty("count", count);
                cost.add(normalizedCost);
            }
            JsonArray rewards = obj.has("rewards") ? requireStringArray(obj, "rewards", true) : new JsonArray();

            JsonObject normalized = new JsonObject();
            normalized.addProperty("level", level);
            normalized.add("cost", cost);
            normalized.add("rewards", rewards);
            out.add(normalized);
        }
        return sortByIntKey(out, "level");
    }

    /**
     * The CURRENT config's title/subtitle for EXACTLY that day ({@code ""} for new days) —
     * {@code EclipseConfig.day} is not used directly because it falls back to a neighbor
     * plan for unmatched days, which would copy another day's announcement lines.
     */
    private static String fallbackTitle(int day, boolean title) {
        for (EclipseConfig.DayPlan plan : EclipseConfig.days()) {
            if (plan.day() == day) {
                return title ? plan.title() : plan.subtitle();
            }
        }
        return "";
    }

    private static int requireInt(JsonObject obj, String key) {
        if (!obj.has(key) || !obj.get(key).isJsonPrimitive() || !obj.getAsJsonPrimitive(key).isNumber()) {
            throw new IllegalArgumentException("missing/non-numeric '" + key + "'");
        }
        return obj.get(key).getAsInt();
    }

    private static String requireString(JsonObject obj, String key) {
        if (!obj.has(key) || !obj.get(key).isJsonPrimitive() || !obj.getAsJsonPrimitive(key).isString()) {
            throw new IllegalArgumentException("missing/non-string '" + key + "'");
        }
        return obj.get(key).getAsString();
    }

    /** Requires an array of strings; {@code stripBlank} drops empty/whitespace-only lines. */
    private static JsonArray requireStringArray(JsonObject obj, String key, boolean stripBlank) {
        if (!obj.has(key) || !obj.get(key).isJsonArray()) {
            throw new IllegalArgumentException("missing/non-array '" + key + "'");
        }
        JsonArray result = new JsonArray();
        for (JsonElement element : obj.getAsJsonArray(key)) {
            if (!element.isJsonPrimitive() || !element.getAsJsonPrimitive().isString()) {
                throw new IllegalArgumentException("'" + key + "' entries must be strings");
            }
            String value = element.getAsString();
            if (!stripBlank || !value.isBlank()) {
                result.add(value.trim());
            }
        }
        return result;
    }

    private static JsonArray sortByIntKey(JsonArray array, String key) {
        java.util.List<JsonElement> elements = new java.util.ArrayList<>(array.asList());
        elements.sort(java.util.Comparator.comparingInt(element -> element.getAsJsonObject().get(key).getAsInt()));
        JsonArray sorted = new JsonArray(elements.size());
        elements.forEach(sorted::add);
        return sorted;
    }
}
