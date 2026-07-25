package dev.projecteclipse.eclipse.glitchzone;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

import dev.projecteclipse.eclipse.core.state.EclipseSavedData;
import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.core.registries.Registries;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.Tag;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

/**
 * Persistent set of live {@link GlitchZone}s, stored in overworld data storage as
 * {@code data/eclipse_glitch_zones.dat} (the {@link EclipseSavedData#getOverworld} house
 * pattern — data dies with the save). Obtain via {@link #get(MinecraftServer)}; all
 * mutators mark the data dirty. Zones from unknown dimensions or with unknown effect ids
 * (e.g. a save touched by a newer build) are dropped silently on load — the event is
 * unannounced by design, so there is nothing to apologize for in chat.
 */
public final class GlitchZoneState extends SavedData {
    public static final String DATA_NAME = "eclipse_glitch_zones";

    /** Hard cap on simultaneously live zones (protects the per-tick player × zone scan). */
    public static final int MAX_ZONES = 64;

    private static final String TAG_ZONES = "zones";
    private static final String TAG_ID = "id";
    private static final String TAG_DIM = "dim";
    private static final String TAG_POS = "pos";
    private static final String TAG_RADIUS = "radius";
    private static final String TAG_EFFECT = "effect";
    private static final String TAG_END = "endGameTime";
    private static final String TAG_FADE = "fadeTicks";

    private final List<GlitchZone> zones = new ArrayList<>();

    public GlitchZoneState() {}

    public static GlitchZoneState get(MinecraftServer server) {
        return EclipseSavedData.getOverworld(server, DATA_NAME,
                new SavedData.Factory<>(GlitchZoneState::new, GlitchZoneState::load));
    }

    public static GlitchZoneState load(CompoundTag tag, HolderLookup.Provider registries) {
        GlitchZoneState state = new GlitchZoneState();
        for (Tag entry : tag.getList(TAG_ZONES, Tag.TAG_COMPOUND)) {
            CompoundTag zone = (CompoundTag) entry;
            if (!zone.hasUUID(TAG_ID) || !GlitchZoneEffects.isValid(zone.getString(TAG_EFFECT))) {
                continue;
            }
            double radius = zone.getDouble(TAG_RADIUS);
            if (radius <= 0.0D) {
                continue;
            }
            state.zones.add(new GlitchZone(
                    zone.getUUID(TAG_ID),
                    ResourceKey.create(Registries.DIMENSION, ResourceLocation.parse(zone.getString(TAG_DIM))),
                    BlockPos.of(zone.getLong(TAG_POS)),
                    radius,
                    zone.getString(TAG_EFFECT),
                    zone.getLong(TAG_END),
                    Math.max(0, zone.getInt(TAG_FADE))));
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        ListTag list = new ListTag();
        for (GlitchZone zone : this.zones) {
            CompoundTag entry = new CompoundTag();
            entry.putUUID(TAG_ID, zone.id());
            entry.putString(TAG_DIM, zone.dim().location().toString());
            entry.putLong(TAG_POS, zone.centre().asLong());
            entry.putDouble(TAG_RADIUS, zone.radius());
            entry.putString(TAG_EFFECT, zone.effect());
            entry.putLong(TAG_END, zone.endGameTime());
            entry.putInt(TAG_FADE, zone.fadeTicks());
            list.add(entry);
        }
        tag.put(TAG_ZONES, list);
        return tag;
    }

    /** Unmodifiable view of the live zones (expired entries are pruned by the service tick). */
    public List<GlitchZone> all() {
        return Collections.unmodifiableList(this.zones);
    }

    /** Adds a zone; returns {@code false} (and adds nothing) once {@link #MAX_ZONES} is hit. */
    public boolean add(GlitchZone zone) {
        if (this.zones.size() >= MAX_ZONES) {
            return false;
        }
        this.zones.add(zone);
        setDirty();
        return true;
    }

    /** Removes the zone with the given id; returns whether anything changed. */
    public boolean remove(UUID id) {
        boolean changed = this.zones.removeIf(zone -> zone.id().equals(id));
        if (changed) {
            setDirty();
        }
        return changed;
    }

    /** Removes every zone; returns how many were dropped. */
    public int clear() {
        int count = this.zones.size();
        if (count > 0) {
            this.zones.clear();
            setDirty();
        }
        return count;
    }

    /** Prunes zones whose {@code endGameTime} has passed; returns whether anything expired. */
    public boolean removeExpired(long now) {
        boolean changed = this.zones.removeIf(zone -> zone.endGameTime() <= now);
        if (changed) {
            setDirty();
        }
        return changed;
    }
}
