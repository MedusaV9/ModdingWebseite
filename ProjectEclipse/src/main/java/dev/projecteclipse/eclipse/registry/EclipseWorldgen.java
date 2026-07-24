package dev.projecteclipse.eclipse.registry;

import java.util.function.Supplier;

import com.mojang.serialization.MapCodec;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscBiomeSource;
import dev.projecteclipse.eclipse.worldgen.DiscChunkGenerator;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.level.biome.BiomeSource;
import net.minecraft.world.level.chunk.ChunkGenerator;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredRegister;

/**
 * Worldgen codec registry: the disc chunk generator ({@code eclipse:disc}) and the
 * angular-sector biome source ({@code eclipse:disc_sectors}) referenced by the
 * {@code data/minecraft/dimension/*.json} overrides.
 */
public final class EclipseWorldgen {
    public static final DeferredRegister<MapCodec<? extends ChunkGenerator>> CHUNK_GENERATORS =
            DeferredRegister.create(Registries.CHUNK_GENERATOR, EclipseMod.MOD_ID);

    public static final DeferredRegister<MapCodec<? extends BiomeSource>> BIOME_SOURCES =
            DeferredRegister.create(Registries.BIOME_SOURCE, EclipseMod.MOD_ID);

    public static final Supplier<MapCodec<DiscChunkGenerator>> DISC =
            CHUNK_GENERATORS.register("disc", () -> DiscChunkGenerator.CODEC);

    public static final Supplier<MapCodec<DiscBiomeSource>> DISC_SECTORS =
            BIOME_SOURCES.register("disc_sectors", () -> DiscBiomeSource.CODEC);

    private EclipseWorldgen() {}

    public static void register(IEventBus modEventBus) {
        CHUNK_GENERATORS.register(modEventBus);
        BIOME_SOURCES.register(modEventBus);
    }
}
