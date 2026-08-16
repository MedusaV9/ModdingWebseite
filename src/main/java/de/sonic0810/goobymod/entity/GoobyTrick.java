package de.sonic0810.goobymod.entity;

import java.util.Locale;

/** Trainable full-body tricks. Enum names are stable NBT and command identifiers. */
public enum GoobyTrick {
    SPIN("trick_spin", 28),
    HIGH_FIVE("trick_high_five", 30),
    FLOP("trick_flop", 42),
    SPEAK("trick_speak", 24);

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
        for (GoobyTrick trick : values()) {
            if (trick.serializedName().equalsIgnoreCase(name)) {
                return trick;
            }
        }
        return SPIN;
    }

    public static GoobyTrick byId(int id) {
        GoobyTrick[] values = values();
        return id >= 0 && id < values.length ? values[id] : SPIN;
    }
}
