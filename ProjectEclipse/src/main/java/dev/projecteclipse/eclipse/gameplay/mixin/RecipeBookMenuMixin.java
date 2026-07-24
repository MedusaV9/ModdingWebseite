package dev.projecteclipse.eclipse.gameplay.mixin;

import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

import dev.projecteclipse.eclipse.progression.CraftGateEnforcement;
import dev.projecteclipse.eclipse.progression.RecipeGate;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.inventory.RecipeBookMenu;
import net.minecraft.world.item.crafting.RecipeHolder;

/**
 * EVAL-DOPA-S #1 recipe-book guard: {@code handlePlacement} is the server handler behind
 * the recipe-book ghost fill / fill-grid button ({@code ServerboundPlaceRecipePacket}).
 * Gated recipes never get their ingredients moved into the grid; the player gets the same
 * locked-craft hint as a confiscated craft. The result-slot guard in
 * {@link CraftingMenuMixin} remains the hard backstop.
 */
@Mixin(RecipeBookMenu.class)
public abstract class RecipeBookMenuMixin {
    @Inject(method = "handlePlacement", at = @At("HEAD"), cancellable = true)
    private void eclipse$blockGatedRecipePlacement(boolean placeAll, RecipeHolder<?> recipe,
            ServerPlayer player, CallbackInfo callbackInfo) {
        if (CraftGateEnforcement.isRecipePlacementLockedFor(player, recipe)) {
            RecipeGate.hintLocked(player,
                    recipe.value().getResultItem(player.server.registryAccess()));
            callbackInfo.cancel();
        }
    }
}
