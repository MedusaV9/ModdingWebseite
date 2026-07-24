package dev.projecteclipse.eclipse.devtools.dev;

/**
 * Lightweight acceptance checks for {@link DevCommandRegistry} (P5-W1). Callable from future
 * GameTest harness once P4-A1 lands {@code eclipse:gametest.empty}.
 */
public final class DevCommandRegistrySelfCheck {
    private DevCommandRegistrySelfCheck() {}

    /**
     * @throws IllegalStateException when perm-2 visibility includes perm-3-only entries
     */
    public static void assertVisibleToFiltersPermission() {
        for (DevCommandDoc doc : DevCommandRegistry.all()) {
            if (doc.permission() >= 3 && DevCommandRegistry.visibleTo(2).contains(doc)) {
                throw new IllegalStateException(
                        "Perm-2 visibleTo included perm-" + doc.permission() + " doc: " + doc.id());
            }
        }
    }
}
