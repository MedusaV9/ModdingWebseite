package dev.projecteclipse.eclipse.progression;

import java.util.List;

import net.minecraft.server.MinecraftServer;
import net.minecraft.world.item.ItemStack;

/**
 * Public query surface for EMI / devtools (P3/P5). Delegates to {@link RecipeGate}.
 */
public final class RecipeGateApi {
    private RecipeGateApi() {}

    /** Whether crafting this stack's item is blocked on the current event day. */
    public static boolean isItemLocked(MinecraftServer server, ItemStack stack) {
        return RecipeGate.isItemLocked(server, stack);
    }

    /** Item registry ids currently locked (tags expanded) — feeds {@code S2CRecipeLocksPayload}. */
    public static List<String> lockedItemIds(MinecraftServer server) {
        return RecipeGate.lockedItemIds(server);
    }

    /** Recipe ids whose results are locked — feeds {@code S2CRecipeLocksPayload}. */
    public static List<String> lockedRecipeIds(MinecraftServer server) {
        return RecipeGate.lockedRecipeIds(server);
    }

    /** Re-broadcast lock state to every online player (e.g. after manual day set). */
    public static void rebroadcast(MinecraftServer server) {
        RecipeGate.broadcastAll(server);
    }
}
