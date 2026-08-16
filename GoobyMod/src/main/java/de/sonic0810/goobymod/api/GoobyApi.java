package de.sonic0810.goobymod.api;

import de.sonic0810.goobymod.registry.ModItemTags;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.tags.TagKey;
import net.minecraft.world.item.Item;

/**
 * Small registration surface for Gooby addons.
 *
 * <p>Hat compatibility is datapack-driven through {@link #GOOBY_HATS}.
 * Addons may additionally register localized speech-key pools during common
 * setup. Public members in this package follow semantic compatibility for 5.x.
 */
public final class GoobyApi {
    public static final TagKey<Item> GOOBY_HATS = ModItemTags.GOOBY_HATS;
    public static final int MAX_SPEECH_POOLS = 128;
    public static final int MAX_KEYS_PER_POOL = 256;
    public static final int MAX_TOTAL_SPEECH_KEYS = 4096;
    public static final int MAX_TRANSLATION_KEY_LENGTH = 256;

    private static final Map<ResourceLocation, List<String>> SPEECH_POOLS = new LinkedHashMap<>();
    private static volatile List<String> flattenedSpeechKeys = List.of();

    public static synchronized void registerSpeechPool(ResourceLocation id, List<String> translationKeys) {
        Objects.requireNonNull(id, "id");
        Objects.requireNonNull(translationKeys, "translationKeys");
        if (translationKeys.isEmpty()) {
            throw new IllegalArgumentException("A Gooby speech pool must contain at least one translation key");
        }
        if (SPEECH_POOLS.size() >= MAX_SPEECH_POOLS) {
            throw new IllegalStateException("Gooby speech pool limit reached: " + MAX_SPEECH_POOLS);
        }
        List<String> validated = translationKeys.stream()
                .map(key -> Objects.requireNonNull(key, "translation key").strip())
                .peek(key -> {
                    if (key.isEmpty()) {
                        throw new IllegalArgumentException("Gooby speech keys may not be blank");
                    }
                    if (key.length() > MAX_TRANSLATION_KEY_LENGTH) {
                        throw new IllegalArgumentException("Gooby speech key exceeds "
                                + MAX_TRANSLATION_KEY_LENGTH + " characters");
                    }
                })
                .distinct()
                .toList();
        if (validated.size() > MAX_KEYS_PER_POOL) {
            throw new IllegalArgumentException("Gooby speech pool exceeds "
                    + MAX_KEYS_PER_POOL + " unique keys");
        }
        if (flattenedSpeechKeys.size() + validated.size() > MAX_TOTAL_SPEECH_KEYS) {
            throw new IllegalStateException("Gooby speech key limit reached: " + MAX_TOTAL_SPEECH_KEYS);
        }
        if (SPEECH_POOLS.putIfAbsent(id, validated) != null) {
            throw new IllegalArgumentException("Duplicate Gooby speech pool: " + id);
        }
        ArrayList<String> flattened = new ArrayList<>();
        SPEECH_POOLS.values().forEach(flattened::addAll);
        flattenedSpeechKeys = List.copyOf(flattened);
    }

    public static synchronized Map<ResourceLocation, List<String>> speechPools() {
        return Map.copyOf(SPEECH_POOLS);
    }

    public static List<String> addonSpeechKeys() {
        return flattenedSpeechKeys;
    }

    private GoobyApi() {
    }
}
