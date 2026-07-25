package dev.projecteclipse.eclipse.collections;

import java.util.List;
import java.util.Set;

/**
 * The item lexicon (uipolish "items need explanations"): the fixed roster of
 * player-obtainable CUSTOM items that earn a handbook Collections entry the first time a
 * player carries one. Shared definition class — {@link ItemLexiconService} (server) sweeps
 * inventories against it and persists discoveries in {@link CollectionsState};
 * {@code client.handbook.tabs.CollectionsTab} renders the roster as the "Items" category
 * (undiscovered rows stay glitch-anonymized "???", the timeline pattern).
 *
 * <p>Deliberately NOT config-driven like {@code collections.json}: the roster mirrors the
 * registry ({@code EclipseItems} / {@code WandItems} / {@code WizardEntities}), and each
 * entry's payload is a LANG line — the functional explanation under
 * {@link #descriptionKey}, beside the poetic {@code item.eclipse.<id>.lore} the items
 * already bake. Admin/op-only items (grave, altar, display_wand) are excluded on purpose;
 * renamed-vanilla props (almond water, wallpaper) have no registry id to track.</p>
 */
public final class ItemLexicon {
    /** Roster in display order — roughly the order players meet the items across the arc. */
    private static final List<String> ORDER = List.of(
            "eclipse:arm_artifact",
            "eclipse:umbral_shard",
            "eclipse:glitch_shard",
            "eclipse:heart_fragment",
            "eclipse:heart_extractor",
            "eclipse:vitae_shard",
            "eclipse:revive_sigil",
            "eclipse:grave_dowser",
            "eclipse:compass_of_watcher",
            "eclipse:umbral_pick",
            "eclipse:umbral_blade",
            "eclipse:wizard_catalyst",
            "eclipse:eclipse_wand",
            "eclipse:heralds_lure",
            "eclipse:herald_core",
            "eclipse:storm_heart",
            "eclipse:fog_core",
            "eclipse:fog_cloak_trim",
            "eclipse:ferryman_toll");

    private static final Set<String> IDS = Set.copyOf(ORDER);

    private ItemLexicon() {}

    /** The full roster in display order (fixed at compile time, same on both sides). */
    public static List<String> entries() {
        return ORDER;
    }

    /** Whether an item id earns a lexicon entry when first carried. */
    public static boolean tracked(String itemId) {
        return IDS.contains(itemId);
    }

    public static int size() {
        return ORDER.size();
    }

    /**
     * Lang key of one entry's functional explanation:
     * {@code eclipse:umbral_pick} → {@code collection.eclipse.item.umbral_pick}
     * (namespaced under {@code item.} so lexicon keys can never collide with the
     * {@code collection.eclipse.<collectionId>} display names).
     */
    public static String descriptionKey(String itemId) {
        String path = itemId.contains(":") ? itemId.substring(itemId.indexOf(':') + 1) : itemId;
        return "collection.eclipse.item." + path;
    }
}
