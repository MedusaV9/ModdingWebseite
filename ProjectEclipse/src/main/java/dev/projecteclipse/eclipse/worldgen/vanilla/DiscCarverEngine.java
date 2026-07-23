package dev.projecteclipse.eclipse.worldgen.vanilla;

import it.unimi.dsi.fastutil.objects.ObjectArrayList;

import net.minecraft.core.Holder;
import net.minecraft.core.QuartPos;
import net.minecraft.core.RegistryAccess;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceKey;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.biome.Biome;
import net.minecraft.world.level.biome.BiomeGenerationSettings;
import net.minecraft.world.level.biome.BiomeManager;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.chunk.CarvingMask;
import net.minecraft.world.level.chunk.ChunkAccess;
import net.minecraft.world.level.chunk.LevelChunkSection;
import net.minecraft.world.level.levelgen.Aquifer;
import net.minecraft.world.level.levelgen.Beardifier;
import net.minecraft.world.level.levelgen.GenerationStep;
import net.minecraft.world.level.levelgen.LegacyRandomSource;
import net.minecraft.world.level.levelgen.NoiseBasedChunkGenerator;
import net.minecraft.world.level.levelgen.NoiseChunk;
import net.minecraft.world.level.levelgen.NoiseGeneratorSettings;
import net.minecraft.world.level.levelgen.RandomState;
import net.minecraft.world.level.levelgen.WorldgenRandom;
import net.minecraft.world.level.levelgen.blending.Blender;
import net.minecraft.world.level.levelgen.carver.CarvingContext;
import net.minecraft.world.level.levelgen.carver.ConfiguredWorldCarver;
import net.minecraft.world.level.levelgen.structure.pools.JigsawJunction;

import dev.projecteclipse.eclipse.worldgen.DiscChunkGenerator;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;

/**
 * Vanilla carvers (caves, extra underground caves, canyons) on the disc base (design
 * D1.3). Mirrors {@code NoiseBasedChunkGenerator.applyCarvers} — the 17×17 chunk
 * neighbourhood, per-carver {@code setLargeFeatureSeed}, biome-driven carver lists —
 * but with every input built here instead of taken from the world:
 *
 * <ul>
 *   <li><b>Seed</b>: the frozen map seed, never the world seed — carved caves are
 *       identical in every save and every ring-growth replay.</li>
 *   <li><b>Carving mask</b>: a fresh {@link CarvingMask} per call — no ProtoChunk
 *       state, so the engine runs unchanged on live {@code LevelChunk}s.</li>
 *   <li><b>Aquifer</b>: disabled, fluid = lava below {@code profile.minY() + 12}, else
 *       air — dry caves; springs come from decoration features.</li>
 *   <li><b>Carving context</b>: built against a lazily-created private vanilla
 *       {@link NoiseBasedChunkGenerator} (the profile's matching vanilla noise settings
 *       from the registry) purely so carvers can repair carved-through surfaces via
 *       {@code topMaterial} — no terrain is ever delegated to it.</li>
 *   <li><b>Biome zoom</b>: a {@link BiomeManager} seeded from the map seed (the region
 *       manager zooms with the per-save world seed, which would leak save-specific
 *       jitter into carver biome checks).</li>
 * </ul>
 *
 * <p>Callers run {@link HullRepair#afterCarving} afterwards — carvers may otherwise
 * puncture the floating hull near the rim/underside. Carvers ARE allowed to breach the
 * top surface: that is where natural cave entrances come from.</p>
 */
public final class DiscCarverEngine {
    /** Same neighbourhood range as vanilla {@code NoiseBasedChunkGenerator.applyCarvers}. */
    private static final int CARVE_RANGE = 8;
    /** Lava pool depth above the profile floor used by the disabled-aquifer fluid picker. */
    private static final int LAVA_ABOVE_MIN_Y = 12;

    /** Per-profile carving toolkit, rebuilt when the registry access or seed changes. */
    private record Ctx(RegistryAccess registries, long seed, Holder<NoiseGeneratorSettings> settings,
            NoiseBasedChunkGenerator proxy, RandomState randomState) {}

    private static volatile Ctx overworldCtx;
    private static volatile Ctx netherCtx;

    private DiscCarverEngine() {}

    /**
     * Carves {@code chunk} with the AIR-step carvers of the surrounding biomes. Safe on
     * worldgen worker threads and on live chunks (writes only through
     * {@code ChunkAccess.setBlockState} with no neighbour updates). No-op for chunks
     * with no solid sections (void beyond the disc).
     */
    public static void carve(DiscChunkGenerator generator, RegistryAccess registryAccess, ChunkAccess chunk,
            GenerationStep.Carving step) {
        if (!hasAnySolidSection(chunk)) {
            return;
        }
        DiscProfile profile = generator.profile();
        long seed = DiscGenPipeline.fixedSeed();
        Ctx ctx = ctxFor(profile, registryAccess, generator, seed);

        BiomeManager biomeManager = new BiomeManager(
                (x, y, z) -> generator.getBiomeSource().getNoiseBiome(x, y, z, ctx.randomState().sampler()),
                BiomeManager.obfuscateSeed(seed));
        Aquifer.FluidPicker fluidPicker = fluidPicker(profile);
        NoiseChunk noiseChunk = NoiseChunk.forChunk(chunk, ctx.randomState(), emptyBeardifier(),
                ctx.settings().value(), fluidPicker, Blender.empty());
        Aquifer aquifer = Aquifer.createDisabled(fluidPicker);
        CarvingContext context = new CarvingContext(ctx.proxy(), registryAccess,
                chunk.getHeightAccessorForGeneration(), noiseChunk, ctx.randomState(),
                ctx.settings().value().surfaceRule());
        CarvingMask mask = new CarvingMask(chunk.getHeight(), chunk.getMinBuildHeight());
        WorldgenRandom random = new WorldgenRandom(new LegacyRandomSource(seed));

        ChunkPos center = chunk.getPos();
        for (int dx = -CARVE_RANGE; dx <= CARVE_RANGE; dx++) {
            for (int dz = -CARVE_RANGE; dz <= CARVE_RANGE; dz++) {
                ChunkPos neighbour = new ChunkPos(center.x + dx, center.z + dz);
                // Vanilla reads the neighbour ProtoChunk's cached carverBiome here; our
                // biome source is a pure function of (x, z), so sampling it directly is
                // byte-identical, costs nothing, and never loads chunks on live replays.
                Holder<Biome> biome = generator.getBiomeSource().getNoiseBiome(
                        QuartPos.fromBlock(neighbour.getMinBlockX()), 0,
                        QuartPos.fromBlock(neighbour.getMinBlockZ()), ctx.randomState().sampler());
                // Same filtered view the generator decorates with (its settings getter IS
                // this method), without the deprecated ChunkGenerator accessor.
                BiomeGenerationSettings settings = BiomeFeatureFilter.settingsFor(biome);
                int carverIndex = 0;
                for (Holder<ConfiguredWorldCarver<?>> holder : settings.getCarvers(step)) {
                    ConfiguredWorldCarver<?> carver = holder.value();
                    random.setLargeFeatureSeed(seed + carverIndex, neighbour.x, neighbour.z);
                    if (carver.isStartChunk(random)) {
                        carver.carve(context, chunk, biomeManager::getBiome, random, aquifer, neighbour, mask);
                    }
                    carverIndex++;
                }
            }
        }
    }

    private static boolean hasAnySolidSection(ChunkAccess chunk) {
        for (LevelChunkSection section : chunk.getSections()) {
            if (!section.hasOnlyAir()) {
                return true;
            }
        }
        return false;
    }

    /** Dry caves: air everywhere except a lava pool in the lowest {@value #LAVA_ABOVE_MIN_Y} blocks. */
    private static Aquifer.FluidPicker fluidPicker(DiscProfile profile) {
        Aquifer.FluidStatus lavaFloor = new Aquifer.FluidStatus(
                profile.minY() + LAVA_ABOVE_MIN_Y, Blocks.LAVA.defaultBlockState());
        return (x, y, z) -> lavaFloor;
    }

    /**
     * A no-op structure beardifier: the disc has no structure starts during generation
     * (structures are stamped at runtime), and {@code DensityFunctions.BeardifierMarker}
     * is not accessible outside its package.
     */
    private static Beardifier emptyBeardifier() {
        return new Beardifier(new ObjectArrayList<Beardifier.Rigid>().iterator(),
                new ObjectArrayList<JigsawJunction>().iterator());
    }

    private static Ctx ctxFor(DiscProfile profile, RegistryAccess registryAccess, DiscChunkGenerator generator,
            long seed) {
        Ctx ctx = profile == DiscProfile.NETHER ? netherCtx : overworldCtx;
        if (ctx != null && ctx.registries() == registryAccess && ctx.seed() == seed) {
            return ctx;
        }
        ResourceKey<NoiseGeneratorSettings> key = profile == DiscProfile.NETHER
                ? NoiseGeneratorSettings.NETHER : NoiseGeneratorSettings.OVERWORLD;
        Holder<NoiseGeneratorSettings> settings =
                registryAccess.registryOrThrow(Registries.NOISE_SETTINGS).getHolderOrThrow(key);
        // Fixed-seed RandomState: carver surface repair (topMaterial) must not depend on
        // the per-save world seed, or replayed/regenerated chunks would diverge by save.
        RandomState randomState = RandomState.create(settings.value(),
                registryAccess.registryOrThrow(Registries.NOISE).asLookup(), seed);
        Ctx built = new Ctx(registryAccess, seed, settings,
                new NoiseBasedChunkGenerator(generator.getBiomeSource(), settings), randomState);
        if (profile == DiscProfile.NETHER) {
            netherCtx = built;
        } else {
            overworldCtx = built;
        }
        return built;
    }
}
