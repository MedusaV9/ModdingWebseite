package dev.projecteclipse.eclipse.awards;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Random;
import java.util.Set;
import java.util.UUID;

/**
 * Pure deterministic math for daily awards. Nothing in this class touches a server, registry
 * or save, so selection and tie behavior can be exercised directly by gametests.
 */
public final class AwardMath {
    /** Minimal weighted-selection view of a configured category. */
    public record Choice(String id, int weight, Set<String> dayTags) {
        public Choice {
            dayTags = Set.copyOf(dayTags);
        }
    }

    /** One candidate and the already-snapshotted value used to rank them. */
    public record Candidate(UUID uuid, long value) {}

    /** Sorted candidates, every UUID tied at the best value, and that best value. */
    public record Resolution(List<Candidate> candidates, List<UUID> winners, long bestValue) {
        public Resolution {
            candidates = List.copyOf(candidates);
            winners = List.copyOf(winners);
        }

        public boolean hasWinner() {
            return !winners.isEmpty();
        }
    }

    public enum Order {
        MAX,
        MIN;

        public static Order parse(String raw) {
            return "min".equalsIgnoreCase(raw) ? MIN : MAX;
        }
    }

    private AwardMath() {}

    /**
     * Stable per-save/day seed. The reroll nonce is zero during normal operation and is only
     * changed by the permission-gated dev command; persisting it makes admin rerolls restart-safe.
     */
    public static long seed(long worldSeed, int day, int rerollNonce) {
        long value = worldSeed ^ 0x9E3779B97F4A7C15L;
        value = mix64(value ^ Integer.toUnsignedLong(day));
        return mix64(value ^ (Integer.toUnsignedLong(rerollNonce) * 0xD1B54A32D192ED03L));
    }

    /**
     * Weighted draw without replacement. Categories intersecting the day's themes receive a
     * threefold weight. Input order is significant and is the stable config-file order.
     */
    public static List<String> pick(long seed, List<Choice> pool, Set<String> themes, int count) {
        if (count <= 0 || pool.isEmpty()) {
            return List.of();
        }
        List<Choice> remaining = new ArrayList<>();
        for (Choice choice : pool) {
            if (choice.weight() > 0) {
                remaining.add(choice);
            }
        }
        List<String> selected = new ArrayList<>(Math.min(count, remaining.size()));
        Random random = new Random(seed);
        while (selected.size() < count && !remaining.isEmpty()) {
            long total = 0L;
            for (Choice choice : remaining) {
                total += effectiveWeight(choice, themes);
            }
            if (total <= 0L) {
                break;
            }
            long roll = Math.floorMod(random.nextLong(), total);
            int picked = 0;
            for (int i = 0; i < remaining.size(); i++) {
                long weight = effectiveWeight(remaining.get(i), themes);
                if (roll < weight) {
                    picked = i;
                    break;
                }
                roll -= weight;
            }
            selected.add(remaining.remove(picked).id());
        }
        return List.copyOf(selected);
    }

    private static long effectiveWeight(Choice choice, Set<String> themes) {
        boolean themed = false;
        for (String tag : choice.dayTags()) {
            if (themes.contains(tag)) {
                themed = true;
                break;
            }
        }
        return Math.max(0L, choice.weight()) * (themed ? 3L : 1L);
    }

    /**
     * Resolves a leaderboard. Candidates are sorted in award order with UUID as the stable
     * tiebreak. MAX categories require a positive best value; MIN categories may legitimately
     * award zero (for example, least damage taken after the playtime eligibility filter).
     */
    public static Resolution resolve(List<Candidate> input, Order order) {
        if (input.isEmpty()) {
            return new Resolution(List.of(), List.of(), 0L);
        }
        List<Candidate> candidates = new ArrayList<>(input);
        Comparator<Candidate> comparator = Comparator.comparingLong(Candidate::value);
        if (order == Order.MAX) {
            comparator = comparator.reversed();
        }
        comparator = comparator.thenComparing(Candidate::uuid);
        candidates.sort(comparator);

        long best = candidates.getFirst().value();
        if (order == Order.MAX && best <= 0L) {
            return new Resolution(candidates, List.of(), best);
        }
        List<UUID> winners = new ArrayList<>();
        for (Candidate candidate : candidates) {
            if (candidate.value() != best) {
                break;
            }
            winners.add(candidate.uuid());
        }
        return new Resolution(candidates, winners, best);
    }

    /** Per-winner integer share: ceil(total / winners), with a minimum of one for positive rewards. */
    public static int splitReward(int total, int winners) {
        if (total <= 0 || winners <= 0) {
            return 0;
        }
        return Math.max(1, (total + winners - 1) / winners);
    }

    /** Ensures a selection contains distinct ids (used by config validation and tests). */
    public static boolean allDistinct(List<String> ids) {
        return new HashSet<>(ids).size() == ids.size();
    }

    private static long mix64(long value) {
        value ^= value >>> 30;
        value *= 0xBF58476D1CE4E5B9L;
        value ^= value >>> 27;
        value *= 0x94D049BB133111EBL;
        return value ^ (value >>> 31);
    }
}
