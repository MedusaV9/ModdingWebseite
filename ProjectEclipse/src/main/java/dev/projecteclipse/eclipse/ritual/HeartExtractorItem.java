package dev.projecteclipse.eclipse.ritual;

import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.UseAnim;
import net.minecraft.world.level.Level;

/**
 * Heart Extractor tool shell (R8 — P4-B8 completes behavior). Hold-to-use for
 * {@value #USE_DURATION_TICKS} ticks with spear animation; costs one heart for two
 * {@code heart_fragment} drops when finished.
 *
 * <p>P4-B8 wires lives check, pain package, and fragment drops.</p>
 */
public class HeartExtractorItem extends Item {
    /** Hold duration in ticks (48t ≈ 2.4 s). */
    public static final int USE_DURATION_TICKS = 48;

    public HeartExtractorItem(Properties properties) {
        super(properties);
    }

    @Override
    public int getUseDuration(ItemStack stack, net.minecraft.world.entity.LivingEntity entity) {
        return USE_DURATION_TICKS;
    }

    @Override
    public UseAnim getUseAnimation(ItemStack stack) {
        return UseAnim.SPEAR;
    }

    @Override
    public ItemStack finishUsingItem(ItemStack stack, Level level, net.minecraft.world.entity.LivingEntity entity) {
        // TODO(P4-B8): LivesApi check (>=2), -1 heart, drop 2x heart_fragment, FX + sounds
        return stack;
    }
}
