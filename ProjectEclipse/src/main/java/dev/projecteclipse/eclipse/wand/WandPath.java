package dev.projecteclipse.eclipse.wand;

import java.util.Locale;

import javax.annotation.Nullable;

/**
 * The three skill paths of the Zauberstab (IDEA-19, F-036 rework) plus the pathless
 * {@link #NONE} state a freshly crafted wand starts in. Wire ids are stable ints
 * (stored in the {@code eclipse:wand_path} data component and in {@code WandStore});
 * never reorder.
 *
 * <p>F-039: the per-path spell ladders (10 spells each) live in {@link WandSpells}; the
 * per-path tree branches (16 nodes each) in {@link WandTree}. The old frozen power-key
 * arrays are gone with them. Path identity: RISS = Raum/Bewegung (void/glitch), GLUT =
 * Zerstörung (ember/magma), STERN = Schutz/Bindung (starlight/marks).</p>
 */
public enum WandPath {
    NONE(0),
    /** Phasenriss — Raum/Bewegung: blinks, pulls, gravity wells, the Umbra-Lanze. */
    RISS(1),
    /** Glutherz — Zerstörung: fire lances, waves, eruptions, the Inferno. */
    GLUT(2),
    /** Sternenfall — Schutz/Bindung: marks, shields, roots, celestial judgment. */
    STERN(3);

    /** Display-level cap (drives the GeckoLib model stages; derived from tree nodes). */
    public static final int MAX_LEVEL = 5;

    private final int id;

    WandPath(int id) {
        this.id = id;
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

    /** Lang key of the path display name ({@code wand.eclipse.path.<name>}). */
    public String langKey() {
        return "wand.eclipse.path." + name().toLowerCase(Locale.ROOT);
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
