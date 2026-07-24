package dev.projecteclipse.eclipse.voice;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Persisted voice moderation state ({@code eclipse_voice.dat}).
 */
public final class VoiceState extends SavedData {
    public static final String DATA_ID = "eclipse_voice";

    private static final String TAG_GLOBAL_MUTED = "globalMuted";

    private boolean globalMuted;

    public VoiceState() {}

    public static VoiceState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_ID,
                new SavedData.Factory<>(VoiceState::new, VoiceState::load));
    }

    public static VoiceState load(CompoundTag tag, HolderLookup.Provider registries) {
        VoiceState state = new VoiceState();
        state.globalMuted = tag.getBoolean(TAG_GLOBAL_MUTED);
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putBoolean(TAG_GLOBAL_MUTED, globalMuted);
        return tag;
    }

    public boolean isGlobalMuted() {
        return globalMuted;
    }

    public void setGlobalMuted(boolean globalMuted) {
        if (this.globalMuted != globalMuted) {
            this.globalMuted = globalMuted;
            setDirty();
        }
    }
}
