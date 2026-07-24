package dev.projecteclipse.eclipse.worldgen;

import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.MultifaceBlock;
import net.minecraft.world.level.block.VineBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.XoroshiroRandomSource;
import net.minecraft.world.level.levelgen.synth.SimplexNoise;

import dev.projecteclipse.eclipse.worldgen.ore.OreField;

/**
 * The single deterministic terrain function of the disc world — v2 (plan v3, worker
 * W1.2): a STRATA-ONLY base. The function owns the disc silhouette, rim, underside,
 * rivers, moat, mountain, ring scars, cave voids ({@link CaveDensity} worms + cheese,
 * {@link CaveEntrances} walk-in craters), the nether-breach funnel
 * ({@link BreachGeometry}), the in-sky End disc ({@link EndDiscGeometry}) and, since
 * IDEA-17 (W4-NETHER), the nether ceiling roof shell with its stalactite forests and
 * the seam lava-fall curtains.
 * It emits NO vegetation and NO ores anymore:
 * trees/grass/flowers/cacti/snow-layers and every other plant come from real vanilla
 * biome features replayed by W1.1's decoration pipeline, and ore placement is delegated
 * to W1.3's {@link OreField} (gated by the frozen stage annuli, hard-capped below
 * typical surfaces). The only "accents" left are strata: snow-cap blocks on high ground
 * and amethyst crystal crust on the ring-scar welds.
 *
 * <p>{@link #stateAt(DiscProfile, int, int, int, int)} is a PURE function of
 * (profile, x, y, z, stage): every input comes from {@link FrozenParams#mapSeed()},
 * {@code disc_map.json}, the per-save frozen params ({@code FrozenParams} — stage radii
 * for scars/annuli, breach/End materialization flags) and the stage radius — never from
 * the world seed or any live world state. The chunk generator (never-generated chunks)
 * and the ring-growth sweep (already-generated chunks) both consume it, so their output
 * is byte-identical.</p>
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
 * <p><b>Stage reproducibility contract (ring sweep):</b> for columns strictly inside
 * {@code stageRadius(n) − }{@link #RIM_REWRITE_MARGIN} the output is independent of the
 * stage, because the lens formula normalises against the FINAL radius
 * ({@link DiscProfile#lensNormRadius()}). Only the rim taper/crumble band changes when a
 * stage grows, so a ring sweep from stage n−1 to n must rewrite the annulus from
 * {@code radius(n−1) − RIM_REWRITE_MARGIN} out to {@code radius(n) + }{@link #RIM_NOISE_AMP}.
 * Everything added on top of the base lens honours the same split: interior dressing
 * (rivers, sector seam blending, dunes, mountain ridges/terraces/ice, ring scars, nether
 * moat lip, cave voids, entrances, breach and End geometry) is keyed exclusively to
 * fixed map data, frozen per-save params and FINAL radii, while every stage-dependent
 * effect (rim spill curtains, crumble-shard promotion, hanging rim lichen/vines, the
 * stalactite fringe) lives inside the rim band the ring sweep rewrites anyway. The
 * breach funnel and End disc flip on once per save ({@code FrozenParams.breachOpen()} /
 * {@code endDiscMaterialized()}); their live materialization sweeps (W1.7/W1.8) write
 * exactly what this function returns afterwards.</p>
 */
public final class DiscTerrainFunction {
    /** Width in blocks of the smoothstep rim taper. */
    public static final int RIM_WIDTH = 12;
    /** Amplitude in blocks of the simplex wobble applied to every disc rim. */
    public static final int RIM_NOISE_AMP = 8;
    /**
     * How far INSIDE the previous stage radius the ring sweep must start rewriting so
     * the old rim taper, crumble holes and spill curtains are replaced by interior
     * terrain (rim width + rim noise + a safety margin).
     */
    public static final int RIM_REWRITE_MARGIN = RIM_WIDTH + RIM_NOISE_AMP + 4;

    /** Half-width in blocks of an authored river channel (depressed bed + water fill). */
    public static final double RIVER_HALF_WIDTH = 4.0D;
    /** Extra sand/gravel bank margin around the channel. */
    public static final double RIVER_BANK_MARGIN = 2.0D;

    /**
     * Radial half-width of a ring-scar weld seam. The scar radii themselves come from
     * the per-save frozen stage radii ({@code FrozenParams.stageRadii}) — index 0 is the
     * faint main-disc weld, indices 1..n−2 carry full seams, and the final radius is the
     * live rim (no scar). NEVER derive scars from the current stage or interior output
     * would stop being stage-independent.
     */
    private static final double SCAR_HALF_WIDTH = 1.5D;

    // Save-frozen noise fields (never the world seed). Salt registry of the
    // map-seed noise family: 1-5 + 9 live here, 6/7/10 in CaveDensity, 8 in
    // DiscMapData's sector-seam wobble, 24/27 here (dunes / red-sand patches),
    // 25 in EndDiscGeometry, 26 in BreachGeometry, 29 in CaveBiomeMap,
    // 30-32 in DiscMapDefaults. Next free noise salt: 33+.
    private static volatile TerrainNoises terrainNoises;

    private record TerrainNoises(long seed, SimplexNoise rim, SimplexNoise surfaceLarge,
            SimplexNoise surfaceMedium, SimplexNoise surfaceDetail, SimplexNoise fringe,
            SimplexNoise ridge, SimplexNoise dune, SimplexNoise sandPatch) {}

    // Hash salts. 13 (CaveEntrances), 14 (BreachGeometry) and 15 (EndDiscGeometry) are
    // owned by the sibling geometry modules; 17 + ore.salt() belongs to W1.3's OreField
    // (cell-coordinate domain, carried over from the legacy in-file ore table). 28 is
    // shared here between the badlands band jitter and the sandstone accents (disjoint
    // column families); 29 between the nether ceiling-forest cell mask (x>>4, z>>4
    // domain) and the roof body mix (x, y, z domain). Next free hash salt: 31+.
    private static final int H_CRUMBLE = 11;
    private static final int H_DEEPSLATE = 12;
    private static final int H_GLOW = 16;
    private static final int H_ACCENT = 28;
    private static final int H_SHARD = 18;
    private static final int H_HANG = 19;
    private static final int H_SCAR = 20;
    private static final int H_INCLUSION = 21;
    private static final int H_STRIPE = 22;
    private static final int H_RIVER_BED = 23;
    /** IDEA-17: nether ceiling stalactite-forest cell mask + roof body mix (W4-NETHER). */
    private static final int H_CEILING = 29;
    /** IDEA-17: lava-fall curtain segment gate on the nether sector seams (W4-NETHER). */
    private static final int H_SEAM = 30;

    // --- IDEA-17 nether roof shell ("the bedrock you are under") ---

    /** Roof lens base Y at the disc center (cavern is tallest here). */
    private static final double CEILING_CENTER_BOTTOM_Y = 232.0D;
    /** Roof lens base Y at the FINAL rim ({@code lensNormRadius}). */
    private static final double CEILING_RIM_BOTTOM_Y = 200.0D;
    /** Max downward reach in blocks of a ceiling stalactite-forest needle. */
    private static final int CEILING_NEEDLE_MAX = 24;
    /** Fraction of 16-block cells that carry a stalactite forest (clearings elsewhere). */
    private static final double CEILING_FOREST_CELL_CHANCE = 0.35D;
    /** Seam-blend weight above which a column joins a lava-fall curtain (~1.3° of seam). */
    private static final double SEAM_CURTAIN_MIN_T = 0.42D;
    /** Seam-blend weight of the curtain CORE (splash bowl + pour sources). */
    private static final double SEAM_CORE_MIN_T = 0.46D;

    private static final BlockState AIR = Blocks.AIR.defaultBlockState();
    private static final BlockState CAVE_AIR = Blocks.CAVE_AIR.defaultBlockState();
    private static final BlockState BEDROCK = Blocks.BEDROCK.defaultBlockState();
    private static final BlockState STONE = Blocks.STONE.defaultBlockState();
    private static final BlockState DEEPSLATE = Blocks.DEEPSLATE.defaultBlockState();
    private static final BlockState SANDSTONE = Blocks.SANDSTONE.defaultBlockState();
    private static final BlockState SMOOTH_SANDSTONE = Blocks.SMOOTH_SANDSTONE.defaultBlockState();
    private static final BlockState CUT_SANDSTONE = Blocks.CUT_SANDSTONE.defaultBlockState();
    private static final BlockState SNOW_BLOCK = Blocks.SNOW_BLOCK.defaultBlockState();
    private static final BlockState LAVA = Blocks.LAVA.defaultBlockState();
    private static final BlockState WATER = Blocks.WATER.defaultBlockState();
    private static final BlockState SAND = Blocks.SAND.defaultBlockState();
    private static final BlockState RED_SAND = Blocks.RED_SAND.defaultBlockState();
    private static final BlockState MUD = Blocks.MUD.defaultBlockState();
    private static final BlockState GRAVEL = Blocks.GRAVEL.defaultBlockState();
    private static final BlockState TUFF = Blocks.TUFF.defaultBlockState();
    private static final BlockState CALCITE = Blocks.CALCITE.defaultBlockState();
    private static final BlockState PACKED_ICE = Blocks.PACKED_ICE.defaultBlockState();
    private static final BlockState BLUE_ICE = Blocks.BLUE_ICE.defaultBlockState();
    private static final BlockState AMETHYST_BLOCK = Blocks.AMETHYST_BLOCK.defaultBlockState();
    private static final BlockState CRYING_OBSIDIAN = Blocks.CRYING_OBSIDIAN.defaultBlockState();
    private static final BlockState ORANGE_TERRACOTTA = Blocks.ORANGE_TERRACOTTA.defaultBlockState();
    /** Absolute-y-keyed badlands strata pattern (per-column jitter of ±2 rows). */
    private static final BlockState[] TERRACOTTA_BANDS = {
            Blocks.TERRACOTTA.defaultBlockState(),
            Blocks.ORANGE_TERRACOTTA.defaultBlockState(),
            Blocks.TERRACOTTA.defaultBlockState(),
            Blocks.YELLOW_TERRACOTTA.defaultBlockState(),
            Blocks.WHITE_TERRACOTTA.defaultBlockState(),
            Blocks.LIGHT_GRAY_TERRACOTTA.defaultBlockState(),
            Blocks.ORANGE_TERRACOTTA.defaultBlockState(),
            Blocks.RED_TERRACOTTA.defaultBlockState(),
            Blocks.TERRACOTTA.defaultBlockState(),
            Blocks.ORANGE_TERRACOTTA.defaultBlockState(),
            Blocks.BROWN_TERRACOTTA.defaultBlockState(),
            Blocks.ORANGE_TERRACOTTA.defaultBlockState(),
            Blocks.YELLOW_TERRACOTTA.defaultBlockState(),
            Blocks.TERRACOTTA.defaultBlockState(),
            Blocks.RED_TERRACOTTA.defaultBlockState()};
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

    private DiscTerrainFunction() {}

    // --- public API (signature-stable per plan v3 §3.10) ---

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
        } else if (profile == DiscProfile.OVERWORLD && style == SectorStyle.SWAMP
                && surface <= profile.seaLevel()) {
            surface = swampPoolBedY(surface); // shallow pool bed (water fills to sea level)
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
     * mountain, cave-entrance anchors) reads the SAME instance, so a concurrent
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

        // Per-save event geometry (D10/D12): both flags flip ON once per save and stay
        // set, so chunk generation after the event and the live materialization sweeps
        // (W1.7 BreachBuilder / W1.8 EndDiscService) produce identical blocks.
        boolean breach = profile == DiscProfile.OVERWORLD && FrozenParams.breachOpen()
                && BreachGeometry.contains(x, z);
        boolean endDisc = profile == DiscProfile.OVERWORLD && FrozenParams.endDiscMaterialized()
                && EndDiscGeometry.footprintContains(x, z);

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

        // Swamp lowering (D2): where the swamp sinks to sea level, open a shallow pool —
        // mud bed 2-4 blocks under a static water fill up to sea level. Interior only
        // (edge gate) so pools never spill over the crumbly rim taper.
        boolean swampPool = false;
        if (profile == DiscProfile.OVERWORLD && style == SectorStyle.SWAMP && !inChannel
                && edge > 0.7D && surfaceY <= profile.seaLevel()) {
            swampPool = true;
            surfaceY = swampPoolBedY(surfaceY);
            waterTopY = profile.seaLevel();
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

        // IDEA-17 idea 5 — lava-fall curtains at the five nether sector seams: segmented
        // sheets pouring from the roof into a magma splash bowl. Keyed to fixed map data
        // + final radii only (stage-independent interior; the edge gate lies inside the
        // rim band the ring sweep rewrites anyway). Level 1 = magma splash lip, 2 = core
        // bowl (1-deep lava fill), 3 = core + ONE ceiling pour source per ~5 radial
        // blocks (bounds the vanilla flow-update budget to <=4 sources per chunk seam
        // run). Suppressed near the moat, its causeways and all landmark clearances.
        int seamCurtain = 0;
        if (profile == DiscProfile.NETHER && edge > 0.5D) {
            DiscMapData.SectorBlend seamBlend = map.sectorBlendAt(profile, x, z);
            if (seamBlend != null && seamBlend.t() > SEAM_CURTAIN_MIN_T) {
                double angle = angleDeg(x, z);
                DiscMapData.Moat moat = map.profile(profile).moat();
                boolean nearMoat = moat != null
                        && (Math.abs(r - moat.radius()) <= moat.halfWidth() + 4.0D
                                || moat.withinBridge(angle, 4.0D));
                if (!nearMoat && !nearNetherLandmark(map, x, z)) {
                    // Both flanks of one seam share a bucket (boundaries at 0/72/…/288°).
                    int seamIndex = ((int) Math.floor((angle + 36.0D) / 72.0D)) % 5;
                    if (hash01(H_SEAM, seamIndex, (int) (r / 24.0D)) < 0.5D) {
                        seamCurtain = seamBlend.t() > SEAM_CORE_MIN_T ? 2 : 1;
                        if (seamCurtain == 2) {
                            surfaceY -= 1; // splash bowl; fill is flush with the terrain
                            lavaTopY = Math.max(lavaTopY, surfaceY + 1);
                            if (Math.floorMod((int) Math.floor(r), 5) == 0) {
                                seamCurtain = 3;
                            }
                        }
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
            SimplexNoise fringeNoise = terrainNoises().fringe();
            double fringe = fringeNoise.getValue(x / 22.0D, z / 22.0D);
            if (fringe > 0.0D) {
                double f2 = fringe * fringe;
                double needle = f2 * f2 * 18.0D;
                double hf = fringeNoise.getValue(x / 6.0D + 512.0D, z / 6.0D - 512.0D);
                if (hf > 0.0D) {
                    needle += hf * hf * fringe * 10.0D;
                }
                groundBottomY -= Math.min(24, (int) needle);
            }
        }

        // IDEA-17 idea 1b — nether roof shell: a mirrored lens hanging from the world
        // top (cavern tallest at the center), rim-tapered by the SAME edge factor as
        // the floor so the roof thins and crumbles inside the rim band the ring sweep
        // rewrites (interior output stays keyed to the FINAL lensNormRadius only).
        // Idea 3 — ceiling stalactite forests: the floor fringe formula mirrored onto
        // the roof on an offset noise domain, clustered by a 16-block cell mask so the
        // needles read as forests with clearings.
        int ceilingBottomY = Integer.MAX_VALUE;
        int ceilingBodyY = Integer.MAX_VALUE;
        int ceilingTopY = Integer.MIN_VALUE;
        if (profile == DiscProfile.NETHER) {
            ceilingTopY = profile.minY() + profile.height() - 1;
            double tRoof = Math.min(1.0D, r / profile.lensNormRadius());
            int roofBase = (int) Math.floor(CEILING_CENTER_BOTTOM_Y
                    + (CEILING_RIM_BOTTOM_Y - CEILING_CENTER_BOTTOM_Y) * tRoof * tRoof);
            int roofFull = Math.max(4, ceilingTopY + 1 - roofBase);
            int roofThickness = Math.max(2, (int) (roofFull * (0.08D + 0.92D * edge)));
            ceilingBodyY = ceilingTopY + 1 - roofThickness;
            ceilingBottomY = ceilingBodyY;
            if (edge > 0.75D && hash01(H_CEILING, x >> 4, z >> 4) < CEILING_FOREST_CELL_CHANCE) {
                SimplexNoise fringeNoise = terrainNoises().fringe();
                double fringe = fringeNoise.getValue(x / 22.0D + 1024.0D, z / 22.0D + 1024.0D);
                if (fringe > 0.0D) {
                    double f2 = fringe * fringe;
                    double needle = f2 * f2 * 18.0D;
                    double hf = fringeNoise.getValue(x / 6.0D + 1536.0D, z / 6.0D - 1536.0D);
                    if (hf > 0.0D) {
                        needle += hf * hf * fringe * 10.0D;
                    }
                    ceilingBottomY -= Math.min(CEILING_NEEDLE_MAX, (int) needle);
                }
            }
        }

        // Hanging rim decor (overworld): glow lichen shining into the void + short vine
        // strands under the tapered underside of the rim band. Stage-dependent by
        // construction (edge), but the whole band lies inside RIM_REWRITE_MARGIN.
        // Suppressed in breach columns (the funnel owns its own hanging dressing).
        BlockState hangState = null;
        int hangLength = 0;
        if (profile == DiscProfile.OVERWORLD && !breach && edge > 0.35D && edge < 0.75D) {
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
        if (breach && BreachGeometry.spoutContains(x, z)) {
            // The chimney wall collar keeps going below the lowest ground block.
            bottomY = Math.min(bottomY, groundBottomY - BreachGeometry.SPOUT_DEPTH);
        }

        int deepslateTopY = profile == DiscProfile.NETHER
                ? 48 + (int) ((hash01(H_DEEPSLATE, x, z) - 0.5D) * 6.0D)
                : (int) ((hash01(H_DEEPSLATE, x, z) - 0.5D) * 6.0D);

        // Ring scars: weld seams on the FROZEN stage boundaries (stage-independent —
        // FrozenParams snapshots the radii once per save). Index 0 is the faint weld
        // where the original main disc ended; the last radius is the live rim (no scar).
        // 1 = faint, 2 = full.
        int scar = 0;
        if (profile == DiscProfile.OVERWORLD) {
            int[] frozenRadii = FrozenParams.stageRadii(profile);
            if (frozenRadii.length > 0 && Math.abs(r - frozenRadii[0]) < SCAR_HALF_WIDTH) {
                scar = 1;
            } else {
                for (int i = 1; i < frozenRadii.length - 1; i++) {
                    if (Math.abs(r - frozenRadii[i]) < SCAR_HALF_WIDTH) {
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
                    double halfWidth = 0.055D
                            + 0.025D * terrainNoises().ridge().getValue(dist / 20.0D, 333.3D);
                    iceCascade = deltaNorth < halfWidth;
                }
            }
        }

        // Cave band (D4): worms + cheese via CaveDensity, clamped >= 4 blocks above the
        // underside, disabled on the rim and around the cavity shell. caveMaxY reaches
        // the SURFACE now — tunnels may daylight naturally (free cave mouths); the
        // cheese layer additionally fades against the rim via caveFade.
        int caveMinY = undersideY + 4;
        int caveMaxY = edge > 0.5D && !cavityShell ? surfaceY : Integer.MIN_VALUE;
        double caveFade = caveMaxY == Integer.MIN_VALUE ? 0.0D
                : smoothstep(Math.max(0.0D, Math.min(1.0D, (edge - 0.55D) / 0.30D)));

        // Authored walk-in cave entrance of this column's 96×96 cell, if any (D4.4).
        CaveEntrances.Entrance entrance = profile == DiscProfile.OVERWORLD
                ? CaveEntrances.entranceAt(map, x, z)
                : null;

        // Snow caps on high ground are strata (SNOW_BLOCK top), not vegetation; snow
        // LAYERS now come from vanilla's freeze_top_layer via W1.1 decoration.
        boolean snowCap = profile == DiscProfile.OVERWORLD && surfaceY >= 210;

        int topY = surfaceY;
        if (lavaTopY > topY) {
            topY = lavaTopY;
        }
        if (waterTopY > topY) {
            topY = waterTopY;
        }
        if (breach) {
            topY = Math.max(topY, surfaceY + 1); // creep-halo fire sits one above the top
        }
        if (endDisc) {
            topY = Math.max(topY, EndDiscGeometry.topYAt(x, z));
        }
        if (ceilingTopY > topY) {
            topY = ceilingTopY; // nether roof shell reaches the world top
        }

        return new DiscColumn(profile, x, z, stage, true, r, surfaceY, undersideY, bottomY,
                groundBottomY, topY, style, deepslateTopY, lavaTopY, waterTopY, waterBottomY,
                snowCap, riverBed, scar, moatLip, iceCascade, swampPool, false, hangState,
                cavityMinY, cavityMaxY, cavityLavaY, cavityShell, caveMinY, caveMaxY,
                caveFade, entrance, breach, endDisc, ceilingBottomY, ceilingBodyY,
                ceilingTopY, seamCurtain);
    }

    /** Whether (x, z) lies within 24 blocks of any nether landmark's clearance radius. */
    private static boolean nearNetherLandmark(DiscMapData map, int x, int z) {
        for (DiscMapData.Landmark landmark : map.profile(DiscProfile.NETHER).landmarks()) {
            double reach = landmark.radius() + 24.0D;
            double dx = x - landmark.x();
            double dz = z - landmark.z();
            if (dx * dx + dz * dz <= reach * reach) {
                return true;
            }
        }
        return false;
    }

    /** Channel depth below the original surface: 4 near the centerline, 3 towards the edges. */
    private static int riverDepth(double riverDist) {
        return riverDist < 2.5D ? 4 : 3;
    }

    /** Shallow swamp-pool bed: 2 blocks under the raw surface, never deeper than y 59. */
    private static int swampPoolBedY(int rawSurface) {
        return Math.max(rawSurface - 2, 59);
    }

    /**
     * A small detached floating shard: a 2-4 thick crumb of surface strata hovering a
     * few blocks below rim height where a crumble-hole column would otherwise be void.
     * No bedrock seal, caves, ores or event geometry — just a drifting scrap of the rim.
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
                false, false, 0, false, false, false, true, null,
                1, 0, Integer.MIN_VALUE, false, 1, 0, 0.0D, null, false, false,
                Integer.MAX_VALUE, Integer.MAX_VALUE, Integer.MIN_VALUE, 0);
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
            // Nether roof shell first (ceilingBottomY is MAX_VALUE on the overworld):
            // solid roof body/needles, then the seam-curtain pour source hanging one
            // block under the needle tip of curtain-core columns.
            if (y >= col.ceilingBottomY()) {
                return ceilingBlock(col, y);
            }
            if (col.seamCurtain() == 3 && y == col.ceilingBottomY() - 1) {
                return LAVA;
            }
            // Sky band: End-disc geometry, then the river/moat fills, then breach fire.
            if (col.endDisc() && y >= EndDiscGeometry.MIN_Y) {
                BlockState end = EndDiscGeometry.stateAt(x, y, z);
                if (end != null) {
                    return end;
                }
            }
            if (y <= col.lavaTopY()) {
                return LAVA;
            }
            if (y <= col.waterTopY()) {
                return WATER; // river channel / swamp pool fill
            }
            if (col.breach() && y == col.surfaceY() + 1) {
                BlockState creep = BreachGeometry.creepAt(x, y, z, col.surfaceY());
                if (creep != null) {
                    return creep; // eternal fire on the crimson-creep halo
                }
            }
            return AIR;
        }
        // Nether-breach funnel: pierces EVERYTHING below the lip — strata, caves,
        // stalactite fringe and the bedrock seal — so it must override first.
        if (col.breach()) {
            BlockState carved = BreachGeometry.carveAt(x, y, z);
            if (carved != null) {
                return carved;
            }
            if (y == col.surfaceY()) {
                BlockState creep = BreachGeometry.creepAt(x, y, z, col.surfaceY());
                if (creep != null) {
                    return creep; // nylium/netherrack halo repaint of the top block
                }
            }
        }
        // Hanging rim decor dangles below the lowest ground block (vines / glow lichen).
        if (y < col.groundBottomY()) {
            BlockState hang = col.hangState();
            return hang == null ? AIR : hang;
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
        if (y >= col.caveMinY() && y <= col.caveMaxY()
                && CaveDensity.carvedAt(x, y, z, col.surfaceY(), col.caveMinY(), col.caveFade())) {
            return CAVE_AIR;
        }
        if (col.entrance() != null && y > col.groundBottomY() + 2
                && CaveEntrances.mask(col.entrance(), x, y, z)) {
            return CAVE_AIR; // authored walk-in entrance cone/helix
        }
        // Ore delegation (D5): W1.3's engine owns table/bands/caps; the terrain function
        // only guarantees ores never reach within 8 blocks of the surface (no more
        // exposed boulders — cave entrances replaced them as the way down).
        if (!col.shard() && y <= col.surfaceY() - 8) {
            BlockState ore = OreField.oreAt(col.profile(), x, y, z, y < col.deepslateTopY());
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
        double n = terrainNoises().rim().getValue(Math.cos(angle) * 6.0D + noiseIndex * 19.17D,
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
     * bump with radiating ridge spurs, terraced high flanks and a summit crater, ±3
     * detail. Per-sector identity (D2): the desert carries directional long-wavelength
     * dune ridges (small-scale jitter suppressed, fading out at wedge borders), and the
     * swamp's floor may sink below sea level (pools cut by {@link #column}).
     */
    private static int computeSurfaceY(DiscMapData map, DiscProfile profile, int x, int z,
            SectorStyle style) {
        if (profile == DiscProfile.NETHER) {
            double[] relief = blendedRelief(map, profile, x, z, style);
            TerrainNoises noises = terrainNoises();
            double n = noises.surfaceLarge().getValue(x / 140.0D, z / 140.0D) * 5.0D
                    + noises.surfaceMedium().getValue(x / 50.0D, z / 50.0D) * 3.0D;
            double s = 138.0D + n * relief[0] + relief[1]
                    + noises.surfaceDetail().getValue(x / 12.0D, z / 12.0D) * 2.0D;
            double r0 = Math.sqrt((double) x * x + (double) z * z);
            if (r0 < 20.0D) {
                double t = smoothstep(r0 / 20.0D);
                s = 132.0D * (1.0D - t) + s * t; // flat pad for the fortress core
            }
            return (int) Math.round(Math.max(100.0D, Math.min(150.0D, s)));
        }
        int painted = map.surfaceOverrideAt(x, z);
        if (painted != Integer.MIN_VALUE) {
            return painted;
        }
        double[] relief = blendedRelief(map, profile, x, z, style);
        TerrainNoises noises = terrainNoises();
        double n = noises.surfaceLarge().getValue(x / 180.0D, z / 180.0D) * 9.0D
                + noises.surfaceMedium().getValue(x / 60.0D, z / 60.0D) * 4.5D;
        double s = profile.surfaceBaseY() + relief[1] + n * relief[0];
        double detailAmp = 2.5D;
        if (style == SectorStyle.DESERT) {
            // D2: transverse dune ridges oriented by the sector mid-angle; amplitude
            // fades to 0 at wedge borders (relief[2]) so seams stay continuous.
            s += duneRidge(map, x, z) * relief[2];
            detailAmp = 0.6D; // dunes suppress the small-scale jitter
        }
        s += noises.surfaceDetail().getValue(x / 12.0D, z / 12.0D) * detailAmp;
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
                double ridge = noises.ridge().getValue(Math.cos(ma) * 1.6D, Math.sin(ma) * 1.6D,
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
            s = 70.0D * (1.0D - t) + s * t; // flat spawn pad for altar + sanctum
        }
        // The swamp floor may sink below sea level (shallow pools, D2); everything else
        // keeps the historical y64 floor.
        double floor = style == SectorStyle.SWAMP ? 56.0D : 64.0D;
        return (int) Math.round(Math.max(floor, Math.min(300.0D, s)));
    }

    /**
     * Surface Y of (x, z) before river/moat/pool carving, evaluated against an explicit
     * map snapshot. Package-private seam for the sibling geometry modules
     * ({@link CaveEntrances} anchor/slope probes, {@link BreachGeometry} lip plane).
     */
    static int baseSurfaceY(DiscMapData map, DiscProfile profile, int x, int z) {
        return computeSurfaceY(map, profile, x, z, styleOf(profile, map.biomeAt(profile, x, z)));
    }

    /**
     * Effective {@code {surfaceAmp, surfaceOffset, borderFade}} of the column: the
     * style's own values, lerped towards the neighbouring sector's within
     * ±{@link DiscMapData#SECTOR_BLEND_DEG}° of a (wobbled) wedge boundary — turning
     * offset steps like SWAMP(−7)→SNOWY(+6) into slopes. Both sides converge to the
     * average ON the boundary, so relief is continuous. {@code borderFade} runs 1
     * (interior) → 0 (on the boundary) and damps border-sensitive extras like dunes.
     */
    private static double[] blendedRelief(DiscMapData map, DiscProfile profile, int x, int z,
            SectorStyle style) {
        double amp = style.surfaceAmp;
        double offset = style.surfaceOffset;
        double borderFade = 1.0D;
        DiscMapData.SectorBlend blend = map.sectorBlendAt(profile, x, z);
        if (blend != null) {
            SectorStyle other = styleOf(profile, blend.neighborBiome());
            amp += (other.surfaceAmp - amp) * blend.t();
            offset += (other.surfaceOffset - offset) * blend.t();
            borderFade = 1.0D - 2.0D * blend.t();
        }
        return new double[] {amp, offset, borderFade};
    }

    /**
     * Transverse dune relief (D2): ridged simplex (sharp crests where the field crosses
     * zero) sampled in a frame rotated to the desert wedge's mid-angle — short ~48-block
     * wavelength across the wind axis, ~170-block coherence along the crests. Returns
     * −2..+4 blocks.
     */
    private static double duneRidge(DiscMapData map, int x, int z) {
        double theta = Math.toRadians(desertWindDeg(map, x, z));
        double cos = Math.cos(theta);
        double sin = Math.sin(theta);
        double u = x * cos + z * sin;   // along-wind axis (ridge-normal)
        double v = -x * sin + z * cos;  // crest axis
        double ridge = 1.0D - Math.abs(terrainNoises().dune().getValue(u / 48.0D, v / 170.0D));
        return ridge * 6.0D - 2.0D;
    }

    /**
     * Prevailing "wind" direction of the desert-family wedge containing (x, z): the
     * wedge mid-angle, so all dunes of one desert share an orientation. Falls back to
     * 45° (the authored default desert wedge mid) when no desert wedge matches.
     */
    private static double desertWindDeg(DiscMapData map, int x, int z) {
        double angle = angleDeg(x, z);
        for (DiscMapData.Sector sector : map.profile(DiscProfile.OVERWORLD).sectors()) {
            SectorStyle style = styleOf(DiscProfile.OVERWORLD, sector.biome());
            if ((style == SectorStyle.DESERT || style == SectorStyle.BADLANDS)
                    && sector.contains(angle)) {
                double span = ((sector.endDeg() - sector.startDeg()) % 360.0D + 360.0D) % 360.0D;
                return sector.startDeg() + span * 0.5D;
            }
        }
        return 45.0D;
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

    // --- strata ---

    /**
     * IDEA-17 nether roof shell block at {@code y >= ceilingBottomY}: the top three
     * layers are BEDROCK (mirror of the floor seal), the lens body a blackstone-veined
     * netherrack mass, and everything below {@code ceilingBodyY} reuses the floor
     * fringe palette — blackstone stalactite needles with glowstone sprinkles, so the
     * forests are glowing-tipped for free.
     */
    private static BlockState ceilingBlock(DiscColumn col, int y) {
        if (y > col.ceilingTopY() - 3) {
            return BEDROCK;
        }
        if (y < col.ceilingBodyY()) {
            return hash01x3(H_GLOW, col.x(), y, col.z()) < 0.10D ? GLOWSTONE : BLACKSTONE;
        }
        return hash01x3(H_CEILING, col.x(), y, col.z()) < 0.30D ? BLACKSTONE : NETHERRACK;
    }

    private static BlockState strataBlock(DiscColumn col, int y) {
        SectorStyle style = col.style();
        if (col.profile() == DiscProfile.NETHER) {
            if (y == col.surfaceY()) {
                return col.moatLip() || col.seamCurtain() > 0 ? MAGMA_BLOCK : style.top;
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
        // 3-4 blocks below (full seams), or a sparse top-block mix (the faint seam).
        // Full seams carry a sparse amethyst crystal crust (a strata accent — the only
        // decoration the terrain function still owns besides snow caps).
        if (col.scar() > 0 && !col.riverBed()) {
            long scarHash = hash(H_SCAR, col.x(), col.z());
            if (col.scar() == 2 && y > col.surfaceY() - 4 - (int) (scarHash & 1L)) {
                double mix = hash01x3(H_SCAR, col.x(), y, col.z());
                if (y == col.surfaceY() && mix > 0.955D) {
                    return AMETHYST_BLOCK;
                }
                return mix < 0.6D ? DEEPSLATE : TUFF;
            }
            if (col.scar() == 1 && y == col.surfaceY() && to01(scarHash) < 0.5D) {
                return ((scarHash >>> 8) & 3L) == 0L ? TUFF : DEEPSLATE;
            }
        }
        // River bed and banks: sand with gravel patches instead of the sector top.
        if (col.riverBed() && y > col.surfaceY() - 2) {
            return hash01x3(H_RIVER_BED, col.x(), y, col.z()) < 0.65D ? SAND : GRAVEL;
        }
        // Swamp pool bed: mud under the standing water (D2).
        if (col.swampPool() && y > col.surfaceY() - 3) {
            return MUD;
        }
        boolean highRock = col.surfaceY() > 140;
        if (y == col.surfaceY()) {
            if (col.snowCap()) {
                return SNOW_BLOCK;
            }
            if (highRock) {
                return STONE;
            }
            if (style == SectorStyle.DESERT && redSandPatch(col.x(), col.z())) {
                return RED_SAND; // transition patches towards the badlands ring (D2)
            }
            return style.top;
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
        // Badlands mesas (D2/D6): orange base under the red-sand top, then the classic
        // absolute-y-keyed terracotta bands so strata lines run level across the mesa.
        if (style == SectorStyle.BADLANDS && !highRock) {
            if (y > col.surfaceY() - 4) {
                return ORANGE_TERRACOTTA;
            }
            if (y > col.surfaceY() - 20) {
                int jitter = (int) (hash01(H_ACCENT, col.x(), col.z()) * 3.0D);
                return TERRACOTTA_BANDS[Math.floorMod(y + jitter, TERRACOTTA_BANDS.length)];
            }
        }
        if (y > col.surfaceY() - style.fillerDepth) {
            if (highRock) {
                return STONE;
            }
            if (style == SectorStyle.DESERT && redSandPatch(col.x(), col.z())) {
                return RED_SAND;
            }
            return style.filler;
        }
        // Desert sandstone shelf (D2): deepened to −10 with smooth/cut accents.
        if (style == SectorStyle.DESERT && y > col.surfaceY() - 10) {
            double accent = hash01x3(H_ACCENT, col.x(), y, col.z());
            if (accent < 0.05D) {
                return SMOOTH_SANDSTONE;
            }
            if (accent < 0.09D) {
                return CUT_SANDSTONE;
            }
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

    /** Sparse red-sand repaint field of the desert (transition towards badlands). */
    private static boolean redSandPatch(int x, int z) {
        return terrainNoises().sandPatch().getValue(x / 33.0D, z / 33.0D) > 0.62D;
    }

    // --- sector styles ---

    /**
     * Per-sector terrain palette and relief shaping. STRATA ONLY as of v2 — vegetation
     * densities are gone (vanilla biome features own all plants via W1.1).
     */
    private enum SectorStyle {
        PLAINS(Blocks.GRASS_BLOCK, Blocks.DIRT, 3, 0.7D, 0.0D),
        DESERT(Blocks.SAND, Blocks.SAND, 3, 0.5D, 2.0D),
        BADLANDS(Blocks.RED_SAND, Blocks.ORANGE_TERRACOTTA, 1, 0.9D, 3.0D),
        FOREST(Blocks.GRASS_BLOCK, Blocks.DIRT, 3, 1.0D, 0.0D),
        JUNGLE(Blocks.GRASS_BLOCK, Blocks.DIRT, 3, 1.15D, 0.0D),
        SAVANNA(Blocks.GRASS_BLOCK, Blocks.DIRT, 3, 0.8D, 1.0D),
        SWAMP(Blocks.GRASS_BLOCK, Blocks.DIRT, 3, 0.35D, -7.0D),
        SNOWY(Blocks.GRASS_BLOCK, Blocks.DIRT, 3, 1.4D, 6.0D),
        GROVE(Blocks.GRASS_BLOCK, Blocks.DIRT, 3, 1.2D, 4.0D),
        DARK_FOREST(Blocks.GRASS_BLOCK, Blocks.DIRT, 3, 1.0D, 0.0D),
        MEADOW(Blocks.GRASS_BLOCK, Blocks.DIRT, 3, 0.6D, 0.0D),
        MUSHROOM(Blocks.MYCELIUM, Blocks.DIRT, 3, 0.55D, 0.0D),
        NETHER_WASTES(Blocks.NETHERRACK, Blocks.NETHERRACK, 3, 1.0D, 0.0D),
        SOUL(Blocks.SOUL_SAND, Blocks.SOUL_SOIL, 3, 0.7D, -2.0D),
        BASALT(Blocks.BASALT, Blocks.BLACKSTONE, 3, 1.3D, 1.0D),
        CRIMSON(Blocks.CRIMSON_NYLIUM, Blocks.NETHERRACK, 3, 0.9D, 0.0D),
        WARPED(Blocks.WARPED_NYLIUM, Blocks.NETHERRACK, 3, 0.9D, 0.0D);

        final BlockState top;
        final BlockState filler;
        final int fillerDepth;
        final double surfaceAmp;
        final double surfaceOffset;

        SectorStyle(Block top, Block filler, int fillerDepth, double surfaceAmp,
                double surfaceOffset) {
            this.top = top.defaultBlockState();
            this.filler = filler.defaultBlockState();
            this.fillerDepth = fillerDepth;
            this.surfaceAmp = surfaceAmp;
            this.surfaceOffset = surfaceOffset;
        }
    }

    /**
     * Palette style of a biome id. Covers the biome-map v2 sub-ring table (W1.4,
     * Appendix A) so outer-ring biomes land on sensible strata the moment the new map
     * defaults ship; unknown ids fall back to plains / nether wastes.
     */
    private static SectorStyle styleOf(DiscProfile profile, String biomeId) {
        String path = biomeId.substring(biomeId.indexOf(':') + 1);
        return switch (path) {
            case "plains", "sunflower_plains", "river" -> SectorStyle.PLAINS;
            case "desert" -> SectorStyle.DESERT;
            case "badlands", "wooded_badlands", "eroded_badlands" -> SectorStyle.BADLANDS;
            case "forest", "birch_forest", "old_growth_birch_forest", "taiga",
                    "old_growth_pine_taiga" -> SectorStyle.FOREST;
            case "jungle", "sparse_jungle", "bamboo_jungle" -> SectorStyle.JUNGLE;
            case "savanna", "savanna_plateau", "windswept_savanna" -> SectorStyle.SAVANNA;
            case "swamp", "mangrove_swamp" -> SectorStyle.SWAMP;
            case "snowy_slopes", "snowy_taiga", "ice_spikes", "jagged_peaks" -> SectorStyle.SNOWY;
            case "grove" -> SectorStyle.GROVE;
            case "dark_forest", "pale_garden" -> SectorStyle.DARK_FOREST;
            case "meadow", "cherry_grove" -> SectorStyle.MEADOW;
            case "mushroom_fields" -> SectorStyle.MUSHROOM;
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
     * ({@code hangState}) and, in breach columns, the chimney wall spout.
     * {@code waterTopY}/{@code waterBottomY} bound the river/pool water fill
     * ({@code MIN_VALUE}/{@code MAX_VALUE} = none); a {@code waterBottomY <= surfaceY}
     * means the rim-face spillway curtain. {@code scar} is 0 = none, 1 = faint (main
     * disc weld), 2 = full ring scar. {@code swampPool} = mud-bedded standing water.
     * {@code shard=true} marks a detached floating rim shard (no bedrock seal, caves,
     * ores or event geometry). {@code caveFade} is the 0..1 rim fade of the cheese cave
     * layer; {@code entrance} the cell's authored walk-in entrance (null = none);
     * {@code breach}/{@code endDisc} flag the per-save event geometry overlays.
     * IDEA-17 nether roof (overworld columns: {@code MAX/MAX/MIN_VALUE}):
     * {@code ceilingBottomY} is the lowest solid roof block (stalactite needle tips),
     * {@code ceilingBodyY} the roof lens base (fringe palette between the two),
     * {@code ceilingTopY} the sealed world-top layer. {@code seamCurtain} is the
     * lava-fall curtain level: 0 none, 1 magma splash lip, 2 core bowl, 3 core with a
     * ceiling pour source.</p>
     */
    public record DiscColumn(DiscProfile profile, int x, int z, int stage, boolean inside,
            double radial, int surfaceY, int undersideY, int bottomY, int groundBottomY,
            int topY, SectorStyle style, int deepslateTopY, int lavaTopY, int waterTopY,
            int waterBottomY, boolean snowCap, boolean riverBed, int scar, boolean moatLip,
            boolean iceCascade, boolean swampPool, boolean shard, BlockState hangState,
            int cavityMinY, int cavityMaxY, int cavityLavaY, boolean cavityShell,
            int caveMinY, int caveMaxY, double caveFade, CaveEntrances.Entrance entrance,
            boolean breach, boolean endDisc, int ceilingBottomY, int ceilingBodyY,
            int ceilingTopY, int seamCurtain) {

        static DiscColumn outside(DiscProfile profile, int x, int z, int stage) {
            return new DiscColumn(profile, x, z, stage, false, 0.0D, 0, 0, 0, 0, -1,
                    SectorStyle.PLAINS, 0, Integer.MIN_VALUE, Integer.MIN_VALUE,
                    Integer.MAX_VALUE, false, false, 0, false, false, false, false, null,
                    1, 0, Integer.MIN_VALUE, false, 1, 0, 0.0D, null, false, false,
                    Integer.MAX_VALUE, Integer.MAX_VALUE, Integer.MIN_VALUE, 0);
        }
    }

    // --- noise / hashing (package-private: shared with the W1.2 geometry modules) ---

    /**
     * A save-frozen simplex field of the map-seed noise family. This factory is intended
     * for lifecycle-keyed caches; callers must not retain its return value across saves.
     */
    static SimplexNoise noise(int salt) {
        return noise(FrozenParams.mapSeed(), salt);
    }

    private static SimplexNoise noise(long seed, int salt) {
        return new SimplexNoise(new XoroshiroRandomSource(seed + salt * 0x9E3779B97F4A7C15L));
    }

    /**
     * Returns all terrain fields for the active frozen seed. A same-JVM save switch
     * rebuilds the set atomically before any caller observes it.
     */
    private static TerrainNoises terrainNoises() {
        long seed = FrozenParams.mapSeed();
        TerrainNoises cached = terrainNoises;
        if (cached == null || cached.seed() != seed) {
            synchronized (DiscTerrainFunction.class) {
                cached = terrainNoises;
                if (cached == null || cached.seed() != seed) {
                    cached = new TerrainNoises(seed, noise(seed, 1), noise(seed, 2), noise(seed, 3),
                            noise(seed, 4), noise(seed, 5), noise(seed, 9), noise(seed, 24),
                            noise(seed, 27));
                    terrainNoises = cached;
                }
            }
        }
        return cached;
    }

    private static long mix(long z) {
        z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
        z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
        return z ^ (z >>> 31);
    }

    static long hash(int salt, int a, int b) {
        long h = FrozenParams.mapSeed() + salt * 0x9E3779B97F4A7C15L;
        h = mix(h ^ (a & 0xFFFFFFFFL));
        return mix(h ^ (b & 0xFFFFFFFFL));
    }

    static long hash3(int salt, int a, int b, int c) {
        long h = FrozenParams.mapSeed() + salt * 0x9E3779B97F4A7C15L;
        h = mix(h ^ (a & 0xFFFFFFFFL));
        h = mix(h ^ (b & 0xFFFFFFFFL));
        return mix(h ^ (c & 0xFFFFFFFFL));
    }

    static double to01(long hash) {
        return (hash >>> 11) * 0x1.0p-53D;
    }

    private static double hash01(int salt, int a, int b) {
        return to01(hash(salt, a, b));
    }

    static double hash01x3(int salt, int a, int b, int c) {
        return to01(hash3(salt, a, b, c));
    }

    private static double smoothstep(double t) {
        return t * t * (3.0D - 2.0D * t);
    }
}
