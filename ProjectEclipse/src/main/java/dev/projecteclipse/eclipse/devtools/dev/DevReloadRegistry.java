package dev.projecteclipse.eclipse.devtools.dev;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * Additive P5 config reload hooks invoked from {@link DevReload} (step 4).
 * Loaders for {@code xboxevent.json}, {@code music.json}, {@code modgate_ids.json}, etc. self-register here.
 */
public final class DevReloadRegistry {
    private static final List<NamedHook> HOOKS = new CopyOnWriteArrayList<>();

    private DevReloadRegistry() {}

    public record NamedHook(String label, Runnable reload) {}

    public static void register(String label, Runnable reload) {
        HOOKS.add(new NamedHook(label, reload));
    }

    static List<NamedHook> hooks() {
        return List.copyOf(HOOKS);
    }
}
