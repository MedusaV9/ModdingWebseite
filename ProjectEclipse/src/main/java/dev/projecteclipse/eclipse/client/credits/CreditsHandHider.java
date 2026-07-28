package dev.projecteclipse.eclipse.client.credits;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.client.CameraDirector;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RenderHandEvent;

/**
 * FXWAVE-9 #2 — hides the FIRST-PERSON hand/held item during cinematic beats. F-057's
 * invisibility only hides the player model from OTHERS; your own arm (and the held wand)
 * kept rendering through the credits black-hole vantage and broke the framing (observed
 * live: the wand poked into the accretion-disc shot for the whole 65 s show).
 *
 * <p>Two gates, either hides:</p>
 * <ul>
 *   <li>{@link CameraDirector#isHudSuppressed()} — every letterboxed cutscene flight and
 *       the credits span up to the roll-stop payload (which hands the HUD back);</li>
 *   <li>{@link CreditsSkyFx#cinematicSkyActive()} — the finale beats AFTER that handback
 *       (eclipse act, black-hole vantage): whenever the credits sky owns the frame, no
 *       hand. Both states already reset on logout, so nothing can leak.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class CreditsHandHider {
    private CreditsHandHider() {}

    @SubscribeEvent
    static void onRenderHand(RenderHandEvent event) {
        if (CameraDirector.isHudSuppressed() || CreditsSkyFx.cinematicSkyActive()) {
            event.setCanceled(true);
        }
    }
}
