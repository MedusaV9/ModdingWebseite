package dev.projecteclipse.eclipse.progression;

import net.minecraft.network.protocol.game.ClientboundContainerSetSlotPacket;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.inventory.AbstractContainerMenu;
import net.minecraft.world.inventory.CraftingContainer;
import net.minecraft.world.inventory.ResultContainer;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.crafting.CraftingRecipe;
import net.minecraft.world.item.crafting.RecipeHolder;
import net.minecraft.world.item.crafting.RecipeType;

/**
 * EVAL-DOPA-S #1: server-authoritative craft-gate enforcement at the MENU level, shared by
 * the {@code gameplay.mixin} seams. The legacy {@code PlayerEvent.ItemCraftedEvent} shrink in
 * {@link RecipeGate}/{@link ModGate} fires from the result slot's post-take path — vanilla
 * quick-move transfers the output into the destination inventory BEFORE {@code Slot.onTake},
 * so shift-click (and recipe-book-then-shift-click) retained locked results, and the vanilla
 * Crafter never fires a player craft event at all. These predicates run where the result is
 * COMPUTED instead, so a gated result never materializes in the result slot server-side:
 *
 * <ul>
 *   <li>{@link #isCraftResultLockedFor} — {@code CraftingMenu.slotChangedCraftingGrid} TAIL
 *       (covers the 3×3 table AND the 2×2 inventory grid, every click flavor and automation
 *       driving a player menu). Checks the per-player union ({@link RecipeGate#isItemLockedFor}
 *       — day tiers ∪ collections provider locks), the ModGate item lock, and the previously
 *       EMI-only config {@code recipes} ids.</li>
 *   <li>{@link #isRecipePlacementLockedFor} — {@code RecipeBookMenu.handlePlacement} HEAD:
 *       the server half of the recipe-book ghost fill / fill-grid button refuses to move
 *       ingredients for a gated recipe (belt-and-braces; the result guard above would empty
 *       the output anyway).</li>
 *   <li>{@link #isAutomationCraftLocked} — {@code CrafterBlock.dispenseFrom} HEAD. Automated
 *       crafting policy: no player context exists, so the Crafter obeys the GLOBAL gates
 *       (day-tier item/recipe locks + ModGate); per-player collection locks deliberately do
 *       not bind furniture.</li>
 * </ul>
 *
 * <p>The {@code ItemCraftedEvent} handlers stay as the backstop for surfaces without a seam
 * here (smithing, modded menus).</p>
 */
public final class CraftGateEnforcement {
    private CraftGateEnforcement() {}

    /**
     * Whether this player may NOT receive {@code result} from the given crafting grid right
     * now (per-player recipe locks ∪ ModGate ∪ config recipe-id locks). Creative players
     * bypass, matching the event-based confiscation policy.
     */
    public static boolean isCraftResultLockedFor(ServerPlayer player, CraftingContainer grid,
            ItemStack result) {
        if (result.isEmpty() || !player.gameMode.isSurvival()) {
            return false;
        }
        if (RecipeGate.isItemLockedFor(player, result) || ModGate.isItemLocked(player.server, result)) {
            return true;
        }
        // Config `recipes` entries (previously EMI-hiding only): resolve the grid's recipe
        // only when the day config actually declares recipe ids — the lookup is not free.
        if (RecipeGate.hasRecipeIdLocks(player.server)) {
            var recipe = player.server.getRecipeManager()
                    .getRecipeFor(RecipeType.CRAFTING, grid.asCraftInput(), player.level());
            return recipe.isPresent() && RecipeGate.isRecipeIdLocked(player.server, recipe.get().id());
        }
        return false;
    }

    /** Recipe-book placement guard (server half of the ghost fill / fill-grid button). */
    public static boolean isRecipePlacementLockedFor(ServerPlayer player, RecipeHolder<?> recipe) {
        if (!player.gameMode.isSurvival()) {
            return false;
        }
        if (RecipeGate.isRecipeIdLocked(player.server, recipe.id())) {
            return true;
        }
        ItemStack result = recipe.value().getResultItem(player.server.registryAccess());
        return !result.isEmpty()
                && (RecipeGate.isItemLockedFor(player, result)
                        || ModGate.isItemLocked(player.server, result));
    }

    /** Automation (Crafter) policy: GLOBAL day-tier item/recipe locks + ModGate only. */
    public static boolean isAutomationCraftLocked(MinecraftServer server,
            RecipeHolder<CraftingRecipe> recipe) {
        if (RecipeGate.isRecipeIdLocked(server, recipe.id())) {
            return true;
        }
        ItemStack result = recipe.value().getResultItem(server.registryAccess());
        return !result.isEmpty()
                && (RecipeGate.isItemLocked(server, result) || ModGate.isItemLocked(server, result));
    }

    /**
     * Confiscates a gated grid result: empties result slot 0 server-side and resyncs the
     * client view immediately, mirroring the tail of vanilla
     * {@code slotChangedCraftingGrid} (which already sent the pre-guard stack one line
     * earlier — {@code setItem} + {@code setRemoteSlot} + slot packet), then plays the
     * locked-craft hint.
     */
    public static void revokeGridResult(AbstractContainerMenu menu, ServerPlayer player,
            ResultContainer resultContainer, ItemStack lockedResult) {
        resultContainer.setItem(0, ItemStack.EMPTY);
        menu.setRemoteSlot(0, ItemStack.EMPTY);
        player.connection.send(new ClientboundContainerSetSlotPacket(
                menu.containerId, menu.incrementStateId(), 0, ItemStack.EMPTY));
        RecipeGate.hintLocked(player, lockedResult);
    }
}
