package de.sonic0810.goobymod.entity;

/**
 * Pfeifen-Kommandos fuer gezaehmte Goobys. Die Reihenfolge ist die
 * Durchschalt-Reihenfolge der Gooby-Pfeife; der Ordinal-Wert wird als Byte
 * synchronisiert und persistiert.
 */
public enum GoobyCommand {
    WANDER,
    FOLLOW,
    STAY;

    public GoobyCommand next() {
        GoobyCommand[] values = values();
        return values[(ordinal() + 1) % values.length];
    }

    public static GoobyCommand byId(int id) {
        GoobyCommand[] values = values();
        return id >= 0 && id < values.length ? values[id] : WANDER;
    }

    public String translationKey() {
        return "msg.goobymod.command_" + name().toLowerCase(java.util.Locale.ROOT);
    }

    public String nameTranslationKey() {
        return "command.goobymod." + name().toLowerCase(java.util.Locale.ROOT);
    }

    /** Private-use glyph from the Gooby icon font for audio-independent feedback. */
    public String icon() {
        return switch (this) {
            case WANDER -> "\uE000";
            case FOLLOW -> "\uE001";
            case STAY -> "\uE002";
        };
    }
}
