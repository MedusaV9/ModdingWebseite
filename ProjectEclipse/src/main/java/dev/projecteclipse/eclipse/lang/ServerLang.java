package dev.projecteclipse.eclipse.lang;

import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;

import javax.annotation.Nullable;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.MutableComponent;
import net.minecraft.network.chat.contents.TranslatableContents;
import net.minecraft.server.level.ServerPlayer;

/**
 * Server-side per-player string baker (Wave-5 A1, {@code docs/plans_v3/plans_v5/PLAN-A_client_ui.md}
 * §A1 contract 0.2). A server-built {@link Component#translatable} serializes as a translatable and
 * resolves on the client with the <em>vanilla</em> game language — the mod's {@code /lang} override
 * (client {@code EclipseLang} + {@link LangService}) is ignored. Every player-facing server send
 * (announcements, xbox event lines, command feedback) should therefore bake through
 * {@link #tr(ServerPlayer, String, Object...)} (key + args) or {@link #resolve(ServerPlayer, Component)}
 * (an already-built component tree) so the line arrives pre-localized for that player's
 * {@link LangService#locale(ServerPlayer)}.
 *
 * <p>Templates come from the mod's own {@code assets/eclipse/lang/en_us.json} / {@code de_de.json}
 * on the classpath (present on both dedicated servers and the client-embedded server), so server and
 * client always agree on the strings. Unknown keys fall back to a plain translatable — the client
 * then resolves them with its vanilla language, which is never worse than the pre-A1 behavior.</p>
 *
 * <p>Placeholder handling mirrors vanilla translatables ({@code %s}, {@code %n$s}, {@code %%};
 * anything else stays literal): {@link Component} args keep their style/click/hover events and are
 * themselves baked recursively when translatable, so styled args like the xbox portal coordinates
 * or {@code worldName(...)} survive the bake.</p>
 */
public final class ServerLang {
    private static final Map<String, String> EN = new HashMap<>();
    private static final Map<String, String> DE = new HashMap<>();
    private static boolean loaded;

    private ServerLang() {}

    /**
     * Resolves {@code key} for {@code player}'s effective locale and bakes it into a literal-based
     * component. Null player (console feedback) and unknown keys fall back to a plain translatable.
     */
    public static MutableComponent tr(@Nullable ServerPlayer player, String key, Object... args) {
        if (player == null) {
            return Component.translatable(key, args);
        }
        String locale = LangService.locale(player);
        String template = template(locale, key);
        if (template == null) {
            return Component.translatable(key, args);
        }
        return bake(locale, template, args);
    }

    /**
     * Re-bakes an already-built component tree for {@code player}: translatable nodes (and
     * translatable args) whose keys live in the mod lang tables become pre-localized literals;
     * styles, siblings and unknown keys pass through untouched. Safe to call once per recipient on
     * a shared broadcast component.
     */
    public static Component resolve(@Nullable ServerPlayer player, Component component) {
        if (player == null) {
            return component;
        }
        return resolveForLocale(LangService.locale(player), component);
    }

    // ------------------------------------------------------------------ internals

    private static MutableComponent resolveForLocale(String locale, Component component) {
        MutableComponent out;
        if (component.getContents() instanceof TranslatableContents translatable) {
            String template = template(locale, translatable.getKey());
            if (template != null) {
                out = bake(locale, template, translatable.getArgs());
            } else {
                out = MutableComponent.create(component.getContents());
            }
        } else {
            out = MutableComponent.create(component.getContents());
        }
        out.setStyle(component.getStyle());
        for (Component sibling : component.getSiblings()) {
            out.append(resolveForLocale(locale, sibling));
        }
        return out;
    }

    /**
     * Vanilla-style template decomposition ({@code %s} / {@code %n$s} / {@code %%}; any other
     * {@code %} stays literal). Component args are appended as components (styles survive) after a
     * recursive bake; everything else is stringified.
     */
    private static MutableComponent bake(String locale, String template, Object[] args) {
        MutableComponent result = Component.empty();
        StringBuilder literal = new StringBuilder();
        int implicitIndex = 0;
        int i = 0;
        while (i < template.length()) {
            char c = template.charAt(i);
            if (c != '%') {
                literal.append(c);
                i++;
                continue;
            }
            if (i + 1 < template.length() && template.charAt(i + 1) == '%') {
                literal.append('%');
                i += 2;
                continue;
            }
            if (i + 1 < template.length() && template.charAt(i + 1) == 's') {
                flush(result, literal);
                appendArg(result, locale, args, implicitIndex++);
                i += 2;
                continue;
            }
            // %n$s (1-based explicit index)
            int digitsEnd = i + 1;
            while (digitsEnd < template.length() && Character.isDigit(template.charAt(digitsEnd))) {
                digitsEnd++;
            }
            if (digitsEnd > i + 1 && digitsEnd + 1 < template.length()
                    && template.charAt(digitsEnd) == '$' && template.charAt(digitsEnd + 1) == 's') {
                flush(result, literal);
                appendArg(result, locale, args,
                        Integer.parseInt(template.substring(i + 1, digitsEnd)) - 1);
                i = digitsEnd + 2;
                continue;
            }
            literal.append('%'); // lone percent ("50% faster") stays literal
            i++;
        }
        flush(result, literal);
        return result;
    }

    private static void flush(MutableComponent result, StringBuilder literal) {
        if (!literal.isEmpty()) {
            result.append(Component.literal(literal.toString()));
            literal.setLength(0);
        }
    }

    private static void appendArg(MutableComponent result, String locale, Object[] args, int index) {
        if (index < 0 || index >= args.length) {
            return; // malformed template/arg mismatch: drop the placeholder, never throw
        }
        Object arg = args[index];
        if (arg instanceof Component component) {
            result.append(resolveForLocale(locale, component));
        } else {
            result.append(Component.literal(String.valueOf(arg)));
        }
    }

    @Nullable
    private static String template(String locale, String key) {
        ensureLoaded();
        if (locale != null && locale.startsWith("de")) {
            String german = DE.get(key);
            if (german != null) {
                return german;
            }
        }
        return EN.get(key);
    }

    private static synchronized void ensureLoaded() {
        if (loaded) {
            return;
        }
        loaded = true;
        loadInto("en_us", EN);
        loadInto("de_de", DE);
        EclipseMod.LOGGER.debug("ServerLang loaded lang tables: en_us={} keys, de_de={} keys",
                EN.size(), DE.size());
    }

    private static void loadInto(String localeFile, Map<String, String> target) {
        String path = "/assets/" + EclipseMod.MOD_ID + "/lang/" + localeFile + ".json";
        try (InputStream stream = ServerLang.class.getResourceAsStream(path)) {
            if (stream == null) {
                EclipseMod.LOGGER.warn("ServerLang: {} not found on the classpath", path);
                return;
            }
            JsonObject root = JsonParser
                    .parseReader(new InputStreamReader(stream, StandardCharsets.UTF_8))
                    .getAsJsonObject();
            for (Map.Entry<String, JsonElement> line : root.entrySet()) {
                if (line.getValue().isJsonPrimitive()) {
                    target.put(line.getKey(), line.getValue().getAsString());
                }
            }
        } catch (Exception exception) {
            EclipseMod.LOGGER.warn("ServerLang: failed to parse {}", path, exception);
        }
    }
}
