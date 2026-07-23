package dev.projecteclipse.eclipse.worldgen;

import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.LeavesBlock;
import net.minecraft.world.level.block.MultifaceBlock;
import net.minecraft.world.level.block.VineBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.XoroshiroRandomSource;
import net.minecraft.world.level.levelgen.synth.SimplexNoise;

/**
 * The single deterministic terrain function of the disc world.
 *
 * <p>{@link #stateAt(DiscProfile, int, int, int, int)} is a PURE function of
 * (profile, x, y, z, stage): every input comes from {@link DiscMapData#ECLIPSE_SEED},
 * {@code disc_map.json} and the stage radius — never from the world seed or any world
 * state. The chunk generator (never-generated chunks) and worker 4's runtime ring-growth
 * sweep (already-generated chunks) both consume it, so their output is byte-identical.</p>
 *
 * <p>For hot loops use {@link #column(DiscProfile, int, int, int)} once per column and
 * {@link #stateInColumn(DiscColumn, int)} per Y — {@code stateAt} is exactly that
 * composition. Everything here is immutable/static, safe on worldgen worker threads.
 * Bulk consumers spanning many columns (chunkgen {@code fillFromNoise}, the ring sweep)
 * must capture ONE {@link DiscMapData} snapshot per unit of work and use
 * {@link #column(DiscProfile, int, int, int, DiscMapData)} — {@code DiscMapData.reload()}
 * swaps the volatile instance mid-flight, and mixing old and new map data within one
 * chunk or sweep would tear the terrain.</p>
 *
 * <p><b>Stage reproducibility contract (worker 4):</b> for columns strictly inside
 * {@code stageRadius(n) − }{@link #RIM_REWRITE_MARGIN} the output is independent of the
 * stage, because the lens formula normalises against the FINAL radius
 * ({@link DiscProfile#lensNormRadius()}). Only the rim taper/crumble band changes when a
 * stage grows, so a ring sweep from stage n−1 to n must rewrite the annulus from
 * {@code radius(n−1) − RIM_REWRITE_MARGIN} out to {@code radius(n) + }{@link #RIM_NOISE_AMP}.
 * Everything added on top of the base lens honours the same split: interior dressing
 * (rivers, sector seam blending, mountain ridges/terraces/ice, ring scars, nether
 * moat lip and vegetation) is keyed exclusively to fixed map data and FINAL radii,
 * while every stage-dependent effect (rim spill curtains, crumble-shard promotion,
 * hanging rim lichen/vines, the stalactite fringe) lives inside the rim band the ring
 * sweep rewrites anyway.</p>
 */
public final class DiscTerrainFunction {
    /** Width in blocks of the smoothstep rim taper. */
    public static final int RIM_WIDTH = 12;
    /** Amplitude in blocks of the simplex wobble applied to every disc rim. */
    public static final int RIM_NOISE_AMP = 8;
    /**
     * How far INSIDE the previous stage radius worker 4's ring sweep must start
     * rewriting so the old rim taper, crumble holes and canopy spill are replaced by
     * interior terrain (rim width + rim noise + tree-canopy margin).
     */
    public static final int RIM_REWRITE_MARGIN = RIM_WIDTH + RIM_NOISE_AMP + 4;

    /** Half-width in blocks of an authored river channel (depressed bed + water fill). */
    public static final double RIVER_HALF_WIDTH = 4.0D;
    /** Extra sand/gravel bank margin around the channel (trees/cover suppressed too). */
    public static final double RIVER_BANK_MARGIN = 2.0D;

    /**
     * FINAL-stage annulus boundaries that carry a "ring scar" weld seam (deepslate/tuff
     * mix + sparse amethyst). Same fixed values as {@link #annulusBand} — NEVER derive
     * these from the current stage or interior output would stop being stage-independent.
     */
    private static final double[] SCAR_RADII = {225.0D, 300.0D, 360.0D, 420.0D};
    /** Radial half-width of a ring scar seam. */
    private static final double SCAR_HALF_WIDTH = 1.5D;
    /** The fainter stage-0 weld left where the main disc first fused into stage 1. */
    private static final double SCAR_FAINT_RADIUS = 96.0D;

    // Fixed-seed noise fields (never the world seed). Salt 8 belongs to DiscMapData's
    // sector-seam wobble; keep the two families disjoint.
    private static final SimplexNoise RIM_NOISE = noise(1);
    private static final SimplexNoise SURFACE_LARGE = noise(2);
    private static final SimplexNoise SURFACE_MEDIUM = noise(3);
    private static final SimplexNoise SURFACE_DETAIL = noise(4);
    private static final SimplexNoise FRINGE_NOISE = noise(5);
    private static final SimplexNoise CAVE_A = noise(6);
    private static final SimplexNoise CAVE_B = noise(7);
    private static final SimplexNoise RIDGE_NOISE = noise(9);

    // Hash salts.
    private static final int H_CRUMBLE = 11;
    private static final int H_DEEPSLATE = 12;
    private static final int H_TREE = 13;
    private static final int H_COVER = 14;
    private static final int H_LEAF = 15;
    private static final int H_GLOW = 16;
    private static final int H_ORE = 17;
    private static final int H_SHARD = 18;
    private static final int H_HANG = 19;
    private static final int H_SCAR = 20;
    private static final int H_INCLUSION = 21;
    private static final int H_STRIPE = 22;
    private static final int H_RIVER_BED = 23;

    private static final BlockState AIR = Blocks.AIR.defaultBlockState();
    private static final BlockState CAVE_AIR = Blocks.CAVE_AIR.defaultBlockState();
    private static final BlockState BEDROCK = Blocks.BEDROCK.defaultBlockState();
    private static final BlockState STONE = Blocks.STONE.defaultBlockState();
    private static final BlockState DEEPSLATE = Blocks.DEEPSLATE.defaultBlockState();
    private static final BlockState SANDSTONE = Blocks.SANDSTONE.defaultBlockState();
    private static final BlockState SNOW_BLOCK = Blocks.SNOW_BLOCK.defaultBlockState();
    private static final BlockState SNOW_LAYER = Blocks.SNOW.defaultBlockState();
    private static final BlockState SHORT_GRASS = Blocks.SHORT_GRASS.defaultBlockState();
    private static final BlockState DEAD_BUSH = Blocks.DEAD_BUSH.defaultBlockState();
    private static final BlockState CACTUS = Blocks.CACTUS.defaultBlockState();
    private static final BlockState LAVA = Blocks.LAVA.defaultBlockState();
    private static final BlockState WATER = Blocks.WATER.defaultBlockState();
    private static final BlockState SAND = Blocks.SAND.defaultBlockState();
    private static final BlockState GRAVEL = Blocks.GRAVEL.defaultBlockState();
    private static final BlockState TUFF = Blocks.TUFF.defaultBlockState();
    private static final BlockState CALCITE = Blocks.CALCITE.defaultBlockState();
    private static final BlockState PACKED_ICE = Blocks.PACKED_ICE.defaultBlockState();
    private static final BlockState BLUE_ICE = Blocks.BLUE_ICE.defaultBlockState();
    private static final BlockState AMETHYST_BLOCK = Blocks.AMETHYST_BLOCK.defaultBlockState();
    private static final BlockState CRYING_OBSIDIAN = Blocks.CRYING_OBSIDIAN.defaultBlockState();
    private static final BlockState AMETHYST_BUD = Blocks.SMALL_AMETHYST_BUD.defaultBlockState();
    /** Glow lichen plastered on the disc underside, shining down into the void. */
    private static final BlockState GLOW_LICHEN_CEILING = Blocks.GLOW_LICHEN.defaultBlockState()
            .setValue(MultifaceBlock.getFaceProperty(Direction.UP), true);
    /** Ceiling-attached vine (each strand block keeps UP so the chain stays supported). */
    private static final BlockState VINE_CEILING = Blocks.VINE.defaultBlockState()
            .setValue(VineBlock.UP, true);
    private static final BlockState BLACKSTONE = Blocks.BLACKSTONE.defaultBlockState();
    private static final BlockState NETHERRACK = Blocks.NETHERRACK.defaultBlockState();
    private static final BlockState GLOWSTONE = Blocks.GLOWSTONE.defaultBlockState();
    private static final BlockState MAGMA_BLOCK = Blocks.MAGMA_BLOCK.defaultBlockState();
    private static final BlockState BASALT = Blocks.BASALT.defaultBlockState();
    private static final BlockState BONE_BLOCK = Blocks.BONE_BLOCK.defaultBlockState();
    private static final BlockState SOUL_FIRE = Blocks.SOUL_FIRE.defaultBlockState();
    private static final BlockState CRIMSON_ROOTS = Blocks.CRIMSON_ROOTS.defaultBlockState();
    private static final BlockState WARPED_ROOTS = Blocks.WARPED_ROOTS.defaultBlockState();
    private static final BlockState NETHER_SPROUTS = Blocks.NETHER_SPROUTS.defaultBlockState();
    private static final BlockState TWISTING_VINES = Blocks.TWISTING_VINES.defaultBlockState();
    private static final BlockState SHROOMLIGHT = Blocks.SHROOMLIGHT.defaultBlockState();
    private static final BlockState[] FLOWERS = {
            Blocks.POPPY.defaultBlockState(),
            Blocks.DANDELION.defaultBlockState(),
            Blocks.CORNFLOWER.defaultBlockState(),
            Blocks.OXEYE_DAISY.defaultBlockState()};

    private DiscTerrainFunction() {}

    // --- public API ---

    /**
     * The block generated at (x, y, z) for the given profile and committed stage.
     * Pure and deterministic; see the class contract.
     */
    public static BlockState stateAt(DiscProfile profile, int x, int y, int z, int stage) {
        return stateInColumn(column(profile, x, z, stage), y);
    }

    /** Ground surface Y at (x, z), ignoring whether the column is inside the disc. */
    public static int surfaceY(DiscProfile profile, int x, int z) {
        DiscMapData map = DiscMapData.get();
        SectorStyle style = styleOf(profile, map.biomeAt(profile, x, z));
        int surface = computeSurfaceY(map, profile, x, z, style);
        double riverDist = map.riverDistance(profile, x, z);
        if (riverDist < RIVER_HALF_WIDTH) {
            surface -= riverDepth(riverDist);
        }
        if (profile == DiscProfile.NETHER && inMoat(map, x, z)) {
            surface -= 8;
        }
        return surface;
    }

    /** Precomputed data of one (x, z) column; feed to {@link #stateInColumn(DiscColumn, int)}. */
    public static DiscColumn column(DiscProfile profile, int x, int z, int stage) {
        return column(profile, x, z, stage, DiscMapData.get());
    }

    /**
     * {@link #column(DiscProfile, int, int, int)} evaluated against an explicit
     * {@code map} snapshot: every map lookup of the column (biome, rivers, moat,
     * mountain, tree anchors) reads the SAME instance, so a concurrent
     * {@code DiscMapData.reload()} can never mix old and new map data inside one column
     * — and callers that thread one snapshot through a whole chunk or sweep job get the
     * same guarantee for their entire unit of work.
     */
    public static DiscColumn column(DiscProfile profile, int x, int z, int stage, DiscMapData map) {
        double edge = edgeFactor(profile, x, z, stage);
        if (edge <= 0.0D) {
            return DiscColumn.outside(profile, x, z, stage);
        }
        // Authored river channel (bbox-gated: MAX_VALUE almost everywhere). Channel
        // columns bypass the crumble holes so the notch stays carved through the taper.
        double riverDist = map.riverDistance(profile, x, z);
        boolean inChannel = riverDist < RIVER_HALF_WIDTH;
        if (edge < 0.35D && !inChannel && hash01(H_CRUMBLE, x, z) < (0.35D - edge) * 1.6D) {
            // ~10% of the crumble holes just outside the rim survive as small detached
            // floating shards a few blocks below rim height; the rest stay void.
            if (hash01(H_SHARD, x, z) < 0.10D) {
                return shardColumn(profile, x, z, stage, map);
            }
            return DiscColumn.outside(profile, x, z, stage);
        }
        String biomeId = map.biomeAt(profile, x, z);
        SectorStyle style = styleOf(profile, biomeId);
        int surfaceY = computeSurfaceY(map, profile, x, z, style);
        double r = Math.sqrt((double) x * x + (double) z * z);

        // River carve: depress the bed 3-4 blocks and fill static water sources up to
        // the original surface − 1. Where the channel crosses the rim taper the water
        // is additionally painted a few blocks DOWN the rim face (spillway curtain into
        // the void); chunk postprocessing turns the exposed sources into the waterfall.
        int waterTopY = Integer.MIN_VALUE;
        int waterBottomY = Integer.MAX_VALUE;
        boolean riverBed = riverDist < RIVER_HALF_WIDTH + RIVER_BANK_MARGIN;
        if (inChannel) {
            waterTopY = surfaceY - 1;
            surfaceY -= riverDepth(riverDist);
            waterBottomY = edge < 0.35D ? surfaceY - 5 : surfaceY + 1;
        }

        // Nether lava moat: sunken channel, lava three blocks below the original
        // surface, plus a 2-block magma lip ringing the channel (not the causeways).
        int lavaTopY = Integer.MIN_VALUE;
        boolean moatLip = false;
        if (profile == DiscProfile.NETHER) {
            DiscMapData.Moat moat = map.profile(DiscProfile.NETHER).moat();
            if (moat != null) {
                double moatDelta = Math.abs(r - moat.radius());
                if (moatDelta <= moat.halfWidth() + 2.0D) {
                    double angle = angleDeg(x, z);
                    if (moatDelta <= moat.halfWidth()) {
                        if (!moat.withinBridge(angle, 0.0D)) {
                            surfaceY -= 8;
                            lavaTopY = surfaceY + 5;
                        }
                    } else if (!moat.withinBridge(angle, 2.0D)) {
                        moatLip = true;
                    }
                }
            }
        }

        // Lens underside (normalised against the FINAL radius: stage-independent) with
        // the rim taper thinning the disc to a crumbly knife edge over the last blocks.
        int lensBottomY = (int) Math.floor(profile.lensBottomY(r));
        int fullThickness = Math.max(4, surfaceY - lensBottomY);
        int thickness = Math.max(2, (int) (fullThickness * (0.08D + 0.92D * edge)));
        int undersideY = surfaceY - thickness;

        // Deepslate stalactite fringe hanging below the underside (interior only):
        // fringe^4 sharpens the profile into needles, a high-frequency octave splinters
        // them — the strongest spikes reach 12-24 blocks.
        int groundBottomY = undersideY;
        if (edge > 0.75D) {
            double fringe = FRINGE_NOISE.getValue(x / 22.0D, z / 22.0D);
            if (fringe > 0.0D) {
                double f2 = fringe * fringe;
                double needle = f2 * f2 * 18.0D;
                double hf = FRINGE_NOISE.getValue(x / 6.0D + 512.0D, z / 6.0D - 512.0D);
                if (hf > 0.0D) {
                    needle += hf * hf * fringe * 10.0D;
                }
                groundBottomY -= Math.min(24, (int) needle);
            }
        }

        // Hanging rim decor (overworld): glow lichen shining into the void + short vine
        // strands under the tapered underside of the rim band. Stage-dependent by
        // construction (edge), but the whole band lies inside RIM_REWRITE_MARGIN.
        BlockState hangState = null;
        int hangLength = 0;
        if (profile == DiscProfile.OVERWORLD && edge > 0.35D && edge < 0.75D) {
            long hangHash = hash(H_HANG, x, z);
            double hang01 = to01(hangHash);
            if (hang01 < 0.045D) {
                hangState = GLOW_LICHEN_CEILING;
                hangLength = 1;
            } else if (hang01 < 0.11D) {
                hangState = VINE_CEILING;
                hangLength = 2 + (int) ((hangHash >>> 8) & 0xFF) % 3; // 2..4
            }
        }
        int bottomY = groundBottomY - hangLength;

        int deepslateTopY = profile == DiscProfile.NETHER
                ? 48 + (int) ((hash01(H_DEEPSLATE, x, z) - 0.5D) * 6.0D)
                : (int) ((hash01(H_DEEPSLATE, x, z) - 0.5D) * 6.0D);

        // Ring scars: weld seams on the FINAL stage boundaries (stage-independent), plus
        // the fainter r=96 line where the original main disc ended. 1 = faint, 2 = full.
        int scar = 0;
        if (profile == DiscProfile.OVERWORLD) {
            if (Math.abs(r - SCAR_FAINT_RADIUS) < SCAR_HALF_WIDTH) {
                scar = 1;
            } else {
                for (double boundary : SCAR_RADII) {
                    if (Math.abs(r - boundary) < SCAR_HALF_WIDTH) {
                        scar = 2;
                        break;
                    }
                }
            }
        }

        // Sealed mountain core cavity (future stronghold) + cave suppression shell +
        // the narrow frozen cascade pouring down the mountain's north face.
        int cavityMinY = 1;
        int cavityMaxY = 0;
        int cavityLavaY = Integer.MIN_VALUE;
        boolean cavityShell = false;
        boolean iceCascade = false;
        DiscMapData.Mountain mountain = map.profile(profile).mountain();
        if (mountain != null) {
            double mdx = x - mountain.x();
            double mdz = z - mountain.z();
            double distSq = mdx * mdx + mdz * mdz;
            double shellR = mountain.caveRadiusXz() + 6.0D;
            if (distSq < shellR * shellR) {
                cavityShell = true;
                double norm = distSq / ((double) mountain.caveRadiusXz() * mountain.caveRadiusXz());
                if (norm < 1.0D) {
                    double halfY = mountain.caveRadiusY() * Math.sqrt(1.0D - norm);
                    cavityMinY = (int) Math.ceil(mountain.caveY() - halfY);
                    cavityMaxY = (int) Math.floor(mountain.caveY() + halfY);
                    cavityLavaY = mountain.caveY() - mountain.caveRadiusY() + 3;
                }
            }
            if (profile == DiscProfile.OVERWORLD && waterTopY == Integer.MIN_VALUE
                    && surfaceY > 126 && surfaceY < 254) {
                double dist = Math.sqrt(distSq);
                if (dist > 14.0D && dist < 58.0D) {
                    // North face = -Z = angle −π/2; no wrap handling needed that far
                    // from the ±π seam. The wedge half-width wiggles slightly with the
                    // radial distance so the cascade meanders like a frozen flow.
                    double deltaNorth = Math.abs(Math.atan2(mdz, mdx) + Math.PI / 2.0D);
                    double halfWidth = 0.055D + 0.025D * RIDGE_NOISE.getValue(dist / 20.0D, 333.3D);
                    iceCascade = deltaNorth < halfWidth;
                }
            }
        }

        // Perlin-worm cave band: clamped >= 4 blocks above the underside, never
        // breaching the surface, disabled on the rim and around the cavity shell.
        int caveMinY = undersideY + 4;
        int caveMaxY = edge > 0.5D && !cavityShell ? surfaceY - 7 : Integer.MIN_VALUE;

        // Vegetation & surface accents.
        Tree tree = null;
        BlockState cover = null;
        BlockState pillarBlock = null;
        int pillarHeight = 0;
        boolean snowCap = false;
        if (profile == DiscProfile.OVERWORLD) {
            snowCap = surfaceY >= 210;
            tree = treeAt(map, profile, x, z, stage);
            boolean trunkHere = tree != null && tree.x() == x && tree.z() == z;
            boolean bareGround = riverBed || scar == 2 || iceCascade;
            if (!trunkHere && !bareGround) {
                long coverHash = hash(H_COVER, x, z);
                double cover01 = to01(coverHash);
                if (style == SectorStyle.DESERT) {
                    if (cover01 < 0.004D && isCactusSpot(map, profile, x, z, surfaceY)) {
                        pillarBlock = CACTUS;
                        pillarHeight = 1 + (int) ((coverHash >>> 8) & 3) % 3; // 1..3
                    } else if (cover01 < 0.016D) {
                        cover = DEAD_BUSH;
                    }
                } else if (style == SectorStyle.SNOWY || style == SectorStyle.GROVE || surfaceY > 150) {
                    if (cover01 < 0.85D) {
                        cover = SNOW_LAYER;
                    }
                } else if (surfaceY <= 140 && cover01 < style.grassDensity) {
                    cover = cover01 < style.grassDensity * 0.15D
                            ? FLOWERS[(int) ((coverHash >>> 16) & 3)]
                            : SHORT_GRASS;
                }
            }
            // Sparse crystal growth on the full weld seams (grass/flowers stay suppressed).
            if (!trunkHere && scar == 2 && waterTopY == Integer.MIN_VALUE
                    && hash01(H_SCAR, x, z) < 0.04D) {
                cover = AMETHYST_BUD;
            }
        } else if (lavaTopY == Integer.MIN_VALUE && !moatLip) {
            // Nether dressing: crimson/warped mini-fungi via the tree machinery, roots/
            // vines ground cover, basalt pillars (cactus column mechanic) and bone
            // clusters + soul fire in the soul sector.
            tree = treeAt(map, profile, x, z, stage);
            boolean trunkHere = tree != null && tree.x() == x && tree.z() == z;
            if (!trunkHere) {
                long coverHash = hash(H_COVER, x, z);
                double cover01 = to01(coverHash);
                switch (style) {
                    case CRIMSON -> {
                        if (cover01 < style.grassDensity) {
                            cover = CRIMSON_ROOTS;
                        }
                    }
                    case WARPED -> {
                        if (cover01 < style.grassDensity) {
                            cover = WARPED_ROOTS;
                        } else if (cover01 < style.grassDensity + 0.04D) {
                            cover = TWISTING_VINES;
                        } else if (cover01 < style.grassDensity + 0.07D) {
                            cover = NETHER_SPROUTS;
                        }
                    }
                    case BASALT -> {
                        if (cover01 < 0.012D) {
                            pillarBlock = BASALT;
                            pillarHeight = 2 + (int) ((coverHash >>> 8) & 0xFF) % 5; // 2..6
                        }
                    }
                    case SOUL -> {
                        if (cover01 < 0.03D && SURFACE_LARGE.getValue(x / 26.0D, z / 26.0D) > 0.35D) {
                            pillarBlock = BONE_BLOCK;
                            pillarHeight = 1 + (int) ((coverHash >>> 8) & 0xFF) % 3; // 1..3
                        } else if (cover01 > 0.90D && cover01 < 0.915D) {
                            cover = SOUL_FIRE;
                        }
                    }
                    default -> {}
                }
            }
        }

        int topY = surfaceY;
        if (cover != null) {
            topY = surfaceY + 1;
        }
        if (pillarHeight > 0) {
            topY = surfaceY + pillarHeight;
        }
        if (tree != null) {
            topY = Math.max(topY, tree.baseY() + tree.height() + 1);
        }
        if (lavaTopY > topY) {
            topY = lavaTopY;
        }
        if (waterTopY > topY) {
            topY = waterTopY;
        }

        return new DiscColumn(profile, x, z, stage, true, r, surfaceY, undersideY, bottomY,
                groundBottomY, topY, style, deepslateTopY, lavaTopY, waterTopY, waterBottomY,
                cover, pillarBlock, pillarHeight, tree, snowCap, riverBed, scar, moatLip,
                iceCascade, false, hangState, cavityMinY, cavityMaxY, cavityLavaY, cavityShell,
                caveMinY, caveMaxY);
    }

    /** Channel depth below the original surface: 4 near the centerline, 3 towards the edges. */
    private static int riverDepth(double riverDist) {
        return riverDist < 2.5D ? 4 : 3;
    }

    /**
     * A small detached floating shard: a 2-4 thick crumb of surface strata hovering a
     * few blocks below rim height where a crumble-hole column would otherwise be void.
     * No bedrock seal, caves, ores or vegetation — just a drifting scrap of the rim.
     */
    private static DiscColumn shardColumn(DiscProfile profile, int x, int z, int stage, DiscMapData map) {
        SectorStyle style = styleOf(profile, map.biomeAt(profile, x, z));
        int rimSurface = computeSurfaceY(map, profile, x, z, style);
        long h = hash(H_SHARD, x, z);
        int top = rimSurface - 3 - (int) ((h >>> 16) & 3);      // 3..6 below rim height
        int thickness = 2 + (int) ((h >>> 24) & 0xFF) % 3;      // 2..4
        int bottom = top - thickness + 1;
        double r = Math.sqrt((double) x * x + (double) z * z);
        return new DiscColumn(profile, x, z, stage, true, r, top, bottom, bottom, bottom, top,
                style, Integer.MIN_VALUE, Integer.MIN_VALUE, Integer.MIN_VALUE, Integer.MAX_VALUE,
                null, null, 0, null, false, false, 0, false, false, true, null,
                1, 0, Integer.MIN_VALUE, false, 1, 0);
    }

    /** Normalised 0..360 disc-map angle (degrees from +X towards +Z) of the column. */
    private static double angleDeg(int x, int z) {
        double angle = Math.toDegrees(Math.atan2(z, x));
        return angle < 0.0D ? angle + 360.0D : angle;
    }

    /** The block at height {@code y} of a precomputed column. */
    public static BlockState stateInColumn(DiscColumn col, int y) {
        if (!col.inside() || y < col.bottomY() || y > col.topY()) {
            return AIR;
        }
        int x = col.x();
        int z = col.z();
        if (y > col.surfaceY()) {
            if (y <= col.lavaTopY()) {
                return LAVA;
            }
            if (y <= col.waterTopY()) {
                return WATER; // river channel fill up to the original surface − 1
            }
            Tree tree = col.tree();
            if (tree != null) {
                if (tree.x() == x && tree.z() == z && y <= tree.baseY() + tree.height()) {
                    return tree.species().log;
                }
                BlockState leaves = leafAt(tree, x, y, z);
                if (leaves != null) {
                    return leaves;
                }
            }
            if (col.pillarHeight() > 0 && y <= col.surfaceY() + col.pillarHeight()) {
                return col.pillarBlock();
            }
            if (y == col.surfaceY() + 1 && col.cover() != null) {
                return col.cover();
            }
            return AIR;
        }
        // Hanging rim decor dangles below the lowest ground block (vines / glow lichen).
        if (y < col.groundBottomY()) {
            return col.hangState();
        }
        // Ground. Bottom three layers of every column are bedrock (sealed underside) —
        // except detached floating shards, which are bare crumbs, not part of the hull.
        if (!col.shard() && y <= col.groundBottomY() + 2) {
            return BEDROCK;
        }
        if (y >= col.waterBottomY()) {
            return WATER; // spillway curtain painted into the rim face
        }
        if (y >= col.cavityMinY() && y <= col.cavityMaxY()) {
            return y <= col.cavityLavaY() ? LAVA : CAVE_AIR;
        }
        if (y >= col.caveMinY() && y <= col.caveMaxY()) {
            double a = CAVE_A.getValue(x / 44.0D, y / 30.0D, z / 44.0D);
            if (Math.abs(a) < 0.085D) {
                double b = CAVE_B.getValue(x / 44.0D, y / 30.0D, z / 44.0D);
                if (Math.abs(b) < 0.085D) {
                    return CAVE_AIR;
                }
            }
        }
        if (!col.shard()) {
            BlockState ore = oreAt(col, y);
            if (ore != null) {
                return ore;
            }
        }
        return strataBlock(col, y);
    }

    // --- disc shape ---

    /**
     * Smoothstepped "how solid is this column" factor: 1 in the disc interior, 0 in the
     * void, easing over the last {@value #RIM_WIDTH} blocks of the (noise-wobbled) rim.
     * Stage 0 overworld is the union of the main disc and the eight player discs.
     */
    private static double edgeFactor(DiscProfile profile, int x, int z, int stage) {
        if (stage >= 1) {
            return discEdge(x, z, 0, 0, StageRadii.radius(profile, stage), 0);
        }
        if (profile == DiscProfile.NETHER) {
            int radius = StageRadii.radius(profile, 0);
            return radius <= 0 ? 0.0D : discEdge(x, z, 0, 0, radius, 0);
        }
        double edge = discEdge(x, z, 0, 0, DiscGeometry.MAIN_DISC_RADIUS, 0);
        if (edge >= 1.0D) {
            return 1.0D;
        }
        for (int i = 0; i < DiscGeometry.PLAYER_DISC_COUNT; i++) {
            BlockPos center = DiscGeometry.playerDiscCenter(i);
            double dx = x - center.getX();
            double dz = z - center.getZ();
            double reach = DiscGeometry.PLAYER_DISC_RADIUS + RIM_NOISE_AMP + 1;
            if (dx * dx + dz * dz > reach * reach) {
                continue;
            }
            edge = Math.max(edge, discEdge(x, z, center.getX(), center.getZ(),
                    DiscGeometry.PLAYER_DISC_RADIUS, i + 1));
            if (edge >= 1.0D) {
                return 1.0D;
            }
        }
        return edge;
    }

    /** Rim of one disc: {@code rEff = radius + simplex(angle·6)·8}, smoothstep over 12 blocks. */
    private static double discEdge(double x, double z, double cx, double cz, double radius, int noiseIndex) {
        double dx = x - cx;
        double dz = z - cz;
        double distSq = dx * dx + dz * dz;
        double outer = radius + RIM_NOISE_AMP;
        if (distSq > outer * outer) {
            return 0.0D;
        }
        double inner = radius - RIM_NOISE_AMP - RIM_WIDTH;
        if (inner > 0.0D && distSq < inner * inner) {
            return 1.0D;
        }
        double dist = Math.sqrt(distSq);
        double angle = Math.atan2(dz, dx);
        double n = RIM_NOISE.getValue(Math.cos(angle) * 6.0D + noiseIndex * 19.17D,
                Math.sin(angle) * 6.0D - noiseIndex * 7.31D);
        double t = (radius + n * RIM_NOISE_AMP - dist) / RIM_WIDTH;
        if (t <= 0.0D) {
            return 0.0D;
        }
        if (t >= 1.0D) {
            return 1.0D;
        }
        return t * t * (3.0D - 2.0D * t);
    }

    // --- surface ---

    /**
     * Layered fixed-seed simplex surface: sector-aware amplitude (relief blended across
     * ±{@link DiscMapData#SECTOR_BLEND_DEG}° of the wobbled wedge boundaries), mountain
     * bump with radiating ridge spurs, terraced high flanks and a summit crater, ±3 detail.
     */
    private static int computeSurfaceY(DiscMapData map, DiscProfile profile, int x, int z,
            SectorStyle style) {
        if (profile == DiscProfile.NETHER) {
            double[] relief = blendedRelief(map, profile, x, z, style);
            double n = SURFACE_LARGE.getValue(x / 140.0D, z / 140.0D) * 5.0D
                    + SURFACE_MEDIUM.getValue(x / 50.0D, z / 50.0D) * 3.0D;
            double s = 138.0D + n * relief[0] + relief[1]
                    + SURFACE_DETAIL.getValue(x / 12.0D, z / 12.0D) * 2.0D;
            double r0 = Math.sqrt((double) x * x + (double) z * z);
            if (r0 < 20.0D) {
                double t = smoothstep(r0 / 20.0D);
                s = 132.0D * (1.0D - t) + s * t; // flat pad for the fortress core (W5)
            }
            return (int) Math.round(Math.max(100.0D, Math.min(150.0D, s)));
        }
        int painted = map.surfaceOverrideAt(x, z);
        if (painted != Integer.MIN_VALUE) {
            return painted;
        }
        double[] relief = blendedRelief(map, profile, x, z, style);
        double n = SURFACE_LARGE.getValue(x / 180.0D, z / 180.0D) * 9.0D
                + SURFACE_MEDIUM.getValue(x / 60.0D, z / 60.0D) * 4.5D;
        double s = profile.surfaceBaseY() + relief[1] + n * relief[0]
                + SURFACE_DETAIL.getValue(x / 12.0D, z / 12.0D) * 2.5D;
        DiscMapData.Mountain mountain = map.profile(profile).mountain();
        if (mountain != null) {
            double dx = x - mountain.x();
            double dz = z - mountain.z();
            double dist = Math.sqrt(dx * dx + dz * dz);
            if (dist < mountain.radius()) {
                double peakAmp = mountain.peakY() - profile.surfaceBaseY();
                double t = dist / mountain.radius();
                double f = 1.0D - t * t;
                s += peakAmp * f * f;
                // Radiating ridge spurs / couloirs: angularly periodic simplex (sampled
                // on a circle for seam-free wrap, drifting slowly with distance) makes
                // 5-7 alternating crests and gullies down the cone, strongest mid-flank.
                double ma = Math.atan2(dz, dx);
                double ridge = RIDGE_NOISE.getValue(Math.cos(ma) * 1.6D, Math.sin(ma) * 1.6D,
                        dist / 90.0D);
                s += ridge * 15.0D * 4.0D * t * (1.0D - t);
                // Slight summit crater: a shallow bowl within ~6 blocks of the peak.
                if (dist < 6.0D) {
                    s -= 5.0D * (1.0D - (dist / 6.0D) * (dist / 6.0D));
                }
                // Terrace quantization above ~y150: lerp towards floor(s/10)*10 by
                // steepness (analytic cone slope) so steep flanks break into stepped
                // cliff bands while flatter ground stays smooth.
                if (s > 150.0D) {
                    double slope = 4.0D * peakAmp * t * f / mountain.radius();
                    double steep = Math.min(1.0D, Math.abs(slope) / 3.5D);
                    double w = smoothstep(Math.min(1.0D, (s - 150.0D) / 14.0D)) * steep;
                    s += (Math.floor(s / 10.0D) * 10.0D - s) * w;
                }
            }
        }
        double r0 = Math.sqrt((double) x * x + (double) z * z);
        if (r0 < 14.0D) {
            double t = smoothstep(r0 / 14.0D);
            s = 70.0D * (1.0D - t) + s * t; // flat spawn pad for altar + sanctum (W5)
        }
        return (int) Math.round(Math.max(64.0D, Math.min(300.0D, s)));
    }

    /**
     * Effective {@code {surfaceAmp, surfaceOffset}} of the column: the style's own values,
     * lerped towards the neighbouring sector's within ±{@link DiscMapData#SECTOR_BLEND_DEG}°
     * of a (wobbled) wedge boundary — turning offset steps like SWAMP(−5)→SNOWY(+6) into
     * slopes. Both sides converge to the average ON the boundary, so relief is continuous.
     */
    private static double[] blendedRelief(DiscMapData map, DiscProfile profile, int x, int z,
            SectorStyle style) {
        double amp = style.surfaceAmp;
        double offset = style.surfaceOffset;
        DiscMapData.SectorBlend blend = map.sectorBlendAt(profile, x, z);
        if (blend != null) {
            SectorStyle other = styleOf(profile, blend.neighborBiome());
            amp += (other.surfaceAmp - amp) * blend.t();
            offset += (other.surfaceOffset - offset) * blend.t();
        }
        return new double[] {amp, offset};
    }

    private static boolean inMoat(DiscMapData map, int x, int z) {
        DiscMapData.Moat moat = map.profile(DiscProfile.NETHER).moat();
        if (moat == null) {
            return false;
        }
        double r = Math.sqrt((double) x * x + (double) z * z);
        double angle = Math.toDegrees(Math.atan2(z, x));
        if (angle < 0.0D) {
            angle += 360.0D;
        }
        return moat.contains(r, angle);
    }

    // --- strata / ores ---

    private static BlockState strataBlock(DiscColumn col, int y) {
        SectorStyle style = col.style();
        if (col.profile() == DiscProfile.NETHER) {
            if (y == col.surfaceY()) {
                return col.moatLip() ? MAGMA_BLOCK : style.top;
            }
            if (y > col.surfaceY() - 3) {
                return style.filler;
            }
            if (y < col.undersideY()) { // stalactite fringe: blackstone + glowstone sprinkles
                return hash01x3(H_GLOW, col.x(), y, col.z()) < 0.10D ? GLOWSTONE : BLACKSTONE;
            }
            return y < col.deepslateTopY() ? BLACKSTONE : NETHERRACK;
        }
        // Frozen cascade down the mountain's north face: packed ice with blue-ice veins.
        if (col.iceCascade() && y > col.surfaceY() - 2) {
            return hash01x3(H_STRIPE, col.x(), y, col.z()) < 0.25D ? BLUE_ICE : PACKED_ICE;
        }
        // Ring scars: the weld line of a former rim — deepslate/tuff mix for the top and
        // 3-4 blocks below (full seams), or a sparse top-block mix (the faint r=96 seam).
        if (col.scar() > 0 && !col.riverBed()) {
            long scarHash = hash(H_SCAR, col.x(), col.z());
            if (col.scar() == 2 && y > col.surfaceY() - 4 - (int) (scarHash & 1L)) {
                return hash01x3(H_SCAR, col.x(), y, col.z()) < 0.6D ? DEEPSLATE : TUFF;
            }
            if (col.scar() == 1 && y == col.surfaceY() && to01(scarHash) < 0.5D) {
                return ((scarHash >>> 8) & 3L) == 0L ? TUFF : DEEPSLATE;
            }
        }
        // River bed and banks: sand with gravel patches instead of the sector top.
        if (col.riverBed() && y > col.surfaceY() - 2) {
            return hash01x3(H_RIVER_BED, col.x(), y, col.z()) < 0.65D ? SAND : GRAVEL;
        }
        boolean highRock = col.surfaceY() > 140;
        if (y == col.surfaceY()) {
            if (col.snowCap()) {
                return SNOW_BLOCK;
            }
            return highRock ? STONE : style.top;
        }
        if (highRock && y > col.surfaceY() - 14) {
            // Banded tuff/calcite strata stripes in the high-rock shell: only sub-surface
            // rows, so they read on steep faces and terrace walls, never on flat tops.
            // The per-column jitter keeps the band edges ragged.
            int band = Math.floorMod(y + (int) (hash01(H_STRIPE, col.x(), col.z()) * 7.0D), 19);
            if (band < 2) {
                return TUFF;
            }
            if (band == 9) {
                return CALCITE;
            }
            return STONE;
        }
        if (y > col.surfaceY() - style.fillerDepth) {
            return highRock ? STONE : style.filler;
        }
        if (style == SectorStyle.DESERT && y > col.surfaceY() - 7) {
            return SANDSTONE;
        }
        if (y < col.undersideY()) {
            // Overworld stalactite fringe: deepslate needles seeded with glints —
            // amethyst inclusions, crying obsidian (drips purple into the void for
            // free) and thin tuff bands, mirroring the nether's glowstone trick.
            double inclusion = hash01x3(H_INCLUSION, col.x(), y, col.z());
            if (inclusion < 0.05D) {
                return AMETHYST_BLOCK;
            }
            if (inclusion < 0.07D) {
                return CRYING_OBSIDIAN;
            }
            if (Math.floorMod(y + (int) (hash01(H_INCLUSION, col.x(), col.z()) * 5.0D), 16) < 2) {
                return TUFF;
            }
            return DEEPSLATE;
        }
        return y < col.deepslateTopY() ? DEEPSLATE : STONE;
    }

    /**
     * Ring-budgeted deterministic ore veins: one hashed vein candidate per 16³ cell and
     * ore type, constrained to lie fully inside its cell. Probabilities are shaped per
     * stage-annulus band (the "ring budget") and diamonds only exist below y −40 with a
     * strong bias towards the disc center.
     */
    private static BlockState oreAt(DiscColumn col, int y) {
        OreType[] ores = col.profile() == DiscProfile.NETHER ? NETHER_ORES : OVERWORLD_ORES;
        int cx = col.x() >> 4;
        int cz = col.z() >> 4;
        int cy = Math.floorDiv(y, 16);
        double cellR = Math.sqrt(Math.pow(cx * 16 + 8, 2) + Math.pow(cz * 16 + 8, 2));
        int band = annulusBand(cellR);
        for (OreType ore : ores) {
            if (y < ore.minY || y > ore.maxY) {
                continue;
            }
            long h = hash3(H_ORE + ore.salt, cx, cy, cz);
            double p = ore.baseP * ore.bandFactor[band];
            if (ore.centerBias) {
                p *= Math.max(0.15D, 1.0D - cellR / 520.0D);
            }
            if (to01(h) >= p) {
                continue;
            }
            int vx = (cx << 4) + 4 + (int) ((h >>> 12) & 7);
            int vy = cy * 16 + 4 + (int) ((h >>> 16) & 7);
            int vz = (cz << 4) + 4 + (int) ((h >>> 20) & 7);
            if (vy < ore.minY || vy > ore.maxY) {
                continue;
            }
            double radius = ore.radius * (0.65D + 0.35D * ((h >>> 24 & 255) / 255.0D));
            double dx = col.x() - vx;
            double dy = y - vy;
            double dz = col.z() - vz;
            if (dx * dx + dy * dy * 1.6D + dz * dz <= radius * radius) {
                return (y < col.deepslateTopY() ? ore.deepOre : ore.stoneOre).defaultBlockState();
            }
        }
        return null;
    }

    /** Annulus band of a radius, delimited by the FINAL stage radii (stage-independent). */
    private static int annulusBand(double r) {
        if (r < 96.0D) {
            return 0;
        }
        if (r < 225.0D) {
            return 1;
        }
        if (r < 300.0D) {
            return 2;
        }
        if (r < 360.0D) {
            return 3;
        }
        if (r < 420.0D) {
            return 4;
        }
        return 5;
    }

    private record OreType(int salt, Block stoneOre, Block deepOre, int minY, int maxY,
            double baseP, double radius, double[] bandFactor, boolean centerBias) {}

    private static final double[] FLAT_BANDS = {1.0D, 1.0D, 1.0D, 1.0D, 1.0D, 1.0D};

    private static final OreType[] OVERWORLD_ORES = {
            new OreType(1, Blocks.COAL_ORE, Blocks.DEEPSLATE_COAL_ORE, -32, 200, 0.30D, 3.2D, FLAT_BANDS, false),
            new OreType(2, Blocks.COPPER_ORE, Blocks.DEEPSLATE_COPPER_ORE, -20, 80, 0.22D, 3.0D, FLAT_BANDS, false),
            new OreType(3, Blocks.IRON_ORE, Blocks.DEEPSLATE_IRON_ORE, -64, 96, 0.30D, 2.8D,
                    new double[] {1.0D, 1.25D, 1.1D, 0.9D, 0.9D, 0.7D}, false),
            new OreType(4, Blocks.GOLD_ORE, Blocks.DEEPSLATE_GOLD_ORE, -64, -8, 0.11D, 2.6D,
                    new double[] {1.0D, 1.2D, 1.0D, 0.9D, 0.8D, 0.7D}, false),
            new OreType(5, Blocks.REDSTONE_ORE, Blocks.DEEPSLATE_REDSTONE_ORE, -96, -24, 0.13D, 2.8D, FLAT_BANDS, false),
            new OreType(6, Blocks.LAPIS_ORE, Blocks.DEEPSLATE_LAPIS_ORE, -80, -16, 0.07D, 2.4D, FLAT_BANDS, false),
            new OreType(7, Blocks.DIAMOND_ORE, Blocks.DEEPSLATE_DIAMOND_ORE, -125, -40, 0.12D, 2.4D,
                    new double[] {1.3D, 1.0D, 0.7D, 0.45D, 0.3D, 0.2D}, true)};

    private static final OreType[] NETHER_ORES = {
            new OreType(1, Blocks.NETHER_QUARTZ_ORE, Blocks.NETHER_QUARTZ_ORE, 36, 140, 0.25D, 3.0D, FLAT_BANDS, false),
            new OreType(2, Blocks.NETHER_GOLD_ORE, Blocks.NETHER_GOLD_ORE, 34, 110, 0.14D, 2.6D, FLAT_BANDS, false),
            new OreType(3, Blocks.ANCIENT_DEBRIS, Blocks.ANCIENT_DEBRIS, 34, 72, 0.022D, 1.6D, FLAT_BANDS, true)};

    // --- vegetation ---

    /**
     * Deterministic tree (or nether mini-fungus) of the 8×8 grid cell containing (x, z),
     * or null when the cell has no tree or its canopy cannot reach this column. The
     * anchor is margin-clamped so a canopy (radius ≤ 2) never leaves its cell —
     * per-column lookups stay cell-local.
     */
    private static Tree treeAt(DiscMapData map, DiscProfile profile, int x, int z, int stage) {
        int cellX = Math.floorDiv(x, 8);
        int cellZ = Math.floorDiv(z, 8);
        long h = hash(H_TREE, cellX, cellZ);
        int ax = cellX * 8 + 2 + (int) ((h >>> 20) & 3);
        int az = cellZ * 8 + 2 + (int) ((h >>> 24) & 3);
        if (Math.abs(x - ax) > 2 || Math.abs(z - az) > 2) {
            return null;
        }
        String biomeId = map.biomeAt(profile, ax, az);
        SectorStyle style = styleOf(profile, biomeId);
        if (style.treeDensity <= 0.0D || to01(h) >= style.treeDensity) {
            return null;
        }
        // No trunks in a river channel or on its banks (keyed to the ANCHOR, so the
        // whole canopy exists or not consistently for every column that samples it).
        if (map.riverDistance(profile, ax, az) < RIVER_HALF_WIDTH + RIVER_BANK_MARGIN + 0.5D) {
            return null;
        }
        // Keep nether fungi off the moat: channel, causeways and magma lip.
        if (profile == DiscProfile.NETHER) {
            DiscMapData.Moat moat = map.profile(DiscProfile.NETHER).moat();
            if (moat != null
                    && Math.abs(Math.sqrt((double) ax * ax + (double) az * az) - moat.radius())
                            <= moat.halfWidth() + 3.0D) {
                return null;
            }
        }
        // Solid-ground anchors only (0.45 is above the crumble-hole threshold of 0.35).
        if (edgeFactor(profile, ax, az, stage) < 0.45D) {
            return null;
        }
        int anchorSurface = computeSurfaceY(map, profile, ax, az, style);
        if (anchorSurface > 170) {
            return null; // no trees on the high mountain rock
        }
        TreeSpecies species = style.species(h);
        if (species == null) {
            return null;
        }
        int height = species.baseHeight + (int) ((h >>> 28) & 0xFF) % species.heightVar;
        return new Tree(ax, az, anchorSurface, height, species);
    }

    /** Canopy shape around the tree top; corner blocks are hash-pruned for irregularity. */
    private static BlockState leafAt(Tree tree, int x, int y, int z) {
        int dx = x - tree.x();
        int dz = z - tree.z();
        int dy = y - (tree.baseY() + tree.height());
        int adx = Math.abs(dx);
        int adz = Math.abs(dz);
        boolean leaf;
        if (tree.species() == TreeSpecies.SPRUCE) {
            leaf = switch (dy) {
                case -4, -2 -> adx <= 2 && adz <= 2 && !(adx == 2 && adz == 2);
                case -3, -1, 0 -> adx <= 1 && adz <= 1;
                case 1 -> adx == 0 && adz == 0;
                default -> false;
            };
        } else if (tree.species().fungus) {
            // Mini-fungus knob cap: a pruned 3×3 collar over the top two stem blocks
            // with a plus-shaped crown, sprinkled with glowing shroomlight.
            leaf = switch (dy) {
                case -1, 0 -> adx <= 1 && adz <= 1
                        && (!(adx == 1 && adz == 1) || hash01x3(H_LEAF, x, y, z) < 0.35D);
                case 1 -> adx + adz <= 1;
                default -> false;
            };
            if (leaf && hash01x3(H_GLOW, x, y, z) < 0.18D) {
                return SHROOMLIGHT;
            }
        } else {
            leaf = switch (dy) {
                case -2, -1 -> adx <= 2 && adz <= 2
                        && (!(adx == 2 && adz == 2) || hash01x3(H_LEAF, x, y, z) < 0.4D);
                case 0 -> adx <= 1 && adz <= 1;
                case 1 -> adx + adz <= 1;
                default -> false;
            };
        }
        return leaf ? tree.species().leaves : null;
    }

    /** Cacti only stand where the four neighbour columns are not higher (survival rule). */
    private static boolean isCactusSpot(DiscMapData map, DiscProfile profile, int x, int z, int surfaceY) {
        return neighbourSurface(map, profile, x + 1, z) <= surfaceY
                && neighbourSurface(map, profile, x - 1, z) <= surfaceY
                && neighbourSurface(map, profile, x, z + 1) <= surfaceY
                && neighbourSurface(map, profile, x, z - 1) <= surfaceY;
    }

    private static int neighbourSurface(DiscMapData map, DiscProfile profile, int x, int z) {
        return computeSurfaceY(map, profile, x, z,
                styleOf(profile, map.biomeAt(profile, x, z)));
    }

    private record Tree(int x, int z, int baseY, int height, TreeSpecies species) {}

    private enum TreeSpecies {
        OAK(Blocks.OAK_LOG, Blocks.OAK_LEAVES, 4, 3),
        BIRCH(Blocks.BIRCH_LOG, Blocks.BIRCH_LEAVES, 5, 3),
        SPRUCE(Blocks.SPRUCE_LOG, Blocks.SPRUCE_LEAVES, 6, 3),
        JUNGLE(Blocks.JUNGLE_LOG, Blocks.JUNGLE_LEAVES, 6, 4),
        ACACIA(Blocks.ACACIA_LOG, Blocks.ACACIA_LEAVES, 5, 2),
        DARK_OAK(Blocks.DARK_OAK_LOG, Blocks.DARK_OAK_LEAVES, 4, 3),
        // Nether mini-fungi: stem "log" + wart-block "canopy" (3-5 tall knob caps).
        CRIMSON_FUNGUS(Blocks.CRIMSON_STEM, Blocks.NETHER_WART_BLOCK, 3, 3),
        WARPED_FUNGUS(Blocks.WARPED_STEM, Blocks.WARPED_WART_BLOCK, 3, 3);

        final BlockState log;
        final BlockState leaves;
        final int baseHeight;
        final int heightVar;
        final boolean fungus;

        TreeSpecies(Block log, Block leaves, int baseHeight, int heightVar) {
            this.log = log.defaultBlockState();
            // Persistent leaves: section writes never trigger distance updates, so
            // non-persistent leaves would all decay on the first random tick. Wart-block
            // fungus caps have no PERSISTENT property (and never decay) — leave them be.
            BlockState canopy = leaves.defaultBlockState();
            this.leaves = canopy.hasProperty(LeavesBlock.PERSISTENT)
                    ? canopy.setValue(LeavesBlock.PERSISTENT, true)
                    : canopy;
            this.baseHeight = baseHeight;
            this.heightVar = heightVar;
            this.fungus = !(leaves instanceof LeavesBlock);
        }
    }

    // --- sector styles ---

    /** Per-sector terrain palette, relief shaping and vegetation densities. */
    private enum SectorStyle {
        PLAINS(Blocks.GRASS_BLOCK, Blocks.DIRT, 3, 0.7D, 0.0D, 0.06D, 0.18D),
        DESERT(Blocks.SAND, Blocks.SAND, 3, 0.5D, 2.0D, 0.0D, 0.0D),
        FOREST(Blocks.GRASS_BLOCK, Blocks.DIRT, 3, 1.0D, 0.0D, 0.5D, 0.12D),
        JUNGLE(Blocks.GRASS_BLOCK, Blocks.DIRT, 3, 1.15D, 0.0D, 0.55D, 0.2D),
        SAVANNA(Blocks.GRASS_BLOCK, Blocks.DIRT, 3, 0.8D, 1.0D, 0.15D, 0.15D),
        SWAMP(Blocks.GRASS_BLOCK, Blocks.DIRT, 3, 0.35D, -5.0D, 0.3D, 0.15D),
        SNOWY(Blocks.GRASS_BLOCK, Blocks.DIRT, 3, 1.4D, 6.0D, 0.2D, 0.0D),
        GROVE(Blocks.GRASS_BLOCK, Blocks.DIRT, 3, 1.2D, 4.0D, 0.35D, 0.0D),
        DARK_FOREST(Blocks.GRASS_BLOCK, Blocks.DIRT, 3, 1.0D, 0.0D, 0.6D, 0.08D),
        MEADOW(Blocks.GRASS_BLOCK, Blocks.DIRT, 3, 0.6D, 0.0D, 0.04D, 0.3D),
        NETHER_WASTES(Blocks.NETHERRACK, Blocks.NETHERRACK, 3, 1.0D, 0.0D, 0.0D, 0.0D),
        SOUL(Blocks.SOUL_SAND, Blocks.SOUL_SOIL, 3, 0.7D, -2.0D, 0.0D, 0.0D),
        BASALT(Blocks.BASALT, Blocks.BLACKSTONE, 3, 1.3D, 1.0D, 0.0D, 0.0D),
        CRIMSON(Blocks.CRIMSON_NYLIUM, Blocks.NETHERRACK, 3, 0.9D, 0.0D, 0.30D, 0.10D),
        WARPED(Blocks.WARPED_NYLIUM, Blocks.NETHERRACK, 3, 0.9D, 0.0D, 0.25D, 0.08D);

        final BlockState top;
        final BlockState filler;
        final int fillerDepth;
        final double surfaceAmp;
        final double surfaceOffset;
        final double treeDensity;
        final double grassDensity;

        SectorStyle(Block top, Block filler, int fillerDepth, double surfaceAmp,
                double surfaceOffset, double treeDensity, double grassDensity) {
            this.top = top.defaultBlockState();
            this.filler = filler.defaultBlockState();
            this.fillerDepth = fillerDepth;
            this.surfaceAmp = surfaceAmp;
            this.surfaceOffset = surfaceOffset;
            this.treeDensity = treeDensity;
            this.grassDensity = grassDensity;
        }

        TreeSpecies species(long hash) {
            return switch (this) {
                case FOREST -> ((hash >>> 40) & 3) == 0 ? TreeSpecies.BIRCH : TreeSpecies.OAK;
                case JUNGLE -> TreeSpecies.JUNGLE;
                case SAVANNA -> TreeSpecies.ACACIA;
                case SNOWY, GROVE -> TreeSpecies.SPRUCE;
                case DARK_FOREST -> TreeSpecies.DARK_OAK;
                case PLAINS, SWAMP, MEADOW -> TreeSpecies.OAK;
                case CRIMSON -> TreeSpecies.CRIMSON_FUNGUS;
                case WARPED -> TreeSpecies.WARPED_FUNGUS;
                default -> null;
            };
        }
    }

    private static SectorStyle styleOf(DiscProfile profile, String biomeId) {
        String path = biomeId.substring(biomeId.indexOf(':') + 1);
        return switch (path) {
            case "plains" -> SectorStyle.PLAINS;
            case "desert" -> SectorStyle.DESERT;
            case "forest" -> SectorStyle.FOREST;
            case "jungle" -> SectorStyle.JUNGLE;
            case "savanna" -> SectorStyle.SAVANNA;
            case "swamp" -> SectorStyle.SWAMP;
            case "snowy_slopes" -> SectorStyle.SNOWY;
            case "grove" -> SectorStyle.GROVE;
            case "dark_forest" -> SectorStyle.DARK_FOREST;
            case "meadow" -> SectorStyle.MEADOW;
            case "nether_wastes" -> SectorStyle.NETHER_WASTES;
            case "soul_sand_valley" -> SectorStyle.SOUL;
            case "basalt_deltas" -> SectorStyle.BASALT;
            case "crimson_forest" -> SectorStyle.CRIMSON;
            case "warped_forest" -> SectorStyle.WARPED;
            default -> profile == DiscProfile.NETHER ? SectorStyle.NETHER_WASTES : SectorStyle.PLAINS;
        };
    }

    // --- column record ---

    /**
     * Immutable per-column snapshot of everything {@link #stateInColumn} needs.
     * {@code inside=false} columns are void; {@code bottomY..topY} bounds the only Y
     * range that can contain non-air blocks (use it to bound generation loops).
     *
     * <p>Component notes: {@code groundBottomY} is the lowest SOLID block (the bedrock
     * seal sits on it) while {@code bottomY} additionally spans the hanging rim decor
     * ({@code hangState}: ceiling vines / glow lichen strands of length
     * {@code groundBottomY − bottomY}). {@code waterTopY}/{@code waterBottomY} bound the
     * river water fill ({@code MIN_VALUE}/{@code MAX_VALUE} = none); a
     * {@code waterBottomY <= surfaceY} means the rim-face spillway curtain. {@code scar}
     * is 0 = none, 1 = faint (r=96 weld), 2 = full ring scar. {@code shard=true} marks a
     * detached floating rim shard (no bedrock seal, caves, ores or vegetation).</p>
     */
    public record DiscColumn(DiscProfile profile, int x, int z, int stage, boolean inside,
            double radial, int surfaceY, int undersideY, int bottomY, int groundBottomY,
            int topY, SectorStyle style, int deepslateTopY, int lavaTopY, int waterTopY,
            int waterBottomY, BlockState cover, BlockState pillarBlock, int pillarHeight,
            Tree tree, boolean snowCap, boolean riverBed, int scar, boolean moatLip,
            boolean iceCascade, boolean shard, BlockState hangState, int cavityMinY,
            int cavityMaxY, int cavityLavaY, boolean cavityShell, int caveMinY, int caveMaxY) {

        static DiscColumn outside(DiscProfile profile, int x, int z, int stage) {
            return new DiscColumn(profile, x, z, stage, false, 0.0D, 0, 0, 0, 0, -1,
                    SectorStyle.PLAINS, 0, Integer.MIN_VALUE, Integer.MIN_VALUE,
                    Integer.MAX_VALUE, null, null, 0, null, false, false, 0, false,
                    false, false, null, 1, 0, Integer.MIN_VALUE, false, 1, 0);
        }
    }

    // --- noise / hashing ---

    private static SimplexNoise noise(int salt) {
        return new SimplexNoise(new XoroshiroRandomSource(DiscMapData.ECLIPSE_SEED + salt * 0x9E3779B97F4A7C15L));
    }

    private static long mix(long z) {
        z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
        z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
        return z ^ (z >>> 31);
    }

    private static long hash(int salt, int a, int b) {
        long h = DiscMapData.ECLIPSE_SEED + salt * 0x9E3779B97F4A7C15L;
        h = mix(h ^ (a & 0xFFFFFFFFL));
        return mix(h ^ (b & 0xFFFFFFFFL));
    }

    private static long hash3(int salt, int a, int b, int c) {
        long h = DiscMapData.ECLIPSE_SEED + salt * 0x9E3779B97F4A7C15L;
        h = mix(h ^ (a & 0xFFFFFFFFL));
        h = mix(h ^ (b & 0xFFFFFFFFL));
        return mix(h ^ (c & 0xFFFFFFFFL));
    }

    private static double to01(long hash) {
        return (hash >>> 11) * 0x1.0p-53D;
    }

    private static double hash01(int salt, int a, int b) {
        return to01(hash(salt, a, b));
    }

    private static double hash01x3(int salt, int a, int b, int c) {
        return to01(hash3(salt, a, b, c));
    }

    private static double smoothstep(double t) {
        return t * t * (3.0D - 2.0D * t);
    }
}
