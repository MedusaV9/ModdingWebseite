package dev.projecteclipse.eclipse.wand;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDeathEvent;

/**
 * Game-bus glue for the Zauberstab: the on-kill XP bonus (IDEA-19 §leveling — "wand XP
 * from using powers + small on-kill bonus"). A kill counts when the killer is a player
 * currently HOLDING (main/off hand) a wand they own — no path/level gate beyond that;
 * {@code WandPowers.handleKill} refuses pathless wands internally (no XP before the
 * first choice). Amount: {@code xp.killBonus} in {@code config/eclipse/wand.json}.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class WandEvents {
    private WandEvents() {}

    @SubscribeEvent
    static void onLivingDeath(LivingDeathEvent event) {
        if (event.getEntity().level().isClientSide) {
            return;
        }
        if (event.getSource().getEntity() instanceof ServerPlayer killer
                && killer != event.getEntity()) {
            WandPowers.handleKill(killer);
        }
    }
}
