package de.sonic0810.goobymod.entity;

import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Set;

/**
 * Bounded Index aller aktuell GELADENEN serverseitigen Goobys.
 *
 * <p>Ersetzt seit 5.3 den Logout-All-Entities-Scan ueber saemtliche Level
 * (Architektur-Audit-Hotspot): {@code onPlayerLogout} musste bisher jede
 * geladene Entity jeder Dimension anfassen, nur um die Handvoll Goobys zu
 * finden. Der Index pflegt sich selbst ueber die symmetrischen
 * Level-Lifecycle-Hooks {@code onAddedToLevel}/{@code onRemovedFromLevel}
 * der {@link GoobyEntity} — Chunk-Load/-Unload, Discard, Tod und
 * Dimensionswechsel halten ihn automatisch exakt auf der Menge, die der
 * alte Scan gesehen haette.
 *
 * <p>Bounded per Konstruktion: nie mehr Eintraege als geladene Goobys, beim
 * Server-Stopp wird geleert. Nur Server-Thread — keine Synchronisation.
 */
public final class GoobyLoadedIndex {
    private static final Set<GoobyEntity> LOADED = Collections.newSetFromMap(new IdentityHashMap<>());

    private GoobyLoadedIndex() {
    }

    static void add(GoobyEntity gooby) {
        LOADED.add(gooby);
    }

    static void remove(GoobyEntity gooby) {
        LOADED.remove(gooby);
    }

    /** Schnappschuss fuer Iterationen, die Gooby-Zustand veraendern. */
    public static List<GoobyEntity> snapshot() {
        return List.copyOf(LOADED);
    }

    public static void clear() {
        LOADED.clear();
    }

    public static boolean containsForTest(GoobyEntity gooby) {
        return LOADED.contains(gooby);
    }

    public static int sizeForTest() {
        return LOADED.size();
    }
}
