package dev.projecteclipse.eclipse.artifact;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDropsEvent;

/**
 * Voids arm-artifact stacks from death drops BEFORE the grave forms (B17).
 *
 * <p>{@code lives.LifecycleEvents#onLivingDrops} (default priority) copies ALL drops into
 * the victim's grave. Without this guard the artifact would ride along: the respawn
 * enforcement then mints a fresh copy for the player, leaving a junk duplicate in the
 * grave that only gets purged when a looter picks it up. Stripping here — at
 * {@link EventPriority#HIGHEST}, guaranteed ahead of the grave capture and of any other
 * mod's drops handling — means death simply voids the artifact and
 * {@code ArtifactSlotLock#onPlayerRespawn} re-grants the one true copy. Applies to every
 * {@code LivingDropsEvent} (not just players): no mob, creative clone or exotic path may
 * ever legitimately drop an artifact.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ArtifactDropGuard {
    private ArtifactDropGuard() {}

    @SubscribeEvent(priority = EventPriority.HIGHEST)
    public static void onLivingDrops(LivingDropsEvent event) {
        event.getDrops().removeIf(drop -> drop.getItem().is(EclipseItems.ARM_ARTIFACT.get()));
    }
}
