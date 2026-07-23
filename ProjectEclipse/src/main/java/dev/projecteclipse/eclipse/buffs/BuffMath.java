package dev.projecteclipse.eclipse.buffs;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import javax.annotation.Nullable;

/**
 * Pure buff decision math (P4-B9 gametest surface). All time values are epoch millis.
 */
public final class BuffMath {
    private BuffMath() {}

    public record ActiveBuff(String id, long endsAtEpochMillis, float magnitude, long lastPeriodicEpochMillis) {
        public ActiveBuff(String id, long endsAtEpochMillis, float magnitude) {
            this(id, endsAtEpochMillis, magnitude, 0L);
        }
    }

    /** Removes entries whose {@code endsAtEpochMillis} is strictly before {@code nowEpochMillis}. */
    public static List<ActiveBuff> pruneExpired(List<ActiveBuff> active, long nowEpochMillis) {
        return active.stream()
                .filter(b -> b.endsAtEpochMillis() > nowEpochMillis)
                .toList();
    }

    /**
     * Product of active multiplier buff magnitudes whose definition tag matches {@code tag}.
     * Unknown ids are skipped. Returns {@code 1.0f} when none apply.
     */
    public static float multiplierProduct(List<ActiveBuff> active, Map<String, BuffConfig.BuffDefinition> defs,
            String tag, long nowEpochMillis) {
        float product = 1.0F;
        for (ActiveBuff buff : active) {
            if (buff.endsAtEpochMillis() <= nowEpochMillis) {
                continue;
            }
            BuffConfig.BuffDefinition def = defs.get(buff.id());
            if (def == null || !(def.effect() instanceof BuffConfig.MultiplierEffect mult)) {
                continue;
            }
            if (mult.tag().equals(tag)) {
                float magnitude = buff.magnitude() > 0.0F ? buff.magnitude() : mult.value();
                product *= magnitude;
            }
        }
        return product;
    }

    public static boolean isActive(List<ActiveBuff> active, String id, long nowEpochMillis) {
        for (ActiveBuff buff : active) {
            if (buff.id().equals(id) && buff.endsAtEpochMillis() > nowEpochMillis) {
                return true;
            }
        }
        return false;
    }

    /**
     * Attempts to start or extend a buff. Returns {@code null} on refusal, otherwise the new active list.
     */
    @Nullable
    public static List<ActiveBuff> applyStart(List<ActiveBuff> active, BuffConfig.BuffDefinition def,
            int maxActive, int minutesOverride, float magnitudeOverride, long nowEpochMillis) {
        active = pruneExpired(active, nowEpochMillis);
        int minutes = minutesOverride > 0 ? minutesOverride : def.defaultMinutes();
        long durationMillis = minutes * 60_000L;
        float magnitude = magnitudeOverride > 0.0F ? magnitudeOverride : defaultMagnitude(def);

        int existingIndex = indexOf(active, def.id());
        if (existingIndex >= 0) {
            if (def.stack() == BuffConfig.StackRule.REFUSE) {
                return null;
            }
            ActiveBuff existing = active.get(existingIndex);
            long newEnds = existing.endsAtEpochMillis() + durationMillis;
            List<ActiveBuff> copy = new ArrayList<>(active);
            copy.set(existingIndex, new ActiveBuff(def.id(), newEnds, magnitude, existing.lastPeriodicEpochMillis()));
            return List.copyOf(copy);
        }

        if (active.size() >= maxActive) {
            return null;
        }

        long endsAt = nowEpochMillis + durationMillis;
        List<ActiveBuff> copy = new ArrayList<>(active);
        copy.add(new ActiveBuff(def.id(), endsAt, magnitude, 0L));
        return List.copyOf(copy);
    }

    public static List<ActiveBuff> applyStop(List<ActiveBuff> active, String id, long nowEpochMillis) {
        active = pruneExpired(active, nowEpochMillis);
        List<ActiveBuff> copy = new ArrayList<>();
        boolean removed = false;
        for (ActiveBuff buff : active) {
            if (!removed && buff.id().equals(id)) {
                removed = true;
                continue;
            }
            copy.add(buff);
        }
        return removed ? List.copyOf(copy) : null;
    }

    private static int indexOf(List<ActiveBuff> active, String id) {
        for (int i = 0; i < active.size(); i++) {
            if (active.get(i).id().equals(id)) {
                return i;
            }
        }
        return -1;
    }

    private static float defaultMagnitude(BuffConfig.BuffDefinition def) {
        if (def.effect() instanceof BuffConfig.MultiplierEffect mult) {
            return mult.value();
        }
        return 1.0F;
    }
}
