package dev.projecteclipse.eclipse.client.emi;

import java.util.Set;

import dev.emi.emi.api.EmiEntrypoint;
import dev.emi.emi.api.EmiPlugin;
import dev.emi.emi.api.EmiRegistry;
import dev.emi.emi.api.recipe.EmiRecipe;
import dev.emi.emi.api.stack.EmiStack;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.progression.ClientUnlockCache;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.tags.TagKey;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;

/**
 * EMI integration (P3 §3.12, EMI 1.1.18+1.21.1 API): hides gated/dev content from EMI's
 * item index and recipe viewer. EMI discovers this class itself via its {@link EmiEntrypoint}
 * annotation scan (the NeoForge plugin mechanism — no service file, no code registration), so
 * when EMI is absent this class is simply never loaded; it is the ONLY Eclipse class with
 * compile-time EMI references, keeping any EMI version drift a single-file fix.
 *
 * <p>{@link #register(EmiRegistry)} runs on every EMI (re)bake — including the
 * {@code EmiReindexer}-triggered reloads after an unlock change — so all predicates read the
 * live {@link ClientUnlockCache} / {@link ClientStateCache} state at bake time. Hidden:</p>
 * <ol>
 *   <li>every stack (item OR fluid) whose id namespace is a currently-locked ModGate
 *       namespace (server-synced; reverses on unlock),</li>
 *   <li>every item in {@code #eclipse:emi_hidden} (172 classic souvenir blocks, the Display
 *       Wand and other dev/admin items — data file seeded by W11, extended by P4/P5),</li>
 *   <li>recipes whose id is RecipeGate-locked, whose id namespace is locked (belt+braces on
 *       top of EMI's own hidden-stack invalidation), or with a hidden/locked output.</li>
 * </ol>
 *
 * <p>Hiding is client cosmetics only — {@code progression.ModGate}/{@code RecipeGate} remain
 * the server-authoritative truth. Everything here is defensive: a throwing predicate would
 * abort EMI's bake, so lookups are null-guarded and the registration is wrapped.</p>
 */
@EmiEntrypoint
public final class EclipseEmiPlugin implements EmiPlugin {
    /** Always-hidden item tag ({@code data/eclipse/tags/item/emi_hidden.json}). */
    public static final TagKey<Item> EMI_HIDDEN = TagKey.create(Registries.ITEM,
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "emi_hidden"));

    /** Belt+braces id guard in case the tag file is ever trimmed: the wand is never indexable. */
    private static final ResourceLocation DISPLAY_WAND_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "display_wand");

    @Override
    public void register(EmiRegistry registry) {
        try {
            // Fresh per bake: RecipeGate's locked ids as O(1) sets (day-cadence data, synced
            // via S2CRecipeLocksPayload into ClientStateCache).
            Set<String> lockedRecipeIds = Set.copyOf(ClientStateCache.lockedRecipeIds);
            Set<String> lockedItemIds = Set.copyOf(ClientStateCache.lockedItemIds);

            registry.removeEmiStacks(EclipseEmiPlugin::isHiddenStack);
            registry.removeRecipes(recipe -> isHiddenRecipe(recipe, lockedRecipeIds, lockedItemIds));
            EclipseMod.LOGGER.debug("Eclipse EMI plugin registered (locked recipes: {}, locked items: {})",
                    lockedRecipeIds.size(), lockedItemIds.size());
        } catch (Throwable t) {
            // Never break EMI's bake: worst case the index shows locked content, the server
            // still rejects its use.
            EclipseMod.LOGGER.error("Eclipse EMI plugin registration failed — EMI index left unfiltered", t);
        }
    }

    private static boolean isHiddenStack(EmiStack stack) {
        try {
            if (stack == null || stack.isEmpty()) {
                return false;
            }
            ItemStack itemStack = stack.getItemStack();
            if (!itemStack.isEmpty() && itemStack.is(EMI_HIDDEN)) {
                return true;
            }
            ResourceLocation id = stack.getId();
            if (id == null) {
                return false;
            }
            return id.equals(DISPLAY_WAND_ID) || ClientUnlockCache.isNamespaceLocked(id.getNamespace());
        } catch (Throwable t) {
            return false;
        }
    }

    private static boolean isHiddenRecipe(EmiRecipe recipe, Set<String> lockedRecipeIds,
            Set<String> lockedItemIds) {
        try {
            if (recipe == null) {
                return false;
            }
            ResourceLocation id = recipe.getId();
            if (id != null && (lockedRecipeIds.contains(id.toString())
                    || ClientUnlockCache.isNamespaceLocked(id.getNamespace()))) {
                return true;
            }
            for (EmiStack output : recipe.getOutputs()) {
                if (output == null) {
                    continue;
                }
                if (isHiddenStack(output)) {
                    return true;
                }
                ResourceLocation outputId = output.getId();
                if (outputId != null && lockedItemIds.contains(outputId.toString())) {
                    return true;
                }
            }
            return false;
        } catch (Throwable t) {
            return false;
        }
    }
}
