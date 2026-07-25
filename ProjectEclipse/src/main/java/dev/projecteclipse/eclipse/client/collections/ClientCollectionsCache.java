package dev.projecteclipse.eclipse.client.collections;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.network.collections.CollectionsPayloads;
import dev.projecteclipse.eclipse.network.collections.S2CCollectionDeltaPayload;
import dev.projecteclipse.eclipse.network.collections.S2CCollectionsPayload;
import dev.projecteclipse.eclipse.network.collections.S2CItemLexiconPayload;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;

/**
 * Client cache of the D1 collections snapshot ({@code ClientBestiaryCache} pattern: the
 * {@code Dist.CLIENT} subscriber annotation loads the class on client startup, the static
 * initializer installs the {@link CollectionsPayloads} consumers so the registrar never
 * references client classes, and the logout hook resets state so one server's progress
 * never leaks into the next session).
 *
 * <p>Definitions AND progress arrive together (full {@link S2CCollectionsPayload} on
 * login / tier grant / config reload; cheap {@link S2CCollectionDeltaPayload}s for plain
 * counter moves) — the tab renders exactly what the server enforces, including live
 * {@code collections.json} edits. Tier-up payloads route to
 * {@link CollectionTierToast#enqueue}, keeping this class presentation-free.</p>
 *
 * <p>Reads are volatile-map lookups; {@link #generation()} bumps on every change so
 * {@code CollectionsTab} can cache its layout between frames.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ClientCollectionsCache {
    /** One collection as last synced: definition + this player's progress. */
    public record Entry(String id, String category, String icon,
            List<S2CCollectionsPayload.Tier> tiers, long count, int grantedTier) {

        /** Whether every tier has been granted. */
        public boolean maxed() {
            return grantedTier >= tiers.size();
        }

        /** The next not-yet-granted tier, or {@code null} when maxed. */
        public S2CCollectionsPayload.Tier nextTier() {
            return maxed() ? null : tiers.get(grantedTier);
        }

        /** Threshold of the last granted tier (progress-bar floor); 0 below tier I. */
        public long previousThreshold() {
            return grantedTier <= 0 ? 0L : tiers.get(grantedTier - 1).threshold();
        }
    }

    /** Insertion-ordered (config order == authoring order per category). */
    private static volatile Map<String, Entry> entries = Map.of();
    /** uipolish item lexicon: discovered roster ids in discovery order (server-synced). */
    private static volatile Set<String> discoveredItems = Set.of();
    private static volatile int generation;

    static {
        // Payload consumer seam (ClientBestiaryCache pattern): installed on client class-load.
        CollectionsPayloads.setSnapshotHandler(ClientCollectionsCache::updateSnapshot);
        CollectionsPayloads.setDeltaHandler(ClientCollectionsCache::updateDelta);
        CollectionsPayloads.setTierHandler(CollectionTierToast::enqueue);
        CollectionsPayloads.setLexiconHandler(ClientCollectionsCache::updateLexicon);
    }

    private ClientCollectionsCache() {}

    /** All synced collections in config order (empty before the first snapshot). */
    public static List<Entry> all() {
        return List.copyOf(entries.values());
    }

    /** One collection by id, or {@code null} when never synced. */
    public static Entry byId(String id) {
        return entries.get(id);
    }

    /** Monotonic counter bumped on every snapshot/delta/reset — include in layout caches. */
    public static int generation() {
        return generation;
    }

    /** uipolish: whether this item-lexicon roster id has been carried at least once. */
    public static boolean itemDiscovered(String itemId) {
        return discoveredItems.contains(itemId);
    }

    /** uipolish: number of discovered item-lexicon entries (rail fraction). */
    public static int discoveredItemCount() {
        return discoveredItems.size();
    }

    /**
     * Display name with graceful degradation (langdrop may land after the feature):
     * {@code collection.eclipse.<id>} → prettified id — never a raw key.
     */
    public static String displayName(String id) {
        String key = "collection.eclipse." + id;
        return EclipseLang.hasKey(key) ? EclipseLang.trString(key) : prettifyId(id);
    }

    /**
     * Unlock-entry display name (toast line 2 + tab reward preview): item ids resolve to
     * the localized item name, {@code #tag} entries prettify their path — never a raw id.
     */
    public static String unlockName(String entry) {
        if (entry.startsWith("#")) {
            return prettifyId(entry.substring(1));
        }
        ResourceLocation id = ResourceLocation.tryParse(entry);
        if (id != null && BuiltInRegistries.ITEM.containsKey(id)) {
            return BuiltInRegistries.ITEM.get(id).getDescription().getString();
        }
        return prettifyId(entry);
    }

    /** {@code rotten_flesh} → "Rotten Flesh" (last-resort fallback). */
    public static String prettifyId(String id) {
        String path = id.contains(":") ? id.substring(id.indexOf(':') + 1) : id;
        StringBuilder pretty = new StringBuilder(path.length());
        for (String word : path.split("_")) {
            if (word.isEmpty()) {
                continue;
            }
            if (pretty.length() > 0) {
                pretty.append(' ');
            }
            pretty.append(word.substring(0, 1).toUpperCase(Locale.ROOT)).append(word.substring(1));
        }
        return pretty.isEmpty() ? path : pretty.toString();
    }

    /** Runs on the client main thread (payload handler). */
    private static void updateSnapshot(S2CCollectionsPayload payload) {
        Map<String, Entry> updated = new LinkedHashMap<>(payload.entries().size());
        for (S2CCollectionsPayload.Entry entry : payload.entries()) {
            updated.put(entry.id(), new Entry(entry.id(), entry.category(), entry.icon(),
                    entry.tiers(), entry.count(), entry.grantedTier()));
        }
        entries = Collections.unmodifiableMap(updated);
        generation++;
    }

    /** Full discovered-set replace (tiny payload — no delta protocol needed). */
    private static void updateLexicon(S2CItemLexiconPayload payload) {
        discoveredItems = Collections.unmodifiableSet(new LinkedHashSet<>(payload.discovered()));
        generation++;
    }

    /** Counter-only move; unknown ids are dropped (snapshot will follow on next grant). */
    private static void updateDelta(S2CCollectionDeltaPayload payload) {
        Entry old = entries.get(payload.collectionId());
        if (old == null || old.count() == payload.newCount()) {
            return;
        }
        Map<String, Entry> updated = new LinkedHashMap<>(entries);
        updated.put(old.id(), new Entry(old.id(), old.category(), old.icon(), old.tiers(),
                payload.newCount(), old.grantedTier()));
        entries = Collections.unmodifiableMap(updated);
        generation++;
    }

    /** Disconnect reset — collections progress never leaks into the next session. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        entries = Map.of();
        discoveredItems = Set.of();
        generation++;
        CollectionTierToast.reset();
    }

    /** Category display order for the tab rail (config authoring order, §3). */
    public static List<String> categoryOrder() {
        List<String> order = new ArrayList<>();
        for (Entry entry : entries.values()) {
            if (!order.contains(entry.category())) {
                order.add(entry.category());
            }
        }
        return order;
    }
}
