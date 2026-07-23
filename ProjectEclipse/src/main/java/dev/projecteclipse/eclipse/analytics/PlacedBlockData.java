package dev.projecteclipse.eclipse.analytics;

import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

import com.mojang.serialization.Codec;

import it.unimi.dsi.fastutil.ints.Int2ObjectMap;
import it.unimi.dsi.fastutil.ints.Int2ObjectOpenHashMap;

/**
 * Chunk attachment payload for the player-placed block tracker (P4-B5). Each section
 * (16-block Y slice) maps to a 4096-bit bitset stored as {@code long[64]} — one bit per
 * block in the section. Analytics owns read/write logic; this class is the serializable shell.
 */
public final class PlacedBlockData {
    /** Longs per section bitset ({@code 64 * 64 == 4096} bits). */
    public static final int LONGS_PER_SECTION = 64;

    private final Int2ObjectMap<long[]> sections = new Int2ObjectOpenHashMap<>();

    public PlacedBlockData() {}

    private PlacedBlockData(Int2ObjectMap<long[]> sections) {
        this.sections.putAll(sections);
    }

    /** Mutable section map for the tracker worker. Keys are section Y indices ({@code pos.getY() >> 4}). */
    public Int2ObjectMap<long[]> sections() {
        return sections;
    }

    /**
     * Returns the bitset for a section, allocating lazily when {@code create} is true.
     */
    public long[] sectionBits(int sectionIndex, boolean create) {
        long[] bits = sections.get(sectionIndex);
        if (bits == null && create) {
            bits = new long[LONGS_PER_SECTION];
            sections.put(sectionIndex, bits);
        }
        return bits;
    }

    private static final Codec<long[]> LONG_ARRAY_CODEC = Codec.LONG.listOf().xmap(
            list -> {
                long[] arr = new long[list.size()];
                for (int i = 0; i < list.size(); i++) {
                    arr[i] = list.get(i);
                }
                return arr;
            },
            arr -> {
                Long[] boxed = new Long[arr.length];
                for (int i = 0; i < arr.length; i++) {
                    boxed[i] = arr[i];
                }
                return Arrays.asList(boxed);
            });

    private static final Codec<Map<String, long[]>> SECTION_MAP_CODEC = Codec.unboundedMap(
            Codec.STRING, LONG_ARRAY_CODEC);

    /** Attachment / disk codec. Section keys are decimal Y-section indices. */
    public static final Codec<PlacedBlockData> CODEC = SECTION_MAP_CODEC.xmap(
            map -> {
                Int2ObjectMap<long[]> converted = new Int2ObjectOpenHashMap<>();
                map.forEach((key, value) -> converted.put(Integer.parseInt(key), value));
                return new PlacedBlockData(converted);
            },
            data -> {
                Map<String, long[]> out = new HashMap<>();
                data.sections.forEach((section, bits) -> out.put(Integer.toString(section), bits));
                return out;
            });

    /** Empty default for chunk attachments. */
    public static PlacedBlockData empty() {
        return new PlacedBlockData();
    }

    @Override
    public boolean equals(Object o) {
        if (o == this) {
            return true;
        }
        if (!(o instanceof PlacedBlockData other)) {
            return false;
        }
        if (sections.size() != other.sections.size()) {
            return false;
        }
        for (var entry : sections.int2ObjectEntrySet()) {
            long[] theirs = other.sections.get(entry.getIntKey());
            if (theirs == null || !Arrays.equals(entry.getValue(), theirs)) {
                return false;
            }
        }
        return true;
    }

    @Override
    public int hashCode() {
        int hash = 0;
        for (var entry : sections.int2ObjectEntrySet()) {
            hash = 31 * hash + entry.getIntKey();
            hash = 31 * hash + Arrays.hashCode(entry.getValue());
        }
        return hash;
    }
}
