package dev.projecteclipse.eclipse.skills;

import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.StringTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Per-save skill persistence (SavedData {@code eclipse_skills} in overworld storage —
 * dies with the save by construction, plan rule 4). Keyed by UUID so offline players stay
 * queryable. Levels are NEVER stored — always derived from {@code totalXp} via
 * {@link SkillCurve} so curve retunes stay consistent; {@code lastLevelSeen} only tracks the
 * highest level already rewarded (points/cues) and never decreases.
 */
public final class SkillState extends SavedData {
    public static final String DATA_NAME = "eclipse_skills";

    /** Mutable per-player record. Call {@link SkillState#setDirty()} after writes. */
    public static final class Entry {
        /** Lifetime skill XP; floored at 0 (death penalty can never go negative). */
        public long totalXp = 0L;
        /** Points spent on tree nodes. Earned points == {@code lastLevelSeen} (1/level). */
        public int spentPoints = 0;
        public final Set<String> ownedNodes = new LinkedHashSet<>();
        /** Chat proc line opt-out (R3); toggled via {@code /skills procmsg}. */
        public boolean procMsgEnabled = true;
        /** Admin-only hidden XP multiplier — never synced, never logged above DEBUG. */
        public float secretMultiplier = 1.0F;
        /** Highest level already rewarded with a point + level-up cue. Never decreases. */
        public int lastLevelSeen = 0;
        /** Extra points granted via {@code SkillsApi.addPoints} (dev/reward surface). */
        public int bonusPoints = 0;
        /** Fractional XP carry so 0.5-value actions pay out without rounding loss. */
        public float xpRemainder = 0.0F;
        /** Event day the daily-cap counters belong to (self-invalidating). */
        public int capDay = 0;
        /** Final granted XP per source key for {@code capDay}. */
        public final Map<String, Float> capUsed = new HashMap<>();

        /** Total points ever earned: one per level plus dev-granted bonus points. */
        public int totalPoints() {
            return Math.max(0, lastLevelSeen + bonusPoints);
        }

        public int unspentPoints() {
            return Math.max(0, totalPoints() - spentPoints);
        }
    }

    private final Map<UUID, Entry> players = new HashMap<>();

    public SkillState() {}

    public static SkillState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_NAME,
                new SavedData.Factory<>(SkillState::new, SkillState::load));
    }

    /** Existing entry or a fresh default one (not persisted until something marks dirty). */
    public Entry entry(UUID uuid) {
        return players.computeIfAbsent(uuid, ignored -> new Entry());
    }

    /** Read-only view for iteration (commands / debug). */
    public Map<UUID, Entry> entries() {
        return java.util.Collections.unmodifiableMap(players);
    }

    public static SkillState load(CompoundTag tag, HolderLookup.Provider registries) {
        SkillState state = new SkillState();
        for (Tag element : tag.getList("players", Tag.TAG_COMPOUND)) {
            CompoundTag playerTag = (CompoundTag) element;
            if (!playerTag.hasUUID("uuid")) {
                continue;
            }
            Entry entry = new Entry();
            entry.totalXp = Math.max(0L, playerTag.getLong("xp"));
            entry.spentPoints = Math.max(0, playerTag.getInt("spent"));
            for (Tag node : playerTag.getList("nodes", Tag.TAG_STRING)) {
                entry.ownedNodes.add(node.getAsString());
            }
            // Default true for pre-existing entries written before the flag existed.
            entry.procMsgEnabled = !playerTag.contains("procMsg") || playerTag.getBoolean("procMsg");
            entry.secretMultiplier = playerTag.contains("mult") ? playerTag.getFloat("mult") : 1.0F;
            entry.lastLevelSeen = Math.max(0, playerTag.getInt("lastLevel"));
            entry.bonusPoints = Math.max(0, playerTag.getInt("bonusPoints"));
            entry.xpRemainder = playerTag.getFloat("remainder");
            entry.capDay = playerTag.getInt("capDay");
            CompoundTag caps = playerTag.getCompound("capUsed");
            for (String key : caps.getAllKeys()) {
                entry.capUsed.put(key, caps.getFloat(key));
            }
            state.players.put(playerTag.getUUID("uuid"), entry);
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        ListTag list = new ListTag();
        for (Map.Entry<UUID, Entry> mapEntry : players.entrySet()) {
            Entry entry = mapEntry.getValue();
            CompoundTag playerTag = new CompoundTag();
            playerTag.putUUID("uuid", mapEntry.getKey());
            playerTag.putLong("xp", entry.totalXp);
            playerTag.putInt("spent", entry.spentPoints);
            ListTag nodes = new ListTag();
            for (String node : entry.ownedNodes) {
                nodes.add(StringTag.valueOf(node));
            }
            playerTag.put("nodes", nodes);
            playerTag.putBoolean("procMsg", entry.procMsgEnabled);
            playerTag.putFloat("mult", entry.secretMultiplier);
            playerTag.putInt("lastLevel", entry.lastLevelSeen);
            playerTag.putInt("bonusPoints", entry.bonusPoints);
            playerTag.putFloat("remainder", entry.xpRemainder);
            playerTag.putInt("capDay", entry.capDay);
            CompoundTag caps = new CompoundTag();
            for (Map.Entry<String, Float> cap : entry.capUsed.entrySet()) {
                caps.putFloat(cap.getKey(), cap.getValue());
            }
            playerTag.put("capUsed", caps);
            list.add(playerTag);
        }
        tag.put("players", list);
        return tag;
    }
}
