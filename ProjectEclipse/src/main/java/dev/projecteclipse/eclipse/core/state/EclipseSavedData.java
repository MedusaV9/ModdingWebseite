package dev.projecteclipse.eclipse.core.state;

import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Shared helpers for per-save {@link SavedData} stored in the overworld dimension.
 * All P4 feature states use this pattern so data dies with the save and never
 * leaks across singleplayer relaunches when static caches are cleared correctly.
 */
public final class EclipseSavedData {
    private EclipseSavedData() {}

    /**
     * Returns the overworld level for Eclipse global state. Event progression keys
     * off overworld day count even when players spread across dimensions.
     */
    public static ServerLevel overworld(MinecraftServer server) {
        return server.overworld();
    }

    /**
     * Loads or creates a {@link SavedData} file in overworld storage.
     *
     * @param server  running dedicated or integrated server
     * @param dataId  file id without extension (e.g. {@code eclipse_realtime})
     * @param factory NeoForge/MC factory with constructor + loader
     */
    public static <T extends SavedData> T getOverworld(MinecraftServer server, String dataId,
            SavedData.Factory<T> factory) {
        return overworld(server).getDataStorage().computeIfAbsent(factory, dataId);
    }
}
