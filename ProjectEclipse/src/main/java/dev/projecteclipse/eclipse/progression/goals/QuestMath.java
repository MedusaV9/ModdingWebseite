package dev.projecteclipse.eclipse.progression.goals;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * Pure, deterministic quest math (plans_v3 P4 §2.2 "Draw math in pure QuestMath"). No MC
 * imports so gametests can exercise every branch without a level. Determinism contract: the
 * same {@code (worldSeed, uuid, day, nonce)} and the same candidate list produce the same
 * draw on every JVM — a relog/restart re-derives an identical personal assignment even if
 * SavedData was rolled back.
 */
public final class QuestMath {
    private QuestMath() {}

    /** One weighted draw candidate ({@code quests.json} pool entry). */
    public record Candidate(String id, int weight) {}

    /**
     * Personal-draw seed: mixes world seed, player uuid and event day (+ reroll nonce; 0 for
     * the daily assignment). Uses xor-fold + SplitMix64 finalization so near-identical inputs
     * (consecutive days, sequential uuids) still decorrelate.
     */
    public static long seed(long worldSeed, UUID uuid, int day, int nonce) {
        long mixed = worldSeed;
        mixed = mix(mixed ^ uuid.getMostSignificantBits());
        mixed = mix(mixed ^ uuid.getLeastSignificantBits());
        mixed = mix(mixed ^ (0x9E3779B97F4A7C15L * (day + 1L)));
        mixed = mix(mixed ^ (0xC2B2AE3D27D4EB4FL * (nonce + 1L)));
        return mixed;
    }

    /**
     * Weighted draw WITHOUT replacement: picks up to {@code n} distinct candidate ids.
     * Zero-weight candidates are never drawn; fewer than {@code n} drawable candidates
     * returns all of them (stable order of draw). Pure and allocation-bounded.
     */
    public static List<String> draw(long seed, List<Candidate> candidates, int n) {
        List<Candidate> pool = new ArrayList<>(candidates.size());
        long totalWeight = 0L;
        for (Candidate candidate : candidates) {
            if (candidate.weight() > 0) {
                pool.add(candidate);
                totalWeight += candidate.weight();
            }
        }
        List<String> drawn = new ArrayList<>(Math.min(n, pool.size()));
        long state = seed;
        while (drawn.size() < n && !pool.isEmpty()) {
            state = mix(state);
            long roll = Math.floorMod(state, totalWeight);
            for (int i = 0; i < pool.size(); i++) {
                roll -= pool.get(i).weight();
                if (roll < 0) {
                    Candidate picked = pool.remove(i);
                    drawn.add(picked.id());
                    totalWeight -= picked.weight();
                    break;
                }
            }
        }
        return drawn;
    }

    /** Legacy sidebar bitmask from ordered done flags (bit i = mains[i], max 8 goals). */
    public static int bitmask(List<Boolean> done) {
        int mask = 0;
        for (int i = 0; i < Math.min(done.size(), 8); i++) {
            if (Boolean.TRUE.equals(done.get(i))) {
                mask |= 1 << i;
            }
        }
        return mask;
    }

    /** Clamps a long progress counter into the payload's int field. */
    public static int clampToInt(long value) {
        return (int) Math.max(Integer.MIN_VALUE, Math.min(Integer.MAX_VALUE, value));
    }

    /** SplitMix64 finalizer — the shared bit mixer for {@link #seed} and {@link #draw}. */
    static long mix(long z) {
        z += 0x9E3779B97F4A7C15L;
        z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
        z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
        return z ^ (z >>> 31);
    }
}
