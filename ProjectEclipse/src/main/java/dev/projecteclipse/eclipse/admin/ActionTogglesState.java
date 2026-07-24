package dev.projecteclipse.eclipse.admin;

import java.util.EnumMap;
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
 * Persisted action-toggle state ({@code eclipse_action_toggles.dat}): per-action global
 * allow flag (default: everything allowed) plus per-player ALLOW/DENY tri-state overrides.
 *
 * <p>Mutations must go through {@link ActionTogglesService} so its lock-free
 * active-restrictions cache and the move-lock reconciliation stay in sync.</p>
 */
public final class ActionTogglesState extends SavedData {
    public static final String DATA_ID = "eclipse_action_toggles";

    private static final String TAG_GLOBAL_PREFIX = "global_";
    private static final String TAG_OVERRIDES = "overrides";
    private static final String TAG_ACTION = "action";
    private static final String TAG_PLAYER = "player";
    private static final String TAG_ALLOW = "allow";

    /** Missing key means allowed (all-allow default keeps a fresh save empty). */
    private final EnumMap<ToggleAction, Boolean> globalAllowed = new EnumMap<>(ToggleAction.class);
    /** Per action: player UUID → TRUE (allow) / FALSE (deny). Absent = inherit global. */
    private final EnumMap<ToggleAction, Map<UUID, Boolean>> overrides = new EnumMap<>(ToggleAction.class);

    public ActionTogglesState() {}

    public static ActionTogglesState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_ID,
                new SavedData.Factory<>(ActionTogglesState::new, ActionTogglesState::load));
    }

    public static ActionTogglesState load(CompoundTag tag, HolderLookup.Provider registries) {
        ActionTogglesState state = new ActionTogglesState();
        for (ToggleAction action : ToggleAction.values()) {
            String key = TAG_GLOBAL_PREFIX + action.id();
            if (tag.contains(key)) {
                state.globalAllowed.put(action, tag.getBoolean(key));
            }
        }
        ListTag list = tag.getList(TAG_OVERRIDES, Tag.TAG_COMPOUND);
        for (int i = 0; i < list.size(); i++) {
            CompoundTag entry = list.getCompound(i);
            ToggleAction action = ToggleAction.byId(entry.getString(TAG_ACTION));
            if (action == null || !entry.hasUUID(TAG_PLAYER)) {
                continue;
            }
            state.overrides.computeIfAbsent(action, a -> new HashMap<>())
                    .put(entry.getUUID(TAG_PLAYER), entry.getBoolean(TAG_ALLOW));
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        for (Map.Entry<ToggleAction, Boolean> entry : globalAllowed.entrySet()) {
            if (!entry.getValue()) {
                tag.putBoolean(TAG_GLOBAL_PREFIX + entry.getKey().id(), false);
            }
        }
        ListTag list = new ListTag();
        for (Map.Entry<ToggleAction, Map<UUID, Boolean>> byAction : overrides.entrySet()) {
            for (Map.Entry<UUID, Boolean> byPlayer : byAction.getValue().entrySet()) {
                CompoundTag entry = new CompoundTag();
                entry.putString(TAG_ACTION, byAction.getKey().id());
                entry.putUUID(TAG_PLAYER, byPlayer.getKey());
                entry.putBoolean(TAG_ALLOW, byPlayer.getValue());
                list.add(entry);
            }
        }
        tag.put(TAG_OVERRIDES, list);
        return tag;
    }

    // --- queries ---

    public boolean isGlobalAllowed(ToggleAction action) {
        return globalAllowed.getOrDefault(action, Boolean.TRUE);
    }

    /** TRUE = allow override, FALSE = deny override, {@code null} = inherit global. */
    @Nullable
    public Boolean override(ToggleAction action, UUID player) {
        Map<UUID, Boolean> byPlayer = overrides.get(action);
        return byPlayer == null ? null : byPlayer.get(player);
    }

    /** Effective permission for one player (override beats global). */
    public boolean isAllowed(ToggleAction action, UUID player) {
        Boolean override = override(action, player);
        return override != null ? override : isGlobalAllowed(action);
    }

    /** Immutable snapshot of one action's overrides (status display). */
    public Map<UUID, Boolean> overridesFor(ToggleAction action) {
        Map<UUID, Boolean> byPlayer = overrides.get(action);
        return byPlayer == null ? Map.of() : Map.copyOf(byPlayer);
    }

    /**
     * Whether enforcement events can skip this action entirely: global allowed AND no
     * DENY override exists (ALLOW overrides on an allowed global are no-ops).
     */
    public boolean hasAnyRestriction(ToggleAction action) {
        if (!isGlobalAllowed(action)) {
            return true;
        }
        Map<UUID, Boolean> byPlayer = overrides.get(action);
        if (byPlayer == null) {
            return false;
        }
        return byPlayer.containsValue(Boolean.FALSE);
    }

    // --- mutations (package-private: ActionTogglesService is the only writer) ---

    void setGlobalAllowed(ToggleAction action, boolean allowed) {
        if (allowed) {
            globalAllowed.remove(action);
        } else {
            globalAllowed.put(action, Boolean.FALSE);
        }
        setDirty();
    }

    /** @param allow TRUE/FALSE to set an override, {@code null} to clear it. */
    void setOverride(ToggleAction action, UUID player, @Nullable Boolean allow) {
        Map<UUID, Boolean> byPlayer = overrides.computeIfAbsent(action, a -> new HashMap<>());
        if (allow == null) {
            byPlayer.remove(player);
            if (byPlayer.isEmpty()) {
                overrides.remove(action);
            }
        } else {
            byPlayer.put(player, allow);
        }
        setDirty();
    }

    void clearAll() {
        globalAllowed.clear();
        overrides.clear();
        setDirty();
    }
}
