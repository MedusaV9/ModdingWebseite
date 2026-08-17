package de.sonic0810.goobymod.entity;

import java.util.Locale;
import javax.annotation.Nullable;

/**
 * Trainable full-body tricks. Enum names are stable NBT and command
 * identifiers; new tricks are appended so persisted ordinals stay valid.
 */
public enum GoobyTrick {
    SPIN("trick_spin", 28),
    HIGH_FIVE("trick_high_five", 30),
    FLOP("trick_flop", 42),
    SPEAK("trick_speak", 24),
    ROLL("trick_roll", 34),
    DANCE("trick_dance", 46);

    private final String animation;
    private final int durationTicks;

    GoobyTrick(String animation, int durationTicks) {
        this.animation = animation;
        this.durationTicks = durationTicks;
    }

    public GoobyTrick next() {
        GoobyTrick[] values = values();
        return values[(ordinal() + 1) % values.length];
    }

    public String serializedName() {
        return name().toLowerCase(Locale.ROOT);
    }

    public String translationKey() {
        return "trick.goobymod." + serializedName();
    }

    public String descriptionKey() {
        return translationKey() + ".description";
    }

    public String animation() {
        return animation;
    }

    public int durationTicks() {
        return durationTicks;
    }

    public static GoobyTrick byName(String name) {
        GoobyTrick strict = byNameStrict(name);
        return strict != null ? strict : SPIN;
    }

    /**
     * Strict lookup for command parsing: unknown names yield {@code null}
     * instead of silently falling back to {@link #SPIN}.
     */
    @Nullable
    public static GoobyTrick byNameStrict(String name) {
        for (GoobyTrick trick : values()) {
            if (trick.serializedName().equalsIgnoreCase(name)) {
                return trick;
            }
        }
        return null;
    }

    public static GoobyTrick byId(int id) {
        GoobyTrick[] values = values();
        return id >= 0 && id < values.length ? values[id] : SPIN;
    }

    /**
     * Strict lookup for network decoding: unknown ids yield {@code null}
     * instead of silently falling back to {@link #SPIN}.
     */
    @Nullable
    public static GoobyTrick byIdStrict(int id) {
        GoobyTrick[] values = values();
        return id >= 0 && id < values.length ? values[id] : null;
    }
}
