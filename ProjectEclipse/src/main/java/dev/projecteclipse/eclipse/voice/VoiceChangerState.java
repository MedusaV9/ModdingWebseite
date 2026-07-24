package dev.projecteclipse.eclipse.voice;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Persisted voice-changer presets ({@code eclipse_voice_changer.dat}): global default preset
 * plus per-player overrides. Mutations go through {@link VoiceChangerService}, which mirrors
 * this state into its thread-safe runtime snapshot for the voice packet thread.
 */
public final class VoiceChangerState extends SavedData {
    public static final String DATA_ID = "eclipse_voice_changer";

    private static final String TAG_GLOBAL_DEFAULT = "globalDefault";
    private static final String TAG_PLAYERS = "players";
    private static final String TAG_PLAYER = "player";
    private static final String TAG_PRESET = "preset";

    private VoicePreset globalDefault = VoicePreset.OFF;
    private final Map<UUID, VoicePreset> playerPresets = new HashMap<>();

    public VoiceChangerState() {}

    public static VoiceChangerState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_ID,
                new SavedData.Factory<>(VoiceChangerState::new, VoiceChangerState::load));
    }

    public static VoiceChangerState load(CompoundTag tag, HolderLookup.Provider registries) {
        VoiceChangerState state = new VoiceChangerState();
        VoicePreset global = VoicePreset.byId(tag.getString(TAG_GLOBAL_DEFAULT));
        state.globalDefault = global == null ? VoicePreset.OFF : global;
        ListTag list = tag.getList(TAG_PLAYERS, Tag.TAG_COMPOUND);
        for (int i = 0; i < list.size(); i++) {
            CompoundTag entry = list.getCompound(i);
            VoicePreset preset = VoicePreset.byId(entry.getString(TAG_PRESET));
            if (preset != null && entry.hasUUID(TAG_PLAYER)) {
                state.playerPresets.put(entry.getUUID(TAG_PLAYER), preset);
            }
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        if (globalDefault != VoicePreset.OFF) {
            tag.putString(TAG_GLOBAL_DEFAULT, globalDefault.id());
        }
        ListTag list = new ListTag();
        for (Map.Entry<UUID, VoicePreset> entry : playerPresets.entrySet()) {
            CompoundTag compound = new CompoundTag();
            compound.putUUID(TAG_PLAYER, entry.getKey());
            compound.putString(TAG_PRESET, entry.getValue().id());
            list.add(compound);
        }
        tag.put(TAG_PLAYERS, list);
        return tag;
    }

    public VoicePreset globalDefault() {
        return globalDefault;
    }

    /** {@code null} = no override (inherit global default). */
    @Nullable
    public VoicePreset playerPreset(UUID player) {
        return playerPresets.get(player);
    }

    public Map<UUID, VoicePreset> playerPresets() {
        return Map.copyOf(playerPresets);
    }

    // --- mutations (package-private: VoiceChangerService is the only writer) ---

    void setGlobalDefault(VoicePreset preset) {
        globalDefault = preset;
        setDirty();
    }

    /** @param preset the override, or {@code null} to clear (inherit global default). */
    void setPlayerPreset(UUID player, @Nullable VoicePreset preset) {
        if (preset == null) {
            playerPresets.remove(player);
        } else {
            playerPresets.put(player, preset);
        }
        setDirty();
    }
}
