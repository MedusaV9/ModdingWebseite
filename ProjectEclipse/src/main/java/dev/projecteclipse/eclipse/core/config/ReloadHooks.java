package dev.projecteclipse.eclipse.core.config;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

import dev.projecteclipse.eclipse.EclipseMod;

/**
 * Registry of idempotent config-reload callbacks invoked at the end of
 * {@link EclipseConfig#reload()}. Every P4 config loader registers here so
 * {@code /eclipse reload} and P5's {@code /dev reload} pick up balance changes
 * without touching {@code EclipseCommands}.
 *
 * <p>Hooks are executed in registration order. A failing hook is logged and
 * skipped; remaining hooks still run.</p>
 */
public final class ReloadHooks {
    private record Entry(String name, Runnable hook) {}

    private static final List<Entry> HOOKS = new CopyOnWriteArrayList<>();

    private ReloadHooks() {}

    /**
     * Registers a named reload hook. Duplicate names are allowed (each registration
     * is independent) but callers should use stable, unique ids for log clarity.
     *
     * @param name human-readable hook id (appears in error logs)
     * @param hook idempotent reload body; must not throw under normal conditions
     */
    public static void register(String name, Runnable hook) {
        HOOKS.add(new Entry(name, hook));
    }

    /**
     * Runs every registered hook. Called once at the tail of {@link EclipseConfig#reload()}.
     * Exceptions are caught per hook so one broken config cannot block the rest.
     */
    public static void runAll() {
        for (Entry entry : HOOKS) {
            try {
                entry.hook().run();
            } catch (Exception e) {
                EclipseMod.LOGGER.error("Reload hook '{}' failed; continuing with remaining hooks", entry.name(), e);
            }
        }
    }

    /**
     * Clears all hooks. Test-only — production hooks live for the JVM lifetime and are
     * re-registered on each {@link net.neoforged.neoforge.event.server.ServerStartedEvent}.
     */
    static void clearForTests() {
        HOOKS.clear();
    }
}
