package dev.projecteclipse.eclipse.wand;

import java.util.Locale;

import javax.annotation.Nullable;

/**
 * The three locked skill paths of the Zauberstab (IDEA-19 adapted per the W4-WAND spec) plus
 * the pathless {@link #NONE} state a freshly crafted wand starts in. Wire ids are stable ints
 * (stored in the {@code eclipse:wand_path} data component and in {@code WandStore}); never
 * reorder.
 *
 * <p>Power keys per path are frozen here so {@code WandConfig} entries, {@code WandPowers}
 * dispatch and the lang keys ({@code wand.eclipse.power.<path>.<index+1>}) all agree. Index
 * 0&ndash;4 unlock at wand levels 1&ndash;5; indices 3/4 re-run the level-2/3 powers with
 * their own (bigger/faster) config entries.</p>
 */
public enum WandPath {
    NONE(0, new String[0]),
    /** Phasenriss — void/glitch: Blink, Phasenwelle, Rissschlag (+ upgraded 2/3). */
    RISS(1, new String[] {"blink", "phasenwelle", "rissschlag", "phasenwelle_2", "rissschlag_2"}),
    /** Glutherz — fire: Glutstoß, Feuerwelle, Magmasprung (+ upgraded 2/3). */
    GLUT(2, new String[] {"glutstoss", "feuerwelle", "magmasprung", "feuerwelle_2", "magmasprung_2"}),
    /** Sternenfall — storm/cosmos: Funkenruf, Sternschauer, Kometenschlag (+ upgraded 2/3). */
    STERN(3, new String[] {"funkenruf", "sternschauer", "kometenschlag", "sternschauer_2", "kometenschlag_2"});

    public static final int MAX_LEVEL = 5;

    private final int id;
    private final String[] powerKeys;

    WandPath(int id, String[] powerKeys) {
        this.id = id;
        this.powerKeys = powerKeys;
    }

    public int id() {
        return id;
    }

    /** Stable wire id → path; unknown ids fall back to {@link #NONE}. */
    public static WandPath byId(int id) {
        for (WandPath path : values()) {
            if (path.id == id) {
                return path;
            }
        }
        return NONE;
    }

    /** Case-insensitive name parse ({@code /dev wand set ... path <name>}), or null. */
    @Nullable
    public static WandPath byName(String name) {
        if (name == null || name.isBlank()) {
            return null;
        }
        try {
            return valueOf(name.strip().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    /** Number of powers this path defines (0 for NONE). */
    public int powerCount() {
        return powerKeys.length;
    }

    /**
     * {@code WandConfig} entry key for the power at {@code index} (0-based, unlocks at wand
     * level {@code index + 1}), e.g. {@code "riss.phasenwelle"}.
     */
    public String powerKey(int index) {
        return name().toLowerCase(Locale.ROOT) + "." + powerKeys[index];
    }

    /** Lang key of the path display name ({@code wand.eclipse.path.<name>}). */
    public String langKey() {
        return "wand.eclipse.path." + name().toLowerCase(Locale.ROOT);
    }

    /** Lang key of the power display name at {@code index} ({@code wand.eclipse.power.<path>.<n>}). */
    public String powerLangKey(int index) {
        return "wand.eclipse.power." + name().toLowerCase(Locale.ROOT) + "." + (index + 1);
    }

    /**
     * Model evolution stage for a wand level: stage 1 at L1, stage 2 at L2&ndash;3, stage 3 at
     * L4&ndash;5. The renderer shows the path's {@code p_<path>_s1..sN} bone groups up to this
     * stage (see {@code client/wand/EclipseWandRenderer}).
     */
    public static int stageForLevel(int level) {
        if (level <= 1) {
            return 1;
        }
        return level <= 3 ? 2 : 3;
    }
}
