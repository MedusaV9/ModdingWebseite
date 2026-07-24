package dev.projecteclipse.eclipse.gameplay.mixin;

import java.util.Optional;

import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

import dev.projecteclipse.eclipse.progression.CraftGateEnforcement;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.item.crafting.CraftingRecipe;
import net.minecraft.world.item.crafting.RecipeHolder;
import net.minecraft.world.level.block.CrafterBlock;
import net.minecraft.world.level.block.entity.CrafterBlockEntity;
import net.minecraft.world.level.block.state.BlockState;

/**
 * EVAL-DOPA-S #1 automation guard: the vanilla Crafter crafts without a player and never
 * fires {@code ItemCraftedEvent}, so it bypassed every gate. Automated crafting policy
 * ({@link CraftGateEnforcement#isAutomationCraftLocked}): the Crafter obeys the GLOBAL
 * day-tier item/recipe locks and ModGate; a gated recipe fails with the vanilla
 * crafter-fail cue, exactly like an empty/invalid grid.
 */
@Mixin(CrafterBlock.class)
public abstract class CrafterBlockMixin {
    @Inject(method = "dispenseFrom", at = @At("HEAD"), cancellable = true)
    private void eclipse$blockGatedAutomation(BlockState state, ServerLevel level, BlockPos pos,
            CallbackInfo callbackInfo) {
        if (!(level.getBlockEntity(pos) instanceof CrafterBlockEntity crafter)) {
            return;
        }
        Optional<RecipeHolder<CraftingRecipe>> recipe =
                CrafterBlock.getPotentialResults(level, crafter.asCraftInput());
        if (recipe.isPresent()
                && CraftGateEnforcement.isAutomationCraftLocked(level.getServer(), recipe.get())) {
            level.levelEvent(1050, pos, 0); // vanilla crafter-fail sound event
            callbackInfo.cancel();
        }
    }
}
