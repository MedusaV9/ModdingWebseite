package dev.projecteclipse.eclipse.worldgen;

import java.util.Arrays;
import java.util.concurrent.atomic.AtomicBoolean;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.vanilla.DiscGenPipeline;
import net.minecraft.core.BlockPos;
import net.minecraft.core.SectionPos;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.WorldGenLevel;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.chunk.ChunkAccess;
import net.minecraft.world.level.chunk.LevelChunk;
import net.minecraft.world.level.chunk.LevelChunkSection;
import net.minecraft.world.level.material.FluidState;
import net.minecraft.server.level.ServerLevel;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLCommonSetupEvent;

/**
 * F-026 — the snow mountain's frost region: the one place on the overworld disc where
 * liquid water and plain {@code minecraft:ice} must not exist.
 *
 * <h2>Why</h2>
 * The authored map puts the head of river polyline #1 at {@code (30, -80)}, which is
 * only ~55 blocks from the mountain centre {@code (54, -129)} — i.e. INSIDE the
 * mountain's {@code radius = 75} footprint. {@link DiscTerrainFunction} therefore carves
 * a river channel UP the mountain flank and fills it with static water sources at
 * y≈100–140, and vanilla {@code spring_water}/lake features add more. Because the
 * channel climbs, every column's source sits higher than its downhill neighbour, so the
 * fill spills out and cascades down the mountainside forever.
 *
 * <p>It also never freezes over: {@link DiscBiomeSource} resolves the river ribbon to
 * the WARM {@code minecraft:river} biome before the mountain flank rules run, and the
 * B1 snowline overlay only upgrades a column to {@code snowy_slopes} at
 * {@code surfaceY >= }{@link DiscBiomeSource#SNOWLINE_Y} (152) — the flank channel tops
 * out around y 140, so B1 never covered it. What little ice {@code freeze_top_layer} did
 * place melts again: {@code IceBlock.randomTick} melts at block light &gt; 11, and the
 * mountain body carries a lava pocket at y≈120.</p>
 *
 * <h2>What</h2>
 * Inside the frost region — the mountain footprint padded by {@value #FROST_MARGIN}
 * blocks, from y {@value #FROST_MIN_Y} up — three passes cooperate so that every
 * generation path ends at the same blocks:
 * <ol>
 *   <li>{@link DiscTerrainFunction} emits {@link #frostState} instead of water for its
 *       own river/pool/spillway fills ({@code DiscColumn.frostFill()}), which keeps
 *       {@code stateAt} the single source of truth for chunk generation, the ring
 *       sweep, {@code ChunkRegen}, {@code SitePrep} and {@code HullRepair}.</li>
 *   <li>{@link #decorate} runs as a {@link DiscGenPipeline.ExtraDecor} AFTER vanilla
 *       decoration and freezes whatever the vanilla features added ({@code spring_water},
 *       lakes, {@code freeze_top_layer} ice).</li>
 *   <li>{@link #refreeze} does the same on a live chunk — the one-time cleanup migration
 *       for worlds generated before this fix, and a permanent guard afterwards
 *       ({@code DiscRepairService} drives it from chunk load).</li>
 * </ol>
 *
 * <p>Meltability is designed out rather than suppressed: {@code PACKED_ICE} and
 * {@code BLUE_ICE} have no {@code randomTick} at all, so no light level, torch or lava
 * pocket can turn them back into water. Snow blocks and snow layers are left alone.</p>
 */
public final class SnowMountainFrost {
    /** Outward pad (blocks) beyond {@code mountain.radius()} — catches runoff past the foot. */
    public static final int FROST_MARGIN = 16;
    /**
     * Frost floor. Above the mountain cavity's lava pool (y≈83–85) and above the deep
     * cave band, so the sealed core and the plain's water table stay untouched, but well
     * below the lowest observed runaway river source on the flank (y≈100).
     */
    public static final int FROST_MIN_Y = 96;

    /**
     * Blue-ice vein salt. Deliberately the same salt {@link DiscTerrainFunction} uses for
     * the authored north-face ice cascade, so frozen river/spring blocks carry the exact
     * same 25 % blue-ice speckle and read as one glacier.
     */
    private static final int SALT_FROST_VEIN = 22;
    private static final double BLUE_ICE_CHANCE = 0.25D;

    private static final BlockState AIR = Blocks.AIR.defaultBlockState();
    private static final BlockState PACKED_ICE = Blocks.PACKED_ICE.defaultBlockState();
    private static final BlockState BLUE_ICE = Blocks.BLUE_ICE.defaultBlockState();

    /** Section writes only: no neighbour reactions, but clients and the light engine update. */
    private static final int LIVE_WRITE_FLAGS = Block.UPDATE_CLIENTS | Block.UPDATE_KNOWN_SHAPE;

    private static final AtomicBoolean REGISTERED = new AtomicBoolean();

    private SnowMountainFrost() {}

    @EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
    public static final class Setup {
        private Setup() {}

        @SubscribeEvent
        static void onCommonSetup(FMLCommonSetupEvent event) {
            event.enqueueWork(() -> {
                if (REGISTERED.compareAndSet(false, true)) {
                    DiscGenPipeline.registerExtraDecor(
                            DiscProfile.OVERWORLD, SnowMountainFrost::decorate);
                    EclipseMod.LOGGER.info("Registered snow-mountain frost pass (F-026)");
                }
            });
        }
    }

    // ------------------------------------------------------------------ region

    /** Whether the column lies in the frost region of {@code profile}'s authored mountain. */
    public static boolean isFrostColumn(DiscMapData map, DiscProfile profile, int x, int z) {
        return isFrostColumn(map.profile(profile).mountain(), x, z);
    }

    /** {@link #isFrostColumn(DiscMapData, DiscProfile, int, int)} against a mountain snapshot. */
    public static boolean isFrostColumn(DiscMapData.Mountain mountain, int x, int z) {
        if (mountain == null) {
            return false;
        }
        double dx = x - mountain.x();
        double dz = z - mountain.z();
        double reach = mountain.radius() + FROST_MARGIN;
        return dx * dx + dz * dz <= reach * reach;
    }

    /** Whether any column of the chunk lies in the frost region (cheap per-chunk early out). */
    public static boolean chunkTouchesFrostRegion(DiscMapData.Mountain mountain, ChunkPos pos) {
        if (mountain == null) {
            return false;
        }
        // Nearest point of the chunk's 16×16 footprint to the mountain axis.
        double dx = Math.max(0, Math.max(pos.getMinBlockX() - mountain.x(),
                mountain.x() - pos.getMaxBlockX()));
        double dz = Math.max(0, Math.max(pos.getMinBlockZ() - mountain.z(),
                mountain.z() - pos.getMaxBlockZ()));
        double reach = mountain.radius() + FROST_MARGIN;
        return dx * dx + dz * dz <= reach * reach;
    }

    /** The glacier block for one position: packed ice with sparse blue-ice veins. */
    public static BlockState frostState(int x, int y, int z) {
        return DiscTerrainFunction.hash01x3(SALT_FROST_VEIN, x, y, z) < BLUE_ICE_CHANCE
                ? BLUE_ICE
                : PACKED_ICE;
    }

    // ------------------------------------------------------------------ generation pass

    /**
     * {@link DiscGenPipeline.ExtraDecor} hook: freezes everything vanilla decoration left
     * behind in the frost region. Registered for the overworld only.
     */
    public static void decorate(WorldGenLevel level, ChunkAccess chunk) {
        DiscMapData.Mountain mountain = DiscMapData.get().profile(DiscProfile.OVERWORLD).mountain();
        if (!chunkTouchesFrostRegion(mountain, chunk.getPos())) {
            return;
        }
        freeze(chunk, mountain, null);
    }

    // ------------------------------------------------------------------ live pass

    /**
     * Cleanup migration / runtime guard on a live chunk: drops flowing water, turns water
     * sources and any plain ice into glacier ice, and drains waterlogged blocks. Returns
     * the number of blocks changed (0 = nothing to do, the common case). The caller owns
     * the follow-up heightmap re-prime and relight.
     */
    public static int refreeze(ServerLevel level, LevelChunk chunk, DiscProfile profile) {
        DiscMapData.Mountain mountain = DiscMapData.get().profile(profile).mountain();
        if (profile != DiscProfile.OVERWORLD || !chunkTouchesFrostRegion(mountain, chunk.getPos())) {
            return 0;
        }
        return freeze(chunk, mountain, level);
    }

    // ------------------------------------------------------------------ shared scan

    /**
     * The one scan both passes share. Walks the chunk TOP-DOWN — so a removed source can
     * never be refilled by the water that was standing above it — down to
     * {@link #FROST_MIN_Y}, skipping any section whose palette proves it holds nothing
     * meltable (which is every section once a chunk has been treated, making the
     * chunk-load guard essentially free). {@code level} non-null selects the
     * live path ({@code ServerLevel.setBlock} with client + light updates but no neighbour
     * reactions); null selects the worldgen path (raw {@code ChunkAccess} writes).
     */
    private static int freeze(ChunkAccess chunk, DiscMapData.Mountain mountain, ServerLevel level) {
        ChunkPos pos = chunk.getPos();
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        // Lowest Y this pass touched per column, for the drainage ticks below.
        int[] lowestChanged = null;
        if (level != null) {
            lowestChanged = new int[256];
            Arrays.fill(lowestChanged, Integer.MAX_VALUE);
        }
        int changed = 0;
        for (int index = chunk.getSectionsCount() - 1; index >= 0; index--) {
            int sectionMinY = SectionPos.sectionToBlockCoord(
                    chunk.getSectionYFromSectionIndex(index));
            if (sectionMinY + 15 < FROST_MIN_Y) {
                break; // sections are ordered bottom-up: everything below is out of region
            }
            LevelChunkSection section = chunk.getSection(index);
            if (section.hasOnlyAir() || !section.maybeHas(SnowMountainFrost::meltable)) {
                continue;
            }
            for (int dy = 15; dy >= 0; dy--) {
                int y = sectionMinY + dy;
                if (y < FROST_MIN_Y) {
                    break;
                }
                for (int lx = 0; lx < 16; lx++) {
                    int x = pos.getMinBlockX() + lx;
                    for (int lz = 0; lz < 16; lz++) {
                        BlockState state = section.getBlockState(lx, dy, lz);
                        if (!meltable(state)) {
                            continue;
                        }
                        int z = pos.getMinBlockZ() + lz;
                        if (!isFrostColumn(mountain, x, z)) {
                            continue;
                        }
                        BlockState frozen = frozenReplacement(state, x, y, z);
                        cursor.set(x, y, z);
                        if (level == null) {
                            chunk.setBlockState(cursor, frozen, false);
                        } else {
                            level.setBlock(cursor, frozen, LIVE_WRITE_FLAGS);
                            lowestChanged[lz << 4 | lx] = y;
                        }
                        changed++;
                    }
                }
            }
        }
        if (level != null && changed > 0) {
            drainBelow(level, pos, lowestChanged);
        }
        return changed;
    }

    /**
     * The cleanup migration only reaches down to {@link #FROST_MIN_Y}, but the runoff it
     * orphans continues below that — and section-level writes fire no updates, so that
     * water would hang there forever with no source feeding it. One scheduled fluid tick
     * per drained column under the frost floor hands it to vanilla's normal decay, which
     * unwinds the whole downstream flow and stops on its own at the first block that a
     * real source (the plain's river, a lake) still supports.
     */
    private static void drainBelow(ServerLevel level, ChunkPos pos, int[] lowestChanged) {
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        for (int index = 0; index < lowestChanged.length; index++) {
            if (lowestChanged[index] == Integer.MAX_VALUE) {
                continue;
            }
            cursor.set(pos.getMinBlockX() + (index & 15), lowestChanged[index] - 1,
                    pos.getMinBlockZ() + (index >> 4));
            FluidState fluid = level.getFluidState(cursor);
            if (!fluid.isEmpty()) {
                level.scheduleTick(cursor.immutable(), fluid.getType(),
                        fluid.getType().getTickDelay(level));
            }
        }
    }

    /** Whether the state is (or carries) water, or is an ice that vanilla can melt. */
    private static boolean meltable(BlockState state) {
        return state.is(Blocks.WATER) || state.is(Blocks.ICE) || state.is(Blocks.FROSTED_ICE)
                || (state.hasProperty(BlockStateProperties.WATERLOGGED)
                        && state.getValue(BlockStateProperties.WATERLOGGED));
    }

    /**
     * Water sources and meltable ice become glacier ice; FLOWING water is deleted (it is
     * only the runoff of a source that this same pass freezes, so re-freezing it in place
     * would leave ice sheets hanging in mid-air down the whole flank); waterlogged blocks
     * are drained.
     */
    private static BlockState frozenReplacement(BlockState state, int x, int y, int z) {
        if (state.is(Blocks.ICE) || state.is(Blocks.FROSTED_ICE)) {
            return frostState(x, y, z);
        }
        if (state.is(Blocks.WATER)) {
            return state.getValue(BlockStateProperties.LEVEL) == 0 ? frostState(x, y, z) : AIR;
        }
        return state.setValue(BlockStateProperties.WATERLOGGED, false);
    }
}
