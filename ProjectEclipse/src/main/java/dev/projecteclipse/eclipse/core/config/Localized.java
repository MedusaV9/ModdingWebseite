package dev.projecteclipse.eclipse.core.config;

import javax.annotation.Nullable;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonPrimitive;

/**
 * Dual-language server-baked string ({@code docs/plans_v3/P3_ui.md} §3.2). Config fields such as
 * {@code days.json} {@code goals[]}, {@code title} and {@code subtitle} accept either a legacy
 * plain string (treated as English for both locales until a German line is authored) or an object
 * {@code {"en": "…", "de": "…"}}. P4-owned parsers should delegate string/object detection here.
 */
public record Localized(String en, @Nullable String de) {
    public Localized {
        en = en != null ? en : "";
        if (de != null && de.isEmpty()) {
            de = null;
        }
    }

    /** Legacy single-language convenience — German falls back to English via {@link #pick(String)}. */
    public static Localized of(String english) {
        return new Localized(english, null);
    }

    /** Parses a JSON string primitive or {@code {en,de}} object from {@code days.json}. */
    public static Localized fromJson(JsonElement element) {
        if (element == null || element.isJsonNull()) {
            return new Localized("", null);
        }
        if (element.isJsonPrimitive()) {
            return new Localized(element.getAsString(), null);
        }
        JsonObject obj = element.getAsJsonObject();
        String english = obj.has("en") ? obj.get("en").getAsString() : "";
        String german = obj.has("de") ? obj.get("de").getAsString() : null;
        return new Localized(english, german);
    }

    /** Backward-compatible alias retained for existing config parsers. */
    public static Localized parse(JsonElement element) {
        return fromJson(element);
    }

    /** Writes legacy string when only English is set, otherwise the dual-language object form. */
    public JsonElement toJsonElement() {
        if (isBlank()) {
            return new JsonPrimitive("");
        }
        if (de == null || de.equals(en)) {
            return new JsonPrimitive(en);
        }
        JsonObject obj = new JsonObject();
        obj.addProperty("en", en);
        obj.addProperty("de", de);
        return obj;
    }

    public boolean isBlank() {
        return en.isBlank() && (de == null || de.isBlank());
    }

    /**
     * Picks the line for a normalized locale token ({@code "en"} / {@code "de"} as returned by
     * {@link dev.projecteclipse.eclipse.lang.LangService#locale(net.minecraft.server.level.ServerPlayer)}).
     * Missing German falls back to English.
     */
    public String pick(String locale) {
        if (locale != null && locale.startsWith("de")) {
            if (de != null && !de.isBlank()) {
                return de;
            }
        }
        return en;
    }
}
