package dev.projecteclipse.eclipse.devtools.dev;

/**
 * Single registry entry for a dev or legacy admin command. Shared by {@link DevCommandRegistry},
 * {@code /dev help}, {@link DevDocsExporter}, and the Dev Handbook GUI (P5-W2).
 *
 * @param id           stable dot-separated id, e.g. {@code timer.pause}
 * @param category     handbook grouping
 * @param syntax       literal Brigadier path, e.g. {@code /dev timer pause}
 * @param descKey      lang key (en+de) for the description
 * @param danger       SAFE / CAUTION / DESTRUCTIVE
 * @param clickAction  RUN vs SUGGEST for handbook + help clicks
 * @param permission   minimum op level (2 default, 3 for destructive leaves)
 * @param legacy       {@code true} for pre-{@code /dev} roots ({@code /eclipse}, reference trees)
 */
public record DevCommandDoc(
        String id,
        DevCategory category,
        String syntax,
        String descKey,
        Danger danger,
        ClickAction clickAction,
        int permission,
        boolean legacy) {

    public DevCommandDoc(String id, DevCategory category, String syntax, String descKey, Danger danger,
            ClickAction clickAction, int permission) {
        this(id, category, syntax, descKey, danger, clickAction, permission, false);
    }

    /** Whether {@code source} may see and run this entry. */
    public boolean visibleTo(int sourcePermission) {
        return sourcePermission >= permission;
    }
}
