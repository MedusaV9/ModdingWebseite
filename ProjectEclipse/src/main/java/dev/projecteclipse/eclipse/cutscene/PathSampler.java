package dev.projecteclipse.eclipse.cutscene;

import java.util.List;

import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;

/**
 * Dist-neutral spline evaluation for {@link CutscenePath} keyframes plus the P2 R12
 * arc-length reparameterization: at construction every segment is sampled
 * {@value #LUT_SAMPLES} times into a cumulative-length LUT, and {@link #position} inverts
 * that LUT so a given fraction of a segment's <b>distance</b> (not of its spline parameter)
 * is covered — uniform Catmull-Rom's "speed pumping" between unevenly spaced keyframes is
 * gone by construction. Easing curves now shape speed <i>along the path</i>, which is what
 * path authors intuitively expect.
 *
 * <p>Built once per flight by the client camera director and per preview command by the
 * server (the class touches no dist-specific code). All math runs in keyframe-local space;
 * {@link #toWorld} applies the anchor transform both sides share.</p>
 */
public final class PathSampler {
    /** Arc-length LUT samples per segment (P2 R12 frozen constant). */
    public static final int LUT_SAMPLES = 64;

    private final List<CutscenePath.Keyframe> keyframes;
    private final boolean bezier;
    /** Per segment: cumulative arc length at parameter j/{@value #LUT_SAMPLES}, j = 0..{@value #LUT_SAMPLES}. */
    private final double[][] cumulative;
    /** Per segment: total arc length (== cumulative[i][{@value #LUT_SAMPLES}]). */
    private final double[] segmentLength;
    private final double totalLength;

    private PathSampler(List<CutscenePath.Keyframe> keyframes, boolean bezier) {
        this.keyframes = keyframes;
        this.bezier = bezier;
        int segments = Math.max(1, keyframes.size() - 1);
        this.cumulative = new double[segments][LUT_SAMPLES + 1];
        this.segmentLength = new double[segments];
        double total = 0.0D;
        for (int segment = 0; segment < segments; segment++) {
            double acc = 0.0D;
            Vec3 previous = evaluateSpline(segment, 0.0F);
            this.cumulative[segment][0] = 0.0D;
            for (int j = 1; j <= LUT_SAMPLES; j++) {
                Vec3 current = evaluateSpline(segment, (float) j / LUT_SAMPLES);
                acc += current.distanceTo(previous);
                this.cumulative[segment][j] = acc;
                previous = current;
            }
            this.segmentLength[segment] = acc;
            total += acc;
        }
        this.totalLength = total;
    }

    /** Builds the sampler (LUT included) for a path. Requires ≥ 2 keyframes (library-enforced). */
    public static PathSampler of(CutscenePath path) {
        return new PathSampler(path.keyframes(),
                CutscenePath.INTERPOLATION_BEZIER.equals(path.interpolation()));
    }

    /** Number of spline segments (keyframes − 1). */
    public int segmentCount() {
        return this.segmentLength.length;
    }

    /** Total path arc length in blocks (keyframe-local space). */
    public double totalLength() {
        return this.totalLength;
    }

    /**
     * Position after covering {@code distanceFraction} (0..1) of the segment's arc length —
     * the arc-length reparameterized replacement for evaluating the spline at the raw eased
     * parameter. Degenerate (zero-length) segments fall back to the raw parameter.
     */
    public Vec3 position(int segment, float distanceFraction) {
        segment = Mth.clamp(segment, 0, this.segmentLength.length - 1);
        float f = Mth.clamp(distanceFraction, 0.0F, 1.0F);
        double length = this.segmentLength[segment];
        if (length < 1.0e-4D) {
            return evaluateSpline(segment, f);
        }
        return evaluateSpline(segment, parameterForDistance(segment, f * length));
    }

    /**
     * Position at a fraction (0..1) of the WHOLE path's arc length — evenly spaced samples
     * for the {@code /eclipsefx cutscene preview} particle trace.
     */
    public Vec3 positionAtPathFraction(double pathFraction) {
        double target = Mth.clamp(pathFraction, 0.0D, 1.0D) * this.totalLength;
        for (int segment = 0; segment < this.segmentLength.length; segment++) {
            if (target <= this.segmentLength[segment] || segment == this.segmentLength.length - 1) {
                double length = this.segmentLength[segment];
                if (length < 1.0e-4D) {
                    return evaluateSpline(segment, 0.0F);
                }
                return evaluateSpline(segment, parameterForDistance(segment, Math.min(target, length)));
            }
            target -= this.segmentLength[segment];
        }
        return evaluateSpline(this.segmentLength.length - 1, 1.0F);
    }

    /** Inverts the segment LUT: distance from segment start → spline parameter in [0,1]. */
    private float parameterForDistance(int segment, double distance) {
        double[] lut = this.cumulative[segment];
        int low = 0;
        int high = LUT_SAMPLES;
        while (low + 1 < high) {
            int mid = (low + high) >>> 1;
            if (lut[mid] <= distance) {
                low = mid;
            } else {
                high = mid;
            }
        }
        double span = lut[high] - lut[low];
        double frac = span <= 1.0e-9D ? 0.0D : (distance - lut[low]) / span;
        return (float) ((low + frac) / LUT_SAMPLES);
    }

    // ------------------------------------------------------------------ raw spline math

    /** Raw (non-reparameterized) spline evaluation at parameter {@code s} of a segment. */
    public Vec3 evaluateSpline(int segment, float s) {
        return this.bezier
                ? bezierPosition(this.keyframes, segment, s)
                : catmullRomPosition(this.keyframes, segment, s);
    }

    /** Uniform Catmull-Rom through the keyframe positions (clamped end tangents). */
    public static Vec3 catmullRomPosition(List<CutscenePath.Keyframe> keyframes, int segment, float t) {
        Vec3 p0 = pos(keyframes, segment - 1);
        Vec3 p1 = pos(keyframes, segment);
        Vec3 p2 = pos(keyframes, segment + 1);
        Vec3 p3 = pos(keyframes, segment + 2);
        return new Vec3(
                catmullRom(t, p0.x, p1.x, p2.x, p3.x),
                catmullRom(t, p0.y, p1.y, p2.y, p3.y),
                catmullRom(t, p0.z, p1.z, p2.z, p3.z));
    }

    /** Double-precision {@code Mth.catmullrom} (float would jitter at large world coordinates). */
    private static double catmullRom(double t, double p0, double p1, double p2, double p3) {
        return 0.5D * (2.0D * p1 + (p2 - p0) * t
                + (2.0D * p0 - 5.0D * p1 + 4.0D * p2 - p3) * t * t
                + (3.0D * p1 - p0 - 3.0D * p2 + p3) * t * t * t);
    }

    /**
     * Segment-local cubic Hermite with damped tangents (half Catmull-Rom): flows less than
     * Catmull-Rom and settles into every keyframe — the {@code "bezier"} mode of the schema.
     */
    public static Vec3 bezierPosition(List<CutscenePath.Keyframe> keyframes, int segment, float t) {
        Vec3 p0 = pos(keyframes, segment - 1);
        Vec3 p1 = pos(keyframes, segment);
        Vec3 p2 = pos(keyframes, segment + 1);
        Vec3 p3 = pos(keyframes, segment + 2);
        Vec3 m1 = p2.subtract(p0).scale(0.25D);
        Vec3 m2 = p3.subtract(p1).scale(0.25D);
        double t2 = t * t;
        double t3 = t2 * t;
        double h1 = 2.0D * t3 - 3.0D * t2 + 1.0D;
        double h2 = t3 - 2.0D * t2 + t;
        double h3 = -2.0D * t3 + 3.0D * t2;
        double h4 = t3 - t2;
        return p1.scale(h1).add(m1.scale(h2)).add(p2.scale(h3)).add(m2.scale(h4));
    }

    private static Vec3 pos(List<CutscenePath.Keyframe> keyframes, int index) {
        CutscenePath.Keyframe keyframe = keyframes.get(Mth.clamp(index, 0, keyframes.size() - 1));
        return new Vec3(keyframe.x(), keyframe.y(), keyframe.z());
    }

    /**
     * Keyframe-local position → world: rotate by the anchor yaw (player-anchored paths),
     * then translate by the anchor origin. Shared by the client camera director and the
     * server-side preview trace so both always agree.
     */
    public static Vec3 toWorld(Vec3 local, Vec3 anchorPos, float anchorYawDeg) {
        if (anchorYawDeg != 0.0F) {
            float radians = (float) -Math.toRadians(anchorYawDeg);
            double sin = Math.sin(radians);
            double cos = Math.cos(radians);
            // rotateY: x' = x·cos + z·sin, z' = −x·sin + z·cos (JOML rotateY convention).
            return anchorPos.add(
                    local.x * cos + local.z * sin,
                    local.y,
                    -local.x * sin + local.z * cos);
        }
        return anchorPos.add(local);
    }
}
