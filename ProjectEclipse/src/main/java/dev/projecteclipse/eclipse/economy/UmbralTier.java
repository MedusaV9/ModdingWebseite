package dev.projecteclipse.eclipse.economy;

import net.minecraft.tags.BlockTags;
import net.minecraft.tags.TagKey;
import net.minecraft.world.item.Tier;
import net.minecraft.world.item.crafting.Ingredient;
import net.minecraft.world.level.block.Block;

/**
 * Tool tier of the eclipse-touched tools (spec §4: "unrepairable, high durability").
 * Diamond-level speed/damage/drops with roughly 1.6x diamond durability; the repair
 * ingredient is empty, so anvils and grindstone-combining can never restore it — when an
 * umbral tool breaks, it is gone.
 */
public final class UmbralTier implements Tier {
    public static final UmbralTier INSTANCE = new UmbralTier();

    private UmbralTier() {}

    @Override
    public int getUses() {
        return 2500;
    }

    @Override
    public float getSpeed() {
        return 8.0F;
    }

    @Override
    public float getAttackDamageBonus() {
        return 3.0F;
    }

    @Override
    public TagKey<Block> getIncorrectBlocksForDrops() {
        return BlockTags.INCORRECT_FOR_DIAMOND_TOOL;
    }

    @Override
    public int getEnchantmentValue() {
        return 14;
    }

    @Override
    public Ingredient getRepairIngredient() {
        return Ingredient.of();
    }
}
