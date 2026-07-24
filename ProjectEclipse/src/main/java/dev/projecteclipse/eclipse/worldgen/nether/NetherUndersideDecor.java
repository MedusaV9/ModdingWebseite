package dev.projecteclipse.eclipse.worldgen.nether;

import java.util.concurrent.atomic.AtomicBoolean;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction.DiscColumn;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import dev.projecteclipse.eclipse.worldgen.WorldStageAccess;
import dev.projecteclipse.eclipse.worldgen.vanilla.DiscGenPipeline;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.WorldGenLevel;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.ChunkAccess;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLCommonSetupEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Deterministic inverted dressing for the Nether disc's void-facing underside. Registered
 * through the W1.1 {@link DiscGenPipeline.ExtraDecor} seam, so it runs after hull repair on
 * both fresh chunk generation and live ring replay.
 *
 * <p>Every decision derives from the frozen map seed and world coordinates: glowstone
 * patches, embedded shroomlight pockets, weeping-vine/root curtains and sparse soul-soil
 * "ash crust". No random source or per-save world seed is consulted. A lightweight
 * server-particle pass supplies drifting ash when players explore below the disc.</p>
 */
public final class NetherUndersideDecor {
    private static final AtomicBoolean REGISTERED = new AtomicBoolean();
    private static final int SALT_GLOW = 0x4E47;
    private static final int SALT_SHROOM = 0x4E53;
    private static final int SALT_VINES = 0x4E56;
    private static final int SALT_ASH = 0x4E41;

    private NetherUndersideDecor() {}

    @EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
    public static final class Setup {
        private Setup() {}

        @SubscribeEvent
        static void onCommonSetup(FMLCommonSetupEvent event) {
            event.enqueueWork(() -> {
                if (REGISTERED.compareAndSet(false, true)) {
                    DiscGenPipeline.registerExtraDecor(
                            DiscProfile.NETHER, NetherUndersideDecor::decorate);
                    EclipseMod.LOGGER.info("Registered deterministic Nether underside dressing");
                }
            });
        }
    }

    /** Chunk-local post-decoration stamp used by {@link DiscGenPipeline}. */
    public static void decorate(WorldGenLevel level, ChunkAccess chunk) {
        int stage = WorldStageAccess.stage(DiscProfile.NETHER);
        if (stage <= 0) {
            return;
        }
        ChunkPos chunkPos = chunk.getPos();
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        for (int localX = 0; localX < 16; localX++) {
            int x = chunkPos.getMinBlockX() + localX;
            for (int localZ = 0; localZ < 16; localZ++) {
                int z = chunkPos.getMinBlockZ() + localZ;
                DiscColumn column = DiscTerrainFunction.column(DiscProfile.NETHER, x, z, stage);
                if (!column.inside() || column.groundBottomY() <= level.getMinBuildHeight() + 8) {
                    continue;
                }
                int underside = column.groundBottomY();

                // Broad, cell-coherent glowstone stains instead of unrelated single pixels.
                if (inPatch(x, z, 14, SALT_GLOW, 0.48D, 2.35D)) {
                    setIfAir(chunk, cursor.set(x, underside - 1, z),
                            Blocks.GLOWSTONE.defaultBlockState());
                    if (inPatch(x, z, 14, SALT_GLOW, 0.48D, 1.15D)) {
                        setIfAir(chunk, cursor.set(x, underside - 2, z),
                                Blocks.GLOWSTONE.defaultBlockState());
                    }
                }

                // Solid light pockets preserve the hull seal while making the underside glow.
                if (inPatch(x, z, 19, SALT_SHROOM, 0.32D, 1.35D)) {
                    BlockPos pos = cursor.set(x, underside, z);
                    if (!chunk.getBlockState(pos).isAir()) {
                        chunk.setBlockState(pos, Blocks.SHROOMLIGHT.defaultBlockState(), false);
                    }
                }

                double vine = hash01(SALT_VINES, x, z);
                if (vine < 0.006D) {
                    int length = 2 + (int) (hash01(SALT_VINES + 1, x, z) * 6.0D);
                    for (int i = 1; i <= length && underside - i > level.getMinBuildHeight(); i++) {
                        BlockState state = i == length
                                ? Blocks.WEEPING_VINES.defaultBlockState()
                                : Blocks.WEEPING_VINES_PLANT.defaultBlockState();
                        setIfAir(chunk, cursor.set(x, underside - i, z), state);
                    }
                } else if (vine < 0.014D) {
                    setIfAir(chunk, cursor.set(x, underside - 1, z),
                            Blocks.HANGING_ROOTS.defaultBlockState());
                }

                // Ash-darkened solid flecks; no air replacement, so the bedrock seal remains.
                if (hash01(SALT_ASH, x, z) < 0.012D) {
                    BlockPos pos = cursor.set(x, underside, z);
                    if (!chunk.getBlockState(pos).isAir()) {
                        chunk.setBlockState(pos, Blocks.SOUL_SOIL.defaultBlockState(), false);
                    }
                }
            }
        }
    }

    private static void setIfAir(ChunkAccess chunk, BlockPos pos, BlockState state) {
        if (chunk.getBlockState(pos).isAir()) {
            chunk.setBlockState(pos, state, false);
        }
    }

    /** Cell-local hashed patch test; every column independently reaches the same answer. */
    private static boolean inPatch(int x, int z, int cellSize, int salt,
            double cellChance, double radius) {
        int cellX = Math.floorDiv(x, cellSize);
        int cellZ = Math.floorDiv(z, cellSize);
        long h = hash(salt, cellX, cellZ);
        if (to01(h) >= cellChance) {
            return false;
        }
        int span = Math.max(1, cellSize - 4);
        int centerX = cellX * cellSize + 2 + (int) ((h >>> 8) & 0x7FFFFFFFL) % span;
        int centerZ = cellZ * cellSize + 2 + (int) ((h >>> 32) & 0x7FFFFFFFL) % span;
        double dx = x - centerX;
        double dz = z - centerZ;
        return dx * dx + dz * dz <= radius * radius;
    }

    private static double hash01(int salt, int x, int z) {
        return to01(hash(salt, x, z));
    }

    private static long hash(int salt, int x, int z) {
        long h = FrozenParams.mapSeed() + (long) salt * 0x9E3779B97F4A7C15L;
        h ^= (long) x * 341873128712L;
        h ^= (long) z * 132897987541L;
        h ^= h >>> 30;
        h *= 0xBF58476D1CE4E5B9L;
        h ^= h >>> 27;
        h *= 0x94D049BB133111EBL;
        return h ^ h >>> 31;
    }

    private static double to01(long hash) {
        return (hash >>> 11) * 0x1.0p-53D;
    }

    /** Server-side ash ambience only when a player is actually below the Nether disc. */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID)
    public static final class AshEvents {
        private AshEvents() {}

        @SubscribeEvent
        static void onServerTick(ServerTickEvent.Post event) {
            if (event.getServer().getTickCount() % 12 != 0) {
                return;
            }
            ServerLevel nether = event.getServer().getLevel(Level.NETHER);
            if (nether == null || WorldStageAccess.stage(DiscProfile.NETHER) <= 0) {
                return;
            }
            int stage = WorldStageAccess.stage(DiscProfile.NETHER);
            for (ServerPlayer player : nether.players()) {
                DiscColumn column = DiscTerrainFunction.column(DiscProfile.NETHER,
                        player.getBlockX(), player.getBlockZ(), stage);
                if (column.inside() && player.getY() < column.groundBottomY() + 10.0D) {
                    nether.sendParticles(ParticleTypes.ASH,
                            player.getX(), player.getY() + 4.0D, player.getZ(),
                            8, 5.0D, 3.0D, 5.0D, 0.012D);
                    nether.sendParticles(ParticleTypes.WHITE_ASH,
                            player.getX(), player.getY() + 2.0D, player.getZ(),
                            3, 3.0D, 2.0D, 3.0D, 0.008D);
                }
            }
        }
    }
}
