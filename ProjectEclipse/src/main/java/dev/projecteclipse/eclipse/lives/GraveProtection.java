package dev.projecteclipse.eclipse.lives;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.EclipseBlocks;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.Level;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDestroyBlockEvent;
import net.neoforged.neoforge.event.level.ExplosionEvent;

/**
 * F-085/086/087 — grave sanctity guards (the {@code MansionDomeProtection} house
 * pattern, deliberately its own sibling: that class knows the mansion, this one knows
 * graves — never double-cancels). A grave ({@code eclipse:grave}) holds a dead player's
 * entire inventory; ANY removal path scatters it ({@code GraveBlock.onRemove}), so the
 * only acceptable destroyer is a player deliberately mining it:
 *
 * <ul>
 *   <li><b>Explosions</b> (F-085): {@link ExplosionEvent.Detonate} prunes every grave
 *       cell from the affected-block list — creepers dragged into a storm fight, TNT,
 *       and any future boss explosion still damage entities, but never pop the grave
 *       (belt-and-braces beside the 1200.0F blast-resistance bump in
 *       {@code EclipseBlocks}).</li>
 *   <li><b>Mob grief</b> (F-085): {@link LivingDestroyBlockEvent} is cancelled on grave
 *       cells (withers, ravagers, future boss abilities).</li>
 *   <li><b>Storm suction / boss block throws</b> (F-086): {@code StormSiege.liftable}
 *       consults {@link #isGraveAt} and {@link #nearGrave} so a siege never lifts a
 *       grave OR the ground directly around/under one (no floating graves).</li>
 *   <li><b>Wand spells</b> (F-087): the live spell set writes zero blocks
 *       ({@code WandSpellEffects} class javadoc); the retired {@code WandPhaseService}
 *       blacklist consults {@link #isGraveAt} defensively.</li>
 * </ul>
 *
 * <p><b>Players stay allowed</b> to mine graves by hand (existing design:
 * {@code GraveBlock.onRemove} scatters safely and the dowser index unregisters) — no
 * {@code BlockEvent.BreakEvent} cancel here.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class GraveProtection {

    private GraveProtection() {}

    /** Whether {@code pos} holds a grave block (one cheap state read, no SavedData scan). */
    public static boolean isGraveAt(Level level, BlockPos pos) {
        return level.getBlockState(pos).is(EclipseBlocks.GRAVE.get());
    }

    /**
     * Whether any grave sits within the cube of {@code radius} around {@code pos}
     * (radius ≤ 2 intended — used by the siege lift sampler at volley cadence; graves
     * are rare, the scan is 27 state reads at r=1).
     */
    public static boolean nearGrave(ServerLevel level, BlockPos pos, int radius) {
        for (BlockPos probe : BlockPos.betweenClosed(
                pos.offset(-radius, -radius, -radius), pos.offset(radius, radius, radius))) {
            if (isGraveAt(level, probe)) {
                return true;
            }
        }
        return false;
    }

    /** F-085: explosions may hurt entities, but never reshape a grave. */
    @SubscribeEvent
    public static void onExplosionDetonate(ExplosionEvent.Detonate event) {
        if (!(event.getLevel() instanceof ServerLevel level)) {
            return;
        }
        event.getAffectedBlocks().removeIf(pos -> isGraveAt(level, pos));
    }

    /** F-085: block-accurate mob-grief cancel (withers, ravagers, future boss abilities). */
    @SubscribeEvent
    public static void onLivingDestroyBlock(LivingDestroyBlockEvent event) {
        if (event.getEntity().level() instanceof ServerLevel level
                && isGraveAt(level, event.getPos())) {
            event.setCanceled(true);
        }
    }
}
