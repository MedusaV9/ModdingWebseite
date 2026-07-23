package dev.projecteclipse.eclipse.worldgen;

import javax.annotation.Nullable;

/**
 * Authored walk-in cave entrances (worker W1.2, plan v3 D4.4): at most one deterministic
 * entrance per {@value #CELL}×{@value #CELL} cell of the overworld disc, opened only
 * where the ground is flat enough. Each entrance is a flaring crater cone from just
 * above the surface down ~12 blocks, continued by a helical ramp tunnel that corkscrews
 * down into the Perlin-worm cave band, ending in a small terminal chamber. These replace
 * the pre-v2 surface ore exposures as the intended "way down" (D5 moved all ores below
 * {@code min(surfaceY − 8, 52)}); glow-lichen rims arrive via vanilla decoration (W1.1).
 *
 * <p>Everything is a pure function of the fixed {@link DiscMapData#ECLIPSE_SEED} (hash
 * salt 13), the map snapshot and the per-save frozen final radius
 * ({@code FrozenParams.stageRadii} — stage-INDEPENDENT, so interior columns never change
 * when a stage grows). Anchors are margin-clamped so a mask never leaves its cell:
 * per-column lookups stay cell-local.</p>
 */
public final class CaveEntrances {
    /** Cell edge length in blocks; each cell rolls at most one entrance candidate. */
    public static final int CELL = 96;
    /** Max horizontal distance from the anchor that any mask block can reach. */
    public static final int REACH = 9;

    /** Hash salt (13 — reuses the retired tree-grid salt of the pre-v2 terrain function). */
    private static final int H_ENTRANCE = 13;

    /** Chance that a cell rolls an entrance candidate at all (before suitability checks). */
    private static final double CELL_CHANCE = 0.65D;
    /** Crater cone depth below the anchor surface. */
    private static final int CONE_DEPTH = 12;
    /** Cone radius at its bottom (walk-through width). */
    private static final double CONE_RADIUS_BOTTOM = 2.6D;
    /** Cone radius at the surface lip. */
    private static final double CONE_RADIUS_TOP = 8.5D;
    /** Horizontal radius of the helical ramp centerline around the anchor. */
    private static final double HELIX_RADIUS = 5.5D;
    /** Tunnel radius of the helical ramp. */
    private static final double HELIX_TUNNEL_RADIUS = 2.3D;
    /** Angular advance (radians) of the helix per block of descent (gentle, walkable). */
    private static final double HELIX_STEP = 0.38D;
    /** Deepest descent below the anchor surface. */
    private static final int MAX_DROP = 58;
    /** Radius of the terminal chamber that opens into the worm band. */
    private static final double CHAMBER_RADIUS = 4.2D;
    /** Max surface height range over the slope probes for a "low slope" verdict. */
    private static final int MAX_SLOPE_RANGE = 6;
    /** Entrances stay this far inside the frozen FINAL disc radius (stage-independent). */
    private static final int FINAL_RIM_MARGIN = 24;

    private CaveEntrances() {}

    /**
     * Resolved geometry of one entrance. {@code coneBottomY} splits the crater cone from
     * the helical ramp; {@code bottomY} is the floor of the terminal chamber.
     */
    public record Entrance(int x, int z, int surfaceY, int coneBottomY, int bottomY, double theta0) {}

    /**
     * The entrance whose mask can affect column (x, z), or null. Threads the caller's
     * {@link DiscMapData} snapshot so all columns of one chunk/sweep resolve the same
     * entrance even across a concurrent {@code disc_map.json} reload. Overworld only.
     */
    @Nullable
    public static Entrance entranceAt(DiscMapData map, int x, int z) {
        int cellX = Math.floorDiv(x, CELL);
        int cellZ = Math.floorDiv(z, CELL);
        long h = DiscTerrainFunction.hash(H_ENTRANCE, cellX, cellZ);
        if (DiscTerrainFunction.to01(h) >= CELL_CHANCE) {
            return null;
        }
        // Anchor jitter clamped to [24, 72) so REACH (9) + cone lip (8.5) stay cell-local.
        int ax = cellX * CELL + 24 + (int) ((h >>> 16) & 0xFFL) % 48;
        int az = cellZ * CELL + 24 + (int) ((h >>> 24) & 0xFFL) % 48;
        if (Math.abs(x - ax) > REACH || Math.abs(z - az) > REACH) {
            return null;
        }
        return resolve(map, ax, az, h);
    }

    /**
     * Standalone mask query per the W1.2 seam outline: whether (x, y, z) is carved open
     * by an authored entrance. Prefer {@link #entranceAt} + {@link #mask(Entrance, int,
     * int, int)} in bulk consumers (one entrance resolve per column, one map snapshot).
     */
    public static boolean mask(int x, int y, int z) {
        Entrance entrance = entranceAt(DiscMapData.get(), x, z);
        return entrance != null && mask(entrance, x, y, z);
    }

    /** Whether block (x, y, z) lies inside the void mask of the given entrance. */
    public static boolean mask(Entrance e, int x, int y, int z) {
        if (y > e.surfaceY() + 1 || y < e.bottomY()) {
            return false;
        }
        double dx = x - e.x();
        double dz = z - e.z();
        double distSq = dx * dx + dz * dz;
        if (y >= e.coneBottomY()) {
            // Crater cone: quadratic flare from the walk-through throat to the open lip.
            double t = (y - e.coneBottomY()) / (double) (e.surfaceY() + 1 - e.coneBottomY());
            double radius = CONE_RADIUS_BOTTOM + (CONE_RADIUS_TOP - CONE_RADIUS_BOTTOM) * t * t;
            return distSq <= radius * radius;
        }
        // Helical ramp: a tunnel disc per Y whose center corkscrews around the anchor.
        // Successive discs offset by ~2.1 blocks (HELIX_RADIUS · HELIX_STEP), well under
        // the tunnel diameter, so the ramp is a connected, gently descending stair.
        int drop = e.coneBottomY() - y;
        double theta = e.theta0() + drop * HELIX_STEP;
        double hdx = x - (e.x() + Math.cos(theta) * HELIX_RADIUS);
        double hdz = z - (e.z() + Math.sin(theta) * HELIX_RADIUS);
        if (hdx * hdx + hdz * hdz <= HELIX_TUNNEL_RADIUS * HELIX_TUNNEL_RADIUS) {
            return true;
        }
        // Terminal chamber: a squashed sphere where the ramp meets the worm band.
        int chamberCenterY = e.bottomY() + 2;
        if (y <= e.bottomY() + 5) {
            double thetaEnd = e.theta0() + (e.coneBottomY() - chamberCenterY) * HELIX_STEP;
            double cdx = x - (e.x() + Math.cos(thetaEnd) * HELIX_RADIUS);
            double cdz = z - (e.z() + Math.sin(thetaEnd) * HELIX_RADIUS);
            double dy = y - chamberCenterY;
            return cdx * cdx + cdz * cdz + dy * dy * 1.3D <= CHAMBER_RADIUS * CHAMBER_RADIUS;
        }
        return false;
    }

    /** Suitability checks + geometry of the cell's entrance; null when the spot is bad. */
    @Nullable
    private static Entrance resolve(DiscMapData map, int ax, int az, long h) {
        double r = Math.sqrt((double) ax * ax + (double) az * az);
        if (r < 30.0D) {
            return null; // keep the spawn pad / center cap pristine
        }
        int[] radii = FrozenParams.stageRadii(DiscProfile.OVERWORLD);
        if (radii.length == 0 || r > radii[radii.length - 1] - FINAL_RIM_MARGIN) {
            return null; // stage-independent: gate against the frozen FINAL radius only
        }
        int surface = DiscTerrainFunction.baseSurfaceY(map, DiscProfile.OVERWORLD, ax, az);
        if (surface > 150 || surface < 66) {
            return null; // no shafts through high mountain rock or swamp-pool floors
        }
        // Low-slope check: the crater must cut a level lip, not a hillside gash.
        int min = surface;
        int max = surface;
        for (int i = 0; i < 4; i++) {
            int px = ax + (i == 0 ? 10 : i == 1 ? -10 : 0);
            int pz = az + (i == 2 ? 10 : i == 3 ? -10 : 0);
            int probe = DiscTerrainFunction.baseSurfaceY(map, DiscProfile.OVERWORLD, px, pz);
            min = Math.min(min, probe);
            max = Math.max(max, probe);
            if (max - min > MAX_SLOPE_RANGE) {
                return null;
            }
        }
        if (map.riverDistance(DiscProfile.OVERWORLD, ax, az)
                < DiscTerrainFunction.RIVER_HALF_WIDTH + DiscTerrainFunction.RIVER_BANK_MARGIN + 6.0D) {
            return null; // never crater a river channel or its banks
        }
        DiscMapData.Mountain mountain = map.profile(DiscProfile.OVERWORLD).mountain();
        if (mountain != null) {
            double mdx = ax - mountain.x();
            double mdz = az - mountain.z();
            double clear = Math.max(40.0D, mountain.caveRadiusXz() + 20.0D);
            if (mdx * mdx + mdz * mdz < clear * clear) {
                return null; // never pierce the sealed mountain core cavity
            }
        }
        for (DiscMapData.Landmark landmark : map.landmarks(DiscProfile.OVERWORLD)) {
            double ldx = ax - landmark.x();
            double ldz = az - landmark.z();
            double clear = landmark.radius() + 12.0D;
            if (ldx * ldx + ldz * ldz < clear * clear) {
                return null; // keep structure sites terraformable
            }
        }
        int coneBottomY = surface - CONE_DEPTH;
        int bottomY = Math.max((int) DiscProfile.OVERWORLD.lensBottomY(r) + 12, surface - MAX_DROP);
        if (coneBottomY - bottomY < 8) {
            return null; // ground too thin for a meaningful descent
        }
        double theta0 = ((h >>> 32) & 0xFFFFL) / 65536.0D * (Math.PI * 2.0D);
        return new Entrance(ax, az, surface, coneBottomY, bottomY, theta0);
    }
}
