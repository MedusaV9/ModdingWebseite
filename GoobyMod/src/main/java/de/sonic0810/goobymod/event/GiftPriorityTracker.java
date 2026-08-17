package de.sonic0810.goobymod.event;

import de.sonic0810.goobymod.entity.GoobyEntity;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import net.minecraft.world.entity.item.ItemEntity;

/**
 * Gezielte Ablauf-Verwaltung des Geschenk-/Ball-Prioritaetsfensters
 * ({@link GoobyEntity#GIFT_PRIORITY_UNTIL_TAG}).
 *
 * <p>Ersetzt seit 5.3 den globalen {@code EntityTickEvent.Post}-Hook, der fuer
 * JEDES ItemEntity der Welt pro Tick lief (Architektur-Audit-Hotspot). Statt
 * dessen registriert der {@code EntityJoinLevelEvent}-Hook nur die wenigen
 * tatsaechlich markierten Drops — beim Spawn durch Gooby/Ballwurf genauso wie
 * beim Chunk-Reload bereits persistierter Drops, denn beide Pfade laufen durch
 * denselben Join-Event. Ein einziger Server-Tick-Sweep ueber diese kleine,
 * selbstbereinigende Liste stellt das identische Verhalten sicher: nach Ablauf
 * des Fensters werden Vanilla-Target und Marker-Tag entfernt.
 *
 * <p>Bounded per Konstruktion: Eintraege verschwinden beim Ablauf, beim
 * Entfernen/Entladen der Entity (naechster Sweep) und beim Server-Stopp.
 * Nur Server-Thread — keine Synchronisation noetig.
 */
public final class GiftPriorityTracker {
    private static final List<ItemEntity> TRACKED = new ArrayList<>();

    private GiftPriorityTracker() {
    }

    /** Join-Hook: nimmt nur serverseitige Drops mit aktivem Prioritaetsfenster auf. */
    public static void trackIfPrioritized(ItemEntity item) {
        if (item.level().isClientSide || item.getTarget() == null
                || item.getPersistentData().getLong(GoobyEntity.GIFT_PRIORITY_UNTIL_TAG) <= 0L) {
            return;
        }
        // Entity-Identitaet: derselbe Drop kann nach Dimensionswechsel erneut joinen.
        for (ItemEntity tracked : TRACKED) {
            if (tracked == item) {
                return;
            }
        }
        TRACKED.add(item);
    }

    /** Server-Tick-Sweep: laeuft NUR ueber registrierte Drops, nie ueber alle Entities. */
    public static void tickServer() {
        if (TRACKED.isEmpty()) {
            return;
        }
        Iterator<ItemEntity> iterator = TRACKED.iterator();
        while (iterator.hasNext()) {
            ItemEntity item = iterator.next();
            if (item.isRemoved() || item.getTarget() == null) {
                iterator.remove();
                continue;
            }
            long priorityUntil = item.getPersistentData().getLong(GoobyEntity.GIFT_PRIORITY_UNTIL_TAG);
            if (priorityUntil <= 0L) {
                iterator.remove();
            } else if (item.level().getGameTime() >= priorityUntil) {
                item.setTarget(null);
                item.getPersistentData().remove(GoobyEntity.GIFT_PRIORITY_UNTIL_TAG);
                iterator.remove();
            }
        }
    }

    public static void clear() {
        TRACKED.clear();
    }

    public static boolean isTrackedForTest(ItemEntity item) {
        for (ItemEntity tracked : TRACKED) {
            if (tracked == item) {
                return true;
            }
        }
        return false;
    }

    public static int trackedCountForTest() {
        return TRACKED.size();
    }
}
