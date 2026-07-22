package dev.projecteclipse.eclipse.worldgen;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.stream.Stream;

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
 * Angular-sector biome source of the disc world ({@code eclipse:disc_sectors}): biomes
 * come from {@code disc_map.json}'s pie wedges (center cap, mountain core/flank, eight
 * overworld sectors / five nether sectors) via {@link DiscMapData#biomeAt}, the exact
 * layout the terrain palette uses — blocks and biomes always agree.
 */
public final class DiscBiomeSource extends BiomeSource {
    public static final MapCodec<DiscBiomeSource> CODEC = RecordCodecBuilder.mapCodec(
            instance -> instance.group(
                    DiscProfile.CODEC.fieldOf("profile").forGetter(source -> source.profile),
                    RegistryOps.retrieveGetter(Registries.BIOME))
            .apply(instance, instance.stable(DiscBiomeSource::new)));

    private final DiscProfile profile;
    private final Map<String, Holder<Biome>> biomesById;
    private final Holder<Biome> fallback;

    public DiscBiomeSource(DiscProfile profile, HolderGetter<Biome> biomes) {
        this.profile = profile;
        this.fallback = biomes.getOrThrow(profile == DiscProfile.NETHER
                ? Biomes.NETHER_WASTES : Biomes.PLAINS);
        this.biomesById = resolveBiomes(profile, biomes, this.fallback);
    }

    private static Map<String, Holder<Biome>> resolveBiomes(DiscProfile profile,
            HolderGetter<Biome> biomes, Holder<Biome> fallback) {
        DiscMapData.MapProfile map = DiscMapData.get().profile(profile);
        Map<String, Holder<Biome>> resolved = new LinkedHashMap<>();
        resolved.put(map.centerBiome(), fallback);
        for (DiscMapData.Sector sector : map.sectors()) {
            resolved.put(sector.biome(), fallback);
        }
        if (map.mountain() != null) {
            resolved.put(map.mountain().coreBiome(), fallback);
            resolved.put(map.mountain().flankBiome(), fallback);
        }
        for (Map.Entry<String, Holder<Biome>> entry : resolved.entrySet()) {
            ResourceLocation id = ResourceLocation.tryParse(entry.getKey());
            if (id == null) {
                EclipseMod.LOGGER.warn("disc_map.json: invalid biome id '{}'; using fallback", entry.getKey());
                continue;
            }
            var holder = biomes.get(ResourceKey.create(Registries.BIOME, id));
            if (holder.isPresent()) {
                entry.setValue(holder.get());
            } else {
                EclipseMod.LOGGER.warn("disc_map.json: unknown biome '{}'; using fallback", entry.getKey());
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
        String biomeId = DiscMapData.get().biomeAt(this.profile,
                QuartPos.toBlock(x) + 2, QuartPos.toBlock(z) + 2);
        Holder<Biome> holder = this.biomesById.get(biomeId);
        return holder != null ? holder : this.fallback;
    }
}
