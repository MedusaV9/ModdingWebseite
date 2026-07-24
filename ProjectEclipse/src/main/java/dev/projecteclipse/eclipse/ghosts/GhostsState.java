package dev.projecteclipse.eclipse.ghosts;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.BlockPos;
import net.minecraft.core.GlobalPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.core.registries.Registries;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.NbtUtils;
import net.minecraft.nbt.Tag;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Maps logout players to their ghost entity ({@code eclipse_ghosts.dat}).
 */
public final class GhostsState extends SavedData {
    public static final String DATA_ID = "eclipse_ghosts";

    private static final String TAG_ENTRIES = "entries";
    private static final String TAG_OWNER = "owner";
    private static final String TAG_GHOST = "ghostEntity";
    private static final String TAG_DIM = "dimension";
    private static final String TAG_POS = "pos";

    public record GhostRecord(UUID ghostEntityUuid, GlobalPos position) {}

    private final Map<UUID, GhostRecord> byOwner = new HashMap<>();

    public GhostsState() {}

    public static GhostsState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_ID,
                new SavedData.Factory<>(GhostsState::new, GhostsState::load));
    }

    public static GhostsState load(CompoundTag tag, HolderLookup.Provider registries) {
        GhostsState state = new GhostsState();
        if (tag.contains(TAG_ENTRIES, Tag.TAG_LIST)) {
            ListTag list = tag.getList(TAG_ENTRIES, Tag.TAG_COMPOUND);
            for (int i = 0; i < list.size(); i++) {
                CompoundTag entry = list.getCompound(i);
                UUID owner = NbtUtils.loadUUID(entry.get(TAG_OWNER));
                UUID ghost = NbtUtils.loadUUID(entry.get(TAG_GHOST));
                ResourceLocation dimId = ResourceLocation.parse(entry.getString(TAG_DIM));
                ResourceKey<Level> dim = ResourceKey.create(Registries.DIMENSION, dimId);
                BlockPos pos = NbtUtils.readBlockPos(entry, TAG_POS).orElse(BlockPos.ZERO);
                state.byOwner.put(owner, new GhostRecord(ghost, GlobalPos.of(dim, pos)));
            }
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        ListTag list = new ListTag();
        for (var entry : byOwner.entrySet()) {
            CompoundTag compound = new CompoundTag();
            compound.put(TAG_OWNER, NbtUtils.createUUID(entry.getKey()));
            compound.put(TAG_GHOST, NbtUtils.createUUID(entry.getValue().ghostEntityUuid()));
            compound.putString(TAG_DIM, entry.getValue().position().dimension().location().toString());
            compound.put(TAG_POS, NbtUtils.writeBlockPos(entry.getValue().position().pos()));
            list.add(compound);
        }
        tag.put(TAG_ENTRIES, list);
        return tag;
    }

    public GhostRecord get(UUID owner) {
        return byOwner.get(owner);
    }

    public void put(UUID owner, GhostRecord record) {
        byOwner.put(owner, record);
        setDirty();
    }

    public GhostRecord remove(UUID owner) {
        GhostRecord removed = byOwner.remove(owner);
        if (removed != null) {
            setDirty();
        }
        return removed;
    }

    public boolean hasRecord(UUID owner) {
        return byOwner.containsKey(owner);
    }

    public Map<UUID, GhostRecord> all() {
        return Map.copyOf(byOwner);
    }
}
