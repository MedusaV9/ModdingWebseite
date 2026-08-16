package de.sonic0810.goobymod.compat;

import net.neoforged.fml.ModList;

/**
 * Optional Curios boundary.
 *
 * <p>The charm-slot membership itself is data-driven through
 * {@code data/curios/tags/item/charm.json}; this guard keeps all future typed
 * API calls dormant when Curios is absent.</p>
 */
public final class CuriosCompat {
    public static boolean isLoaded() {
        return ModList.get().isLoaded("curios");
    }

    private CuriosCompat() {
    }
}
