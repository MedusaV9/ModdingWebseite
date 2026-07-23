package dev.projecteclipse.eclipse.skills;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.tags.TagKey;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.block.state.BlockState;
import net.neoforged.fml.loading.FMLPaths;

/**
 * Loader for {@code config/eclipse/skills.json} (R3, plan §2.3): curve knobs, proc feedback,
 * the FULL per-action XP earn table and per-source daily soft caps. Defaults are written on
 * first run ({@code EclipseConfig.loadOrCreate} pattern); hot-reload rides
 * {@code ReloadHooks} (registered by {@link SkillService}). A missing runtime file is generated
 * from the fully authored event defaults below.
 *
 * <p>Value lookup order everywhere: exact id → first matching {@code #tag} in file order →
 * {@code default}. Fractional values are legal — {@link SkillService} carries a per-player
 * float remainder so e.g. {@code stone: 0.5} pays out every second block.</p>
 */
public final class SkillConfig {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final String FILE_NAME = "skills.json";

    // statics reset on ServerStopped (SkillService.onServerStopped calls invalidate())
    private static volatile Data data;

    private SkillConfig() {}

    /** One id/tag → value table (mine / kill / craft / smelt). Preserves file order for tags. */
    public static final class ValueTable {
        private final Map<ResourceLocation, Float> exact = new LinkedHashMap<>();
        private final List<Map.Entry<ResourceLocation, Float>> tags = new java.util.ArrayList<>();
        private final float defaultValue;

        ValueTable(float defaultValue) {
            this.defaultValue = defaultValue;
        }

        public float defaultValue() {
            return defaultValue;
        }

        void put(String key, float value) {
            if (key.startsWith("#")) {
                ResourceLocation rl = ResourceLocation.tryParse(key.substring(1));
                if (rl != null) {
                    tags.add(Map.entry(rl, value));
                }
            } else {
                ResourceLocation rl = ResourceLocation.tryParse(key);
                if (rl != null) {
                    exact.put(rl, value);
                }
            }
        }

        public float forBlock(BlockState state) {
            Float exactHit = exact.get(BuiltInRegistries.BLOCK.getKey(state.getBlock()));
            if (exactHit != null) {
                return exactHit;
            }
            for (Map.Entry<ResourceLocation, Float> tag : tags) {
                if (state.is(TagKey.create(Registries.BLOCK, tag.getKey()))) {
                    return tag.getValue();
                }
            }
            return defaultValue;
        }

        public float forEntity(LivingEntity entity) {
            Float exactHit = exact.get(BuiltInRegistries.ENTITY_TYPE.getKey(entity.getType()));
            if (exactHit != null) {
                return exactHit;
            }
            for (Map.Entry<ResourceLocation, Float> tag : tags) {
                if (entity.getType().is(TagKey.create(Registries.ENTITY_TYPE, tag.getKey()))) {
                    return tag.getValue();
                }
            }
            return defaultValue;
        }

        public float forItem(ItemStack stack) {
            Float exactHit = exact.get(BuiltInRegistries.ITEM.getKey(stack.getItem()));
            if (exactHit != null) {
                return exactHit;
            }
            for (Map.Entry<ResourceLocation, Float> tag : tags) {
                if (stack.is(TagKey.create(Registries.ITEM, tag.getKey()))) {
                    return tag.getValue();
                }
            }
            return defaultValue;
        }

        /** Plain string lookup (advancement ids — no tag semantics). */
        public float forKey(String key) {
            ResourceLocation rl = ResourceLocation.tryParse(key);
            Float exactHit = rl != null ? exact.get(rl) : null;
            return exactHit != null ? exactHit : defaultValue;
        }
    }

    /** Immutable parsed config snapshot. */
    public record Data(
            SkillCurve.Params curve,
            String procSound,
            boolean procChatLine,
            ValueTable mine,
            ValueTable kill,
            ValueTable craft,
            ValueTable smelt,
            ValueTable advancements,
            float exploreChunk,
            float visitNewBiome,
            float trade,
            float breed,
            float altarDepositPerValuePoint,
            float shardBankedEach,
            float death,
            float questMain,
            float questSide,
            float questPersonal,
            Map<String, Float> dailyCaps) {

        public float dailyCap(String source) {
            Float cap = dailyCaps.get(source);
            return cap != null ? cap : Float.MAX_VALUE;
        }
    }

    /** Live config (loads defaults on first access). */
    public static Data get() {
        Data snapshot = data;
        if (snapshot == null) {
            reload();
            snapshot = data;
        }
        return snapshot;
    }

    /** Re-reads {@code config/eclipse/skills.json}, creating it with defaults when missing. */
    public static synchronized void reload() {
        reloadFromDir(FMLPaths.CONFIGDIR.get().resolve("eclipse"));
    }

    /** Injectable-directory variant for gametests (plan risk #8). */
    public static synchronized void reloadFromDir(Path dir) {
        try {
            Files.createDirectories(dir);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to create config directory {}", dir, e);
        }
        Path file = dir.resolve(FILE_NAME);
        if (!Files.exists(file)) {
            try {
                Files.writeString(file, GSON.toJson(defaultsJson()), StandardCharsets.UTF_8);
                EclipseMod.LOGGER.info("Created default Eclipse config {}", file);
            } catch (IOException e) {
                EclipseMod.LOGGER.error("Failed to write default config {}", file, e);
            }
        }
        try {
            JsonObject root = JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)).getAsJsonObject();
            data = parse(root);
            EclipseMod.LOGGER.info("Skill config loaded: curve base {} exp {} softcap {}x{}, {} daily caps",
                    data.curve().baseCost(), data.curve().exponent(), data.curve().softcapLevel(),
                    data.curve().softcapMult(), data.dailyCaps().size());
        } catch (Exception e) {
            EclipseMod.LOGGER.error("Failed to parse {}; keeping previous values (or defaults)", file, e);
            if (data == null) {
                data = parse(defaultsJson());
            }
        }
    }

    /** Drops the cached snapshot (server stop) so a SP relaunch re-reads cleanly. */
    static void invalidate() {
        data = null;
    }

    /** Pure parser — gametests feed synthetic JSON here. Unknown keys are ignored. */
    public static Data parse(JsonObject root) {
        JsonObject curve = obj(root, "curve");
        SkillCurve.Params params = new SkillCurve.Params(
                asDouble(curve, "baseCost", 20.0D),
                asDouble(curve, "exponent", 1.3D),
                (int) asDouble(curve, "softcapLevel", 50.0D),
                asDouble(curve, "softcapMult", 2.0D));

        JsonObject proc = obj(root, "procFeedback");
        String procSound = proc.has("sound") ? proc.get("sound").getAsString() : "eclipse:skill.proc";
        boolean chatLine = !proc.has("chatLine") || proc.get("chatLine").getAsBoolean();

        JsonObject xp = obj(root, "xp");
        Map<String, Float> caps = new LinkedHashMap<>();
        if (root.has("dailyCaps") && root.get("dailyCaps").isJsonObject()) {
            for (Map.Entry<String, JsonElement> entry : root.getAsJsonObject("dailyCaps").entrySet()) {
                if (!entry.getKey().startsWith("_") && entry.getValue().isJsonPrimitive()) {
                    caps.put(entry.getKey(), entry.getValue().getAsFloat());
                }
            }
        }

        return new Data(
                params,
                procSound,
                chatLine,
                table(xp, "mine", 1.0F),
                table(xp, "kill", 5.0F),
                table(xp, "craft", 0.5F),
                table(xp, "smelt", 1.0F),
                table(xp, "advancements", 50.0F),
                asFloat(xp, "exploreChunk", 5.0F),
                asFloat(xp, "visitNewBiome", 40.0F),
                asFloat(xp, "trade", 10.0F),
                asFloat(xp, "breed", 6.0F),
                asFloat(xp, "altarDepositPerValuePoint", 2.0F),
                asFloat(xp, "shardBankedEach", 3.0F),
                asFloat(xp, "death", -50.0F),
                asFloat(xp, "questMain", 0.0F),
                asFloat(xp, "questSide", 0.0F),
                asFloat(xp, "questPersonal", 0.0F),
                Map.copyOf(caps));
    }

    private static JsonObject obj(JsonObject parent, String key) {
        return parent.has(key) && parent.get(key).isJsonObject() ? parent.getAsJsonObject(key) : new JsonObject();
    }

    private static double asDouble(JsonObject obj, String key, double fallback) {
        return obj.has(key) && obj.get(key).isJsonPrimitive() ? obj.get(key).getAsDouble() : fallback;
    }

    private static float asFloat(JsonObject obj, String key, float fallback) {
        return obj.has(key) && obj.get(key).isJsonPrimitive() ? obj.get(key).getAsFloat() : fallback;
    }

    private static ValueTable table(JsonObject xp, String key, float builtinDefault) {
        JsonObject source = obj(xp, key);
        float def = asFloat(source, "default", builtinDefault);
        ValueTable table = new ValueTable(def);
        for (Map.Entry<String, JsonElement> entry : source.entrySet()) {
            String k = entry.getKey();
            if ("default".equals(k) || k.startsWith("_") || !entry.getValue().isJsonPrimitive()) {
                continue;
            }
            table.put(k, entry.getValue().getAsFloat());
        }
        return table;
    }

    // ------------------------------------------------------------------
    // Defaults (plan §2.3 earn table verbatim + conservative completeness fills).
    // Every knob is re-tunable live: edit config/eclipse/skills.json → /eclipse reload.
    // ------------------------------------------------------------------

    /** Canonical default config JSON (public for gametest table pinning). */
    public static JsonObject defaultsJson() {
        JsonObject root = new JsonObject();

        JsonObject doc = new JsonObject();
        doc.addProperty("curve", "xpForLevel(n)=C(n)-C(n-1), C(L)=baseCost*L^(exponent+1)/(exponent+1); "
                + "past softcapLevel each level costs softcapMult x the raw increment. "
                + "Defaults hit C(12)=2639 (~L12 after 4h at ~660 XP/h) and C(50)=70296.");
        doc.addProperty("xp", "Earn values per action. Sub-tables (mine/kill/craft/smelt/advancements) "
                + "resolve exact id -> first #tag in file order -> default. Fractions allowed "
                + "(remainder carried per player). death is the only negative entry and skips all "
                + "multipliers; total XP floors at 0.");
        doc.addProperty("xpSourceKeys", "mine kill explore craft smelt trade breed altar quest advancement death admin "
                + "- frozen source keys used by SkillsApi.addXp and dailyCaps.");
        doc.addProperty("questXp", "questMain/questSide/questPersonal 0 = use each goal spec's reward.skillXp "
                + "(P4-B2 grants it); >0 = flat bonus granted on the questCompleted signal IN ADDITION.");
        doc.addProperty("altarXp", "MILESTONE/OFFERING deposits pay altarDepositPerValuePoint x item count "
                + "(1 value point per item - deliberately NOT the secret offering value, which must never "
                + "be observable). SHARD_BANK pays shardBankedEach x count.");
        doc.addProperty("dailyCaps", "Per-source cap on FINAL granted XP per event day per player "
                + "(anti-grind, generous). Remove a key to uncap. Negative XP ignores caps.");
        doc.addProperty("procFeedback", "sound = played to the proc-ing player; chatLine = global default "
                + "for the clickable chat notice (players opt out via /skills procmsg off).");
        root.add("_doc", doc);

        JsonObject curve = new JsonObject();
        curve.addProperty("baseCost", 20);
        curve.addProperty("exponent", 1.3D);
        curve.addProperty("softcapLevel", 50);
        curve.addProperty("softcapMult", 2.0D);
        root.add("curve", curve);

        JsonObject proc = new JsonObject();
        proc.addProperty("sound", "eclipse:skill.proc");
        proc.addProperty("chatLine", true);
        root.add("procFeedback", proc);

        JsonObject xp = new JsonObject();

        JsonObject mine = new JsonObject();
        mine.addProperty("default", 1);
        mine.addProperty("#minecraft:coal_ores", 3);
        mine.addProperty("#minecraft:iron_ores", 4);
        mine.addProperty("#minecraft:copper_ores", 2);
        mine.addProperty("#minecraft:gold_ores", 5);
        mine.addProperty("#minecraft:redstone_ores", 4);
        mine.addProperty("#minecraft:lapis_ores", 6);
        mine.addProperty("#minecraft:diamond_ores", 12);
        mine.addProperty("#minecraft:emerald_ores", 10);
        mine.addProperty("minecraft:nether_quartz_ore", 3);
        mine.addProperty("minecraft:nether_gold_ore", 3);
        mine.addProperty("minecraft:ancient_debris", 20);
        mine.addProperty("minecraft:obsidian", 8);
        mine.addProperty("minecraft:crying_obsidian", 10);
        mine.addProperty("#minecraft:logs", 1);
        mine.addProperty("minecraft:stone", 0.5D);
        mine.addProperty("minecraft:deepslate", 0.5D);
        mine.addProperty("minecraft:netherrack", 0.25D);
        xp.add("mine", mine);

        JsonObject kill = new JsonObject();
        kill.addProperty("default", 5);
        kill.addProperty("minecraft:zombie", 8);
        kill.addProperty("minecraft:husk", 8);
        kill.addProperty("minecraft:drowned", 8);
        kill.addProperty("minecraft:skeleton", 9);
        kill.addProperty("minecraft:stray", 9);
        kill.addProperty("minecraft:creeper", 10);
        kill.addProperty("minecraft:spider", 7);
        kill.addProperty("minecraft:cave_spider", 9);
        kill.addProperty("minecraft:witch", 14);
        kill.addProperty("minecraft:enderman", 15);
        kill.addProperty("minecraft:blaze", 14);
        kill.addProperty("minecraft:wither_skeleton", 16);
        kill.addProperty("minecraft:piglin", 8);
        kill.addProperty("minecraft:zombified_piglin", 6);
        kill.addProperty("minecraft:hoglin", 12);
        kill.addProperty("minecraft:ghast", 15);
        kill.addProperty("minecraft:phantom", 10);
        kill.addProperty("minecraft:guardian", 10);
        kill.addProperty("minecraft:elder_guardian", 60);
        kill.addProperty("minecraft:shulker", 15);
        kill.addProperty("minecraft:pillager", 8);
        kill.addProperty("minecraft:vindicator", 12);
        kill.addProperty("minecraft:evoker", 25);
        kill.addProperty("minecraft:ravager", 30);
        kill.addProperty("minecraft:slime", 2);
        kill.addProperty("minecraft:magma_cube", 3);
        kill.addProperty("minecraft:silverfish", 3);
        kill.addProperty("minecraft:endermite", 3);
        kill.addProperty("minecraft:warden", 150);
        kill.addProperty("minecraft:wither", 300);
        kill.addProperty("minecraft:ender_dragon", 500);
        kill.addProperty("eclipse:gazer", 20);
        kill.addProperty("eclipse:umbral_stalker", 18);
        kill.addProperty("eclipse:the_other", 40);
        kill.addProperty("eclipse:herald", 400);
        kill.addProperty("eclipse:ferryman", 600);
        kill.addProperty("#eclipse:glitched", 60);
        xp.add("kill", kill);

        xp.addProperty("exploreChunk", 5);
        xp.addProperty("visitNewBiome", 40);

        JsonObject craft = new JsonObject();
        craft.addProperty("default", 0.5D);
        craft.addProperty("minecraft:crafting_table", 2);
        craft.addProperty("#minecraft:planks", 0);
        craft.addProperty("minecraft:stick", 0);
        xp.add("craft", craft);

        JsonObject smelt = new JsonObject();
        smelt.addProperty("default", 1);
        xp.add("smelt", smelt);

        xp.addProperty("trade", 10);
        xp.addProperty("breed", 6);
        xp.addProperty("altarDepositPerValuePoint", 2);
        xp.addProperty("shardBankedEach", 3);
        xp.addProperty("death", -50);
        xp.addProperty("questMain", 0);
        xp.addProperty("questSide", 0);
        xp.addProperty("questPersonal", 0);

        JsonObject advancements = new JsonObject();
        advancements.addProperty("default", 50);
        advancements.addProperty("eclipse:root", 25);
        advancements.addProperty("eclipse:first_shard", 50);
        advancements.addProperty("eclipse:first_offering", 75);
        advancements.addProperty("eclipse:heart_extractor", 75);
        advancements.addProperty("eclipse:first_revive", 200);
        advancements.addProperty("eclipse:nether_disc", 100);
        advancements.addProperty("eclipse:survive_day_3", 125);
        advancements.addProperty("eclipse:fog_storm_found", 125);
        advancements.addProperty("eclipse:herald_slain", 200);
        advancements.addProperty("eclipse:tame_the_dark", 175);
        advancements.addProperty("eclipse:classic_collector", 150);
        advancements.addProperty("eclipse:glitch_hunter", 125);
        advancements.addProperty("eclipse:deep_below", 100);
        advancements.addProperty("eclipse:team_survives_day", 200);
        advancements.addProperty("eclipse:skill_10", 100);
        advancements.addProperty("eclipse:skill_25", 150);
        advancements.addProperty("eclipse:skill_40", 250);
        advancements.addProperty("eclipse:ferryman_slain", 300);
        xp.add("advancements", advancements);

        root.add("xp", xp);

        JsonObject caps = new JsonObject();
        caps.addProperty("mine", 3000);
        caps.addProperty("kill", 3000);
        caps.addProperty("explore", 2000);
        caps.addProperty("craft", 1000);
        caps.addProperty("smelt", 1000);
        caps.addProperty("trade", 500);
        caps.addProperty("breed", 400);
        caps.addProperty("altar", 1500);
        root.add("dailyCaps", caps);

        return root;
    }
}
