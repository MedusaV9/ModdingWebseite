package dev.projecteclipse.eclipse.xboxevent;

import java.util.LinkedHashMap;
import java.util.Map;

import javax.annotation.Nullable;

import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.Level;

/**
 * Dimension keys for the three Xbox-360 tutorial event dimensions (plan §2.13.2). The
 * datapack JSONs live at {@code data/eclipse/dimension/xbox_<id>.json} (all of type
 * {@code eclipse:xbox_classic}); real terrain comes from the region files installed by
 * {@link XboxWorldInstaller} into {@code <world>/dimensions/eclipse/xbox_<id>/}.
 */
public final class XboxDimensions {
    public static final ResourceKey<Level> XBOX_TU1 = key("xbox_tu1");
    public static final ResourceKey<Level> XBOX_TU12 = key("xbox_tu12");
    public static final ResourceKey<Level> XBOX_TU14 = key("xbox_tu14");

    /** worldId (manifest id, e.g. {@code tu12}) → dimension key, insertion-ordered. */
    private static final Map<String, ResourceKey<Level>> BY_WORLD_ID = new LinkedHashMap<>();

    static {
        BY_WORLD_ID.put("tu1", XBOX_TU1);
        BY_WORLD_ID.put("tu12", XBOX_TU12);
        BY_WORLD_ID.put("tu14", XBOX_TU14);
    }

    private XboxDimensions() {}

    private static ResourceKey<Level> key(String path) {
        return ResourceKey.create(Registries.DIMENSION,
                ResourceLocation.fromNamespaceAndPath("eclipse", path));
    }

    /** The dimension key for a manifest world id, or {@code null} for unknown ids. */
    @Nullable
    public static ResourceKey<Level> byWorldId(String worldId) {
        return worldId == null ? null : BY_WORLD_ID.get(worldId);
    }

    /** The manifest world id for an Xbox dimension key, or {@code null} for foreign dims. */
    @Nullable
    public static String worldIdOf(ResourceKey<Level> dimension) {
        for (Map.Entry<String, ResourceKey<Level>> entry : BY_WORLD_ID.entrySet()) {
            if (entry.getValue().equals(dimension)) {
                return entry.getKey();
            }
        }
        return null;
    }

    public static boolean isXboxDimension(ResourceKey<Level> dimension) {
        return worldIdOf(dimension) != null;
    }

    public static boolean isInXboxDimension(Entity entity) {
        return entity != null && isXboxDimension(entity.level().dimension());
    }

    /** All known world ids in manifest order ({@code tu1, tu12, tu14}). */
    public static Iterable<String> worldIds() {
        return BY_WORLD_ID.keySet();
    }
}
