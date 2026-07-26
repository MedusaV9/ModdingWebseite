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
 * unannounced by design, so there is nothing to apologize for in chat. An unknown COLOUR
 * is not fatal: it degrades to the effect's shipped accent.
 *
 * <p>The file also carries the {@link AltarGlitchAmbience} schedule (next/last fire in
 * overworld game time). It lives here rather than in {@code EclipseWorldState} so the whole
 * glitchzone feature owns exactly one save file.</p>
 */
public final class GlitchZoneState extends SavedData {
    public static final String DATA_NAME = "eclipse_glitch_zones";

    /** Hard cap on simultaneously live zones (protects the per-tick player × zone scan). */
    public static final int MAX_ZONES = 64;

    /** "Never fired" sentinel — far enough below 0 that {@code now - last} cannot overflow. */
    public static final long AMBIENT_NEVER = -1_000_000L;

    private static final String TAG_ZONES = "zones";
    private static final String TAG_ID = "id";
    private static final String TAG_DIM = "dim";
    private static final String TAG_POS = "pos";
    private static final String TAG_RADIUS = "radius";
    private static final String TAG_EFFECT = "effect";
    private static final String TAG_COLOUR = "colour";
    private static final String TAG_START = "startGameTime";
    private static final String TAG_END = "endGameTime";
    private static final String TAG_FADE_IN = "fadeInTicks";
    private static final String TAG_FADE = "fadeTicks";
    private static final String TAG_ORIGIN_CENTRE = "originAtCentre";
    private static final String TAG_AMBIENT_NEXT = "ambientNextGameTime";
    private static final String TAG_AMBIENT_LAST = "ambientLastGameTime";

    private final List<GlitchZone> zones = new ArrayList<>();

    /** Overworld game time the altar ambience may next fire at; 0 = "roll a first date". */
    private long ambientNextGameTime = 0L;
    /** Overworld game time the altar ambience last fired at (the minimum-gap anchor). */
    private long ambientLastGameTime = AMBIENT_NEVER;

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
            // Pre-F-049 zones have no colour/start/fade-in/origin tags: getString returns
            // "" (= the shipped accent), getLong/getInt return 0 (= no in-ramp, camera
            // origin, and a start that is already in the past). Old saves keep working.
            state.zones.add(new GlitchZone(
                    zone.getUUID(TAG_ID),
                    ResourceKey.create(Registries.DIMENSION, ResourceLocation.parse(zone.getString(TAG_DIM))),
                    BlockPos.of(zone.getLong(TAG_POS)),
                    radius,
                    zone.getString(TAG_EFFECT),
                    GlitchColors.normalize(zone.getString(TAG_COLOUR)),
                    zone.getLong(TAG_START),
                    zone.getLong(TAG_END),
                    Math.max(0, zone.getInt(TAG_FADE_IN)),
                    Math.max(0, zone.getInt(TAG_FADE)),
                    zone.getBoolean(TAG_ORIGIN_CENTRE)));
        }
        state.ambientNextGameTime = tag.getLong(TAG_AMBIENT_NEXT);
        state.ambientLastGameTime = tag.contains(TAG_AMBIENT_LAST)
                ? tag.getLong(TAG_AMBIENT_LAST) : AMBIENT_NEVER;
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
            entry.putString(TAG_COLOUR, zone.colour());
            entry.putLong(TAG_START, zone.startGameTime());
            entry.putLong(TAG_END, zone.endGameTime());
            entry.putInt(TAG_FADE_IN, zone.fadeInTicks());
            entry.putInt(TAG_FADE, zone.fadeTicks());
            entry.putBoolean(TAG_ORIGIN_CENTRE, zone.originAtCentre());
            list.add(entry);
        }
        tag.put(TAG_ZONES, list);
        tag.putLong(TAG_AMBIENT_NEXT, this.ambientNextGameTime);
        tag.putLong(TAG_AMBIENT_LAST, this.ambientLastGameTime);
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

    /**
     * Repaints one live zone ({@code /dev glitch color <id> <colour>}); returns whether a
     * zone with that id existed. The client cross-fades the accent, so a repaint mid-zone
     * is a colour SLIDE, not a pop.
     */
    public boolean recolour(UUID id, String colour) {
        for (int i = 0; i < this.zones.size(); i++) {
            GlitchZone zone = this.zones.get(i);
            if (zone.id().equals(id)) {
                this.zones.set(i, zone.withColour(colour));
                setDirty();
                return true;
            }
        }
        return false;
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

    // --- altar ambience schedule (F-048) ------------------------------------------------

    /** Earliest overworld game time the altar ambience may fire; 0 = not scheduled yet. */
    public long ambientNextGameTime() {
        return this.ambientNextGameTime;
    }

    /** Overworld game time of the last altar ambience, or {@link #AMBIENT_NEVER}. */
    public long ambientLastGameTime() {
        return this.ambientLastGameTime;
    }

    /** Arms the next altar ambience date (persisted: a restart never re-rolls the cadence). */
    public void setAmbientNextGameTime(long gameTime) {
        this.ambientNextGameTime = gameTime;
        setDirty();
    }

    /** Records a fire: stamps the minimum-gap anchor and arms the next date in one write. */
    public void markAmbientFired(long now, long nextGameTime) {
        this.ambientLastGameTime = now;
        this.ambientNextGameTime = nextGameTime;
        setDirty();
    }
}
