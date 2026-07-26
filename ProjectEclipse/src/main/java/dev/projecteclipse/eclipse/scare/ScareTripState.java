package dev.projecteclipse.eclipse.scare;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import javax.annotation.Nullable;

import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.Tag;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Persistent per-player state of F-065 backrooms scare trips (SavedData
 * {@code eclipse_scare_trips} in overworld storage, the {@code BackroomsState} NBT
 * conventions). Persistence is the whole point: a relog or server stop mid-trip must
 * never strand a player in the backrooms — {@link ScareTripService}'s login cleanup
 * reads the stored return anchor and pulls them back.
 *
 * <p>One record per player, two phases: {@code PENDING} (the clip script is running on
 * the client; the teleport into the backrooms is scheduled) and {@code INSIDE} (the
 * player is in the dimension until {@code endsAtEpochMillis}). Wall-clock epoch millis
 * like the sibling event states, so downtime counts against the trip.</p>
 */
public final class ScareTripState extends SavedData {
    public static final String DATA_NAME = "eclipse_scare_trips";

    /** Trip lifecycle. */
    public enum Phase {
        PENDING, INSIDE;

        static Phase byName(String name) {
            return "inside".equalsIgnoreCase(name) ? INSIDE : PENDING;
        }
    }

    /** One player's trip: return anchor + schedule. {@code seed} rides all trip beats. */
    public record Trip(Phase phase, ResourceKey<Level> dimension, double x, double y, double z,
            float yaw, float pitch, long teleportAtEpochMillis, long endsAtEpochMillis, long seed) {

        public Trip withPhase(Phase newPhase) {
            return new Trip(newPhase, dimension, x, y, z, yaw, pitch,
                    teleportAtEpochMillis, endsAtEpochMillis, seed);
        }
    }

    private final Map<UUID, Trip> trips = new HashMap<>();

    public ScareTripState() {}

    public static ScareTripState get(MinecraftServer server) {
        return server.overworld().getDataStorage().computeIfAbsent(
                new SavedData.Factory<>(ScareTripState::new, ScareTripState::load),
                DATA_NAME);
    }

    @Nullable
    public Trip trip(UUID uuid) {
        return trips.get(uuid);
    }

    public void put(UUID uuid, Trip trip) {
        trips.put(uuid, trip);
        setDirty();
    }

    public void remove(UUID uuid) {
        if (trips.remove(uuid) != null) {
            setDirty();
        }
    }

    /** Snapshot for the tick sweep (the map is mutated from inside the loop). */
    public Map<UUID, Trip> snapshot() {
        return Collections.unmodifiableMap(new HashMap<>(trips));
    }

    // ------------------------------------------------------------------ NBT

    public static ScareTripState load(CompoundTag tag, HolderLookup.Provider registries) {
        ScareTripState state = new ScareTripState();
        for (Tag entryTag : tag.getList("trips", Tag.TAG_COMPOUND)) {
            CompoundTag entry = (CompoundTag) entryTag;
            ResourceLocation dim = ResourceLocation.tryParse(entry.getString("dim"));
            if (dim == null) {
                continue;
            }
            state.trips.put(entry.getUUID("uuid"), new Trip(
                    Phase.byName(entry.getString("phase")),
                    ResourceKey.create(net.minecraft.core.registries.Registries.DIMENSION, dim),
                    entry.getDouble("x"), entry.getDouble("y"), entry.getDouble("z"),
                    entry.getFloat("yaw"), entry.getFloat("pitch"),
                    entry.getLong("teleportAt"), entry.getLong("endsAt"), entry.getLong("seed")));
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        ListTag list = new ListTag();
        for (Map.Entry<UUID, Trip> mapEntry : trips.entrySet()) {
            Trip trip = mapEntry.getValue();
            CompoundTag entry = new CompoundTag();
            entry.putUUID("uuid", mapEntry.getKey());
            entry.putString("phase", trip.phase().name().toLowerCase(java.util.Locale.ROOT));
            entry.putString("dim", trip.dimension().location().toString());
            entry.putDouble("x", trip.x());
            entry.putDouble("y", trip.y());
            entry.putDouble("z", trip.z());
            entry.putFloat("yaw", trip.yaw());
            entry.putFloat("pitch", trip.pitch());
            entry.putLong("teleportAt", trip.teleportAtEpochMillis());
            entry.putLong("endsAt", trip.endsAtEpochMillis());
            entry.putLong("seed", trip.seed());
            list.add(entry);
        }
        tag.put("trips", list);
        return tag;
    }
}
