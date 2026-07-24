package dev.projecteclipse.eclipse.gameplay.mixin;

import javax.annotation.Nullable;

import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

import dev.projecteclipse.eclipse.progression.CraftGateEnforcement;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.inventory.AbstractContainerMenu;
import net.minecraft.world.inventory.CraftingContainer;
import net.minecraft.world.inventory.CraftingMenu;
import net.minecraft.world.inventory.ResultContainer;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.crafting.CraftingRecipe;
import net.minecraft.world.item.crafting.RecipeHolder;
import net.minecraft.world.level.Level;

/**
 * EVAL-DOPA-S #1 result-slot guard: after vanilla computes the crafting result, a gated
 * stack is emptied BEFORE any pickup/quick-move path can read it — the shift-click and
 * recipe-book bypasses of the post-take {@code ItemCraftedEvent} shrink can no longer
 * retain locked output. {@code InventoryMenu.slotsChanged} delegates to this same static,
 * so the 2×2 player grid is covered too. Policy lives in
 * {@link CraftGateEnforcement#isCraftResultLockedFor}; this mixin is only the seam.
 */
@Mixin(CraftingMenu.class)
public abstract class CraftingMenuMixin {
    @Inject(method = "slotChangedCraftingGrid", at = @At("TAIL"))
    private static void eclipse$guardGatedResult(AbstractContainerMenu menu, Level level,
            Player player, CraftingContainer craftSlots, ResultContainer resultSlots,
            @Nullable RecipeHolder<CraftingRecipe> recipe, CallbackInfo callbackInfo) {
        if (level.isClientSide || !(player instanceof ServerPlayer serverPlayer)) {
            return;
        }
        ItemStack result = resultSlots.getItem(0);
        if (!result.isEmpty()
                && CraftGateEnforcement.isCraftResultLockedFor(serverPlayer, craftSlots, result)) {
            CraftGateEnforcement.revokeGridResult(menu, serverPlayer, resultSlots, result.copy());
        }
    }
}
