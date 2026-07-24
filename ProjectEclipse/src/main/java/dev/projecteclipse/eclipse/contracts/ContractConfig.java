package dev.projecteclipse.eclipse.contracts;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.util.Mth;
import net.neoforged.fml.loading.FMLPaths;

/**
 * Loads {@code config/eclipse/contracts.json} (IDEA-20 §2 odds + §6 ledger knobs). Missing
 * files are generated from the authored defaults below; parse failures fall back to the
 * defaults (the {@code BuffConfig} house pattern). Registered with {@code ReloadHooks} by
 * {@link ContractService} so {@code /dev reload} hot-applies every knob.
 *
 * <p>{@code /dev contract odds|window} mutate the LIVE snapshot only (transient until the
 * next reload/restart) — mirroring {@code /dev xboxevent reward set} semantics.</p>
 */
public final class ContractConfig {

    /** SUCCESS ledger (hunter advantage + target disadvantage, all expiring at rollover). */
    public record SuccessValues(float hunterSkillsMul, int hunterShards, int hunterTempHearts,
            float hunterDamageMul, String hunterGlobalBuffId, int hunterXp,
            float targetSkillsMul, float targetDamageMul) {}

    /** EXPIRY consolation ("survived the hunt"). */
    public record ExpiryValues(int survivorXp, int survivorShards) {}

    /** WRONG_KILL justice pair (Blutschuld for the killer, Vergeltung for the victim). */
    public record WrongKillValues(float killerDamageMul, float killerSkillsMul,
            int victimTempHearts, float victimGrudgeMul) {}

    /** Immutable snapshot of every knob. */
    public record Values(
            boolean autoDaily,
            int realChancePct,
            int prankChancePct,
            int windowMinutes,
            int omenSeconds,
            int windowStartMinMinutes,
            int windowStartMaxMinutes,
            int minOnlineForReal,
            int pairCooldownDays,
            boolean proximityWeighting,
            int ghostKillHits,
            int ghostPayoutPct,
            int prankConsolationShards,
            SuccessValues success,
            ExpiryValues expiry,
            WrongKillValues wrongKill) {}

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final String FILE_NAME = "contracts.json";

    private static volatile Values values = defaults();
    private static volatile Path configDir = FMLPaths.CONFIGDIR.get().resolve("eclipse");

    private ContractConfig() {}

    public static Values get() {
        return values;
    }

    public static void setConfigDirForTests(Path dir) {
        configDir = dir;
        reload();
    }

    /** Live odds override ({@code /dev contract odds <pct>}) — transient until reload. */
    public static void setRealChancePct(int pct) {
        Values v = values;
        values = new Values(v.autoDaily(), Mth.clamp(pct, 0, 100), v.prankChancePct(),
                v.windowMinutes(), v.omenSeconds(), v.windowStartMinMinutes(), v.windowStartMaxMinutes(),
                v.minOnlineForReal(), v.pairCooldownDays(), v.proximityWeighting(), v.ghostKillHits(),
                v.ghostPayoutPct(), v.prankConsolationShards(), v.success(), v.expiry(), v.wrongKill());
    }

    /** Live window override ({@code /dev contract window <minutes>}) — transient until reload. */
    public static void setWindowMinutes(int minutes) {
        Values v = values;
        values = new Values(v.autoDaily(), v.realChancePct(), v.prankChancePct(),
                Mth.clamp(minutes, 1, 1_440), v.omenSeconds(), v.windowStartMinMinutes(),
                v.windowStartMaxMinutes(), v.minOnlineForReal(), v.pairCooldownDays(),
                v.proximityWeighting(), v.ghostKillHits(), v.ghostPayoutPct(),
                v.prankConsolationShards(), v.success(), v.expiry(), v.wrongKill());
    }

    public static void reload() {
        Path file = configDir.resolve(FILE_NAME);
        try {
            Files.createDirectories(configDir);
            if (!Files.isRegularFile(file)) {
                Files.writeString(file, GSON.toJson(defaultJson()), StandardCharsets.UTF_8);
            }
            String json = Files.readString(file, StandardCharsets.UTF_8);
            values = parse(JsonParser.parseString(json).getAsJsonObject());
            EclipseMod.LOGGER.info(
                    "ContractConfig loaded: autoDaily={}, real={}%, prank={}%, window={}m",
                    values.autoDaily(), values.realChancePct(), values.prankChancePct(),
                    values.windowMinutes());
        } catch (Exception e) {
            EclipseMod.LOGGER.error("ContractConfig failed to load {}; using defaults", file, e);
            values = defaults();
        }
    }

    public static Values defaults() {
        return parse(defaultJson());
    }

    /**
     * Authored defaults: the auto-daily roll ships OFF (dev-triggered until the operator
     * arms it); when armed the default odds are 25% REAL / 5% PRANK per day.
     */
    private static JsonObject defaultJson() {
        JsonObject root = new JsonObject();
        root.addProperty("autoDaily", false);
        root.addProperty("realChancePct", 25);
        root.addProperty("prankChancePct", 5);
        root.addProperty("windowMinutes", 30);
        root.addProperty("omenSeconds", 60);
        root.addProperty("windowStartMinMinutes", 30);
        root.addProperty("windowStartMaxMinutes", 240);
        root.addProperty("minOnlineForReal", 4);
        root.addProperty("pairCooldownDays", 3);
        root.addProperty("proximityWeighting", true);
        root.addProperty("ghostKillHits", 3);
        root.addProperty("ghostPayoutPct", 60);
        root.addProperty("prankConsolationShards", 2);

        JsonObject success = new JsonObject();
        success.addProperty("hunterSkillsMul", 1.5F);
        success.addProperty("hunterShards", 12);
        success.addProperty("hunterTempHearts", 1);
        success.addProperty("hunterDamageMul", 1.10F);
        success.addProperty("hunterGlobalBuffId", "");
        success.addProperty("hunterXp", 400);
        success.addProperty("targetSkillsMul", 0.75F);
        success.addProperty("targetDamageMul", 0.85F);
        root.add("success", success);

        JsonObject expiry = new JsonObject();
        expiry.addProperty("survivorXp", 250);
        expiry.addProperty("survivorShards", 4);
        root.add("expiry", expiry);

        JsonObject wrongKill = new JsonObject();
        wrongKill.addProperty("killerDamageMul", 0.80F);
        wrongKill.addProperty("killerSkillsMul", 0.5F);
        wrongKill.addProperty("victimTempHearts", -1);
        wrongKill.addProperty("victimGrudgeMul", 1.35F);
        root.add("wrongKill", wrongKill);
        return root;
    }

    private static Values parse(JsonObject root) {
        JsonObject s = obj(root, "success");
        JsonObject e = obj(root, "expiry");
        JsonObject w = obj(root, "wrongKill");
        return new Values(
                bool(root, "autoDaily", false),
                clampPct(intVal(root, "realChancePct", 25)),
                clampPct(intVal(root, "prankChancePct", 5)),
                Mth.clamp(intVal(root, "windowMinutes", 30), 1, 1_440),
                Mth.clamp(intVal(root, "omenSeconds", 60), 0, 600),
                Math.max(0, intVal(root, "windowStartMinMinutes", 30)),
                Math.max(0, intVal(root, "windowStartMaxMinutes", 240)),
                Math.max(2, intVal(root, "minOnlineForReal", 4)),
                Math.max(0, intVal(root, "pairCooldownDays", 3)),
                bool(root, "proximityWeighting", true),
                Math.max(1, intVal(root, "ghostKillHits", 3)),
                Mth.clamp(intVal(root, "ghostPayoutPct", 60), 0, 100),
                Math.max(0, intVal(root, "prankConsolationShards", 2)),
                new SuccessValues(
                        floatVal(s, "hunterSkillsMul", 1.5F),
                        Math.max(0, intVal(s, "hunterShards", 12)),
                        Mth.clamp(intVal(s, "hunterTempHearts", 1), 0, 2),
                        floatVal(s, "hunterDamageMul", 1.10F),
                        str(s, "hunterGlobalBuffId", ""),
                        Math.max(0, intVal(s, "hunterXp", 400)),
                        floatVal(s, "targetSkillsMul", 0.75F),
                        floatVal(s, "targetDamageMul", 0.85F)),
                new ExpiryValues(
                        Math.max(0, intVal(e, "survivorXp", 250)),
                        Math.max(0, intVal(e, "survivorShards", 4))),
                new WrongKillValues(
                        floatVal(w, "killerDamageMul", 0.80F),
                        floatVal(w, "killerSkillsMul", 0.5F),
                        Mth.clamp(intVal(w, "victimTempHearts", -1), -2, 0),
                        floatVal(w, "victimGrudgeMul", 1.35F)));
    }

    private static int clampPct(int pct) {
        return Mth.clamp(pct, 0, 100);
    }

    private static JsonObject obj(JsonObject root, String key) {
        return root != null && root.has(key) && root.get(key).isJsonObject()
                ? root.getAsJsonObject(key) : new JsonObject();
    }

    private static boolean bool(JsonObject obj, String key, boolean fallback) {
        return obj != null && obj.has(key) ? obj.get(key).getAsBoolean() : fallback;
    }

    private static int intVal(JsonObject obj, String key, int fallback) {
        return obj != null && obj.has(key) ? obj.get(key).getAsInt() : fallback;
    }

    private static float floatVal(JsonObject obj, String key, float fallback) {
        return obj != null && obj.has(key) ? obj.get(key).getAsFloat() : fallback;
    }

    private static String str(JsonObject obj, String key, String fallback) {
        return obj != null && obj.has(key) ? obj.get(key).getAsString() : fallback;
    }
}
