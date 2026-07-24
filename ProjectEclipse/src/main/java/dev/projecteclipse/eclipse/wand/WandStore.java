package dev.projecteclipse.eclipse.wand;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.Mth;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Per-save wand state ({@code data/eclipse_wand.dat}, overworld storage via
 * {@link EclipseSavedData}): the per-<b>player</b> progression table that makes soulbind
 * conversion work ("picking up someone's wand converts it to YOUR wand"), plus the three
 * event-ops globals driven by {@code /dev wand …}:
 *
 * <ul>
 *   <li>{@code players}: UUID → (path, level, xp). In the default PLAYER mode this table is
 *       the single source of truth; item components are a synced mirror (see
 *       {@link WandSoulbind}).</li>
 *   <li>{@code perItemMode}: {@code /dev wand mode player|item} — in ITEM mode progression
 *       lives on the stack and conversion only rewrites the owner.</li>
 *   <li>{@code trading}: {@code /dev wand trading on|off} — while on, foreign wands are NOT
 *       converted (deliberate hand-over/showing around becomes possible).</li>
 *   <li>{@code disabledUntilEpochMs}: {@code /dev wand disable <minutes>} panic switch —
 *       all wands refuse to cast until the timestamp passes (0 = enabled).</li>
 * </ul>
 */
public final class WandStore extends SavedData {
    private static final String DATA_NAME = "eclipse_wand";

    /** Mutable per-player progression row. Call {@link #setDirty()} after edits. */
    public static final class Progress {
        public int pathId = WandPath.NONE.id();
        public int level = 1;
        public int xp;

        public WandPath path() {
            return WandPath.byId(pathId);
        }
    }

    private final Map<UUID, Progress> players = new HashMap<>();
    private boolean perItemMode;
    private boolean trading;
    private long disabledUntilEpochMs;

    public static WandStore get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_NAME,
                new SavedData.Factory<>(WandStore::new, WandStore::load));
    }

    public WandStore() {}

    public static WandStore load(CompoundTag tag, HolderLookup.Provider registries) {
        WandStore store = new WandStore();
        store.perItemMode = tag.getBoolean("perItemMode");
        store.trading = tag.getBoolean("trading");
        store.disabledUntilEpochMs = tag.getLong("disabledUntilEpochMs");
        ListTag list = tag.getList("players", Tag.TAG_COMPOUND);
        for (int i = 0; i < list.size(); i++) {
            CompoundTag entry = list.getCompound(i);
            if (!entry.hasUUID("id")) {
                continue;
            }
            Progress progress = new Progress();
            progress.pathId = WandPath.byId(entry.getInt("path")).id();
            progress.level = Mth.clamp(entry.getInt("level"), 1, WandPath.MAX_LEVEL);
            progress.xp = Math.max(0, entry.getInt("xp"));
            store.players.put(entry.getUUID("id"), progress);
        }
        return store;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        tag.putBoolean("perItemMode", perItemMode);
        tag.putBoolean("trading", trading);
        tag.putLong("disabledUntilEpochMs", disabledUntilEpochMs);
        ListTag list = new ListTag();
        for (Map.Entry<UUID, Progress> entry : players.entrySet()) {
            CompoundTag row = new CompoundTag();
            row.putUUID("id", entry.getKey());
            row.putInt("path", entry.getValue().pathId);
            row.putInt("level", entry.getValue().level);
            row.putInt("xp", entry.getValue().xp);
            list.add(row);
        }
        tag.put("players", list);
        return tag;
    }

    // ------------------------------------------------------------------ players

    /** Existing or freshly created (pathless, level 1) row for the player. */
    public Progress progress(UUID uuid) {
        return players.computeIfAbsent(uuid, key -> new Progress());
    }

    /** Drops the player's row entirely ({@code /dev wand reset}). */
    public void reset(UUID uuid) {
        players.remove(uuid);
        setDirty();
    }

    // ------------------------------------------------------------------ globals

    public boolean perItemMode() {
        return perItemMode;
    }

    public void setPerItemMode(boolean perItemMode) {
        this.perItemMode = perItemMode;
        setDirty();
    }

    public boolean tradingEnabled() {
        return trading;
    }

    public void setTradingEnabled(boolean trading) {
        this.trading = trading;
        setDirty();
    }

    public boolean isDisabled() {
        return disabledUntilEpochMs > System.currentTimeMillis();
    }

    /** Remaining disable window in whole seconds (0 when enabled). */
    public long disabledRemainingSeconds() {
        return Math.max(0L, (disabledUntilEpochMs - System.currentTimeMillis() + 999L) / 1000L);
    }

    public void disableForMinutes(int minutes) {
        this.disabledUntilEpochMs = System.currentTimeMillis() + minutes * 60_000L;
        setDirty();
    }

    public void enable() {
        this.disabledUntilEpochMs = 0L;
        setDirty();
    }
}
