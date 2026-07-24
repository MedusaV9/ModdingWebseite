package dev.projecteclipse.eclipse.minigames;

import java.util.LinkedHashMap;
import java.util.Map;

import javax.annotation.Nullable;

import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.Level;

/**
 * Dimension keys for the two minigame dimensions (the {@code XboxDimensions} pattern).
 * The datapack JSONs live at {@code data/eclipse/dimension/minigame_<id>.json} (both of
 * type {@code eclipse:minigame}, a void flat generator); the actual course blocks are
 * generated at open time by {@link ArenaGame} / {@link ElytraRace}.
 */
public final class MinigameDimensions {
    /** Game id of the FFA fight arena ({@code /dev minigame start arena}). */
    public static final String GAME_ARENA = "arena";
    /** Game id of the elytra ring race ({@code /dev minigame start race}). */
    public static final String GAME_RACE = "race";

    public static final ResourceKey<Level> ARENA = key("minigame_arena");
    public static final ResourceKey<Level> SKY = key("minigame_sky");

    /** gameId → dimension key, insertion-ordered. */
    private static final Map<String, ResourceKey<Level>> BY_GAME_ID = new LinkedHashMap<>();

    static {
        BY_GAME_ID.put(GAME_ARENA, ARENA);
        BY_GAME_ID.put(GAME_RACE, SKY);
    }

    private MinigameDimensions() {}

    private static ResourceKey<Level> key(String path) {
        return ResourceKey.create(Registries.DIMENSION,
                ResourceLocation.fromNamespaceAndPath("eclipse", path));
    }

    /** The dimension key for a game id, or {@code null} for unknown ids. */
    @Nullable
    public static ResourceKey<Level> byGameId(String gameId) {
        return gameId == null ? null : BY_GAME_ID.get(gameId);
    }

    /** The game id owning a minigame dimension key, or {@code null} for foreign dims. */
    @Nullable
    public static String gameIdOf(ResourceKey<Level> dimension) {
        for (Map.Entry<String, ResourceKey<Level>> entry : BY_GAME_ID.entrySet()) {
            if (entry.getValue().equals(dimension)) {
                return entry.getKey();
            }
        }
        return null;
    }

    public static boolean isMinigameDimension(ResourceKey<Level> dimension) {
        return gameIdOf(dimension) != null;
    }

    public static boolean isInMinigameDimension(Entity entity) {
        return entity != null && isMinigameDimension(entity.level().dimension());
    }

    /** All known game ids in declaration order ({@code arena, race}). */
    public static Iterable<String> gameIds() {
        return BY_GAME_ID.keySet();
    }
}
