package dev.projecteclipse.eclipse.client.lang;

import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;

import javax.annotation.Nullable;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.resources.language.I18n;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.packs.resources.Resource;
import net.minecraft.server.packs.resources.ResourceManager;
import net.minecraft.server.packs.resources.ResourceManagerReloadListener;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RegisterClientReloadListenersEvent;

/**
 * Eclipse UI string resolver with per-mod locale override ({@code docs/plans_v3/P3_ui.md} §3.2).
 * When the effective locale matches the vanilla game language, {@link #tr(String, Object...)}
 * delegates to {@link Component#translatable} (zero-cost {@code auto} path). Otherwise strings are
 * resolved from internally cached lang tables keyed by {@link #generation()}.
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class EclipseLang {
    private static final String[] KEY_PREFIXES = {
            "gui.eclipse.",
            "announce.eclipse.",
            "sidebar.eclipse.",
            "message.eclipse.",
            "bestiary.eclipse.",
            "ritual.eclipse.",
            "shop.eclipse.",
            "commands.eclipse.",
            "subtitles.eclipse.",
            "key.eclipse.",
            "item.eclipse.",
            "block.eclipse.",
            "entity.eclipse.",
    };

    private static final Map<String, String> EN_US = new HashMap<>();
    private static final Map<String, String> DE_DE = new HashMap<>();
    private static final List<Runnable> RELOAD_LISTENERS = new CopyOnWriteArrayList<>();

    private static String override = "auto";
    private static int generation;

    private EclipseLang() {}

    /** Current override token: {@code auto}, {@code en_us} or {@code de_de}. */
    public static String overrideRaw() {
        return override;
    }

    /** Effective locale code used for table lookup: {@code en_us} or {@code de_de}. */
    public static String locale() {
        return effectiveLocaleCode();
    }

    /** Monotonic counter bumped on every override change or resource reload — include in HUD caches. */
    public static int generation() {
        return generation;
    }

    /** Whether {@link #tr} currently delegates to vanilla {@link Component#translatable}. */
    public static boolean usesVanillaPath() {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft == null) {
            return true;
        }
        return effectiveLocaleCode().equals(normalizeClientLocale(minecraft.options.languageCode));
    }

    public static Component tr(String key, Object... args) {
        if (usesVanillaPath()) {
            return Component.translatable(key, args);
        }
        return Component.literal(trString(key, args));
    }

    public static String trString(String key, Object... args) {
        if (usesVanillaPath()) {
            return Component.translatable(key, args).getString();
        }
        String template = lookupTemplate(key);
        return format(template, args);
    }

    /** True when the key exists in the active lookup chain (used by literal-audit call sites). */
    public static boolean hasKey(String key) {
        if (usesVanillaPath()) {
            return I18n.exists(key);
        }
        return tableForEffectiveLocale().containsKey(key)
                || EN_US.containsKey(key)
                || I18n.exists(key);
    }

    /**
     * Sets the client override ({@code auto}, {@code en_us}, {@code de_de}) and persists via
     * {@link LangConfigBridge} when the W3 config key is wired.
     */
    public static void setOverride(String value) {
        override = normalizeOverride(value);
        LangConfigBridge.save(override);
        reload();
    }

    /** Rebuilds lang tables, bumps {@link #generation()} and refreshes open Eclipse screens. */
    public static void reload() {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft != null) {
            rebuildMaps(minecraft.getResourceManager());
        }
        generation++;
        for (Runnable listener : RELOAD_LISTENERS) {
            try {
                listener.run();
            } catch (RuntimeException exception) {
                EclipseMod.LOGGER.warn("EclipseLang reload listener failed", exception);
            }
        }
        refreshOpenScreen(minecraft);
    }

    /** Registers a callback invoked after every {@link #reload()}. */
    public static void addReloadListener(Runnable listener) {
        RELOAD_LISTENERS.add(listener);
    }

    /**
     * Resolves a key from a specific locale table ({@code en_us} / {@code de_de}) without changing
     * the active override — used by {@code /sprache} confirmation lines.
     */
    public static Component trForLocale(String localeCode, String key, Object... args) {
        Map<String, String> table = localeCode.startsWith("de") ? DE_DE : EN_US;
        String template = table.getOrDefault(key, EN_US.getOrDefault(key, key));
        return Component.literal(format(template, args));
    }

    /** Loads override from client config on startup (no-op until W3 wires {@code langOverride}). */
    public static void initFromConfig() {
        override = normalizeOverride(LangConfigBridge.load());
    }

    @SubscribeEvent
    static void onRegisterReloadListeners(RegisterClientReloadListenersEvent event) {
        event.registerReloadListener((ResourceManagerReloadListener) manager -> {
            rebuildMaps(manager);
            generation++;
        });
    }

    private static void rebuildMaps(ResourceManager resourceManager) {
        EN_US.clear();
        DE_DE.clear();
        mergeLocale(resourceManager, "en_us", EN_US);
        mergeLocale(resourceManager, "de_de", DE_DE);
    }

    private static void mergeLocale(ResourceManager resourceManager, String localeFile,
            Map<String, String> target) {
        Map<ResourceLocation, List<Resource>> stacks = resourceManager.listResourceStacks(
                "lang", location -> location.getPath().endsWith("/" + localeFile)
                        || location.getPath().equals(localeFile));
        for (Map.Entry<ResourceLocation, List<Resource>> entry : stacks.entrySet()) {
            for (Resource resource : entry.getValue()) {
                try (var reader = resource.openAsReader()) {
                    JsonObject root = JsonParser.parseReader(reader).getAsJsonObject();
                    for (Map.Entry<String, JsonElement> line : root.entrySet()) {
                        if (matchesPrefix(line.getKey()) && line.getValue().isJsonPrimitive()) {
                            target.put(line.getKey(), line.getValue().getAsString());
                        }
                    }
                } catch (Exception exception) {
                    EclipseMod.LOGGER.warn("EclipseLang: failed to parse {} for {}",
                            entry.getKey(), localeFile, exception);
                }
            }
        }
    }

    private static boolean matchesPrefix(String key) {
        for (String prefix : KEY_PREFIXES) {
            if (key.startsWith(prefix)) {
                return true;
            }
        }
        return false;
    }

    private static String lookupTemplate(String key) {
        Map<String, String> primary = tableForEffectiveLocale();
        String value = primary.get(key);
        if (value != null) {
            return value;
        }
        value = EN_US.get(key);
        if (value != null) {
            return value;
        }
        return Component.translatable(key).getString();
    }

    private static Map<String, String> tableForEffectiveLocale() {
        return effectiveLocaleCode().startsWith("de") ? DE_DE : EN_US;
    }

    private static String effectiveLocaleCode() {
        if ("auto".equals(override)) {
            Minecraft minecraft = Minecraft.getInstance();
            if (minecraft != null) {
                return normalizeClientLocale(minecraft.options.languageCode);
            }
            return "en_us";
        }
        return normalizeClientLocale(override);
    }

    static String normalizeOverride(String token) {
        if (token == null || token.isEmpty() || "auto".equalsIgnoreCase(token)) {
            return "auto";
        }
        return normalizeClientLocale(token);
    }

    static String normalizeClientLocale(String token) {
        if (token == null || token.isEmpty()) {
            return "en_us";
        }
        String lower = token.toLowerCase(Locale.ROOT);
        if (lower.startsWith("de")) {
            return "de_de";
        }
        return "en_us";
    }

    private static String format(String template, Object... args) {
        if (args.length == 0) {
            return template;
        }
        Object[] stringArgs = new Object[args.length];
        for (int i = 0; i < args.length; i++) {
            Object arg = args[i];
            stringArgs[i] = arg instanceof Component component ? component.getString() : arg;
        }
        try {
            return String.format(Locale.ROOT, template, stringArgs);
        } catch (RuntimeException exception) {
            EclipseMod.LOGGER.warn("EclipseLang format failed for template {}", template, exception);
            return template;
        }
    }

    private static void refreshOpenScreen(@Nullable Minecraft minecraft) {
        if (minecraft == null || minecraft.screen == null) {
            return;
        }
        Screen screen = minecraft.screen;
        if (!isEclipseScreen(screen)) {
            return;
        }
        screen.resize(minecraft, minecraft.getWindow().getGuiScaledWidth(),
                minecraft.getWindow().getGuiScaledHeight());
    }

    private static boolean isEclipseScreen(Screen screen) {
        return screen.getClass().getName().startsWith("dev.projecteclipse.eclipse.client.");
    }

    /** Bridges {@code langOverride} in {@code eclipse-client.toml} once P3-W3 lands. */
    static final class LangConfigBridge {
        private LangConfigBridge() {}

        static String load() {
            // Wave-1 partner (P3-W3): return EclipseClientConfig.langOverride();
            return "auto";
        }

        static void save(String value) {
            // Wave-1 partner (P3-W3): EclipseClientConfig.setLangOverride(value);
        }
    }
}
