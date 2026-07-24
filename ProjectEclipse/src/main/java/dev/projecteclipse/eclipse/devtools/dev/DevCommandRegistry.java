package dev.projecteclipse.eclipse.devtools.dev;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;

import javax.annotation.Nullable;

import net.minecraft.server.level.ServerPlayer;

/**
 * Insertion-ordered single source of truth for dev command documentation and handbook data.
 * Parallel workers register their {@link DevCommandDoc} entries from static initializers;
 * the registry freezes on {@link #freeze()} (called at server start).
 */
public final class DevCommandRegistry {
    private static final Map<String, DevCommandDoc> BY_ID = new LinkedHashMap<>();
    private static final List<DevCommandDoc> ORDER = new ArrayList<>();
    private static volatile boolean frozen;

    private DevCommandRegistry() {}

    /**
     * Registers one or more command docs. Duplicate {@code id} values throw.
     * No-op after {@link #freeze()}.
     */
    public static void register(DevCommandDoc... docs) {
        Objects.requireNonNull(docs, "docs");
        if (frozen) {
            throw new IllegalStateException("DevCommandRegistry is frozen — cannot register " + docs.length + " doc(s)");
        }
        for (DevCommandDoc doc : docs) {
            Objects.requireNonNull(doc, "doc");
            if (BY_ID.containsKey(doc.id())) {
                throw new IllegalArgumentException("Duplicate DevCommandDoc id: " + doc.id());
            }
            BY_ID.put(doc.id(), doc);
            ORDER.add(doc);
        }
    }

    /** Returns an unmodifiable view of all registered docs (insertion order). */
    public static List<DevCommandDoc> all() {
        return Collections.unmodifiableList(ORDER);
    }

    /** Docs the given permission level may see (server-side filter). */
    public static List<DevCommandDoc> visibleTo(int permissionLevel) {
        return ORDER.stream().filter(doc -> doc.visibleTo(permissionLevel)).toList();
    }

    /** Docs visible to an online player (uses their command permission level). */
    public static List<DevCommandDoc> visibleTo(ServerPlayer player) {
        var stack = player.createCommandSourceStack();
        int perm = stack.hasPermission(3) ? 3 : 2;
        return visibleTo(perm);
    }

    public static Optional<DevCommandDoc> byId(String id) {
        return Optional.ofNullable(BY_ID.get(id));
    }

    /**
     * Finds the longest registered doc whose {@code syntax} is a prefix of {@code commandLine}
     * (used by handbook run validation in P5-W2).
     */
    public static Optional<DevCommandDoc> matchSyntaxPrefix(String commandLine) {
        if (commandLine == null || commandLine.isBlank()) {
            return Optional.empty();
        }
        String normalized = commandLine.strip();
        if (!normalized.startsWith("/")) {
            normalized = "/" + normalized;
        }
        DevCommandDoc best = null;
        int bestLen = -1;
        for (DevCommandDoc doc : ORDER) {
            String syntax = doc.syntax();
            if (normalized.equals(syntax) || normalized.startsWith(syntax + " ")) {
                if (syntax.length() > bestLen) {
                    best = doc;
                    bestLen = syntax.length();
                }
            }
        }
        return Optional.ofNullable(best);
    }

    public static List<DevCommandDoc> byCategory(DevCategory category) {
        return ORDER.stream().filter(doc -> doc.category() == category).toList();
    }

    public static List<DevCommandDoc> byCategory(DevCategory category, int permissionLevel) {
        return ORDER.stream()
                .filter(doc -> doc.category() == category && doc.visibleTo(permissionLevel))
                .toList();
    }

    /** @return category names suitable for {@code /dev help <category>} tab completion */
    public static Iterable<String> categoryNames() {
        List<String> names = new ArrayList<>();
        for (DevCategory cat : DevCategory.values()) {
            names.add(cat.name().toLowerCase(Locale.ROOT));
        }
        return names;
    }

    @Nullable
    public static DevCategory parseCategory(String name) {
        if (name == null || name.isBlank()) {
            return null;
        }
        try {
            return DevCategory.valueOf(name.strip().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    public static boolean isFrozen() {
        return frozen;
    }

    /** Locks the registry; further {@link #register} calls throw. */
    public static void freeze() {
        frozen = true;
    }

    /** Test-only reset (not used in production). */
    static void resetForTesting() {
        BY_ID.clear();
        ORDER.clear();
        frozen = false;
    }
}
