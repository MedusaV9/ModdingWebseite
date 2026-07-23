package dev.projecteclipse.eclipse.worldgen;

import javax.annotation.Nullable;

import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.synth.SimplexNoise;

/**
 * Terrain-side geometry of the overworld nether breach (worker W1.2, plan v3 D10): a
 * {@value #CRATER_RADIUS}·2-block-wide funnel crater that flares from the desert-ring
 * surface down into a vertical chimney piercing the FULL lens — underside, stalactite
 * fringe and bedrock seal included — so anything falling in drops out of the disc (the
 * transfer to the nether is W1.7's {@code BreachTransferService}). Walls are layered
 * netherrack → blackstone with magma sprinkles and a magma-lined spout mouth; the lip
 * ring overhangs slightly and dangles weeping-vine strands; a
 * {@code HALO_RADIUS − CRATER_RADIUS}-block "crimson creep" halo repaints the
 * surrounding surface with nylium/netherrack patches and eternal fire.
 *
 * <p>Anchored on the {@code eclipse:nether_breach} landmark of {@code disc_map.json}
 * (default: x 92, z 92 — r ≈ 130 on the desert wedge mid-angle). All shapes derive from
 * {@link FrozenParams#mapSeed()} (hash salt 14, noise salt 26); results are pure per
 * map snapshot. The terrain function only consults this class when
 * {@code FrozenParams.breachOpen()} is set, which flips once per save — new chunk
 * generation and W1.7's live materialization sweep therefore always agree.</p>
 *
 * <p>Site parameters are cached per {@link DiscMapData} instance (volatile swap on
 * {@code disc_map.json} reload).</p>
 */
public final class BreachGeometry {
    /** Landmark id that anchors the breach; falls back to (92, 92) when unauthored. */
    public static final String LANDMARK_ID = "eclipse:nether_breach";
    /** Funnel mouth radius at the surface lip (crater is twice this across). */
    public static final int CRATER_RADIUS = 16;
    /** Outer radius of the crimson-creep halo (12-block band beyond the crater). */
    public static final int HALO_RADIUS = CRATER_RADIUS + 12;
    /**
     * How far below a column's lowest ground block the chimney wall collar ("spout")
     * keeps going — the terrain function extends spout columns' {@code bottomY} by this.
     */
    public static final int SPOUT_DEPTH = 14;

    /** Chimney radius below the funnel flare. */
    private static final double CHIMNEY_RADIUS = 5.5D;
    /** Vertical extent of the funnel flare from lip down to the chimney top. */
    private static final int FUNNEL_DEPTH = 44;
    /** Wall shell thickness around the void. */
    private static final double WALL_THICKNESS = 3.0D;
    /** Amplitude of the angular/depth wobble applied to the funnel radius. */
    private static final double WOBBLE_AMP = 1.6D;
    /** Inward jut of the overhanging lip ring (weeping vines anchor under it). */
    private static final double LIP_NOTCH = 1.6D;

    private static final int H_BREACH = 14;

    private record SeededNoise(long seed, SimplexNoise noise) {}

    private static volatile SeededNoise wobble;

    private static final int DEFAULT_X = 92;
    private static final int DEFAULT_Z = 92;

    private static final BlockState AIR = Blocks.AIR.defaultBlockState();
    private static final BlockState NETHERRACK = Blocks.NETHERRACK.defaultBlockState();
    private static final BlockState BLACKSTONE = Blocks.BLACKSTONE.defaultBlockState();
    private static final BlockState MAGMA_BLOCK = Blocks.MAGMA_BLOCK.defaultBlockState();
    private static final BlockState CRIMSON_NYLIUM = Blocks.CRIMSON_NYLIUM.defaultBlockState();
    private static final BlockState FIRE = Blocks.FIRE.defaultBlockState();
    private static final BlockState WEEPING_VINES_TIP = Blocks.WEEPING_VINES.defaultBlockState();
    private static final BlockState WEEPING_VINES_BODY = Blocks.WEEPING_VINES_PLANT.defaultBlockState();

    /** Resolved site of the current map snapshot. {@code floorY} = void continues below. */
    private record Site(DiscMapData map, int x, int z, int lipY, int chimneyTopY, int floorY) {}

    private static volatile Site site;

    private BreachGeometry() {}

    private static SimplexNoise wobble() {
        long seed = FrozenParams.mapSeed();
        SeededNoise cached = wobble;
        if (cached == null || cached.seed() != seed) {
            synchronized (BreachGeometry.class) {
                cached = wobble;
                if (cached == null || cached.seed() != seed) {
                    cached = new SeededNoise(seed, DiscTerrainFunction.noise(26));
                    wobble = cached;
                }
            }
        }
        return cached.noise();
    }

    private static Site site() {
        DiscMapData map = DiscMapData.get();
        Site cached = site;
        if (cached == null || cached.map() != map) {
            int cx = DEFAULT_X;
            int cz = DEFAULT_Z;
            for (DiscMapData.Landmark landmark : map.landmarks(DiscProfile.OVERWORLD)) {
                if (LANDMARK_ID.equals(landmark.id())) {
                    cx = landmark.x();
                    cz = landmark.z();
                    break;
                }
            }
            int lipY = DiscTerrainFunction.baseSurfaceY(map, DiscProfile.OVERWORLD, cx, cz);
            double r = Math.sqrt((double) cx * cx + (double) cz * cz);
            int floorY = (int) DiscProfile.OVERWORLD.lensBottomY(r) - 40;
            cached = new Site(map, cx, cz, lipY, lipY - FUNNEL_DEPTH, floorY);
            site = cached;
        }
        return cached;
    }

    /** X of the breach center (landmark-driven). */
    public static int centerX() {
        return site().x();
    }

    /** Z of the breach center (landmark-driven). */
    public static int centerZ() {
        return site().z();
    }

    /** Surface Y of the crater lip plane. */
    public static int lipY() {
        return site().lipY();
    }

    /** Whether column (x, z) lies inside the breach footprint (crater + creep halo). */
    public static boolean contains(int x, int z) {
        Site s = site();
        double dx = x - s.x();
        double dz = z - s.z();
        return dx * dx + dz * dz <= (double) HALO_RADIUS * HALO_RADIUS;
    }

    /**
     * Whether column (x, z) is close enough to the chimney that its wall collar keeps
     * going below the column's lowest ground block (callers extend {@code bottomY} by
     * {@link #SPOUT_DEPTH} for these columns).
     */
    public static boolean spoutContains(int x, int z) {
        Site s = site();
        double dx = x - s.x();
        double dz = z - s.z();
        double reach = CHIMNEY_RADIUS + WALL_THICKNESS + WOBBLE_AMP + 1.0D;
        return dx * dx + dz * dz <= reach * reach;
    }

    /**
     * Funnel override at (x, y, z): {@code AIR} inside the void (including the pierced
     * bedrock seal and the shaved crater interior above the lip), wall/vine states in
     * the shell, or null where the base terrain stands. Standalone per the W1.2 seam
     * contract — W1.7's {@code BreachBuilder} may call this per block on live chunks,
     * though rewriting whole columns through {@code DiscTerrainFunction.column} (with
     * {@code FrozenParams.breachOpen()} already flipped) is equivalent and simpler.
     */
    @Nullable
    public static BlockState carveAt(int x, int y, int z) {
        Site s = site();
        double dx = x - s.x();
        double dz = z - s.z();
        double distSq = dx * dx + dz * dz;
        double maxReach = CRATER_RADIUS + WALL_THICKNESS + WOBBLE_AMP;
        if (distSq > maxReach * maxReach) {
            return null;
        }
        if (y > s.lipY()) {
            // Shave any terrain bump (dunes) hanging over the crater interior.
            return y <= s.lipY() + 12 && distSq < (double) (CRATER_RADIUS + 1) * (CRATER_RADIUS + 1)
                    ? AIR : null;
        }
        if (y < s.floorY()) {
            return null; // below the spout mouth the disc's own void takes over
        }
        double dist = Math.sqrt(distSq);
        double angle = Math.atan2(dz, dx);
        SimplexNoise wobbleNoise = wobble();
        double wobble = wobbleNoise.getValue(Math.cos(angle) * 3.0D, Math.sin(angle) * 3.0D, y / 40.0D)
                * WOBBLE_AMP;
        double radius = radiusAt(y, s) + wobble;
        double lipNotchRadius = radiusAt(s.lipY(), s)
                + wobbleNoise.getValue(Math.cos(angle) * 3.0D, Math.sin(angle) * 3.0D, s.lipY() / 40.0D)
                        * WOBBLE_AMP
                - LIP_NOTCH;
        if (y == s.lipY()) {
            radius -= LIP_NOTCH; // overhanging lip ring juts in over the funnel
        }
        if (dist < radius) {
            // Weeping-vine strands hanging from the overhanging lip ring into the void.
            if (y < s.lipY() && dist >= lipNotchRadius) {
                long vineHash = DiscTerrainFunction.hash(H_BREACH, x, z);
                if (DiscTerrainFunction.to01(vineHash) < 0.45D) {
                    int strand = 2 + (int) ((vineHash >>> 8) & 3L); // 2..5
                    if (y >= s.lipY() - strand) {
                        return y == s.lipY() - strand ? WEEPING_VINES_TIP : WEEPING_VINES_BODY;
                    }
                }
            }
            return AIR;
        }
        if (dist < radius + WALL_THICKNESS) {
            return wallBlock(x, y, z, s);
        }
        return null;
    }

    /**
     * Crimson-creep halo override for the column's own surface: nylium/netherrack
     * repaint at {@code y == localSurfaceY}, eternal fire one above (only on repainted
     * netherrack), null elsewhere. Split from {@link #carveAt} because the halo follows
     * the LOCAL surface, which a standalone (x, y, z) query cannot know.
     */
    @Nullable
    public static BlockState creepAt(int x, int y, int z, int localSurfaceY) {
        Site s = site();
        double dx = x - s.x();
        double dz = z - s.z();
        double distSq = dx * dx + dz * dz;
        if (distSq > (double) HALO_RADIUS * HALO_RADIUS) {
            return null;
        }
        double dist = Math.sqrt(distSq);
        double p = Math.min(1.0D,
                1.0D - (dist - CRATER_RADIUS) / (double) (HALO_RADIUS - CRATER_RADIUS));
        if (p <= 0.0D) {
            return null;
        }
        long h = DiscTerrainFunction.hash3(H_BREACH, x, z, 991);
        boolean repainted = DiscTerrainFunction.to01(h) < p * 0.85D;
        if (!repainted) {
            return null;
        }
        boolean nylium = ((h >>> 8) & 0xFFL) < 77L; // ~30 % of repainted blocks
        if (y == localSurfaceY) {
            return nylium ? CRIMSON_NYLIUM : NETHERRACK;
        }
        if (y == localSurfaceY + 1 && !nylium && ((h >>> 16) & 0xFFL) < 18L) { // ~7 %
            return FIRE; // eternal fire: sits on the netherrack repaint below
        }
        return null;
    }

    /** Funnel void radius at height y: quadratic flare from chimney to crater mouth. */
    private static double radiusAt(int y, Site s) {
        if (y <= s.chimneyTopY()) {
            return CHIMNEY_RADIUS;
        }
        double t = (y - s.chimneyTopY()) / (double) (s.lipY() - s.chimneyTopY());
        return CHIMNEY_RADIUS + (CRATER_RADIUS - CHIMNEY_RADIUS) * t * t;
    }

    /** Layered wall shell: netherrack up top, blackstone deep, magma accents + spout ring. */
    private static BlockState wallBlock(int x, int y, int z, Site s) {
        double m = DiscTerrainFunction.hash01x3(H_BREACH, x, y, z);
        if (y <= s.floorY() + 6) {
            return m < 0.45D ? MAGMA_BLOCK : BLACKSTONE; // glowing spout mouth
        }
        if (m < 0.07D) {
            return MAGMA_BLOCK;
        }
        double depth = (s.lipY() - y) / (double) Math.max(1, s.lipY() - s.floorY());
        if (depth < 0.30D) {
            return m < 0.80D ? NETHERRACK : BLACKSTONE;
        }
        if (depth < 0.65D) {
            return m < 0.45D ? NETHERRACK : BLACKSTONE;
        }
        return m < 0.88D ? BLACKSTONE : NETHERRACK;
    }
}
