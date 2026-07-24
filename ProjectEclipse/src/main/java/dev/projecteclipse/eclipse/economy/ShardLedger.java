package dev.projecteclipse.eclipse.economy;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.StringTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * FIX-ECON (EVAL-SAT-S #3): persisted pending ledger for shard grants that could not be
 * delivered on the spot — participants who are offline, dead or out of the boss dimension
 * when a payout ceremony fires. Mirrors the {@code MinigameState.PendingPayout} offline
 * queue pattern: queue once by a stable, kill-scoped idempotency id, durably claim BEFORE
 * any player-visible grant, pay at next login ({@link ShardPayouts} owns delivery).
 *
 * <p>The pending queue and the delivered-marker set live in the SAME SavedData
 * ({@code eclipse_shard_ledger} in overworld storage), so a crash replay of a boss death
 * ceremony can never apply the same grant id twice.</p>
 */
public final class ShardLedger extends SavedData {
    public static final String DATA_NAME = "eclipse_shard_ledger";

    /**
     * One queued shard grant: a stable idempotency id (e.g. {@code boss:herald:<bossUuid>})
     * plus the personal-balance and physical-item shard amounts of the 50/50 split.
     */
    public record PendingGrant(String id, int personalShards, int physicalShards) {}

    private static final String TAG_PENDING = "pending";
    private static final String TAG_DELIVERED = "delivered";

    private final Map<UUID, List<PendingGrant>> pending = new HashMap<>();
    private final Map<UUID, Set<String>> deliveredIds = new HashMap<>();

    public ShardLedger() {}

    public static ShardLedger get(MinecraftServer server) {
        return server.overworld().getDataStorage().computeIfAbsent(
                new SavedData.Factory<>(ShardLedger::new, ShardLedger::load),
                DATA_NAME);
    }

    /** Queues once by stable grant id (skipped when already pending or already delivered). */
    public boolean queue(UUID player, PendingGrant grant) {
        if (deliveredIds.getOrDefault(player, Set.of()).contains(grant.id())) {
            return false;
        }
        List<PendingGrant> grants = pending.computeIfAbsent(player, key -> new ArrayList<>());
        if (grants.stream().anyMatch(existing -> existing.id().equals(grant.id()))) {
            return false;
        }
        grants.add(grant);
        setDirty();
        return true;
    }

    /** Immutable snapshot of one player's queued grants. */
    public List<PendingGrant> pending(UUID player) {
        List<PendingGrant> grants = pending.get(player);
        return grants == null ? List.of() : Collections.unmodifiableList(grants);
    }

    /**
     * Durably claims one queued grant by stable id BEFORE its effects are applied (the
     * {@code MinigameState.claimPayout} pattern): the delivered marker and the queue live
     * in the same SavedData, so a crash replay can never apply the same grant id twice.
     */
    public boolean claim(UUID player, String grantId) {
        Set<String> delivered = deliveredIds.computeIfAbsent(player, key -> new HashSet<>());
        if (!delivered.add(grantId)) {
            return false;
        }
        List<PendingGrant> grants = pending.get(player);
        if (grants != null) {
            grants.removeIf(grant -> grant.id().equals(grantId));
            if (grants.isEmpty()) {
                pending.remove(player);
            }
        }
        setDirty();
        return true;
    }

    // ------------------------------------------------------------------ NBT

    public static ShardLedger load(CompoundTag tag, HolderLookup.Provider registries) {
        ShardLedger ledger = new ShardLedger();
        for (Tag raw : tag.getList(TAG_PENDING, Tag.TAG_COMPOUND)) {
            CompoundTag playerTag = (CompoundTag) raw;
            if (!playerTag.hasUUID("uuid")) {
                continue;
            }
            List<PendingGrant> grants = new ArrayList<>();
            for (Tag grantRaw : playerTag.getList("grants", Tag.TAG_COMPOUND)) {
                CompoundTag grantTag = (CompoundTag) grantRaw;
                grants.add(new PendingGrant(grantTag.getString("id"),
                        grantTag.getInt("personal"), grantTag.getInt("physical")));
            }
            if (!grants.isEmpty()) {
                ledger.pending.put(playerTag.getUUID("uuid"), grants);
            }
        }
        for (Tag raw : tag.getList(TAG_DELIVERED, Tag.TAG_COMPOUND)) {
            CompoundTag playerTag = (CompoundTag) raw;
            if (!playerTag.hasUUID("uuid")) {
                continue;
            }
            Set<String> ids = new HashSet<>();
            for (Tag idTag : playerTag.getList("ids", Tag.TAG_STRING)) {
                ids.add(idTag.getAsString());
            }
            if (!ids.isEmpty()) {
                UUID uuid = playerTag.getUUID("uuid");
                ledger.deliveredIds.put(uuid, ids);
                // Reconcile a torn write: a grant both pending and delivered stays claimed.
                List<PendingGrant> grants = ledger.pending.get(uuid);
                if (grants != null) {
                    grants.removeIf(grant -> ids.contains(grant.id()));
                    if (grants.isEmpty()) {
                        ledger.pending.remove(uuid);
                    }
                }
            }
        }
        return ledger;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        ListTag pendingTag = new ListTag();
        for (Map.Entry<UUID, List<PendingGrant>> entry : pending.entrySet()) {
            CompoundTag playerTag = new CompoundTag();
            playerTag.putUUID("uuid", entry.getKey());
            ListTag grantList = new ListTag();
            for (PendingGrant grant : entry.getValue()) {
                CompoundTag grantTag = new CompoundTag();
                grantTag.putString("id", grant.id());
                grantTag.putInt("personal", grant.personalShards());
                grantTag.putInt("physical", grant.physicalShards());
                grantList.add(grantTag);
            }
            playerTag.put("grants", grantList);
            pendingTag.add(playerTag);
        }
        tag.put(TAG_PENDING, pendingTag);

        ListTag deliveredTag = new ListTag();
        for (Map.Entry<UUID, Set<String>> entry : deliveredIds.entrySet()) {
            CompoundTag playerTag = new CompoundTag();
            playerTag.putUUID("uuid", entry.getKey());
            ListTag ids = new ListTag();
            entry.getValue().stream().sorted().forEach(id -> ids.add(StringTag.valueOf(id)));
            playerTag.put("ids", ids);
            deliveredTag.add(playerTag);
        }
        tag.put(TAG_DELIVERED, deliveredTag);
        return tag;
    }
}
