package dev.projecteclipse.eclipse.worldgen.ore;

import java.util.ArrayList;
import java.util.BitSet;
import java.util.List;

import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import net.minecraft.util.Mth;

/**
 * ONE shared, deterministic port of vanilla {@code OreFeature.doPlace}'s vein shape
 * (B2, PLAN-B plans_v5): a short line segment through the vein anchor with
 * sine-modulated ellipsoid bulges along it — the classic snake vein — instead of the
 * old squashed-ellipsoid blob. {@link OreField} (generation membership) and
 * {@link VeinTracker} (mining feel / anti-xray census) both derive veins EXCLUSIVELY
 * through this class, so they stay in lockstep by construction.
 *
 * <p><b>Determinism contract:</b> every random draw comes from a splitmix64 stream
 * seeded by {@code hash(mapSeed, H_ORE + ore.salt(), cellX, cellY, cellZ)} — a pure
 * function of the frozen map seed and the 16³ cell. No {@link net.minecraft.util.RandomSource}
 * is consumed, so no RNG state leaks across chunks: the same seed + chunk always
 * yields byte-identical veins, and the {@code RingGrowthService} sweep replay stays
 * reproducible.</p>
 *
 * <p><b>Vanilla math ported 1:1</b> (1.21.1 {@code OreFeature.place}/{@code doPlace}):
 * segment endpoints {@code anchor ± (sin(f)·size/8, nextInt(3)−2, cos(f)·size/8)},
 * per-step bulge centers {@code lerp(k/size, start, end)} with radius
 * {@code ((sin(π·k/size)+1) · nextDouble·size/16 + 1) / 2}, the contained-sphere cull
 * pass, and block membership {@code Σ((coord+0.5−center)/r)² < 1}. Only vanilla's
 * BulkSectionAccess write loop and the air-exposure discard are omitted (membership
 * is a pure per-block query; there is no neighbour access on this path).</p>
 *
 * <p><b>Cell containment invariant:</b> anchors sit at {@code cell·16 + 4 + [0..7]}
 * and layer sizes are capped at {@value OreConfig#MAX_VEIN_SIZE} (vanilla's largest,
 * copper 20), so the worst-case reach (segment half-length {@code 20/8 = 2.5} + max
 * bulge radius {@code ((sin+1)·20/16+1)/2 = 1.75} &lt; 4.5) keeps every member block
 * inside the anchor's own 16³ cell — one cell derivation covers the whole vein,
 * exactly like the legacy blob invariant.</p>
 */
final class OreVeinShape {
    /** Ore channel salt of the shared hash (legacy {@code OreField.H_ORE}, kept for continuity). */
    static final int H_ORE = 17;
    /** Hard cap on simultaneously derived veins of one layer in one cell (config abuse guard). */
    private static final int MAX_VEINS_PER_CELL = 6;
    /** Shared empty result — the overwhelmingly common case. */
    static final OreVeinShape[] NO_VEINS = new OreVeinShape[0];

    /** Ellipsoid chain: {@code [x, y, z, radius] × size}; radius &lt; 0 = culled (vanilla rule). */
    private final double[] spheres;
    private final int cellMinX;
    private final int cellMinY;
    private final int cellMinZ;

    private OreVeinShape(double[] spheres, int cellMinX, int cellMinY, int cellMinZ) {
        this.spheres = spheres;
        this.cellMinX = cellMinX;
        this.cellMinY = cellMinY;
        this.cellMinZ = cellMinZ;
    }

    /** Member-block visitor for {@link #forEachBlock}. */
    interface BlockConsumer {
        void accept(int x, int y, int z);
    }

    /**
     * Stage-gate multiplier for one cell column: {@code -1} when the annulus band is
     * still locked for this ore, otherwise the configured band factor × center bias.
     * Identical to the legacy gate — B2 changes SHAPE/distribution only.
     */
    static double gateScale(OreConfig.ResolvedOre ore, DiscProfile profile, int cellX, int cellZ) {
        double cellR = Math.hypot(cellX * 16 + 8, cellZ * 16 + 8);
        int band = FrozenParams.annulusBand(profile, cellR);
        if (band < ore.unlockStage()) {
            return -1.0D;
        }
        double scale = ore.bandFactor()[Math.min(band, ore.bandFactor().length - 1)];
        if (ore.centerBias()) {
            scale *= Math.max(0.15D, 1.0D - cellR / profile.lensNormRadius());
        }
        return scale;
    }

    /**
     * Every vein of {@code ore} anchored in the given 16³ cell. Per configured layer the
     * expected vein count is {@code countPerChunk × heightDistributionMass(cellBand) ×
     * gateScale}; the integer part always spawns, the fraction is one extra hash-gated
     * vein — matching vanilla's per-chunk {@code CountPlacement} + height-range mass at
     * 16-block resolution. {@code gateScale} must come from
     * {@link #gateScale(OreConfig.ResolvedOre, DiscProfile, int, int)}.
     */
    static OreVeinShape[] veinsOf(long seed, OreConfig.ResolvedOre ore, int cellX, int cellY, int cellZ,
            double gateScale) {
        List<OreConfig.Layer> layers = ore.layers();
        if (layers.isEmpty() || gateScale <= 0.0D) {
            return NO_VEINS;
        }
        long cellSeed = hash3(seed, H_ORE + ore.salt(), cellX, cellY, cellZ);
        List<OreVeinShape> out = null;
        for (int li = 0; li < layers.size(); li++) {
            OreConfig.Layer layer = layers.get(li);
            double lambda = layer.count() * layer.cellMass(cellY * 16) * gateScale;
            if (lambda <= 0.0D) {
                continue;
            }
            long layerSeed = mix(cellSeed ^ ((li + 1) * 0x9E3779B97F4A7C15L));
            int attempts = (int) lambda;
            if (to01(layerSeed) < lambda - attempts) {
                attempts++;
            }
            attempts = Math.min(attempts, MAX_VEINS_PER_CELL);
            for (int a = 0; a < attempts; a++) {
                long attemptSeed = mix(layerSeed ^ ((a + 1) * 0xC2B2AE3D27D4EB4FL));
                OreVeinShape vein = derive(attemptSeed, ore, layer.size(), cellX, cellY, cellZ);
                if (vein != null) {
                    if (out == null) {
                        out = new ArrayList<>(attempts);
                    }
                    out.add(vein);
                }
            }
        }
        return out == null ? NO_VEINS : out.toArray(NO_VEINS);
    }

    /**
     * Derives one vein: anchor in the cell's middle 8³ (legacy scheme, keeps the
     * containment invariant), then the exact vanilla segment + bulge chain + cull pass.
     * Returns {@code null} when the anchor falls outside the ore's Y gate.
     */
    private static OreVeinShape derive(long attemptSeed, OreConfig.ResolvedOre ore, int size,
            int cellX, int cellY, int cellZ) {
        Rand rand = new Rand(attemptSeed);
        long bits = rand.nextLong();
        int anchorX = (cellX << 4) + 4 + (int) (bits & 7);
        int anchorY = cellY * 16 + 4 + (int) ((bits >>> 3) & 7);
        int anchorZ = (cellZ << 4) + 4 + (int) ((bits >>> 6) & 7);
        if (anchorY < ore.minY() || anchorY > ore.maxY()) {
            return null;
        }

        // --- vanilla OreFeature.place: segment endpoints through the anchor ---
        float angle = rand.nextFloat() * (float) Math.PI;
        float halfLength = size / 8.0F;
        double startX = anchorX + Math.sin(angle) * halfLength;
        double endX = anchorX - Math.sin(angle) * halfLength;
        double startZ = anchorZ + Math.cos(angle) * halfLength;
        double endZ = anchorZ - Math.cos(angle) * halfLength;
        double startY = anchorY + rand.nextInt(3) - 2;
        double endY = anchorY + rand.nextInt(3) - 2;

        // --- vanilla OreFeature.doPlace: per-step sine-modulated ellipsoid chain ---
        double[] spheres = new double[size * 4];
        for (int k = 0; k < size; k++) {
            float t = (float) k / (float) size;
            double bulge = rand.nextDouble() * size / 16.0D;
            double radius = ((double) (Mth.sin((float) Math.PI * t) + 1.0F) * bulge + 1.0D) / 2.0D;
            spheres[k * 4] = Mth.lerp(t, startX, endX);
            spheres[k * 4 + 1] = Mth.lerp(t, startY, endY);
            spheres[k * 4 + 2] = Mth.lerp(t, startZ, endZ);
            spheres[k * 4 + 3] = radius;
        }
        // Vanilla cull pass: a sphere entirely inside a bigger one is dropped (r = -1).
        for (int i = 0; i < size - 1; i++) {
            if (spheres[i * 4 + 3] <= 0.0D) {
                continue;
            }
            for (int j = i + 1; j < size; j++) {
                if (spheres[j * 4 + 3] <= 0.0D) {
                    continue;
                }
                double dx = spheres[i * 4] - spheres[j * 4];
                double dy = spheres[i * 4 + 1] - spheres[j * 4 + 1];
                double dz = spheres[i * 4 + 2] - spheres[j * 4 + 2];
                double dr = spheres[i * 4 + 3] - spheres[j * 4 + 3];
                if (dr * dr > dx * dx + dy * dy + dz * dz) {
                    if (dr > 0.0D) {
                        spheres[j * 4 + 3] = -1.0D;
                    } else {
                        spheres[i * 4 + 3] = -1.0D;
                    }
                }
            }
        }
        return new OreVeinShape(spheres, cellX << 4, cellY * 16, cellZ << 4);
    }

    /** Vanilla membership test: block center inside any live sphere of the chain. */
    boolean contains(int x, int y, int z) {
        double[] s = this.spheres;
        for (int i = 0; i < s.length; i += 4) {
            double r = s[i + 3];
            if (r < 0.0D) {
                continue;
            }
            double dx = (x + 0.5D - s[i]) / r;
            double dy = (y + 0.5D - s[i + 1]) / r;
            double dz = (z + 0.5D - s[i + 2]) / r;
            if (dx * dx + dy * dy + dz * dz < 1.0D) {
                return true;
            }
        }
        return false;
    }

    /**
     * Visits every member block exactly once (vanilla's BitSet-deduped sphere walk),
     * clamped to the vein's cell — a no-op clamp under the containment invariant.
     * Callers apply their own Y gates in the consumer.
     */
    void forEachBlock(BlockConsumer consumer) {
        BitSet seen = new BitSet(16 * 16 * 16);
        double[] s = this.spheres;
        for (int i = 0; i < s.length; i += 4) {
            double r = s[i + 3];
            if (r < 0.0D) {
                continue;
            }
            double cx = s[i];
            double cy = s[i + 1];
            double cz = s[i + 2];
            int minX = Math.max(Mth.floor(cx - r), this.cellMinX);
            int minY = Math.max(Mth.floor(cy - r), this.cellMinY);
            int minZ = Math.max(Mth.floor(cz - r), this.cellMinZ);
            int maxX = Math.min(Math.max(Mth.floor(cx + r), minX), this.cellMinX + 15);
            int maxY = Math.min(Math.max(Mth.floor(cy + r), minY), this.cellMinY + 15);
            int maxZ = Math.min(Math.max(Mth.floor(cz + r), minZ), this.cellMinZ + 15);
            for (int x = minX; x <= maxX; x++) {
                double dx = (x + 0.5D - cx) / r;
                if (dx * dx >= 1.0D) {
                    continue;
                }
                for (int y = minY; y <= maxY; y++) {
                    double dy = (y + 0.5D - cy) / r;
                    if (dx * dx + dy * dy >= 1.0D) {
                        continue;
                    }
                    for (int z = minZ; z <= maxZ; z++) {
                        double dz = (z + 0.5D - cz) / r;
                        if (dx * dx + dy * dy + dz * dz >= 1.0D) {
                            continue;
                        }
                        int idx = (x - this.cellMinX) | ((y - this.cellMinY) << 4) | ((z - this.cellMinZ) << 8);
                        if (!seen.get(idx)) {
                            seen.set(idx);
                            consumer.accept(x, y, z);
                        }
                    }
                }
            }
        }
    }

    // --- the ONE frozen hash algorithm (formerly duplicated OreField/VeinTracker privates) ---

    /** splitmix64 finalizer — shared by the cell hash and {@link OreField}'s cache slots. */
    static long mix(long z) {
        z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
        z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
        return z ^ (z >>> 31);
    }

    /** Seed-salted 3-coordinate hash (bit-identical to the legacy private copies). */
    static long hash3(long seed, int salt, int a, int b, int c) {
        long h = seed + salt * 0x9E3779B97F4A7C15L;
        h = mix(h ^ (a & 0xFFFFFFFFL));
        h = mix(h ^ (b & 0xFFFFFFFFL));
        return mix(h ^ (c & 0xFFFFFFFFL));
    }

    /** Uniform [0,1) from a hash (legacy helper, unchanged). */
    static double to01(long hash) {
        return (hash >>> 11) * 0x1.0p-53D;
    }

    /** Deterministic splitmix64 stream standing in for vanilla's {@code RandomSource}. */
    private static final class Rand {
        private long state;

        Rand(long seed) {
            this.state = seed;
        }

        long nextLong() {
            return mix(this.state += 0x9E3779B97F4A7C15L);
        }

        double nextDouble() {
            return (nextLong() >>> 11) * 0x1.0p-53D;
        }

        float nextFloat() {
            return (nextLong() >>> 40) * 0x1.0p-24F;
        }

        int nextInt(int bound) {
            return (int) ((nextLong() >>> 33) % bound);
        }
    }
}
