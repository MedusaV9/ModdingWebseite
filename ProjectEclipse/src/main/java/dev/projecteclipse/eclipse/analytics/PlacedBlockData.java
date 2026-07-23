package dev.projecteclipse.eclipse.analytics;

import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

import com.mojang.serialization.Codec;

import it.unimi.dsi.fastutil.ints.Int2ObjectMap;
import it.unimi.dsi.fastutil.ints.Int2ObjectOpenHashMap;
import net.minecraft.server.level.ServerLevel;

/**
 * Chunk attachment payload for the player-placed block tracker (P4-B5). Each section
 * (16-block Y slice) maps to a 4096-bit bitset stored as {@code long[64]} — one bit per
 * block in the section. Analytics owns read/write logic; this class is the serializable shell.
 */
public final class PlacedBlockData {
    /** Longs per section bitset ({@code 64 * 64 == 4096} bits). */
    public static final int LONGS_PER_SECTION = 64;
    private static final String FORMAT_KEY = "_eclipse_section_format";
    private static final long FORMAT_LEVEL_INDEXED = 2L;

    private final Int2ObjectMap<long[]> sections = new Int2ObjectOpenHashMap<>();
    /**
     * Legacy attachments keyed sections by absolute section Y ({@code blockY >> 4}). V2 keys
     * by {@code level.getSectionIndex(blockY)}; this flag and min-section marker let the old
     * tracker call shape coexist while chunks migrate lazily on their first lookup.
     */
    private boolean levelIndexed;
    private int minSection;

    public PlacedBlockData() {}

    private PlacedBlockData(Int2ObjectMap<long[]> sections, boolean levelIndexed, int minSection) {
        this.sections.putAll(sections);
        this.levelIndexed = levelIndexed;
        this.minSection = minSection;
    }

    /** Mutable section map for diagnostics. V2 keys are level-relative section indices. */
    public Int2ObjectMap<long[]> sections() {
        return sections;
    }

    /**
     * Compatibility entry point used by {@code PlacedBlockTracker}, whose argument is an
     * absolute section coordinate ({@code blockY >> 4}). Once this attachment has migrated,
     * the coordinate is translated to the level-relative index before lookup/write.
     */
    public long[] sectionBits(int sectionCoordinate, boolean create) {
        int key = levelIndexed ? sectionCoordinate - minSection : sectionCoordinate;
        return sectionBitsByLevelIndex(key, create);
    }

    /** Direct v2 lookup by {@link ServerLevel#getSectionIndex(int)} result. */
    public long[] sectionBitsByLevelIndex(int sectionIndex, boolean create) {
        long[] bits = sections.get(sectionIndex);
        if (bits == null && create) {
            bits = new long[LONGS_PER_SECTION];
            sections.put(sectionIndex, bits);
        }
        return bits;
    }

    /**
     * Lazily converts old absolute section-Y keys to level-relative indices. The probe also
     * preserves pre-v2 test/helper data that was already written with a relative key. Returns
     * true exactly once so the caller can mark the chunk unsaved and persist the format marker.
     */
    public boolean ensureLevelIndexed(ServerLevel level, int probeBlockY) {
        if (levelIndexed) {
            return false;
        }
        int newMinSection = level.getMinSection();
        int probeLevelIndex = level.getSectionIndex(probeBlockY);
        int probeAbsoluteSection = probeBlockY >> 4;
        /*
         * Some pre-v2 helper callers already supplied getSectionIndex(y), while the real
         * tracker supplied y >> 4. A lone probe-relative key is the only unambiguous signal
         * that this attachment is already relative; when both candidates exist, prefer the
         * production tracker's legacy absolute format. At worst an ambiguous old chunk can
         * misclassify one section during migration, which is safer than shifting known-v2
         * data a second time.
         */
        boolean alreadyRelative = probeLevelIndex != probeAbsoluteSection
                && sections.containsKey(probeLevelIndex)
                && !sections.containsKey(probeAbsoluteSection);
        if (!alreadyRelative) {
            Int2ObjectMap<long[]> migrated = new Int2ObjectOpenHashMap<>();
            for (var entry : sections.int2ObjectEntrySet()) {
                migrated.put(entry.getIntKey() - newMinSection, entry.getValue());
            }
            sections.clear();
            sections.putAll(migrated);
        }
        minSection = newMinSection;
        levelIndexed = true;
        return true;
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
                boolean levelIndexed = false;
                int minSection = 0;
                for (Map.Entry<String, long[]> entry : map.entrySet()) {
                    if (FORMAT_KEY.equals(entry.getKey())) {
                        long[] marker = entry.getValue();
                        if (marker.length >= 2 && marker[0] == FORMAT_LEVEL_INDEXED) {
                            levelIndexed = true;
                            minSection = (int) marker[1];
                        }
                    } else {
                        converted.put(Integer.parseInt(entry.getKey()), entry.getValue());
                    }
                }
                return new PlacedBlockData(converted, levelIndexed, minSection);
            },
            data -> {
                Map<String, long[]> out = new HashMap<>();
                data.sections.forEach((section, bits) -> out.put(Integer.toString(section), bits));
                if (data.levelIndexed) {
                    out.put(FORMAT_KEY, new long[] {FORMAT_LEVEL_INDEXED, data.minSection});
                }
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
        if (levelIndexed != other.levelIndexed || minSection != other.minSection
                || sections.size() != other.sections.size()) {
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
        int hash = Boolean.hashCode(levelIndexed);
        hash = 31 * hash + minSection;
        for (var entry : sections.int2ObjectEntrySet()) {
            hash = 31 * hash + entry.getIntKey();
            hash = 31 * hash + Arrays.hashCode(entry.getValue());
        }
        return hash;
    }
}
