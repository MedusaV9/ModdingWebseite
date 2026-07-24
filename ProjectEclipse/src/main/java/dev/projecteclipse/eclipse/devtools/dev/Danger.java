package dev.projecteclipse.eclipse.devtools.dev;

/**
 * Operator-facing severity for a dev command (handbook badge + confirm dialog).
 */
public enum Danger {
    SAFE,
    CAUTION,
    DESTRUCTIVE;

    /** Lang key: {@code dev.eclipse.danger.<name lowercase>}. */
    public String langKey() {
        return "dev.eclipse.danger." + name().toLowerCase();
    }
}
