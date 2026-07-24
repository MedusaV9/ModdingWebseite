package dev.projecteclipse.eclipse.worldgen.structure;

import java.util.ArrayList;
import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.registry.EclipseBlocks;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.block.AmethystClusterBlock;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.LanternBlock;
import net.minecraft.world.level.block.RotatedPillarBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.block.state.properties.SlabType;
import net.minecraft.world.phys.Vec3;

/**
 * P6-W4 (plans_v3 §2.6): the v2 "Sanctum of the Occluded Sun" — the whole altar plateau
 * torn out of the disc, hovering {@value #ISLAND_LIFT} blocks above the flattened spawn
 * grounds with the {@link SanctumCrater wound} below it.
 *
 * <p><b>Composition</b> (everything deterministic via {@link FallbackBuilders#hash01},
 * fixed tables, zero {@code RandomSource}; built exactly once, guarded by
 * {@link SanctumVersionData}):</p>
 * <ul>
 *   <li><b>Island top</b>: ellipse r={@value #SURFACE_RADIUS_X}/{@value #SURFACE_RADIUS_Z}
 *       plateau whose surface layer is {@link AltarSanctumBuilder#groundMix} (the sundial
 *       erase contract), carrying the UNCHANGED v1 sanctum-top language: 3-step dais,
 *       altar at top+{@value AltarSanctumBuilder#ALTAR_ABOVE_GROUND}, the 8 pillars on the
 *       r={@value AltarSanctumBuilder#PILLAR_RING_RADIUS} ring (Herald LOS contract:
 *       {@code pillarBaseCorner/pillarBases/pillarTopY} formulas ride {@code altarPos}
 *       untouched), glass + crying-obsidian halos, decor, approach paths and the
 *       {@link SundialPlaza} dial.</li>
 *   <li><b>Rim</b>: a near-continuous polished-blackstone parapet (keeps Herald-fight
 *       knockback on the island), broken only by four diagonal <b>auto-glide notches</b>
 *       (protruding slab ledges flanked by amethyst markers — geometry + anchors for
 *       P4's edge-safety rule and P2's glide FX, see {@link #glideLedges}) and the south
 *       access gap where the bridge lands.</li>
 *   <li><b>Underside</b>: three inverted taper strata (grass/dirt lip → deepslate/
 *       blackstone/tuff core → blackstone/basalt/obsidian/crying-obsidian tip) with
 *       hash-jittered thickness, hanging roots, chain drops ending in crying obsidian or
 *       soul lanterns, down-facing amethyst clusters, and two torn dark-oak root strands
 *       reaching for the crater but stopping short (the 3-block rip gap).</li>
 *   <li><b>Access</b> (day-1 walkability, zero required jumps): spawn plaza on the south
 *       crater rim → two hand-authored switchback slab flights (half-step ascents on
 *       blackstone stilts, hugging the crater arc so everything stays inside the
 *       protection radius) → a toppled purpur pillar that leans onto the island lip as
 *       the final gangplank, crashing a small notch into the rim lawn.</li>
 *   <li><b>Orbital anchors</b>: {@link #orbitalAnchors} exposes the frozen positions/
 *       sizes/blocks of the 12 debris block-displays on two counter-rotating rings —
 *       P6-W5 spawns and animates the display entities in build pass 2; W4 owns only the
 *       anchor data.</li>
 * </ul>
 *
 * <p><b>Geometry v3 dress pass (W4-ISLAND, {@link SanctumVersionData#REVISION_ISLAND_V3}):</b>
 * a purely ADDITIVE layer on top of the v2 island — no airspace sweeps, no clears — so the
 * v2→v3 migration ({@link #upgradeToV3}) can run over a lived-in world without eating
 * player builds. Contents (all deterministic, {@link FallbackBuilders#hash01} only):</p>
 * <ul>
 *   <li><b>Belly tendrils + amethyst pockets</b>: glow-berry cave-vine strands and inset
 *       amethyst pockets under the island belly ({@link #placeBellyTendrils}; columns the
 *       v2 hanging decor already claimed are skipped via the same hash predicate).</li>
 *   <li><b>Satellite islets</b>: four small hash-carved stone islets floating off the rim
 *       ({@link #ISLETS}, r 23–26 — clear of the bridge, crater rim and glide notches),
 *       each contributing one extra ring-2 companion-shard anchor to
 *       {@link #orbitalAnchors} so {@code SanctumOrbitals} animates a debris shard arcing
 *       around every islet (the connecting particle-arc anchors).</li>
 *   <li><b>Rune ring</b>: 16 glowstone/crying-obsidian tiles inlaid flush in the lawn on
 *       the r≈6.5 band ({@link #RUNE_RING_CELLS}) — inside the sundial shadow band
 *       (r 7–10, erase contract untouched) and outside the dais slab skirt (r ≤ 6).</li>
 *   <li><b>Crater terraces + updraft</b>: {@link SanctumCrater#dressTerraces} layers two
 *       slab terrace bands onto the bowl rim; the faint updraft + waterfall-of-light are
 *       client-side managed emitters ({@code client/sanctum/SanctumLightfall}) keyed on
 *       the {@code ALTAR_CENTER} anchor — zero server blocks/packets.</li>
 * </ul>
 */
public final class FloatingSanctumBuilder {
    /** Height of the island top surface above the flattened ground surface. */
    public static final int ISLAND_LIFT = 14;
    /** Island top ellipse semi-axis along X. */
    public static final int SURFACE_RADIUS_X = 16;
    /** Island top ellipse semi-axis along Z. */
    public static final int SURFACE_RADIUS_Z = 14;
    /** South offset of the v2 world spawn (crater-rim plaza) from the altar column. */
    public static final int SPAWN_SOUTH_OFFSET = 16;
    /** Radius of the legacy v1 sanctum volume cleared before the island build (plan §2.6). */
    public static final int CLEAR_RADIUS = 13;
    /** Height (above ground) of the legacy clear volume. */
    public static final int CLEAR_HEIGHT = 16;

    // --- auto-glide notches (block-side geometry; P4 owns the safety rule, P2 the FX) ---

    /** Rim angles (degrees, atan2(z,x) convention) of the four glide notches. */
    public static final int[] GLIDE_NOTCH_ANGLES = {45, 135, 225, 315};
    /** Angular half-width of a glide notch gap in the rim parapet. */
    public static final int GLIDE_NOTCH_HALF_ANGLE = 9;
    /**
     * South-southeast access gap in the parapet where the fallen-pillar gangplank lands
     * (kept narrow so the south tip of the rim stays railed for the Herald fight).
     */
    public static final int ACCESS_GAP_FROM_DEG = 72;
    public static final int ACCESS_GAP_TO_DEG = 85;

    // --- orbital anchor data (P6-W5 consumes; frozen per plan §2.6) ---

    /** Low debris ring: radius, count, Y offset below the island top (mid-height). */
    public static final double ORBITAL_LOW_RADIUS = 13.0D;
    public static final int ORBITAL_LOW_COUNT = 7;
    public static final int ORBITAL_LOW_BELOW_TOP = 4;
    /** High debris ring: radius, count, Y offset above the altar (above the glass halo). */
    public static final double ORBITAL_HIGH_RADIUS = 9.0D;
    public static final int ORBITAL_HIGH_COUNT = 5;
    public static final int ORBITAL_HIGH_ABOVE_ALTAR = 7;

    // --- v3 dress-pass data (W4-ISLAND; additive only, see class doc) ---

    /** Satellite islets: {angleDeg, ringRadius, yAboveGround, size} — bridge/notches avoided. */
    private static final int[][] ISLETS = {
            {20, 24, 7, 2}, {110, 26, 10, 3}, {200, 23, 6, 2}, {290, 25, 9, 3}};
    /** Companion-shard orbit radius around each islet (ring-2 orbital anchors). */
    public static final double ISLET_ORBIT_RADIUS = 2.0D;
    /**
     * Rune ring lawn cells (relative to the altar column), all with r² in [37, 47]:
     * strictly outside the dais slab skirt (r ≤ 6) and strictly inside the sundial
     * shadow band (r 7–10) so neither ever stamps over a rune tile.
     */
    private static final int[][] RUNE_RING_CELLS = {
            {6, 2}, {5, 4}, {3, 6}, {1, 6}, {-1, 6}, {-3, 6}, {-5, 4}, {-6, 2},
            {-6, -2}, {-5, -4}, {-3, -6}, {-1, -6}, {1, -6}, {3, -6}, {5, -4}, {6, -2}};

    /** Switchback flight 1 walk cells (relative to center), plaza level → landing A. */
    private static final int[][] FLIGHT_1 = {
            {0, 13}, {1, 13}, {2, 13}, {3, 12}, {4, 12}, {5, 12},
            {6, 11}, {7, 11}, {8, 10}, {9, 9}, {10, 9}, {10, 8}};
    /** Switchback flight 2 walk cells, landing A → landing B. */
    private static final int[][] FLIGHT_2 = {
            {14, 9}, {13, 10}, {12, 10}, {12, 11}, {11, 12}, {10, 13},
            {9, 13}, {8, 14}, {7, 15}, {6, 15}, {5, 15}, {4, 16}};
    /** Fallen-pillar gangplank cells (landing B → island lip) + parallel rail cells. */
    private static final int[][] PILLAR_MAIN = {{3, 14}, {2, 13}, {2, 12}, {1, 11}};
    private static final int[][] PILLAR_PAIR = {{4, 14}, {3, 13}, {3, 12}, {2, 11}};
    /** Torn root strands: {dx, dz, driftAxisX?} — island columns whose roots reach down. */
    private static final int[][] ROOT_STRANDS = {{-5, 3, 1}, {6, -4, 0}};

    private FloatingSanctumBuilder() {}

    // --- public anchor/geometry API (frozen interface for W5 / P4 / P2) ---

    /** Y of the island top surface block layer for a given (island) altar position. */
    public static int islandTopY(BlockPos altarPos) {
        return altarPos.getY() - AltarSanctumBuilder.ALTAR_ABOVE_GROUND;
    }

    /** Y of the flattened ground surface below the island (crater datum). */
    public static int groundY(BlockPos altarPos) {
        return islandTopY(altarPos) - ISLAND_LIFT;
    }

    /**
     * One rotating-debris block-display anchor. {@code ring} 0 = low ring (clockwise),
     * 1 = high ring (counter-clockwise; W5's counter-rotation convention).
     * {@code phaseRadians} is the display's angular offset on its ring at t=0;
     * {@code center} is the ring center, {@code radius} the orbit radius, {@code scale}
     * the display transform scale, {@code block} the displayed state.
     */
    public record OrbitalAnchor(int ring, int index, Vec3 center, double radius,
            double phaseRadians, float scale, BlockState block) {}

    /**
     * The debris anchors for {@code SanctumOrbitals} (P6-W5): 7 on the low ring
     * (r={@value #ORBITAL_LOW_RADIUS} at island mid-height), 5 on the high ring
     * (r={@value #ORBITAL_HIGH_RADIUS} above the glass halo) — both UNCHANGED since the
     * frozen v2 hand-off (composition per plan §2.6: 5 purpur, 3 obsidian shards, 2
     * crying obsidian, 2 amethyst clusters) — plus, since geometry v3 (W4-ISLAND), four
     * ring-2 companion shards each tightly orbiting one satellite islet
     * (r={@value #ISLET_ORBIT_RADIUS}, the islets' connecting particle-arc anchors).
     */
    public static List<OrbitalAnchor> orbitalAnchors(BlockPos altarPos) {
        Vec3 lowCenter = new Vec3(altarPos.getX() + 0.5D,
                islandTopY(altarPos) - ORBITAL_LOW_BELOW_TOP, altarPos.getZ() + 0.5D);
        Vec3 highCenter = new Vec3(altarPos.getX() + 0.5D,
                altarPos.getY() + ORBITAL_HIGH_ABOVE_ALTAR, altarPos.getZ() + 0.5D);
        BlockState purpur = Blocks.PURPUR_BLOCK.defaultBlockState();
        BlockState obsidian = Blocks.OBSIDIAN.defaultBlockState();
        BlockState crying = Blocks.CRYING_OBSIDIAN.defaultBlockState();
        BlockState amethyst = Blocks.AMETHYST_CLUSTER.defaultBlockState();
        BlockState[] lowBlocks = {purpur, obsidian, purpur, crying, obsidian, purpur, amethyst};
        float[] lowScales = {0.70F, 0.50F, 0.60F, 0.55F, 0.40F, 0.65F, 0.60F};
        BlockState[] highBlocks = {purpur, obsidian, crying, purpur, amethyst};
        float[] highScales = {0.60F, 0.45F, 0.50F, 0.55F, 0.60F};

        List<OrbitalAnchor> anchors =
                new ArrayList<>(ORBITAL_LOW_COUNT + ORBITAL_HIGH_COUNT + ISLETS.length);
        for (int i = 0; i < ORBITAL_LOW_COUNT; i++) {
            anchors.add(new OrbitalAnchor(0, i, lowCenter, ORBITAL_LOW_RADIUS,
                    i * (Math.PI * 2.0D / ORBITAL_LOW_COUNT), lowScales[i], lowBlocks[i]));
        }
        for (int i = 0; i < ORBITAL_HIGH_COUNT; i++) {
            anchors.add(new OrbitalAnchor(1, i, highCenter, ORBITAL_HIGH_RADIUS,
                    i * (Math.PI * 2.0D / ORBITAL_HIGH_COUNT), highScales[i], highBlocks[i]));
        }
        BlockState[] isletBlocks = {amethyst, obsidian, amethyst, crying};
        for (int i = 0; i < ISLETS.length; i++) {
            anchors.add(new OrbitalAnchor(2, i, isletShardCenter(altarPos, i),
                    ISLET_ORBIT_RADIUS, i * (Math.PI / 2.0D), 0.40F, isletBlocks[i]));
        }
        return anchors;
    }

    /** North-west base corner of islet {@code index} (pure geometry, crater datum math). */
    private static BlockPos isletBasePos(BlockPos altarPos, int index) {
        int[] islet = ISLETS[index];
        double angle = Math.toRadians(islet[0]);
        return new BlockPos(
                altarPos.getX() + (int) Math.round(Math.cos(angle) * islet[1]),
                groundY(altarPos) + islet[2],
                altarPos.getZ() + (int) Math.round(Math.sin(angle) * islet[1]));
    }

    /** Orbit center of islet {@code index}'s companion shard (just above the islet cap). */
    private static Vec3 isletShardCenter(BlockPos altarPos, int index) {
        BlockPos base = isletBasePos(altarPos, index);
        return new Vec3(base.getX() + 0.5D, base.getY() + ISLETS[index][3] + 1.5D,
                base.getZ() + 0.5D);
    }

    /**
     * The four glide-notch launch ledges (outer slab block of each diagonal rim notch, at
     * island-top Y; the walk surface is one above). P4's edge auto-glide safety rule and
     * P2's glide FX key off these — pure geometry, no level access.
     */
    public static List<BlockPos> glideLedges(BlockPos altarPos) {
        List<BlockPos> ledges = new ArrayList<>(GLIDE_NOTCH_ANGLES.length);
        int topY = islandTopY(altarPos);
        for (int angleDeg : GLIDE_NOTCH_ANGLES) {
            double angle = Math.toRadians(angleDeg);
            double cos = Math.cos(angle);
            double sin = Math.sin(angle);
            double t = rimDistance(cos, sin);
            ledges.add(new BlockPos(
                    altarPos.getX() + (int) Math.round(cos * (t + 1.4D)), topY,
                    altarPos.getZ() + (int) Math.round(sin * (t + 1.4D))));
        }
        return ledges;
    }

    /** Distance from center to the top ellipse boundary along direction (cos, sin). */
    private static double rimDistance(double cos, double sin) {
        return 1.0D / Math.sqrt(cos * cos / (double) (SURFACE_RADIUS_X * SURFACE_RADIUS_X)
                + sin * sin / (double) (SURFACE_RADIUS_Z * SURFACE_RADIUS_Z));
    }

    // --- build orchestration (called by AltarSanctumBuilder.ensureSanctum, version-gated) ---

    /**
     * Builds the floating sanctum, either upgrading a v1 grounded sanctum in place
     * ({@code groundedAltar} = the persisted v1 altar) or stamping fresh onto a stage-1+
     * world. Returns the NEW island altar position; the caller persists it via the
     * existing {@code EclipseWorldState.setSanctumBuilt} path and stamps
     * {@link SanctumVersionData#VERSION_FLOATING}.
     */
    static BlockPos buildOrUpgrade(ServerLevel level, @Nullable BlockPos groundedAltar) {
        int cx;
        int cz;
        int ground;
        if (groundedAltar != null) {
            cx = groundedAltar.getX();
            cz = groundedAltar.getZ();
            ground = groundedAltar.getY() - AltarSanctumBuilder.ALTAR_ABOVE_GROUND;
        } else {
            BlockPos adminAltar = AltarSanctumBuilder.findExistingAltar(level);
            cx = adminAltar != null ? adminAltar.getX() : 0;
            cz = adminAltar != null ? adminAltar.getZ() : 0;
            ground = DiscTerrainFunction.surfaceY(DiscProfile.OVERWORLD, cx, cz);
        }
        int topY = ground + ISLAND_LIFT;
        BlockPos altarPos = new BlockPos(cx, topY + AltarSanctumBuilder.ALTAR_ABOVE_GROUND, cz);

        int cleared = clearLegacySanctum(level, cx, cz, ground);
        buildIslandMass(level, cx, cz, ground);
        SanctumCrater.build(level, cx, cz, ground);
        buildRim(level, cx, cz, topY);
        AltarSanctumBuilder.buildDais(level, cx, cz, topY);
        AltarSanctumBuilder.buildPillars(level, cx, cz, topY, altarPos);
        AltarSanctumBuilder.buildFloatingRings(level, cx, cz, topY);
        AltarSanctumBuilder.buildDecor(level, cx, cz, topY);
        AltarSanctumBuilder.buildApproachPaths(level, cx, cz, topY);
        buildAccess(level, cx, cz, ground);
        dressV3(level, cx, cz, ground);
        if (!level.getBlockState(altarPos).is(EclipseBlocks.ALTAR.get())) {
            set(level, altarPos, EclipseBlocks.ALTAR.get().defaultBlockState());
        }
        if (groundedAltar != null) {
            EclipseMod.LOGGER.info(
                    "Sanctum altar relocated {} -> {} (block entity state is transient-only; durable progress lives in EclipseWorldState)",
                    groundedAltar.toShortString(), altarPos.toShortString());
        }
        SundialPlaza.buildDial(level, altarPos);
        SundialPlaza.placeShadow(level, altarPos,
                EclipseWorldState.get(level.getServer()).getDay());
        rescueStranded(level, cx, cz, ground);
        EclipseMod.LOGGER.info(
                "Sanctum v2 floating island built (geometry v3 dress inline): altar {}, island top y{} (ellipse r{}x{}), ground y{}, crater floor y{}, {} legacy blocks cleared, bridge+plaza south, glide notches at {} deg, {} satellite islets",
                altarPos.toShortString(), topY, SURFACE_RADIUS_X, SURFACE_RADIUS_Z, ground,
                ground - SanctumCrater.MAX_DEPTH, cleared,
                java.util.Arrays.toString(GLIDE_NOTCH_ANGLES), ISLETS.length);
        return altarPos;
    }

    /**
     * v2 → v3 migration entry ({@code AltarSanctumBuilder.ensureSanctum}, revision-gated):
     * runs ONLY the additive v3 dress pass over an already-floating island. Deliberately
     * no clears, no airspace sweeps, no re-stamp of the v2 mass — a lived-in island keeps
     * every player-placed block; the pass itself is idempotent (fixed deterministic
     * positions, plain setBlock).
     */
    static void upgradeToV3(ServerLevel level, BlockPos altarPos) {
        int cx = altarPos.getX();
        int cz = altarPos.getZ();
        int ground = groundY(altarPos);
        dressV3(level, cx, cz, ground);
        EclipseMod.LOGGER.info(
                "Sanctum island upgraded v2 -> geometry v3 (belly tendrils, {} satellite islets, rune ring, crater terraces) around altar {}",
                ISLETS.length, altarPos.toShortString());
    }

    // --- v3 dress pass (additive only — see class doc) ---

    /** Runs every v3 dressing layer; shared by the fresh build and the v2→v3 migration. */
    private static void dressV3(ServerLevel level, int cx, int cz, int ground) {
        placeBellyTendrils(level, cx, cz, ground);
        buildSatelliteIslets(level, cx, cz, ground);
        buildRuneRing(level, cx, cz, ground + ISLAND_LIFT);
        SanctumCrater.dressTerraces(level, cx, cz, ground);
    }

    /**
     * Glow-berry cave-vine tendrils and inset amethyst pockets under the island belly.
     * Only columns the v2 hanging decor left untouched are used (same salt-23 predicate
     * as {@link #placeHangingDecor}), the torn-root strand columns are excluded, and the
     * central d &lt; 0.30 core stays clear for the waterfall-of-light column.
     */
    private static void placeBellyTendrils(ServerLevel level, int cx, int cz, int ground) {
        int topY = ground + ISLAND_LIFT;
        for (int dx = -SURFACE_RADIUS_X; dx <= SURFACE_RADIUS_X; dx++) {
            for (int dz = -SURFACE_RADIUS_Z; dz <= SURFACE_RADIUS_Z; dz++) {
                double d = Math.sqrt(ellipse(dx, dz));
                if (d < 0.30D || d > 0.95D || isRootStrandColumn(dx, dz)) {
                    continue;
                }
                int x = cx + dx;
                int z = cz + dz;
                if (FallbackBuilders.hash01(x, 23, z) < 0.115D) {
                    continue; // column already carries v2 hanging decor
                }
                level.getChunk(x >> 4, z >> 4);
                int bottomY = topY - thicknessAt(x, z, d) + 1;
                if (FallbackBuilders.hash01(x, 141, z) < 0.035D) {
                    // Amethyst pocket: inset block + down-facing cluster beneath it.
                    set(level, new BlockPos(x, bottomY, z), Blocks.AMETHYST_BLOCK.defaultBlockState());
                    set(level, new BlockPos(x, bottomY - 1, z),
                            Blocks.AMETHYST_CLUSTER.defaultBlockState()
                                    .setValue(AmethystClusterBlock.FACING, Direction.DOWN));
                } else if (FallbackBuilders.hash01(x, 143, z) < 0.05D) {
                    int length = 2 + (int) (FallbackBuilders.hash01(x, 145, z) * 4.0D);
                    for (int i = 1; i < length; i++) {
                        set(level, new BlockPos(x, bottomY - i, z),
                                Blocks.CAVE_VINES_PLANT.defaultBlockState().setValue(
                                        BlockStateProperties.BERRIES,
                                        FallbackBuilders.hash01(x, bottomY - i, z) < 0.35D));
                    }
                    set(level, new BlockPos(x, bottomY - length, z),
                            Blocks.CAVE_VINES.defaultBlockState().setValue(
                                    BlockStateProperties.BERRIES,
                                    FallbackBuilders.hash01(x, 147, z) < 0.5D));
                }
            }
        }
    }

    /** Whether (dx, dz) is one of the torn-root strand start columns (v2 decor, avoid). */
    private static boolean isRootStrandColumn(int dx, int dz) {
        for (int[] strand : ROOT_STRANDS) {
            if (strand[0] == dx && strand[1] == dz) {
                return true;
            }
        }
        return false;
    }

    /**
     * Four small hash-carved stone islets floating off the rim ({@link #ISLETS}) — torn
     * shrapnel of the rip, each with a lawn cap, one glinting amethyst cluster and a
     * hanging root. Their companion-shard orbital anchors ride {@link #orbitalAnchors}.
     */
    private static void buildSatelliteIslets(ServerLevel level, int cx, int cz, int ground) {
        BlockPos altarSurrogate = new BlockPos(cx,
                ground + ISLAND_LIFT + AltarSanctumBuilder.ALTAR_ABOVE_GROUND, cz);
        for (int i = 0; i < ISLETS.length; i++) {
            int size = ISLETS[i][3];
            BlockPos base = isletBasePos(altarSurrogate, i);
            int half = size / 2;
            level.getChunk(base.getX() >> 4, base.getZ() >> 4);
            for (int ox = -half; ox <= half; ox++) {
                for (int oz = -half; oz <= half; oz++) {
                    for (int oy = 0; oy < size; oy++) {
                        int x = base.getX() + ox;
                        int y = base.getY() + oy;
                        int z = base.getZ() + oz;
                        double keep = 0.92D - 0.20D * (Math.abs(ox) + Math.abs(oz)) - 0.12D * oy;
                        if (FallbackBuilders.hash01(x, y, z) >= keep) {
                            continue;
                        }
                        level.getChunk(x >> 4, z >> 4);
                        set(level, new BlockPos(x, y, z), oy == size - 1
                                ? AltarSanctumBuilder.groundMix(x, z) : isletMix(x, y, z));
                    }
                }
            }
            // Cap glint + hanging root on the islet's center column.
            set(level, base.above(size), Blocks.AMETHYST_CLUSTER.defaultBlockState()
                    .setValue(AmethystClusterBlock.FACING, Direction.UP));
            set(level, base.below(), Blocks.HANGING_ROOTS.defaultBlockState());
        }
    }

    /** Islet stone mix — the island-underside palette, minus the bright tip blocks. */
    private static BlockState isletMix(int x, int y, int z) {
        double h = FallbackBuilders.hash01(x, y + 151, z);
        if (h < 0.35D) return Blocks.DEEPSLATE.defaultBlockState();
        if (h < 0.62D) return Blocks.BLACKSTONE.defaultBlockState();
        if (h < 0.82D) return Blocks.TUFF.defaultBlockState();
        return Blocks.COBBLED_DEEPSLATE.defaultBlockState();
    }

    /**
     * Sixteen glowing rune tiles inlaid flush in the lawn around the altar
     * ({@link #RUNE_RING_CELLS}), alternating glowstone and crying obsidian — the gold →
     * violet identity of the milestone FX, sculk-sensor-free and outside both the dais
     * skirt and the sundial shadow band.
     */
    private static void buildRuneRing(ServerLevel level, int cx, int cz, int topY) {
        for (int i = 0; i < RUNE_RING_CELLS.length; i++) {
            int x = cx + RUNE_RING_CELLS[i][0];
            int z = cz + RUNE_RING_CELLS[i][1];
            level.getChunk(x >> 4, z >> 4);
            set(level, new BlockPos(x, topY, z), (i & 1) == 0
                    ? Blocks.GLOWSTONE.defaultBlockState()
                    : Blocks.CRYING_OBSIDIAN.defaultBlockState());
        }
    }

    /** Erases the v1 grounded sanctum volume (r=13, ground+1..+16 — plan §2.6). */
    private static int clearLegacySanctum(ServerLevel level, int cx, int cz, int ground) {
        BlockState air = Blocks.AIR.defaultBlockState();
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        int cleared = 0;
        for (int dx = -CLEAR_RADIUS; dx <= CLEAR_RADIUS; dx++) {
            for (int dz = -CLEAR_RADIUS; dz <= CLEAR_RADIUS; dz++) {
                if (dx * dx + dz * dz > CLEAR_RADIUS * CLEAR_RADIUS) {
                    continue;
                }
                int x = cx + dx;
                int z = cz + dz;
                level.getChunk(x >> 4, z >> 4);
                for (int y = ground + 1; y <= ground + CLEAR_HEIGHT; y++) {
                    cursor.set(x, y, z);
                    if (!level.getBlockState(cursor).isAir()) {
                        level.setBlock(cursor, air, 2);
                        cleared++;
                    }
                }
            }
        }
        return cleared;
    }

    // --- island mass ---

    /** Plateau + tapered underside + hanging decor + torn roots + broken lip fragments. */
    private static void buildIslandMass(ServerLevel level, int cx, int cz, int ground) {
        int topY = ground + ISLAND_LIFT;
        BlockState air = Blocks.AIR.defaultBlockState();
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        for (int dx = -(SURFACE_RADIUS_X + 1); dx <= SURFACE_RADIUS_X + 1; dx++) {
            for (int dz = -(SURFACE_RADIUS_Z + 1); dz <= SURFACE_RADIUS_Z + 1; dz++) {
                double d = Math.sqrt(ellipse(dx, dz));
                int x = cx + dx;
                int z = cz + dz;
                if (d > 1.0D) {
                    // Torn-lip fragments floating just off the edge.
                    if (d <= 1.06D && FallbackBuilders.hash01(x, 131, z) < 0.35D) {
                        level.getChunk(x >> 4, z >> 4);
                        set(level, new BlockPos(x, topY, z), AltarSanctumBuilder.groundMix(x, z));
                        if (FallbackBuilders.hash01(x, 132, z) < 0.5D) {
                            set(level, new BlockPos(x, topY - 1, z), Blocks.HANGING_ROOTS.defaultBlockState());
                        }
                    }
                    continue;
                }
                level.getChunk(x >> 4, z >> 4);
                // Airspace sweep: stray vegetation/terrain must never pierce the island.
                for (int y = ground + 1; y <= topY + 13; y++) {
                    cursor.set(x, y, z);
                    if (!level.getBlockState(cursor).isAir()) {
                        level.setBlock(cursor, air, 2);
                    }
                }
                int thickness = thicknessAt(x, z, d);
                int bottomY = topY - thickness + 1;
                for (int y = bottomY; y <= topY; y++) {
                    set(level, new BlockPos(x, y, z), massMix(x, y, z, topY - y, thickness));
                }
                placeHangingDecor(level, x, z, bottomY, d);
            }
        }
        placeTornRoots(level, cx, cz, ground, topY);
    }

    /** (dx/rx)^2 + (dz/rz)^2 — inside the island top footprint when <= 1. */
    private static double ellipse(int dx, int dz) {
        return dx * dx / (double) (SURFACE_RADIUS_X * SURFACE_RADIUS_X)
                + dz * dz / (double) (SURFACE_RADIUS_Z * SURFACE_RADIUS_Z);
    }

    /**
     * Inverted-cone thickness: 3 at the lip growing to ~9 at the center, plus a hash
     * jitter block on inner columns. Edge band (d >= 0.85) stays exactly 3 thick so the
     * underside bottom never dips below topY-2 over the low bridge flight.
     */
    private static int thicknessAt(int x, int z, double d) {
        int thickness = 3 + (int) Math.round((1.0D - d) * (1.0D - d) * 6.0D);
        if (d < 0.85D && FallbackBuilders.hash01(x, 5, z) < 0.40D) {
            thickness++;
        }
        return thickness;
    }

    /** Strata by depth-from-top: lawn, dirt band, deepslate core, bedrock-black tip. */
    private static BlockState massMix(int x, int y, int z, int depthFromTop, int thickness) {
        if (depthFromTop == 0) {
            return AltarSanctumBuilder.groundMix(x, z); // sundial erase contract
        }
        if (depthFromTop <= 2 && depthFromTop < thickness - 2) {
            return FallbackBuilders.hash01(x, y, z) < 0.25D
                    ? Blocks.COARSE_DIRT.defaultBlockState()
                    : Blocks.DIRT.defaultBlockState();
        }
        double h = FallbackBuilders.hash01(x, y, z);
        if (depthFromTop >= thickness - 2) {
            // Bedrock-black tip with dripping crying obsidian.
            if (h < 0.30D) return Blocks.BLACKSTONE.defaultBlockState();
            if (h < 0.48D) return Blocks.BASALT.defaultBlockState();
            if (h < 0.60D) return Blocks.OBSIDIAN.defaultBlockState();
            if (h < 0.68D) return Blocks.CRYING_OBSIDIAN.defaultBlockState();
            if (h < 0.85D) return Blocks.DEEPSLATE.defaultBlockState();
            return Blocks.BLACKSTONE.defaultBlockState();
        }
        if (h < 0.35D) return Blocks.DEEPSLATE.defaultBlockState();
        if (h < 0.60D) return Blocks.BLACKSTONE.defaultBlockState();
        if (h < 0.80D) return Blocks.TUFF.defaultBlockState();
        return Blocks.COBBLED_DEEPSLATE.defaultBlockState();
    }

    /** Hanging roots / chain drops (crying obsidian or soul lantern) / amethyst pips. */
    private static void placeHangingDecor(ServerLevel level, int x, int z, int bottomY, double d) {
        double h = FallbackBuilders.hash01(x, 23, z);
        if (h < 0.05D && d > 0.50D) {
            set(level, new BlockPos(x, bottomY - 1, z), Blocks.HANGING_ROOTS.defaultBlockState());
        } else if (h < 0.085D && d < 0.80D) {
            int length = 2 + (int) (FallbackBuilders.hash01(x, 29, z) * 3.0D);
            for (int i = 1; i <= length; i++) {
                set(level, new BlockPos(x, bottomY - i, z), Blocks.CHAIN.defaultBlockState());
            }
            BlockState end = FallbackBuilders.hash01(x, 31, z) < 0.55D
                    ? Blocks.CRYING_OBSIDIAN.defaultBlockState()
                    : Blocks.SOUL_LANTERN.defaultBlockState().setValue(LanternBlock.HANGING, true);
            set(level, new BlockPos(x, bottomY - length - 1, z), end);
        } else if (h < 0.115D) {
            set(level, new BlockPos(x, bottomY - 1, z), Blocks.AMETHYST_CLUSTER.defaultBlockState()
                    .setValue(AmethystClusterBlock.FACING, Direction.DOWN));
        }
    }

    /**
     * Two torn dark-oak root strands reaching from the underside toward the crater and
     * stopping ~3-4 blocks short of its floor — the rip made visible.
     */
    private static void placeTornRoots(ServerLevel level, int cx, int cz, int ground, int topY) {
        for (int[] strand : ROOT_STRANDS) {
            int x = cx + strand[0];
            int z = cz + strand[1];
            boolean driftX = strand[2] == 1;
            int bottomY = topY - thicknessAt(x, z, Math.sqrt(ellipse(strand[0], strand[1]))) + 1;
            for (int y = bottomY - 1; y >= ground + 2; y--) {
                if (y == ground + 7) {
                    if (driftX) {
                        x--;
                    } else {
                        z--;
                    }
                    // Side nub where the strand kinks.
                    set(level, new BlockPos(driftX ? x + 1 : x, y, driftX ? z : z + 1),
                            Blocks.DARK_OAK_FENCE.defaultBlockState());
                }
                set(level, new BlockPos(x, y, z), Blocks.DARK_OAK_LOG.defaultBlockState());
            }
            set(level, new BlockPos(x, ground + 1, z), Blocks.DARK_OAK_FENCE.defaultBlockState());
        }
    }

    // --- rim parapet + glide notches ---

    /**
     * Near-continuous rim parapet (wall blocks with occasional gilded pedestals) on the
     * outermost top ring, gapped at the four diagonal glide notches (slab launch ledges +
     * amethyst markers) and the south access gap.
     */
    private static void buildRim(ServerLevel level, int cx, int cz, int topY) {
        for (int dx = -SURFACE_RADIUS_X; dx <= SURFACE_RADIUS_X; dx++) {
            for (int dz = -SURFACE_RADIUS_Z; dz <= SURFACE_RADIUS_Z; dz++) {
                if (ellipse(dx, dz) > 1.0D || !isRimCell(dx, dz)) {
                    continue;
                }
                double angle = angleDeg(dx, dz);
                if (inAccessGap(angle) || inGlideNotch(angle)) {
                    continue;
                }
                int x = cx + dx;
                int z = cz + dz;
                BlockState post = FallbackBuilders.hash01(x, 121, z) < 0.14D
                        ? Blocks.GILDED_BLACKSTONE.defaultBlockState()
                        : Blocks.POLISHED_BLACKSTONE_BRICK_WALL.defaultBlockState();
                set(level, new BlockPos(x, topY + 1, z), post);
            }
        }
        for (int angleDeg : GLIDE_NOTCH_ANGLES) {
            buildGlideNotch(level, cx, cz, topY, angleDeg);
        }
    }

    /** A rim cell is an inside column with at least one orthogonal outside neighbor. */
    private static boolean isRimCell(int dx, int dz) {
        return ellipse(dx + 1, dz) > 1.0D || ellipse(dx - 1, dz) > 1.0D
                || ellipse(dx, dz + 1) > 1.0D || ellipse(dx, dz - 1) > 1.0D;
    }

    private static double angleDeg(int dx, int dz) {
        double angle = Math.toDegrees(Math.atan2(dz, dx));
        return angle < 0.0D ? angle + 360.0D : angle;
    }

    private static boolean inAccessGap(double angle) {
        return angle >= ACCESS_GAP_FROM_DEG && angle <= ACCESS_GAP_TO_DEG;
    }

    private static boolean inGlideNotch(double angle) {
        for (int notch : GLIDE_NOTCH_ANGLES) {
            double dist = Math.abs(angle - notch);
            if (Math.min(dist, 360.0D - dist) < GLIDE_NOTCH_HALF_ANGLE) {
                return true;
            }
        }
        return false;
    }

    /** Protruding two-slab launch ledge + flanking amethyst markers for one notch. */
    private static void buildGlideNotch(ServerLevel level, int cx, int cz, int topY, int angleDeg) {
        double angle = Math.toRadians(angleDeg);
        double cos = Math.cos(angle);
        double sin = Math.sin(angle);
        double t = rimDistance(cos, sin);
        BlockState ledge = Blocks.POLISHED_BLACKSTONE_SLAB.defaultBlockState()
                .setValue(BlockStateProperties.SLAB_TYPE, SlabType.TOP);
        for (double reach : new double[] {0.6D, 1.4D}) {
            int x = cx + (int) Math.round(cos * (t + reach));
            int z = cz + (int) Math.round(sin * (t + reach));
            set(level, new BlockPos(x, topY, z), ledge);
        }
        // Amethyst markers flanking the notch (only where the rim lawn supports them).
        double perpX = -sin;
        double perpZ = cos;
        for (int side = -1; side <= 1; side += 2) {
            int dx = (int) Math.round(cos * (t - 0.3D) + perpX * 2.0D * side);
            int dz = (int) Math.round(sin * (t - 0.3D) + perpZ * 2.0D * side);
            if (ellipse(dx, dz) <= 1.0D) {
                set(level, new BlockPos(cx + dx, topY + 1, cz + dz),
                        Blocks.AMETHYST_CLUSTER.defaultBlockState()
                                .setValue(AmethystClusterBlock.FACING, Direction.UP));
            }
        }
    }

    // --- access: spawn plaza, switchback flights, fallen-pillar gangplank ---

    /**
     * Day-1 walkability chain, all ascents 0.5-block slab steps (zero required jumps):
     * plaza (ground) → flight 1 (+6, crater-arc, low, under the island lip) → landing A →
     * flight 2 (+6, outer arc, on stilts) → landing B → toppled purpur pillar (+2) onto
     * the island lawn through the south rim gap.
     */
    private static void buildAccess(ServerLevel level, int cx, int cz, int ground) {
        stampPad(level, cx - 2, cz + 14, cx + 2, cz + 17, ground); // spawn plaza
        stampPad(level, cx - 1, cz + 12, cx + 1, cz + 15, ground); // trailhead
        buildFlight(level, cx, cz, FLIGHT_1, ground + 1);
        buildLanding(level, cx + 11, cz + 6, cx + 13, cz + 8, ground + 6);
        placeLanternPost(level, cx + 13, cz + 6, ground + 7);
        buildFlight(level, cx, cz, FLIGHT_2, ground + 7);
        buildLanding(level, cx + 2, cz + 15, cx + 4, cz + 17, ground + 12);
        placeLanternPost(level, cx + 2, cz + 17, ground + 13);
        buildFallenPillar(level, cx, cz, ground);
    }

    /** Ground-level pad: deterministic surface mix, cleared headroom, solid footing. */
    private static void stampPad(ServerLevel level, int x1, int z1, int x2, int z2, int ground) {
        BlockState air = Blocks.AIR.defaultBlockState();
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        for (int x = x1; x <= x2; x++) {
            for (int z = z1; z <= z2; z++) {
                level.getChunk(x >> 4, z >> 4);
                set(level, new BlockPos(x, ground, z), AltarSanctumBuilder.groundMix(x, z));
                cursor.set(x, ground - 1, z);
                if (!level.getBlockState(cursor).isSolidRender(level, cursor)) {
                    level.setBlock(cursor, Blocks.DIRT.defaultBlockState(), 2);
                }
                for (int y = ground + 1; y <= ground + 4; y++) {
                    cursor.set(x, y, z);
                    if (!level.getBlockState(cursor).isAir()) {
                        level.setBlock(cursor, air, 2);
                    }
                }
            }
        }
    }

    /**
     * One switchback flight over its hand-authored cell table: odd steps are bottom
     * slabs, even steps full bricks (each +0.5), with a radially-shifted ruin/rail line,
     * wall stilts to the ground every third step, and 3-block headroom above every cell.
     */
    private static void buildFlight(ServerLevel level, int cx, int cz, int[][] cells, int startSurfaceY) {
        BlockState brick = Blocks.POLISHED_BLACKSTONE_BRICKS.defaultBlockState();
        BlockState cracked = Blocks.CRACKED_POLISHED_BLACKSTONE_BRICKS.defaultBlockState();
        BlockState slab = Blocks.POLISHED_BLACKSTONE_BRICK_SLAB.defaultBlockState();
        for (int j = 1; j <= cells.length; j++) {
            int dx = cells[j - 1][0];
            int dz = cells[j - 1][1];
            int x = cx + dx;
            int z = cz + dz;
            level.getChunk(x >> 4, z >> 4);
            boolean slabStep = (j & 1) == 1;
            int blockY = slabStep ? startSurfaceY + (j - 1) / 2 : startSurfaceY - 1 + j / 2;
            BlockState step = slabStep ? slab
                    : (FallbackBuilders.hash01(x, blockY, z) < 0.15D ? cracked : brick);
            set(level, new BlockPos(x, blockY, z), step);
            clearAbove(level, x, blockY, z, 3);
            if (j % 3 == 2) {
                buildStilt(level, x, blockY - 1, z);
            }
            // Radially-shifted twin line: reads as the ruined second half of the stair.
            double len = Math.sqrt(dx * dx + dz * dz);
            int ox = cx + (int) Math.round(dx + dx / len);
            int oz = cz + (int) Math.round(dz + dz / len);
            int odx = ox - cx;
            int odz = oz - cz;
            boolean insidePads = (Math.abs(odx) <= 2 && odz >= 12 && odz <= 17);
            if (!insidePads && odx * odx + odz * odz <= 320 && ellipse(odx, odz) > 1.0D) {
                set(level, new BlockPos(ox, blockY, oz), step);
                clearAbove(level, ox, blockY, oz, 3);
                if (!slabStep) {
                    set(level, new BlockPos(ox, blockY + 1, oz),
                            Blocks.POLISHED_BLACKSTONE_BRICK_WALL.defaultBlockState());
                }
            }
        }
    }

    /** Full-brick landing platform with corner rails. */
    private static void buildLanding(ServerLevel level, int x1, int z1, int x2, int z2, int blockY) {
        BlockState brick = Blocks.POLISHED_BLACKSTONE_BRICKS.defaultBlockState();
        BlockState cracked = Blocks.CRACKED_POLISHED_BLACKSTONE_BRICKS.defaultBlockState();
        for (int x = x1; x <= x2; x++) {
            for (int z = z1; z <= z2; z++) {
                level.getChunk(x >> 4, z >> 4);
                set(level, new BlockPos(x, blockY, z),
                        FallbackBuilders.hash01(x, blockY, z) < 0.15D ? cracked : brick);
                clearAbove(level, x, blockY, z, 3);
            }
        }
        for (int[] corner : new int[][] {{x1, z1}, {x1, z2}, {x2, z1}, {x2, z2}}) {
            buildStilt(level, corner[0], blockY - 1, corner[1]);
        }
    }

    /** Wall-block stilt from {@code fromY} down to the first solid block (bounded). */
    private static void buildStilt(ServerLevel level, int x, int fromY, int z) {
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        for (int y = fromY; y > fromY - 14; y--) {
            cursor.set(x, y, z);
            if (level.getBlockState(cursor).isSolidRender(level, cursor)) {
                return;
            }
            level.setBlock(cursor, Blocks.POLISHED_BLACKSTONE_BRICK_WALL.defaultBlockState(),
                    Block.UPDATE_ALL);
        }
    }

    /** Gilded pedestal + standing soul lantern (landing waymark). */
    private static void placeLanternPost(ServerLevel level, int x, int z, int blockY) {
        set(level, new BlockPos(x, blockY, z), Blocks.GILDED_BLACKSTONE.defaultBlockState());
        set(level, new BlockPos(x, blockY + 1, z), Blocks.SOUL_LANTERN.defaultBlockState()
                .setValue(LanternBlock.HANGING, false));
    }

    /**
     * The toppled purpur pillar leaning from landing B onto the island lip — the final
     * +2 of the climb. It crashes a 2-wide notch into the rim lawn (top blocks replaced
     * by purpur slabs/shafts) so the ascent stays 0.5-block steps the whole way.
     */
    private static void buildFallenPillar(ServerLevel level, int cx, int cz, int ground) {
        BlockState shaft = Blocks.PURPUR_PILLAR.defaultBlockState()
                .setValue(RotatedPillarBlock.AXIS, Direction.Axis.Z);
        BlockState slab = Blocks.PURPUR_SLAB.defaultBlockState();
        int startSurfaceY = ground + 13;
        for (int[][] line : new int[][][] {PILLAR_MAIN, PILLAR_PAIR}) {
            for (int j = 1; j <= line.length; j++) {
                int x = cx + line[j - 1][0];
                int z = cz + line[j - 1][1];
                level.getChunk(x >> 4, z >> 4);
                boolean slabStep = (j & 1) == 1;
                int blockY = slabStep ? startSurfaceY + (j - 1) / 2 : startSurfaceY - 1 + j / 2;
                set(level, new BlockPos(x, blockY, z), slabStep ? slab : shaft);
                clearAbove(level, x, blockY, z, 3);
            }
        }
        // Torn sockets where the pillar smashed into the lawn.
        set(level, new BlockPos(cx + 1, ground + ISLAND_LIFT, cz + 10), Blocks.PURPUR_BLOCK.defaultBlockState());
        set(level, new BlockPos(cx, ground + ISLAND_LIFT, cz + 11), Blocks.OBSIDIAN.defaultBlockState());
    }

    private static void clearAbove(ServerLevel level, int x, int blockY, int z, int height) {
        BlockState air = Blocks.AIR.defaultBlockState();
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        for (int y = blockY + 1; y <= blockY + height; y++) {
            cursor.set(x, y, z);
            if (!level.getBlockState(cursor).isAir()) {
                level.setBlock(cursor, air, 2);
            }
        }
    }

    /**
     * Live stage-0→1 flip only: anyone standing where the grounded sanctum just got torn
     * out (inside the clear/crater zone, below the island) is snapped to the new spawn
     * plaza instead of being left inside freshly-carved terrain.
     */
    private static void rescueStranded(ServerLevel level, int cx, int cz, int ground) {
        for (ServerPlayer player : level.players()) {
            double dx = player.getX() - (cx + 0.5D);
            double dz = player.getZ() - (cz + 0.5D);
            if (dx * dx + dz * dz > 13.5D * 13.5D) {
                continue;
            }
            double y = player.getY();
            if (y > ground - 6 && y < ground + ISLAND_LIFT + 1) {
                player.teleportTo(level, cx + 0.5D, ground + 1, cz + SPAWN_SOUTH_OFFSET + 0.5D,
                        180.0F, 0.0F);
                EclipseMod.LOGGER.info("Sanctum island flip: rescued {} to the crater-rim spawn plaza",
                        player.getScoreboardName());
            }
        }
    }

    private static void set(ServerLevel level, BlockPos pos, BlockState state) {
        level.setBlock(pos, state, Block.UPDATE_ALL);
    }
}
