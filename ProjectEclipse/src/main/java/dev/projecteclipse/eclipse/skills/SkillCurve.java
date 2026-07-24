package dev.projecteclipse.eclipse.skills;

/**
 * Pure leveling math for the Eclipse skill system (R3, plan §2.3). Stateless and
 * config-parameterized so gametests can pin the numbers without touching disk.
 *
 * <p>The cumulative curve is the closed form the planner used for its anchors
 * ({@code C(12) ≈ 2 650}, {@code C(50) ≈ 70 000}):
 * {@code C(L) = baseCost · L^(exponent+1) / (exponent+1)}, i.e. the integral of the
 * per-action cost sketch {@code baseCost · n^exponent}. Past {@code softcapLevel}
 * every additional level costs {@code softcapMult} times the raw increment. Per-level
 * cost is the difference of consecutive cumulative values — strictly increasing
 * (fast → slow) and always ≥ 1.</p>
 */
public final class SkillCurve {
    /** Hard sanity bound so a corrupt totalXp can never loop forever. */
    public static final int MAX_LEVEL = 1000;

    /** Curve knobs (mirrors the {@code curve} object in {@code skills.json}). */
    public record Params(double baseCost, double exponent, int softcapLevel, double softcapMult) {
        /** Plan defaults: 20 / 1.3 / 50 / 2.0. */
        public static Params defaults() {
            return new Params(20.0D, 1.3D, 50, 2.0D);
        }
    }

    private SkillCurve() {}

    private static double raw(int level, Params p) {
        if (level <= 0) {
            return 0.0D;
        }
        double power = p.exponent() + 1.0D;
        return p.baseCost() * Math.pow(level, power) / power;
    }

    /** Total XP required to HOLD {@code level} (cumulative from 0). {@code C(0) == 0}. */
    public static long cumulativeXp(int level, Params p) {
        if (level <= 0) {
            return 0L;
        }
        int capped = Math.min(level, MAX_LEVEL);
        double value;
        if (capped <= p.softcapLevel()) {
            value = raw(capped, p);
        } else {
            double atCap = raw(p.softcapLevel(), p);
            value = atCap + p.softcapMult() * (raw(capped, p) - atCap);
        }
        return Math.round(value);
    }

    /** XP cost of gaining {@code level} (from {@code level - 1}); always ≥ 1. */
    public static int xpForLevel(int level, Params p) {
        if (level <= 0) {
            return 0;
        }
        long cost = cumulativeXp(level, p) - cumulativeXp(level - 1, p);
        return (int) Math.max(1L, Math.min(cost, Integer.MAX_VALUE));
    }

    /** Level derived from lifetime XP (never stored — plan §2.3). */
    public static int levelForXp(long totalXp, Params p) {
        if (totalXp <= 0L) {
            return 0;
        }
        // Levels are small (softcap 50, MAX 1000) and addXp calls are already coalesced;
        // a forward walk is simpler than a bisection and trivially correct.
        int level = 0;
        while (level < MAX_LEVEL && cumulativeXp(level + 1, p) <= totalXp) {
            level++;
        }
        return level;
    }

    /** XP progressed inside the current level (for the client XP bar). */
    public static int xpIntoLevel(long totalXp, int level, Params p) {
        long into = totalXp - cumulativeXp(level, p);
        return (int) Math.max(0L, Math.min(into, Integer.MAX_VALUE));
    }
}
