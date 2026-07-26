package dev.projecteclipse.eclipse.worldgen;

import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
import java.util.stream.Stream;

import javax.annotation.Nullable;

import com.mojang.serialization.MapCodec;
import com.mojang.serialization.codecs.RecordCodecBuilder;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.Holder;
import net.minecraft.core.HolderGetter;
import net.minecraft.core.QuartPos;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.RegistryOps;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.level.biome.Biome;
import net.minecraft.world.level.biome.BiomeSource;
import net.minecraft.world.level.biome.Biomes;
import net.minecraft.world.level.biome.Climate;

/**
 * Biome source of the disc world ({@code eclipse:disc_sectors}), v2: the authored 2-D
 * map (pie wedges via {@link DiscMapData#biomeAt}, now split into sub-rings via
 * {@link DiscMapDefaults#ringBiome}) plus a y-aware 3-D layer (D4.3/D6):
 *
 * <ul>
 *   <li><b>Cave biomes</b> below {@code surfaceY − 14}: dripstone / lush regions from
 *       {@link CaveBiomeMap}, {@code minecraft:deep_dark} under the mountain below
 *       y −96 (Ancient City region); the neutral band keeps the surface biome. WG2
 *       y-bands the regions per sample ({@link CaveBiomeMap#bandedBiome}): deep lush →
 *       {@code eclipse:fungal_hollows}, deep dripstone → {@code eclipse:ember_depths},
 *       the crystal detail region → {@code eclipse:crystal_chasms}, and the neutral
 *       band below y −96 → {@code eclipse:umbral_depths} (the basement no longer reads
 *       the surface biome).</li>
 *   <li><b>End sky band</b>: {@code minecraft:the_end} for EVERY column above y 320
 *       (plans_v5 PLAN-C C12) — always on (the biome pre-exists the materialization
 *       flag harmlessly, so chunks baked early stay correct). The band deliberately
 *       ignores the {@code EndDiscGeometry} footprint: vanilla precipitation gets
 *       colder with altitude, so footprint-edged columns snowed onto the disc rim
 *       through biome-quart blending. Nothing else legitimately occupies the band
 *       (the wizard mountain tops out at ≈ 280; see
 *       {@code gametest.worldgen.EndBiomeBandTest}), so the whole sky layer reads
 *       End: no precipitation, no snow accumulation, correct sky/fog tint.</li>
 *   <li><b>Mountain</b>: core flips to {@code minecraft:jagged_peaks} above y 200; the
 *       flank ring splits into flank biome / cherry grove / meadow thirds. A snowline
 *       overlay (plans_v5 PLAN-B B1) covers the WHOLE mountain footprint: any sample at
 *       {@code by >= }{@value #SNOWLINE_Y} inside {@code mountain.radius()} reads
 *       {@code minecraft:snowy_slopes} (jagged core above y 200 still outranks), so
 *       {@code freeze_top_layer} snow/ice persists and high-altitude rain falls as snow
 *       instead of melting the caps into runoff.</li>
 *   <li><b>River ribbon</b>: {@code minecraft:river} along the authored polylines
 *       (channel + banks), upgraded to {@code minecraft:frozen_river} inside the snow
 *       mountain's frost region — polyline #1 starts on the flank BELOW the snowline, so
 *       B1 never reached it and a warm river gash used to cut through the glacier
 *       (F-026, see {@link SnowMountainFrost}).</li>
 *   <li><b>Detached shards</b>: crumble shards off the FINAL rim read
 *       {@code minecraft:mushroom_fields} (exact — evaluated through the terrain
 *       function's own final-stage shard predicate).</li>
 * </ul>
 *
 * <p>Every lookup is a pure function of position + frozen per-save data — never the
 * current world stage. Biomes are baked into chunk sections at generation time and ring
 * sweeps rewrite only blocks, so a chunk generated as void at stage 1 must already carry
 * the biomes its terrain will expose when the rim grows over it at stage 5.</p>
 *
 * <p>Per-sample cost is kept flat by a per-thread direct-mapped column cache: one
 * {@link ColumnInfo} per (x, z) covers all ~160 y-quarts of a column fill. The cache
 * self-invalidates when {@link DiscMapData} swaps instances (save load, reload,
 * refreeze).</p>
 */
public final class DiscBiomeSource extends BiomeSource {
    public static final MapCodec<DiscBiomeSource> CODEC = RecordCodecBuilder.mapCodec(
            instance -> instance.group(
                    DiscProfile.CODEC.fieldOf("profile").forGetter(source -> source.profile),
                    RegistryOps.retrieveGetter(Registries.BIOME))
            .apply(instance, instance.stable(DiscBiomeSource::new)));

    /**
     * {@code minecraft:the_end} applies to EVERY column above this block Y (C12). No
     * authored terrain may exceed it outside the disc: {@code DiscTerrainFunction}'s
     * mountain peaks at ≈ 280 and {@code EndDiscGeometry.MIN_Y} is 340 — asserted by
     * {@code gametest.worldgen.EndBiomeBandTest}.
     */
    public static final int END_BIOME_MIN_Y = 320;
    /** Mountain-core samples above this block Y read {@code minecraft:jagged_peaks}. */
    public static final int JAGGED_PEAKS_MIN_Y = 200;
    /**
     * Mountain-footprint samples at/above this block Y read {@code minecraft:snowy_slopes}
     * (B1 snowline overlay) — just above the terrace-quantization start (y 150 in
     * {@code DiscTerrainFunction.computeSurfaceY}) so the stepped cliff bands read snowy.
     */
    public static final int SNOWLINE_Y = 152;
    /** River-ribbon biome inside the snow mountain's frost region ({@link SnowMountainFrost}). */
    private static final String FROST_RIVER_ID = "minecraft:frozen_river";
    /** River-ribbon half width: channel ({@code RIVER_HALF_WIDTH}) + bank margin. */
    public static final double RIVER_BIOME_HALF_WIDTH =
            DiscTerrainFunction.RIVER_HALF_WIDTH + DiscTerrainFunction.RIVER_BANK_MARGIN;
    /**
     * Columns within this many blocks of the final rim radius run the exact (heavier)
     * final-stage shard predicate; everything farther inside can never be a shard. Wide
     * enough to cover the rim noise wobble + the outside crumble band.
     */
    private static final int SHARD_BAND_MARGIN = 64;

    /** Direct-mapped per-thread column cache size (power of two). */
    private static final int CACHE_SIZE = 2048;

    private final DiscProfile profile;
    private final Map<String, Holder<Biome>> biomesById;
    private final Holder<Biome> fallback;
    /** Hot-path holders (null where the overlay does not apply to this profile). */
    @Nullable
    private final Holder<Biome> endHolder;
    @Nullable
    private final Holder<Biome> deepDarkHolder;
    @Nullable
    private final Holder<Biome> jaggedHolder;
    @Nullable
    private final Holder<Biome> snowySlopesHolder;

    private final ThreadLocal<ColumnCache> columnCache = ThreadLocal.withInitial(ColumnCache::new);

    public DiscBiomeSource(DiscProfile profile, HolderGetter<Biome> biomes) {
        this.profile = profile;
        this.fallback = biomes.getOrThrow(profile == DiscProfile.NETHER
                ? Biomes.NETHER_WASTES : Biomes.PLAINS);
        this.biomesById = resolveBiomes(profile, biomes, this.fallback);
        boolean overworld = profile != DiscProfile.NETHER;
        this.endHolder = overworld ? this.biomesById.get("minecraft:the_end") : null;
        this.deepDarkHolder = overworld ? this.biomesById.get(CaveBiomeMap.DEEP_DARK_ID) : null;
        this.jaggedHolder = overworld ? this.biomesById.get("minecraft:jagged_peaks") : null;
        this.snowySlopesHolder = overworld ? this.biomesById.get("minecraft:snowy_slopes") : null;
    }

    /**
     * Resolves every biome id the v2 lookup can produce: the static
     * {@link DiscMapDefaults#allBiomeIds} table (ring outputs, cave/end/special ids)
     * unioned with whatever the live (possibly user-authored) map references. Unknown or
     * unparsable ids warn once and fall back, matching the data-driven contract.
     */
    private static Map<String, Holder<Biome>> resolveBiomes(DiscProfile profile,
            HolderGetter<Biome> biomes, Holder<Biome> fallback) {
        DiscMapData.MapProfile map = DiscMapData.get().profile(profile);
        Set<String> ids = new LinkedHashSet<>(DiscMapDefaults.allBiomeIds(profile));
        ids.add(map.centerBiome());
        for (DiscMapData.Sector sector : map.sectors()) {
            ids.add(sector.biome());
        }
        if (map.mountain() != null) {
            ids.add(map.mountain().coreBiome());
            ids.add(map.mountain().flankBiome());
            ids.add(FROST_RIVER_ID); // F-026: the river ribbon inside the frost region
        }
        Map<String, Holder<Biome>> resolved = new LinkedHashMap<>();
        for (String id : ids) {
            ResourceLocation location = ResourceLocation.tryParse(id);
            if (location == null) {
                EclipseMod.LOGGER.warn("disc map: invalid biome id '{}'; using fallback", id);
                resolved.put(id, fallback);
                continue;
            }
            var holder = biomes.get(ResourceKey.create(Registries.BIOME, location));
            if (holder.isPresent()) {
                resolved.put(id, holder.get());
            } else {
                EclipseMod.LOGGER.warn("disc map: unknown biome '{}'; using fallback", id);
                resolved.put(id, fallback);
            }
        }
        return Map.copyOf(resolved);
    }

    public DiscProfile profile() {
        return this.profile;
    }

    @Override
    protected MapCodec<? extends BiomeSource> codec() {
        return CODEC;
    }

    @Override
    protected Stream<Holder<Biome>> collectPossibleBiomes() {
        return Stream.concat(this.biomesById.values().stream(), Stream.of(this.fallback)).distinct();
    }

    @Override
    public Holder<Biome> getNoiseBiome(int x, int y, int z, Climate.Sampler sampler) {
        int bx = QuartPos.toBlock(x) + 2;
        int by = QuartPos.toBlock(y) + 2;
        int bz = QuartPos.toBlock(z) + 2;
        // 1. End sky band (overworld only, always on — pre-exists harmlessly). The WHOLE
        //    layer above END_BIOME_MIN_Y is the_end, not just the disc footprint: the
        //    old footprint check left neighboring high-altitude columns snowy/cold, and
        //    quart blending rendered their snowfall over the disc rim (C12).
        if (this.endHolder != null && by > END_BIOME_MIN_Y) {
            return this.endHolder;
        }
        ColumnInfo info = columnInfo(bx, bz);
        // 2. Underground: deep dark under the mountain, then the dripstone/lush/crystal
        //    regions (WG2 y-bands split their deep halves into fungal_hollows /
        //    ember_depths); the neutral band falls through to the surface biome
        //    (vanilla-style) until the umbral basement takes over below y −96.
        if (this.profile != DiscProfile.NETHER && by < info.surfaceY() - CaveBiomeMap.SURFACE_MARGIN) {
            if (info.deepDark() && by < CaveBiomeMap.DEEP_DARK_MAX_Y && this.deepDarkHolder != null) {
                return this.deepDarkHolder;
            }
            String region = info.caveRegion();
            if (region != null) {
                return holderOf(CaveBiomeMap.bandedBiome(region, by));
            }
            if (by < CaveBiomeMap.UMBRAL_MAX_Y) {
                return holderOf(CaveBiomeMap.UMBRAL_DEPTHS_ID);
            }
        }
        // 3. High mountain core reads jagged peaks.
        if (info.jaggedCore() && by > JAGGED_PEAKS_MIN_Y && this.jaggedHolder != null) {
            return this.jaggedHolder;
        }
        // 4. Snowline overlay (B1): every above-snowline sample of the whole mountain
        //    footprint is snowy — y-aware like the jagged rule, so vertical cliff faces
        //    and the frozen-cascade sides freeze consistently, not just column tops.
        if (info.mountainFootprint() && by >= SNOWLINE_Y && this.snowySlopesHolder != null) {
            return this.snowySlopesHolder;
        }
        return info.base();
    }

    /**
     * Cached per-column data: 2-D resolution + everything the y rules key off.
     * {@code caveRegion} stays the RAW region id (not a holder) since WG2 — the y-banded
     * biome is resolved per sample via {@link CaveBiomeMap#bandedBiome} + the immutable
     * {@code biomesById} map, which is a plain map hit on the hot path.
     */
    private record ColumnInfo(Holder<Biome> base, int surfaceY, boolean jaggedCore,
            boolean mountainFootprint, @Nullable String caveRegion, boolean deepDark) {}

    /** Per-thread direct-mapped cache; keyed to the live {@link DiscMapData} instance. */
    private static final class ColumnCache {
        final long[] keys = new long[CACHE_SIZE];
        final ColumnInfo[] values = new ColumnInfo[CACHE_SIZE];
        DiscMapData map;

        ColumnCache() {
            Arrays.fill(this.keys, Long.MIN_VALUE);
        }
    }

    private ColumnInfo columnInfo(int bx, int bz) {
        ColumnCache cache = this.columnCache.get();
        DiscMapData map = DiscMapData.get();
        if (cache.map != map) {
            // Map swapped (save load / reload / refreeze) — drop every cached column.
            Arrays.fill(cache.keys, Long.MIN_VALUE);
            Arrays.fill(cache.values, null);
            cache.map = map;
        }
        long key = ((long) bx << 32) ^ (bz & 0xFFFFFFFFL);
        int slot = (int) (mix(key) & (CACHE_SIZE - 1));
        if (cache.keys[slot] == key) {
            return cache.values[slot];
        }
        ColumnInfo info = resolveColumn(map, bx, bz);
        cache.keys[slot] = key;
        cache.values[slot] = info;
        return info;
    }

    /**
     * Full 2-D resolution of one column. Order: mountain core → river ribbon → mountain
     * flank ring → center cap → final-rim shard check → wedge + sub-rings. The river
     * outranks flank/center because the terrain function carves its channel through
     * both; the mountain core outranks the river (no river reaches it by authoring).
     */
    private ColumnInfo resolveColumn(DiscMapData map, int bx, int bz) {
        if (this.profile == DiscProfile.NETHER) {
            // Nether stays the plain 2-D wedge map (Appendix A: ids unchanged, no rings).
            return new ColumnInfo(holderOf(map.biomeAt(this.profile, bx, bz)), 0, false, false, null, false);
        }
        DiscMapData.MapProfile mapProfile = map.profile(this.profile);
        DiscMapData.Mountain mountain = mapProfile.mountain();
        int surfaceY = DiscTerrainFunction.surfaceY(this.profile, bx, bz);
        boolean jaggedCore = false;
        boolean mountainFootprint = false;
        String id = null;
        double mountainDistSq = Double.MAX_VALUE;
        if (mountain != null) {
            double dx = bx - mountain.x();
            double dz = bz - mountain.z();
            mountainDistSq = dx * dx + dz * dz;
            mountainFootprint = mountainDistSq < (double) mountain.radius() * mountain.radius();
            double coreR = mountain.radius() * 0.45D;
            if (mountainDistSq < coreR * coreR) {
                id = mountain.coreBiome();
                jaggedCore = true;
            }
        }
        if (id == null && map.riverDistance(this.profile, bx, bz) < RIVER_BIOME_HALF_WIDTH) {
            // F-026: the head of river polyline #1 sits INSIDE the mountain footprint, so
            // its ribbon climbs the flank at y≈100-140 — below the B1 snowline, which is
            // why that fix never reached it. Plain minecraft:river (temperature 0.5) then
            // painted a warm gash straight through the glacier: no snow layers, rain
            // instead of snowfall, and freeze_top_layer skipping the channel entirely.
            // Inside the frost region the channel is solid ice, so it reads as the cold
            // biome it now looks like.
            id = SnowMountainFrost.isFrostColumn(mountain, bx, bz) ? FROST_RIVER_ID : "minecraft:river";
        }
        if (id == null && mountain != null) {
            double flankR = mountain.radius() * 0.8D;
            if (mountainDistSq < flankR * flankR) {
                id = DiscMapDefaults.flankBiome(mountain, bx, bz, surfaceY);
            }
        }
        if (id == null) {
            double r = Math.sqrt((double) bx * bx + (double) bz * bz);
            if (r < mapProfile.centerRadius()) {
                id = mapProfile.centerBiome();
            } else {
                int[] radii = FrozenParams.stageRadii(this.profile);
                int finalStage = radii.length - 1;
                if (r > radii[finalStage] - SHARD_BAND_MARGIN
                        && DiscTerrainFunction.column(this.profile, bx, bz, finalStage, map).shard()) {
                    // Detached crumble shard off the final rim → mushroom fields (D6).
                    id = "minecraft:mushroom_fields";
                } else {
                    id = DiscMapDefaults.ringBiome(this.profile,
                            map.biomeAt(this.profile, bx, bz), bx, bz);
                }
            }
        }
        // B1 snowline overlay, column part: whatever the 2-D rules resolved (flank thirds,
        // warm wedge terraces, high river/pool columns), an above-snowline surface on the
        // mountain reads snowy_slopes so freeze_top_layer keeps its snow layers and ice.
        if (mountainFootprint && surfaceY >= SNOWLINE_Y) {
            id = "minecraft:snowy_slopes";
        }
        String caveRegion = CaveBiomeMap.regionAt(bx, bz);
        boolean deepDark = CaveBiomeMap.deepDarkColumn(mountain, bx, bz);
        return new ColumnInfo(holderOf(id), surfaceY, jaggedCore, mountainFootprint,
                caveRegion, deepDark);
    }

    private Holder<Biome> holderOf(String id) {
        Holder<Biome> holder = this.biomesById.get(id);
        return holder != null ? holder : this.fallback;
    }

    /** Stafford-13 style finalizer for the cache slot hash (matches the map-noise mixer). */
    private static long mix(long z) {
        z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
        z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
        return z ^ (z >>> 31);
    }
}
